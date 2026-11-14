class_name AudioTimeline
extends Control
## Multitrack audio editor for a scene: waveforms, drag clips to move them
## (snapped to frames), drag clip edges to trim, click M/S to mute/solo,
## scrub on the ruler. Delete removes the selected clip.

signal clip_selected

var frame_w: float = 8.0
var scroll_x: float = 0.0
var scroll_y: float = 0.0
var selected_clip: AudioClipData = null
var selected_track: AudioTrackData = null

var _drag: String = ""
var _drag_clip: AudioClipData = null
var _before: Dictionary = {}
var _press_x: float = 0.0


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame_w = UI.px(8)
	for sig: Signal in [App.project_opened, App.scene_switched, App.audio_changed, App.markers_changed,
			App.timeline_changed, App.playback_changed]:
		sig.connect(_on_data_changed)
	App.frame_changed.connect(_on_frame)
	Audio.peaks_ready.connect(func(_p: String) -> void: queue_redraw())


func _header_w() -> float:
	return UI.px(180)


func _ruler_h() -> float:
	return UI.px(24)


func _row_h() -> float:
	return UI.px(62)


func _tracks() -> Array:
	var s := App.current_scene()
	return s.audio_tracks if s != null else []


func _frame_x(f: float) -> float:
	return _header_w() + f * frame_w - scroll_x


func _frame_at(x: float) -> int:
	return floori((x - _header_w() + scroll_x) / frame_w)


func _px_per_sec() -> float:
	return frame_w * App.project.fps


func clip_rect(clip: AudioClipData, row: int) -> Rect2:
	var y := _ruler_h() + row * _row_h() - scroll_y
	var x0 := _frame_x(clip.start_frame)
	return Rect2(x0, y + UI.px(4), clip.length * _px_per_sec(), _row_h() - UI.px(8))


func _on_data_changed() -> void:
	if selected_clip != null:
		var found := false
		for t in _tracks():
			if (t as AudioTrackData).clips.has(selected_clip):
				found = true
		if not found:
			selected_clip = null
			selected_track = null
			clip_selected.emit()
	queue_redraw()


func _on_frame() -> void:
	if App.playing and App.has_project():
		var view_w := size.x - _header_w()
		var x := App.frame * frame_w
		if x < scroll_x or x > scroll_x + view_w:
			scroll_x = maxf(0.0, x - view_w * 0.1)
	queue_redraw()


# ================================================================ waveform helper

## Draws the waveform of `clip` inside `rect` (shared with the dope sheet).
static func draw_wave(ci: CanvasItem, clip: AudioClipData, rect: Rect2, px_per_sec: float, fps: int, color: Color, left: float, right: float) -> void:
	var peaks := Audio.peaks_for(clip.file)
	var mid := rect.position.y + rect.size.y * 0.5
	var xa := maxf(rect.position.x, left)
	var xb := minf(rect.end.x, right)
	if peaks.is_empty():
		ci.draw_line(Vector2(xa, mid), Vector2(xb, mid), color, 1.0)
		return
	var half := rect.size.y * 0.46
	var stream_len := Audio.length_of(clip.file)
	var gain := db_to_linear(clip.gain_db)
	var pts := PackedVector2Array()
	var dt := 1.0 / px_per_sec
	var x := floorf(xa)
	while x < xb:
		var t := clip.start_time(fps) + (x - rect.position.x) * dt
		var src := clip.source_pos(t, fps, stream_len)
		if src >= 0.0:
			var v := minf(1.0, Audio.peak_between(clip.file, src, src + dt) * gain * clip.fade_gain(t, fps))
			var h := maxf(0.5, v * half)
			pts.append(Vector2(x, mid - h))
			pts.append(Vector2(x, mid + h))
		x += 1.0
	if pts.size() >= 2:
		ci.draw_multiline(pts, color, 1.0)


