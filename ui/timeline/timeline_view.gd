class_name TimelineView
extends Control
## Dope-sheet timeline. One row per layer (top layer first) and optionally a
## camera row. A block is a drawing key; the bar after it shows how long the
## drawing is held. Click to select frame/layer, drag a key to retime it,
## double-click an empty cell to create a drawing, drag the ruler to scrub.
## Ctrl/Cmd-click adds or removes drawings from the selection, Shift-click
## selects everything between the last clicked drawing and this one (across
## layers too); dragging any selected drawing moves the whole group.
## Only visible frames are drawn, so very long scenes stay fast.

var show_camera_row: bool = false
## Shows the scene's audio tracks (waveforms) under the layers, for timing and lip-sync.
var show_audio_rows: bool = false
var frame_w: float = 16.0
var scroll_x: float = 0.0
var scroll_y: float = 0.0

var _drag: String = ""
var _drag_layer: LayerData = null
var _drag_from: int = -1
var _drag_to: int = -1
## Selected drawings: "layer_id:frame" -> [LayerData, frame].
var _sel: Dictionary = {}
var _anchor: Array = []  # [LayerData, frame] of the last plain/ctrl click
var _pending_single: bool = false  # plain click on a selected key: select only it if not dragged


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame_w = UI.px(16)
	for sig: Signal in [App.project_opened, App.scene_switched, App.layers_changed, App.layer_selected,
			App.timeline_changed, App.camera_changed, App.playback_changed, App.markers_changed, App.audio_changed]:
		sig.connect(queue_redraw)
	Audio.peaks_ready.connect(func(_p: String) -> void: queue_redraw())
	App.frame_changed.connect(_on_frame_changed)
	App.timeline_changed.connect(_prune_selection)
	App.layers_changed.connect(_prune_selection)
	App.scene_switched.connect(clear_selection)
	App.project_opened.connect(clear_selection)
	resized.connect(_clamp_scroll)


func _header_w() -> float:
	return UI.px(150)


func _ruler_h() -> float:
	return UI.px(24)


func _row_h() -> float:
	return UI.px(26)


func _rows() -> Array:
	var rows := []
	if show_camera_row:
		rows.append({"kind": "camera"})
	var s := App.current_scene()
	if s != null:
		for i in range(s.layers.size() - 1, -1, -1):
			rows.append({"kind": "layer", "layer": s.layers[i], "index": i})
		if show_audio_rows:
			for t in s.audio_tracks:
				rows.append({"kind": "audio", "track": t})
	return rows


func _frame_at(x: float) -> int:
	return floori((x - _header_w() + scroll_x) / frame_w)


func _row_at(y: float) -> int:
	if y < _ruler_h():
		return -1
	return floori((y - _ruler_h() + scroll_y) / _row_h())


func _frame_x(f: int) -> float:
	return _header_w() + f * frame_w - scroll_x


# ================================================================ drawing

