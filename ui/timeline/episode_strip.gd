class_name EpisodeStrip
extends Control
## The episode timeline: shots (scenes and title cards) laid end to end with
## their real lengths, transitions shown as overlaps, the episode soundtrack
## underneath. Click to select a shot, drag a shot to reorder, click the
## ruler to scrub, drag music clips to retime them.

signal entry_selected(index: int)
signal frame_requested(frame: int)
signal effect_selected(id: String)

var episode: EpisodeData = null
var selected: int = -1
var playhead: int = 0
var frame_w: float = 2.0
var scroll_x: float = 0.0

var _sched: Array = []
var _thumbs: Dictionary = {}  # scene id -> ImageTexture
var _drag: String = ""
var _drag_index: int = -1
var _drag_x: float = 0.0
var _drag_clip: AudioClipData = null
var _before: Dictionary = {}
var selected_fx: String = ""
var _drag_fx: Dictionary = {}
var _fx_before: Array = []
var _fx_start0: int = 0
var _fx_len0: int = 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_w = UI.px(2)
	Audio.peaks_ready.connect(func(_p: String) -> void: queue_redraw())


func set_episode(ep: EpisodeData) -> void:
	episode = ep
	refresh()


func refresh() -> void:
	_sched = episode.schedule(App.project) if episode != null and App.has_project() else []
	queue_redraw()


func invalidate_thumbs() -> void:
	_thumbs.clear()
	queue_redraw()


func _ruler_h() -> float:
	return UI.px(22)


func _shot_h() -> float:
	return UI.px(84)


## Effects track sits between the shots and the soundtrack.
func _fx_y() -> float:
	return _ruler_h() + _shot_h() + UI.px(2)


func _fx_row_h() -> float:
	return UI.px(22)


func _fx_rows() -> int:
	if episode == null or episode.effects.is_empty():
		return 1
	var mx := 0
	var ln := VideoFx.lanes(episode.effects)
	for k in ln.keys():
		mx = maxi(mx, int(ln[k]))
	return mx + 1


func _fx_rect(e: Dictionary, row: int) -> Rect2:
	var y := _fx_y() + row * (_fx_row_h() + UI.px(3))
	return Rect2(_x(int(e.get("start", 0))), y, maxf(UI.px(6), int(e.get("length", 1)) * frame_w), _fx_row_h())


func _music_y() -> float:
	return _fx_y() + _fx_rows() * (_fx_row_h() + UI.px(3)) + UI.px(8)


func _x(f: float) -> float:
	return UI.px(8) + f * frame_w - scroll_x


func _frame_at(x: float) -> int:
	return maxi(0, floori((x - UI.px(8) + scroll_x) / frame_w))


func fit() -> void:
	var total := EpisodeData.total_frames(_sched)
	if total > 0 and size.x > 50:
		frame_w = clampf((size.x - UI.px(24)) / total, 0.05, UI.px(30))
		scroll_x = 0.0
	queue_redraw()