# ================================================================ drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG_DEEP)
	if not App.has_project() or App.current_scene() == null:
		return
	var s := App.current_scene()
	var font := get_theme_default_font()
	var fs := int(UI.px(12))
	var hw := _header_w()
	var rh := _ruler_h()
	var row_h := _row_h()
	var fps: int = App.project.fps
	var fc := s.frame_count
	var first := maxi(0, floori(scroll_x / frame_w))
	var last := ceili((scroll_x + size.x - hw) / frame_w) + 1

	# seconds grid and scene end
	for f in range(first, last):
		if f % fps == 0:
			var x := _frame_x(f)
			draw_line(Vector2(x, rh), Vector2(x, size.y), Color(1, 1, 1, 0.06), 1.0)
	var end_x := _frame_x(fc)
	if end_x < size.x:
		draw_rect(Rect2(maxf(end_x, hw), rh, size.x - maxf(end_x, hw), size.y - rh), Color(0, 0, 0, 0.35))

	var tracks := _tracks()
	for r in tracks.size():
		var t: AudioTrackData = tracks[r]
		var y := rh + r * row_h - scroll_y
		if y + row_h < rh or y > size.y:
			continue
		if t == selected_track:
			draw_rect(Rect2(hw, y, size.x - hw, row_h), Color(1, 1, 1, 0.025))
		draw_line(Vector2(hw, y + row_h), Vector2(size.x, y + row_h), Color(1, 1, 1, 0.05), 1.0)
		var audible := Audio.is_audible(t)
		for item in t.clips:
			var clip: AudioClipData = item
			var rect := clip_rect(clip, r)
			if rect.end.x < hw or rect.position.x > size.x:
				continue
			var col := t.color()
			if not audible:
				col = Palette.DIM
			var fill := col
			fill.a = 0.16
			var vis := Rect2(maxf(rect.position.x, hw), rect.position.y, minf(rect.end.x, size.x) - maxf(rect.position.x, hw), rect.size.y)
			draw_rect(vis, fill)
			draw_wave(self, clip, rect, _px_per_sec(), fps, Color(col, 0.85), hw, size.x)
			# fades
			var fade_col := Color(1, 1, 1, 0.5)
			if clip.fade_in > 0.0:
				var fx := rect.position.x + clip.fade_in * _px_per_sec()
				if fx > hw:
					draw_line(Vector2(maxf(rect.position.x, hw), rect.end.y), Vector2(fx, rect.position.y), fade_col, 1.0)
			if clip.fade_out > 0.0:
				var fx := rect.end.x - clip.fade_out * _px_per_sec()
				if rect.end.x > hw:
					draw_line(Vector2(maxf(fx, hw), rect.position.y), Vector2(rect.end.x, rect.end.y), fade_col, 1.0)
			var border := Color.WHITE if clip == selected_clip else Color(col, 0.6)
			draw_rect(vis, border, false, 2.0 if clip == selected_clip else 1.0)
			var label := clip.name + ("  (loop)" if clip.loop else "")
			if Audio.is_missing(clip.file):
				label = "MISSING FILE · " + clip.name
			if rect.position.x + UI.px(6) > hw - UI.px(200):
				draw_string(font, Vector2(maxf(rect.position.x, hw) + UI.px(6), rect.position.y + fs + UI.px(2)), label, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, vis.size.x - UI.px(10)), int(UI.px(11)), Palette.TEXT)

	# markers
	for k in s.markers.keys():
		var mx := _frame_x(int(k))
		if mx >= hw and mx <= size.x:
			draw_line(Vector2(mx, rh), Vector2(mx, size.y), Color(1.0, 0.82, 0.4, 0.3), 1.0)

	# headers
	draw_rect(Rect2(0, rh, hw, size.y - rh), Palette.PANEL)
	draw_line(Vector2(hw, 0), Vector2(hw, size.y), Palette.BORDER, 1.0)
	for r in tracks.size():
		var t: AudioTrackData = tracks[r]
		var y := rh + r * row_h - scroll_y
		if y + row_h < rh or y > size.y:
			continue
		if t == selected_track:
			draw_rect(Rect2(0, y + 1, hw, row_h - 2), Palette.ACCENT_SOFT)
		draw_rect(Rect2(UI.px(8), y + UI.px(10), UI.px(4), row_h - UI.px(20)), t.color())
		draw_string(font, Vector2(UI.px(20), y + UI.px(24)), t.name, HORIZONTAL_ALIGNMENT_LEFT, hw - UI.px(80), fs, Palette.TEXT)
		draw_string(font, Vector2(UI.px(20), y + UI.px(42)), "%s · %+.1f dB" % [AudioTrackData.KIND_LABELS.get(t.kind, t.kind), t.volume_db], HORIZONTAL_ALIGNMENT_LEFT, hw - UI.px(80), int(UI.px(11)), Palette.DIM)
		var mrect := _mute_rect(r)
		var srect := _solo_rect(r)
		draw_rect(mrect, Palette.DANGER if t.muted else Palette.RAISED)
		draw_rect(srect, Color("#ffc94d") if t.solo else Palette.RAISED)
		draw_string(font, Vector2(mrect.position.x, mrect.position.y + mrect.size.y * 0.72), "M", HORIZONTAL_ALIGNMENT_CENTER, mrect.size.x, int(UI.px(11)), Color("#1a1210") if t.muted else Palette.MUTED)
		draw_string(font, Vector2(srect.position.x, srect.position.y + srect.size.y * 0.72), "S", HORIZONTAL_ALIGNMENT_CENTER, srect.size.x, int(UI.px(11)), Color("#1a1210") if t.solo else Palette.MUTED)
	if tracks.is_empty():
		draw_string(font, Vector2(hw + UI.px(16), rh + UI.px(40)), "No audio yet — click “Import audio…” or drag WAV, OGG or MP3 files onto the window.", HORIZONTAL_ALIGNMENT_LEFT, -1, int(UI.px(13)), Palette.MUTED)

	# ruler
	draw_rect(Rect2(0, 0, size.x, rh), Palette.PANEL)
	draw_line(Vector2(0, rh), Vector2(size.x, rh), Palette.BORDER, 1.0)
	var step_s := 1
	for cand in [1, 2, 5, 10, 15, 30, 60]:
		step_s = cand
		if cand * fps * frame_w >= UI.px(60):
			break
	for f in range(first, mini(last, fc + 1)):
		var x := _frame_x(f)
		if x < hw:
			continue
		if f % (fps * step_s) == 0:
			var secs := f / fps
			draw_line(Vector2(x, rh - UI.px(8)), Vector2(x, rh), Palette.DIM, 1.0)
			draw_string(font, Vector2(x + UI.px(3), rh - UI.px(8)), "%d:%02d" % [secs / 60, secs % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, int(UI.px(11)), Palette.MUTED)
		elif frame_w >= UI.px(5) and f % maxi(1, fps / 4) == 0:
			draw_line(Vector2(x, rh - UI.px(3)), Vector2(x, rh), Color(1, 1, 1, 0.15), 1.0)
	draw_string(font, Vector2(UI.px(12), rh * 0.5 + fs * 0.36), "Audio", HORIZONTAL_ALIGNMENT_LEFT, hw, int(UI.px(11)), Palette.DIM)

	# playhead
	var px := _frame_x(App.frame) + frame_w * 0.5
	if App.playing:
		px = _header_w() + App.playhead_seconds() * _px_per_sec() - scroll_x
	if px >= hw:
		draw_line(Vector2(px, 0), Vector2(px, size.y), Palette.ACCENT, maxf(1.0, UI.px(1.5)))


func _mute_rect(row: int) -> Rect2:
	var y := _ruler_h() + row * _row_h() - scroll_y
	return Rect2(_header_w() - UI.px(58), y + UI.px(18), UI.px(22), UI.px(22))


func _solo_rect(row: int) -> Rect2:
	var y := _ruler_h() + row * _row_h() - scroll_y
	return Rect2(_header_w() - UI.px(32), y + UI.px(18), UI.px(22), UI.px(22))


func _process(_delta: float) -> void:
	if App.playing and is_visible_in_tree():
		queue_redraw()


# ================================================================ input

func _hit(pos: Vector2) -> Dictionary:
	var tracks := _tracks()
	var row := floori((pos.y - _ruler_h() + scroll_y) / _row_h())
	if pos.y < _ruler_h() or row < 0 or row >= tracks.size():
		return {}
	var t: AudioTrackData = tracks[row]
	var out := {"track": t, "row": row}
	if pos.x < _header_w():
		return out
	for i in range(t.clips.size() - 1, -1, -1):
		var clip: AudioClipData = t.clips[i]
		var r := clip_rect(clip, row)
		if r.has_point(pos):
			out["clip"] = clip
			var edge := UI.px(7)
			if pos.x - r.position.x < edge:
				out["edge"] = "left"
			elif r.end.x - pos.x < edge:
				out["edge"] = "right"
			break
	return out


func _gui_input(event: InputEvent) -> void:
	if not App.has_project():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mb.ctrl_pressed or mb.meta_pressed:
				zoom_by(1.2 if dir < 0 else 1.0 / 1.2, mb.position.x)
			elif mb.shift_pressed:
				scroll_y = maxf(0.0, scroll_y + dir * _row_h() * 0.5)
			else:
				scroll_x = maxf(0.0, scroll_x + dir * frame_w * 8.0)
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_press(mb.position, mb.double_click)
			else:
				_release()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag != "":
			_motion(mm.position)
		else:
			var h := _hit(mm.position)
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if h.has("edge") else Control.CURSOR_ARROW
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		scroll_x = maxf(0.0, scroll_x + pg.delta.x * frame_w * 4.0)
		scroll_y = maxf(0.0, scroll_y + pg.delta.y * _row_h() * 0.3)
		queue_redraw()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and (k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE) and selected_clip != null:
			Ops.delete_audio_clip(selected_track, selected_clip)
			accept_event()


func _press(pos: Vector2, double: bool) -> void:
	var fc := App.frame_count()
	var f := clampi(_frame_at(pos.x), 0, fc - 1)
	if pos.y < _ruler_h():
		if pos.x >= _header_w():
			if double:
				Ops.toggle_marker(f)
				return
			App.stop()
			App.set_frame(f)
			_drag = "scrub"
		return
	var h := _hit(pos)
	if h.is_empty():
		return
	var t: AudioTrackData = h["track"]
	var row: int = h["row"]
	selected_track = t
	if _mute_rect(row).has_point(pos):
		Ops.set_audio_prop(t, "muted", not t.muted, "Mute %s" % t.name)
		return
	if _solo_rect(row).has_point(pos):
		Ops.set_audio_prop(t, "solo", not t.solo, "Solo %s" % t.name)
		return
	if not h.has("clip"):
		selected_clip = null
		clip_selected.emit()
		if pos.x >= _header_w():
			App.stop()
			App.set_frame(f)
			_drag = "scrub"
		queue_redraw()
		return
	var clip: AudioClipData = h["clip"]
	selected_clip = clip
	clip_selected.emit()
	if double:
		App.set_frame(clip.start_frame)
		return
	_drag_clip = clip
	_before = clip.to_dict()
	_press_x = pos.x
	_drag = "move"
	if h.has("edge"):
		_drag = "trim_left" if h["edge"] == "left" else "trim_right"
	queue_redraw()


func _motion(pos: Vector2) -> void:
	if _drag == "scrub":
		App.set_frame(clampi(_frame_at(pos.x), 0, App.frame_count() - 1))
		return
	if _drag_clip == null:
		return
	var fps: int = App.project.fps
	var df := roundi((pos.x - _press_x) / frame_w)
	var dt := df / float(fps)
	var c := _drag_clip
	var o := _before
	var stream_len := Audio.length_of(c.file)
	match _drag:
		"move":
			c.start_frame = maxi(0, int(o["start_frame"]) + df)
		"trim_left":
			var max_shift := float(o["length"]) - 0.05
			dt = clampf(dt, -float(o["trim_in"]), max_shift)
			var shift_frames := roundi(dt * fps)
			dt = shift_frames / float(fps)
			if int(o["start_frame"]) + shift_frames < 0:
				shift_frames = -int(o["start_frame"])
				dt = shift_frames / float(fps)
			c.trim_in = float(o["trim_in"]) + dt
			c.length = float(o["length"]) - dt
			c.start_frame = int(o["start_frame"]) + shift_frames
		"trim_right":
			var new_len := float(o["length"]) + dt
			if not c.loop:
				new_len = minf(new_len, stream_len - c.trim_in)
			c.length = maxf(0.05, new_len)
	queue_redraw()


func _release() -> void:
	if _drag_clip != null and _drag != "scrub" and _drag != "":
		Ops.commit_clip_edit(_drag_clip, _before)
		clip_selected.emit()
	_drag = ""
	_drag_clip = null


func zoom_by(factor: float, anchor_x: float = -1.0) -> void:
	if anchor_x < 0.0:
		anchor_x = _header_w() + (size.x - _header_w()) * 0.5
	var anchor_frame := (anchor_x - _header_w() + scroll_x) / frame_w
	frame_w = clampf(frame_w * factor, UI.px(0.5), UI.px(40))
	scroll_x = maxf(0.0, anchor_frame * frame_w - (anchor_x - _header_w()))
	queue_redraw()