func _draw() -> void:
	var font := get_theme_default_font()
	var fs := int(UI.px(12))
	var hw := _header_w()
	var rh := _ruler_h()
	var row_h := _row_h()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG_DEEP)
	if not App.has_project():
		return
	var s := App.current_scene()
	if s == null:
		return
	var fc := s.frame_count
	var fps: int = App.project.fps
	var rows := _rows()
	var first := maxi(0, floori(scroll_x / frame_w))
	var last := ceili((scroll_x + size.x - hw) / frame_w) + 1

	# frame columns
	for f in range(first, last):
		var x := _frame_x(f)
		if f >= fc:
			draw_rect(Rect2(x, rh, frame_w, size.y - rh), Color(0, 0, 0, 0.35))
			continue
		var second := int(f / float(fps)) % 2 == 1
		if second:
			draw_rect(Rect2(x, rh, frame_w, size.y - rh), Color(1, 1, 1, 0.018))
		var line_col := Color(1, 1, 1, 0.1) if f % fps == 0 else Color(1, 1, 1, 0.035)
		draw_line(Vector2(x, rh), Vector2(x, size.y), line_col, 1.0)

	# current frame column
	var cx := _frame_x(App.frame)
	draw_rect(Rect2(cx, rh, frame_w, size.y - rh), Color(1.0, 0.478, 0.349, 0.10))

	# rows
	var active_layer := App.current_layer()
	for r in rows.size():
		var y := rh + r * row_h - scroll_y
		if y + row_h < rh or y > size.y:
			continue
		var row: Dictionary = rows[r]
		draw_line(Vector2(hw, y + row_h), Vector2(size.x, y + row_h), Color(1, 1, 1, 0.04), 1.0)
		if row["kind"] == "camera":
			_draw_camera_row(s, y, row_h, first, last)
			continue
		if row["kind"] == "audio":
			_draw_audio_row(row["track"], y, row_h)
			continue
		var layer: LayerData = row["layer"]
		var selected := layer == active_layer
		if selected:
			draw_rect(Rect2(hw, y, size.x - hw, row_h), Color(1, 1, 1, 0.025))
		_draw_layer_cels(layer, s, y, row_h, first, last, selected)

	# header column
	draw_rect(Rect2(0, rh, hw, size.y - rh), Palette.PANEL)
	draw_line(Vector2(hw, 0), Vector2(hw, size.y), Palette.BORDER, 1.0)
	for r in rows.size():
		var y := rh + r * row_h - scroll_y
		if y + row_h < rh or y > size.y:
			continue
		var row: Dictionary = rows[r]
		var text := ""
		var col := Palette.MUTED
		if row["kind"] == "camera":
			text = "Camera"
			col = Palette.DEPTH
		elif row["kind"] == "audio":
			var at: AudioTrackData = row["track"]
			text = "♪ " + at.name
			col = at.color()
		else:
			var layer: LayerData = row["layer"]
			text = layer.name
			if layer == active_layer:
				draw_rect(Rect2(0, y + 1, hw, row_h - 2), Palette.ACCENT_SOFT)
				draw_rect(Rect2(0, y + 1, UI.px(3), row_h - 2), Palette.ACCENT)
				col = Palette.TEXT
			if not layer.visible:
				col = Palette.DIM
				text += "  (hidden)"
		draw_string(font, Vector2(UI.px(12), y + row_h * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, hw - UI.px(18), fs, col)

	# ruler
	draw_rect(Rect2(0, 0, size.x, rh), Palette.PANEL)
	draw_line(Vector2(0, rh), Vector2(size.x, rh), Palette.BORDER, 1.0)
	var step := 1
	for candidate in [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]:
		step = candidate
		if candidate * frame_w >= UI.px(34):
			break
	for f in range(first, mini(last, fc + 1)):
		var x := _frame_x(f)
		if x < hw - 1:
			continue
		if f % step == 0 or f == 0:
			draw_line(Vector2(x, rh - UI.px(7)), Vector2(x, rh), Palette.DIM, 1.0)
			draw_string(font, Vector2(x + UI.px(3), rh - UI.px(8)), str(f + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(UI.px(11)), Palette.MUTED)
		else:
			draw_line(Vector2(x, rh - UI.px(3)), Vector2(x, rh), Color(1, 1, 1, 0.12), 1.0)
	draw_string(font, Vector2(UI.px(12), rh * 0.5 + fs * 0.36), "%d fps" % fps, HORIZONTAL_ALIGNMENT_LEFT, hw - UI.px(16), int(UI.px(11)), Palette.DIM)

	# markers: a flag on the ruler and a faint line through the rows
	for k in s.markers.keys():
		var mf: int = k
		if mf < first or mf >= last:
			continue
		var mx := _frame_x(mf)
		if mx < hw:
			continue
		var marker_col := Color("#ffd166")
		draw_line(Vector2(mx, rh), Vector2(mx, size.y), Color(1.0, 0.82, 0.4, 0.25), 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(mx, UI.px(2)), Vector2(mx + UI.px(8), UI.px(6)), Vector2(mx, UI.px(10))]), marker_col)
		draw_line(Vector2(mx, UI.px(2)), Vector2(mx, rh), marker_col, 1.0)
		draw_string(font, Vector2(mx + UI.px(10), UI.px(11)), str(s.markers[k]), HORIZONTAL_ALIGNMENT_LEFT, UI.px(120), int(UI.px(10)), marker_col)

	# playhead
	if cx + frame_w >= hw:
		var px := cx + frame_w * 0.5
		draw_line(Vector2(px, rh), Vector2(px, size.y), Palette.ACCENT, maxf(1.0, UI.px(1.5)))
		var tag := Rect2(cx - UI.px(4), UI.px(2), frame_w + UI.px(8), rh - UI.px(4))
		draw_rect(tag, Palette.ACCENT)
		draw_string(font, Vector2(tag.position.x, tag.position.y + tag.size.y * 0.5 + fs * 0.33), str(App.frame + 1), HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, int(UI.px(11)), Color("#1a1210"))

	# selected drawings: a bright outline on each
	if not _sel.is_empty():
		var rows_sel := _rows()
		for r in rows_sel.size():
			var row: Dictionary = rows_sel[r]
			if row["kind"] != "layer":
				continue
			var y := rh + r * row_h - scroll_y
			for item in _sel.values():
				if item[0] == row["layer"]:
					var sx := _frame_x(int(item[1]))
					if sx + frame_w > hw and sx < size.x:
						draw_rect(Rect2(sx + 1, y + UI.px(2), frame_w - 2, row_h - UI.px(4)), Color("#ffffff"), false, maxf(1.5, UI.px(2)))

	# drag preview for drawings being retimed (one, or the whole selection)
	if _drag == "key" and _drag_to != _drag_from:
		var delta := _drag_to - _drag_from
		var rows_now := _rows()
		for r in rows_now.size():
			var row: Dictionary = rows_now[r]
			if row["kind"] != "layer":
				continue
			var y := rh + r * row_h - scroll_y
			for item in _drag_items():
				if item[0] == row["layer"]:
					var rect := Rect2(_frame_x(int(item[1]) + delta) + 1, y + 3, frame_w - 2, row_h - 6)
					draw_rect(rect, Color(1, 1, 1, 0.25))
					draw_rect(rect, Color(1, 1, 1, 0.8), false, 2.0)