func _thumb(scene: SceneData, frame: int) -> Texture2D:
	if not _thumbs.has(scene.id):
		var w := 160
		_thumbs[scene.id] = Thumbs.scene_frame(scene, clampi(frame, 0, scene.frame_count - 1), w, maxi(1, int(w * float(App.project.height) / App.project.width)))
	return _thumbs[scene.id]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG_DEEP)
	if episode == null or not App.has_project():
		return
	var font := get_theme_default_font()
	var fps: int = App.project.fps
	var rh := _ruler_h()
	var sh := _shot_h()
	var total := EpisodeData.total_frames(_sched)
	# ruler with timecode
	draw_rect(Rect2(0, 0, size.x, rh), Palette.PANEL)
	var step := 1
	for cand in [1, 2, 5, 10, 15, 30, 60, 120, 300]:
		step = cand
		if cand * fps * frame_w >= UI.px(64):
			break
	var sec := 0
	while sec * fps <= total:
		var x := _x(sec * fps)
		if x > size.x:
			break
		if x >= 0:
			draw_line(Vector2(x, rh - UI.px(7)), Vector2(x, rh), Palette.DIM, 1.0)
			draw_string(font, Vector2(x + UI.px(3), rh - UI.px(7)), "%d:%02d" % [sec / 60, sec % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, int(UI.px(11)), Palette.MUTED)
		sec += step
	# shots
	for item in _sched:
		var s: Dictionary = item
		var e: Dictionary = s["entry"]
		var idx: int = s["index"]
		var x0 := _x(int(s["start"]))
		var w := int(s["length"]) * frame_w
		var r := Rect2(x0, rh + UI.px(6), w - 2.0, sh - UI.px(12))
		if r.end.x < 0 or r.position.x > size.x:
			continue
		var is_scene := str(e.get("type", "")) == "scene"
		var scene: SceneData = s["scene"]
		var base := Palette.RAISED
		if not is_scene:
			base = Color.from_string(str(e.get("bg", "101116ff")), Palette.RAISED).lerp(Palette.RAISED, 0.3)
		draw_rect(r, base)
		if is_scene and scene != null and r.size.x > UI.px(20):
			var tex := _thumb(scene, int(e.get("trim_in", 0)))
			var th := r.size.y - UI.px(22)
			var tw := minf(th * tex.get_width() / maxf(1.0, tex.get_height()), r.size.x - UI.px(8))
			draw_texture_rect(tex, Rect2(r.position + Vector2(UI.px(4), UI.px(4)), Vector2(tw, th)), false)
		var label := ""
		if is_scene:
			label = scene.name if scene != null else "Missing scene"
		elif str(e.get("type", "")) == "credits":
			label = "Credits"
		else:
			label = "Title: " + str(e.get("text", "")).split("\n")[0]
		draw_string(font, Vector2(r.position.x + UI.px(5), r.end.y - UI.px(6)), "%d  %s · %.1fs" % [idx + 1, label, int(s["length"]) / float(fps)], HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, r.size.x - UI.px(8)), int(UI.px(11)), Palette.TEXT if scene != null or not is_scene else Palette.DANGER)
		var ov: int = s["overlap"]
		var tr := str(e.get("transition", "cut"))
		if ov > 0:
			var orect := Rect2(x0, r.position.y, ov * frame_w, r.size.y)
			draw_rect(orect, Color(0.31, 0.82, 0.77, 0.25))
		if idx > 0 and tr != "cut":
			draw_string(font, Vector2(x0 + UI.px(3), r.position.y + UI.px(12)), EpisodeData.TRANSITION_LABELS.get(tr, tr), HORIZONTAL_ALIGNMENT_LEFT, maxf(UI.px(40), ov * frame_w), int(UI.px(10)), Palette.DEPTH)
		if idx == selected:
			draw_rect(r, Palette.ACCENT, false, 2.0)
		else:
			draw_rect(r, Color(1, 1, 1, 0.1), false, 1.0)
	# effects track
	var fy := _fx_y()
	var rows := _fx_rows()
	draw_rect(Rect2(0, fy - UI.px(1), size.x, rows * (_fx_row_h() + UI.px(3)) + UI.px(2)), Color(0, 0, 0, 0.12))
	if episode.effects.is_empty():
		draw_string(font, Vector2(UI.px(10), fy + UI.px(15)), "Effects: add VHS, glitch, datamosh and more with “+ Effect” — they go here, at the playhead", HORIZONTAL_ALIGNMENT_LEFT, -1, int(UI.px(11)), Palette.DIM)
	var lanes := VideoFx.lanes(episode.effects)
	for item in episode.effects:
		var fx: Dictionary = item
		var id := str(fx.get("id", ""))
		var r := _fx_rect(fx, int(lanes.get(id, 0)))
		if r.end.x < 0 or r.position.x > size.x:
			continue
		var inf := VideoFx.info(str(fx.get("type", "")))
		var col := VideoFx.category_color(str(inf[2]))
		draw_rect(r, Color(col, 0.55))
		# fade ramps
		var fi := int(fx.get("fade_in", 0)) * frame_w
		var fo := int(fx.get("fade_out", 0)) * frame_w
		if fi > 1.0:
			draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(fi, 0), Vector2(r.position.x, r.end.y)]), Color(0, 0, 0, 0.35))
		if fo > 1.0:
			draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x - fo, r.position.y)]), Color(0, 0, 0, 0.35))
		draw_string(font, r.position + Vector2(UI.px(5), UI.px(15)), "✦ " + str(inf[1]), HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, r.size.x - UI.px(8)), int(UI.px(11)), Palette.TEXT)
		if id == selected_fx:
			draw_rect(r, Palette.ACCENT, false, 2.0)
			# trim handles
			draw_rect(Rect2(r.position.x, r.position.y, UI.px(4), r.size.y), Palette.ACCENT)
			draw_rect(Rect2(r.end.x - UI.px(4), r.position.y, UI.px(4), r.size.y), Palette.ACCENT)
		else:
			draw_rect(r, Color(col, 0.9), false, 1.0)
	# soundtrack row
	var my := _music_y()
	draw_rect(Rect2(0, my, size.x, size.y - my), Color(0, 0, 0, 0.18))
	var row_h := UI.px(30)
	for ti in episode.audio_tracks.size():
		var t: AudioTrackData = episode.audio_tracks[ti]
		var y := my + UI.px(4) + ti * (row_h + UI.px(4))
		for c in t.clips:
			var rect := Rect2(_x(c.start_frame), y, c.length * fps * frame_w, row_h)
			var col := t.color()
			if t.muted:
				col = Palette.DIM
			draw_rect(rect, Color(col, 0.15))
			AudioTimeline.draw_wave(self, c, rect, frame_w * fps, fps, Color(col, 0.85), 0.0, size.x)
			draw_string(font, rect.position + Vector2(UI.px(4), UI.px(11)), "♪ " + c.name, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, rect.size.x - UI.px(6)), int(UI.px(10)), Palette.TEXT)
	if episode.audio_tracks.is_empty():
		draw_string(font, Vector2(UI.px(10), my + UI.px(20)), "Episode soundtrack: add music that runs across scenes with “+ Music…”", HORIZONTAL_ALIGNMENT_LEFT, -1, int(UI.px(11)), Palette.DIM)
	# drag preview
	if _drag == "shot" and _drag_index >= 0:
		var target := _drop_index(get_local_mouse_position().x)
		var tx := UI.px(8)
		if target < _sched.size():
			var ts: Dictionary = _sched[target]
			tx = _x(int(ts["start"]))
		elif not _sched.is_empty():
			tx = _x(total)
		draw_line(Vector2(tx, rh), Vector2(tx, rh + sh), Palette.ACCENT, maxf(2.0, UI.px(3)))
	# playhead
	var px := _x(playhead)
	draw_line(Vector2(px, 0), Vector2(px, size.y), Palette.ACCENT, maxf(1.0, UI.px(1.5)))