func _draw_layer_cels(layer: LayerData, s: SceneData, y: float, row_h: float, first: int, last: int, selected: bool) -> void:
	var hw := _header_w()
	if layer.is_character():
		_draw_character_keys(layer, s, y, row_h, first, last, selected)
	var keys := layer.sorted_keys()
	var base := Palette.ACCENT if selected else Color("#c9694f")
	if not layer.visible:
		base = Palette.DIM
	for k in keys:
		var key: int = k
		var end := layer.exposure_end(key, s.frame_count)
		if end <= first or key >= last:
			continue
		var x0 := maxf(_frame_x(key), hw)
		var x1 := _frame_x(end)
		if x1 <= hw:
			continue
		var hold := Rect2(x0, y + row_h * 0.38, x1 - x0 - 1, row_h * 0.24)
		var hold_col := base
		hold_col.a = 0.35
		draw_rect(hold, hold_col)
		var kx := _frame_x(key)
		if kx + frame_w > hw:
			var block := Rect2(maxf(kx + 1, hw), y + UI.px(4), frame_w - 2, row_h - UI.px(8))
			if kx < hw:
				block.size.x = maxf(0.0, kx + frame_w - 1 - hw)
			draw_rect(block, base)
			var dot_col := Color("#1a1210")
			dot_col.a = 0.7
			if block.size.x > UI.px(6):
				draw_circle(Vector2(kx + frame_w * 0.5, y + row_h * 0.5), UI.px(2.2), dot_col)
	# layer motion keys: small diamonds along the bottom edge of the row
	for k in layer.motion_keys.keys():
		var mk: int = k
		if mk < first or mk >= last:
			continue
		var c := Vector2(_frame_x(mk) + frame_w * 0.5, y + row_h - UI.px(4))
		if c.x < hw:
			continue
		var r := UI.px(3.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), Color("#ffd166"))


## Character instances: a band across the scene, pose keys as violet
## diamonds and drawing/view switches as small ticks.
func _draw_character_keys(layer: LayerData, s: SceneData, y: float, row_h: float, first: int, last: int, selected: bool) -> void:
	var hw := _header_w()
	var x0 := maxf(_frame_x(0), hw)
	var x1 := _frame_x(s.frame_count)
	if x1 > hw:
		var band := Color(0.61, 0.42, 1.0, 0.22 if selected else 0.12)
		draw_rect(Rect2(x0, y + row_h * 0.3, x1 - x0, row_h * 0.4), band)
	var violet := Color("#9b6cff")
	for k in layer.pose_keys.keys():
		var key: int = k
		if key < first or key >= last:
			continue
		var c := Vector2(_frame_x(key) + frame_w * 0.5, y + row_h * 0.5)
		if c.x < hw:
			continue
		var r := minf(frame_w, row_h) * 0.34
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), violet)
	for track: Dictionary in [layer.swap_keys, layer.view_keys]:
		for k in track.keys():
			var key: int = k
			if key < first or key >= last:
				continue
			var tx := _frame_x(key) + frame_w * 0.5
			if tx < hw:
				continue
			draw_line(Vector2(tx, y + UI.px(2)), Vector2(tx, y + UI.px(8)), Color("#d9c8ff"), maxf(1.0, UI.px(2)))


func _draw_audio_row(t: AudioTrackData, y: float, row_h: float) -> void:
	var fps: int = App.project.fps
	var hw := _header_w()
	var px_per_sec := frame_w * fps
	var col := t.color()
	if not Audio.is_audible(t):
		col = Palette.DIM
	for item in t.clips:
		var clip: AudioClipData = item
		var rect := Rect2(_frame_x(clip.start_frame), y + 2, clip.length * px_per_sec, row_h - 4)
		if rect.end.x < hw or rect.position.x > size.x:
			continue
		var fill := col
		fill.a = 0.12
		var x0 := maxf(rect.position.x, hw)
		draw_rect(Rect2(x0, rect.position.y, minf(rect.end.x, size.x) - x0, rect.size.y), fill)
		AudioTimeline.draw_wave(self, clip, rect, px_per_sec, fps, Color(col, 0.9), hw, size.x)


func _draw_camera_row(s: SceneData, y: float, row_h: float, first: int, last: int) -> void:
	var keys := s.camera_keys.keys()
	keys.sort()
	var hw := _header_w()
	if keys.size() >= 2:
		var x0 := maxf(_frame_x(int(keys[0])) + frame_w * 0.5, hw)
		var x1 := _frame_x(int(keys[keys.size() - 1])) + frame_w * 0.5
		if x1 > hw:
			draw_line(Vector2(x0, y + row_h * 0.5), Vector2(x1, y + row_h * 0.5), Color(0.31, 0.82, 0.77, 0.45), maxf(1.0, UI.px(2)))
	for k in keys:
		var key: int = k
		if key < first or key >= last:
			continue
		var c := Vector2(_frame_x(key) + frame_w * 0.5, y + row_h * 0.5)
		if c.x < hw:
			continue
		var r := minf(frame_w, row_h) * 0.36
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, Palette.DEPTH)


# ================================================================ input