func _drop_index(x: float) -> int:
	for item in _sched:
		var s: Dictionary = item
		var mid := _x(int(s["start"]) + int(s["length"]) * 0.5)
		if x < mid:
			return int(s["index"])
	return _sched.size()


func _gui_input(event: InputEvent) -> void:
	if episode == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mb.ctrl_pressed or mb.meta_pressed:
				var anchor := (mb.position.x - UI.px(8) + scroll_x) / frame_w
				frame_w = clampf(frame_w * (1.2 if dir < 0 else 1.0 / 1.2), 0.05, UI.px(30))
				scroll_x = maxf(0.0, anchor * frame_w - (mb.position.x - UI.px(8)))
			else:
				scroll_x = maxf(0.0, scroll_x + dir * UI.px(60))
			queue_redraw()
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press(mb.position)
		else:
			_release(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag == "scrub":
			frame_requested.emit(_frame_at(mm.position.x))
		elif _drag == "music" and _drag_clip != null:
			var df := roundi((mm.position.x - _drag_x) / frame_w)
			_drag_clip.start_frame = maxi(0, int(_before["start_frame"]) + df)
			queue_redraw()
		elif _drag == "shot":
			queue_redraw()
		elif _drag.begins_with("fx_") and not _drag_fx.is_empty():
			var df := roundi((mm.position.x - _drag_x) / frame_w)
			match _drag:
				"fx_move":
					_drag_fx["start"] = maxi(0, _fx_start0 + df)
				"fx_left":
					var ns := clampi(_fx_start0 + df, 0, _fx_start0 + _fx_len0 - 1)
					_drag_fx["start"] = ns
					_drag_fx["length"] = _fx_len0 - (ns - _fx_start0)
				"fx_right":
					_drag_fx["length"] = maxi(1, _fx_len0 + df)
			queue_redraw()
			frame_requested.emit(int(_drag_fx["start"]) if _drag != "fx_right" else int(_drag_fx["start"]) + int(_drag_fx["length"]) - 1)


func _press(pos: Vector2) -> void:
	if pos.y < _ruler_h():
		_drag = "scrub"
		frame_requested.emit(_frame_at(pos.x))
		return
	if pos.y < _ruler_h() + _shot_h():
		var f := _frame_at(pos.x)
		for i in range(_sched.size() - 1, -1, -1):
			var s: Dictionary = _sched[i]
			if f >= int(s["start"]) and f < int(s["start"]) + int(s["length"]):
				selected = int(s["index"])
				selected_fx = ""
				entry_selected.emit(selected)
				_drag = "shot"
				_drag_index = selected
				_drag_x = pos.x
				queue_redraw()
				return
		return
	# effect clips (topmost row first)
	var lanes := VideoFx.lanes(episode.effects)
	for i in range(episode.effects.size() - 1, -1, -1):
		var fx: Dictionary = episode.effects[i]
		var r := _fx_rect(fx, int(lanes.get(str(fx.get("id", "")), 0)))
		if r.grow(UI.px(3)).has_point(pos):
			selected_fx = str(fx.get("id", ""))
			effect_selected.emit(selected_fx)
			_drag_fx = fx
			_fx_before = episode.effects.duplicate(true)
			_fx_start0 = int(fx.get("start", 0))
			_fx_len0 = int(fx.get("length", 1))
			_drag_x = pos.x
			var edge := UI.px(7)
			if pos.x - r.position.x < edge:
				_drag = "fx_left"
			elif r.end.x - pos.x < edge:
				_drag = "fx_right"
			else:
				_drag = "fx_move"
			queue_redraw()
			return
	# soundtrack clips
	var my := _music_y()
	var row_h := UI.px(30)
	var fps: int = App.project.fps
	for ti in episode.audio_tracks.size():
		var t: AudioTrackData = episode.audio_tracks[ti]
		var y := my + UI.px(4) + ti * (row_h + UI.px(4))
		for c in t.clips:
			var rect := Rect2(_x(c.start_frame), y, c.length * fps * frame_w, row_h)
			if rect.has_point(pos):
				_drag = "music"
				_drag_clip = c
				_before = c.to_dict()
				_drag_x = pos.x
				return


func _release(pos: Vector2) -> void:
	if _drag == "shot" and _drag_index >= 0 and absf(pos.x - _drag_x) > UI.px(6):
		var target := _drop_index(pos.x)
		if target > _drag_index:
			target -= 1
		if target != _drag_index:
			Ops.move_entry(episode, _drag_index, target)
			selected = target
			entry_selected.emit(selected)
	elif _drag == "music" and _drag_clip != null:
		Ops.commit_clip_edit(_drag_clip, _before)
	elif _drag.begins_with("fx_") and not _drag_fx.is_empty():
		var label := "Move effect" if _drag == "fx_move" else "Trim effect"
		_drag_fx = {}
		Ops.commit_effects(episode, _fx_before, label)
	_drag = ""
	_drag_index = -1
	_drag_clip = null
	queue_redraw()