func _gui_input(event: InputEvent) -> void:
	if not App.has_project():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mb.ctrl_pressed or mb.meta_pressed:
				_zoom_at(mb.position.x, 1.15 if dir < 0 else 1.0 / 1.15)
			elif mb.shift_pressed:
				scroll_y += dir * _row_h()
			else:
				scroll_x += dir * frame_w * 3.0
			_clamp_scroll()
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position, mb.double_click, mb.ctrl_pressed or mb.meta_pressed, mb.shift_pressed)
			else:
				_release()
			accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		_motion((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		scroll_x += pg.delta.x * frame_w
		scroll_y += pg.delta.y * _row_h() * 0.5
		_clamp_scroll()
		queue_redraw()
		accept_event()


func _press(pos: Vector2, double: bool, ctrl: bool = false, shift: bool = false) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var f := clampi(_frame_at(pos.x), 0, s.frame_count - 1)
	if pos.y < _ruler_h():
		if pos.x >= _header_w():
			if double:
				Ops.toggle_marker(f)
				return
			App.stop()
			_drag = "scrub"
			App.set_frame(f)
		return
	var rows := _rows()
	var ri := _row_at(pos.y)
	if ri < 0 or ri >= rows.size():
		return
	var row: Dictionary = rows[ri]
	if row["kind"] == "camera" or row["kind"] == "audio":
		if pos.x >= _header_w():
			App.stop()
			App.set_frame(f)
			_drag = "scrub"
		return
	var layer: LayerData = row["layer"]
	App.set_layer(int(row["index"]))
	if pos.x < _header_w():
		return
	App.stop()
	var has_key := layer.cels.has(f)
	if ctrl and has_key:
		# add / remove this drawing; no drag unless it's now selected
		var id := _sel_id(layer, f)
		if _sel.has(id):
			_sel.erase(id)
		else:
			_sel[id] = [layer, f]
			_start_key_drag(layer, f)
		_anchor = [layer, f]
		App.set_frame(f)
		queue_redraw()
		return
	if shift and not _anchor.is_empty():
		_select_range(_anchor, layer, f, ctrl)
		App.set_frame(f)
		if has_key:
			_start_key_drag(layer, f)
		queue_redraw()
		return
	App.set_frame(f)
	if double and not has_key:
		Ops.new_drawing(layer, f)
		return
	if has_key:
		if _sel.has(_sel_id(layer, f)) and _sel.size() > 1:
			_pending_single = true  # drag moves the group; a plain click picks just this one
		else:
			_sel = {_sel_id(layer, f): [layer, f]}
		_anchor = [layer, f]
		_start_key_drag(layer, f)
		queue_redraw()
	else:
		if not ctrl and not shift:
			clear_selection()
			_anchor = []
		_drag = "scrub"


func _motion(pos: Vector2) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var f := clampi(_frame_at(pos.x), 0, s.frame_count - 1)
	if _drag == "scrub":
		App.set_frame(f)
	elif _drag == "key":
		if f != _drag_to:
			_drag_to = f
			queue_redraw()


func _release() -> void:
	if _drag == "key" and _drag_layer != null and _drag_to != _drag_from:
		var delta := _drag_to - _drag_from
		var items := _drag_items()
		if items.size() <= 1:
			Ops.move_key(_drag_layer, _drag_from, _drag_to)
			_sel = {_sel_id(_drag_layer, _drag_to): [_drag_layer, _drag_to]}
		else:
			var groups := {}
			for item in items:
				if not groups.has(item[0]):
					groups[item[0]] = []
				var arr: Array = groups[item[0]]
				arr.append(int(item[1]))
			if Ops.move_keys(groups, delta):
				var moved := {}
				for item in items:
					moved[_sel_id(item[0], int(item[1]) + delta)] = [item[0], int(item[1]) + delta]
				_sel = moved
		if not _anchor.is_empty():
			_anchor = [_anchor[0], int(_anchor[1]) + delta]
	elif _drag == "key" and _pending_single and _drag_layer != null:
		_sel = {_sel_id(_drag_layer, _drag_from): [_drag_layer, _drag_from]}
	_pending_single = false
	_drag = ""
	_drag_layer = null
	queue_redraw()


# ================================================================ selection

func _sel_id(layer: LayerData, f: int) -> String:
	return "%s:%d" % [layer.id, f]


func _start_key_drag(layer: LayerData, f: int) -> void:
	_drag = "key"
	_drag_layer = layer
	_drag_from = f
	_drag_to = f


## What a drag moves: the whole selection if the grabbed drawing is in it,
## otherwise just the grabbed drawing.
func _drag_items() -> Array:
	if _drag_layer != null and _sel.has(_sel_id(_drag_layer, _drag_from)):
		return _sel.values()
	return [[_drag_layer, _drag_from]]


## Shift-click: every drawing between the anchor and (layer, f), on the
## anchor's row, this row and the rows between.
func _select_range(anchor: Array, layer: LayerData, f: int, add: bool) -> void:
	var a_layer: LayerData = anchor[0]
	var f0 := mini(int(anchor[1]), f)
	var f1 := maxi(int(anchor[1]), f)
	var rows := _rows()
	var r0 := -1
	var r1 := -1
	for r in rows.size():
		var row: Dictionary = rows[r]
		if row["kind"] != "layer":
			continue
		if row["layer"] == a_layer:
			r0 = r
		if row["layer"] == layer:
			r1 = r
	if r0 < 0:
		r0 = r1
	if not add:
		_sel = {}
	for r in range(mini(r0, r1), maxi(r0, r1) + 1):
		var row: Dictionary = rows[r]
		if row["kind"] != "layer":
			continue
		var l: LayerData = row["layer"]
		if l.is_character():
			continue
		for k in l.cels.keys():
			var kf := int(k)
			if kf >= f0 and kf <= f1:
				_sel[_sel_id(l, kf)] = [l, kf]


func clear_selection() -> void:
	if _sel.is_empty():
		return
	_sel = {}
	queue_redraw()


## Drops selected drawings that no longer exist (after undo, delete, …).
func _prune_selection() -> void:
	if _drag != "":
		return
	var s := App.current_scene()
	for id in _sel.keys():
		var item: Array = _sel[id]
		var l: LayerData = item[0]
		if s == null or not s.layers.has(l) or not l.cels.has(int(item[1])):
			_sel.erase(id)


func _zoom_at(x: float, factor: float) -> void:
	var anchor_frame := (x - _header_w() + scroll_x) / frame_w
	frame_w = clampf(frame_w * factor, UI.px(5), UI.px(60))
	scroll_x = anchor_frame * frame_w - (x - _header_w())


func zoom_by(factor: float) -> void:
	_zoom_at(_header_w() + (size.x - _header_w()) * 0.5, factor)
	_clamp_scroll()
	queue_redraw()


func _clamp_scroll() -> void:
	var fc := App.frame_count() if App.has_project() else 1
	var max_x := maxf(0.0, (fc + 8) * frame_w - (size.x - _header_w()))
	scroll_x = clampf(scroll_x, 0.0, max_x)
	var max_y := maxf(0.0, _rows().size() * _row_h() - (size.y - _ruler_h()))
	scroll_y = clampf(scroll_y, 0.0, max_y)


func _on_frame_changed() -> void:
	var view_w := size.x - _header_w()
	var x := App.frame * frame_w
	if x < scroll_x or x + frame_w > scroll_x + view_w:
		scroll_x = x - view_w * (0.1 if App.playing else 0.4)
		_clamp_scroll()
	queue_redraw()
