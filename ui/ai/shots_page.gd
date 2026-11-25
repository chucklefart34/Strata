class_name AiShotsPage
extends Control
## Every drawing of every shot. A shot is genuine frame-by-frame animation:
## one picture per drawing, held for its exposure (ones/twos/threes).
## Here you can preview, scrub, inspect and edit each drawing, switch
## between its takes, approve or reject revisions, select several drawings
## and ask for a correction, run QC, and place the shot on the timeline.

const FPS := [12, 18, 24, 30]
const EXPOSURES := [[1, "On ones (every frame drawn)"], [2, "On twos (each drawing held 2 frames)"], [3, "On threes"]]

var ws: AiStudioWorkspace
var _list: ItemList
var _shot_ids: Array = []
var _empty: Control
var _main: Control
var _title: LineEdit
var _truth: Label
var _preview: TextureRect
var _scrub: HSlider
var _frame_label: Label
var _play: Button
var _timer: Timer
var _pframe: int = 0
var _grid: HFlowContainer
var _cards: Dictionary = {}  # index -> Button
var _sel_label: Label
var _note: LineEdit
var _bg_thumb: TextureRect
var _bg_label: Label
# inspector
var _i_title: Label
var _i_info: Label
var _i_take: Label
var _i_pose: TextEdit
var _i_expr: LineEdit
var _i_notes: LineEdit
var _i_qc: Label
var _i_review: HBoxContainer
var _view_take: int = -1
# settings
var _s_action: TextEdit
var _s_env: LineEdit
var _s_light: LineEdit
var _s_camera: LineEdit
var _s_mood: LineEdit
var _s_dialogue: LineEdit
var _s_bg: LineEdit
var _s_fps: OptionButton
var _s_exp: OptionButton
var _s_frames: SpinBox
var _s_preset: OptionButton
var _s_sep: CheckBox
var _s_guide: OptionButton
var _s_chars: VBoxContainer
var _s_keys: TextEdit
var _syncing: bool = false
var _rebuild_pending: bool = false
var _last_click: int = -1


func _ready() -> void:
	var root := UI.hbox(12)
	UI.full_rect(root)
	add_child(root)
	# ---- shot list
	var left := AiUi.sidebar(root, 240)
	var h := AiUi.head(left, "Shots")
	var add := UI.icon_button("plus", "New shot")
	add.pressed.connect(_new_shot)
	h.add_child(add)
	var del := UI.icon_button("trash", "Delete shot (its pictures stay on disk until you clear them)")
	del.pressed.connect(func() -> void:
		var sid := str(ws.selection.get("shot_id", ""))
		if sid != "":
			Studio.delete_shot(sid)
			ws.select_shot(""))
	h.add_child(del)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: ws.select_shot(str(_shot_ids[i])))
	left.add_child(_list)

	# ---- centre
	var centre := Control.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(centre)
	_empty = AiUi.wrap_label("No shot selected.\n\nAsk the Director for a scene, or press + to plan a shot yourself.", "Lead")
	UI.full_rect(_empty)
	centre.add_child(_empty)
	_main = UI.vbox(8)
	UI.full_rect(_main)
	centre.add_child(_main)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", int(UI.px(6)))
	top.add_theme_constant_override("v_separation", int(UI.px(6)))
	_main.add_child(top)
	_title = AiUi.line("", "Shot name")
	_title.custom_minimum_size.x = UI.px(220)
	_title.text_submitted.connect(func(t: String) -> void: _change({"name": t}))
	_title.focus_exited.connect(func() -> void: _change({"name": _title.text}))
	top.add_child(_title)
	for spec in [
		["Render", "render", "Queue every drawing that has no picture yet", _render_missing],
		["Redraw all", "reset", "Draw new takes of every drawing (you approve them)", _redraw_all],
		["Place on timeline", "film", "Put the shot's drawings onto layers of the current scene, starting at the playhead", _place],
		["QC", "check", "Automatic checks: flicker, pops, colour/costume drift, background changes", _qc],
		["Vision QC", "eye", "Ask the director (Claude, cloud) to look for anatomy, face and continuity problems", _vision_qc],
		["Fix flagged", "flag", "Redraw every drawing QC flagged, with what QC found as the correction", _fix_flagged],
	]:
		var b := UI.button(spec[0], spec[1], spec[2])
		b.pressed.connect(spec[3])
		top.add_child(b)
	_truth = AiUi.wrap_label("", "Small")
	_main.add_child(_truth)

	var mid := UI.hbox(10)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_child(mid)
	var pv := UI.vbox(6)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(pv)
	var frame_card := PanelContainer.new()
	frame_card.theme_type_variation = "CanvasFrame"
	frame_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(frame_card)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = UI.size2(420, 236)
	frame_card.add_child(_preview)
	var tr := UI.hbox(6)
	pv.add_child(tr)
	_play = UI.icon_button("play", "Play the shot (chosen takes, at the shot's frame rate)")
	_play.pressed.connect(_toggle_play)
	tr.add_child(_play)
	_scrub = HSlider.new()
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.value_changed.connect(func(v: float) -> void:
		_pframe = int(v)
		_show_frame())
	tr.add_child(_scrub)
	_frame_label = UI.label("", "ValueLabel")
	_frame_label.custom_minimum_size.x = UI.px(150)
	tr.add_child(_frame_label)
	_timer = Timer.new()
	_timer.timeout.connect(_tick)
	add_child(_timer)

	# ---- inspector
	var insp := AiUi.scroll(AiUi.sidebar(mid, 300))
	_i_title = UI.label("", "Heading")
	insp.add_child(_i_title)
	_i_info = AiUi.wrap_label("", "Small")
	insp.add_child(_i_info)
	var tk := UI.hbox(4)
	insp.add_child(tk)
	var prev := UI.icon_button("prev", "Previous take")
	prev.pressed.connect(func() -> void: _step_take(-1))
	tk.add_child(prev)
	_i_take = UI.label("", "ValueLabel")
	_i_take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_i_take.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tk.add_child(_i_take)
	var nxt := UI.icon_button("next", "Next take")
	nxt.pressed.connect(func() -> void: _step_take(1))
	tk.add_child(nxt)
	var use := UI.button("Use this take", "check", "Use the take you're looking at for this drawing")
	use.pressed.connect(_use_take)
	insp.add_child(use)
	_i_review = UI.hbox(4)
	insp.add_child(_i_review)
	var ap := UI.button("Approve new", "check", "Use the newest take", "AccentButton")
	ap.pressed.connect(func() -> void: _review(true))
	_i_review.add_child(ap)
	var rj := UI.button("Reject new", "close", "Throw the newest take away and keep the current one")
	rj.pressed.connect(func() -> void: _review(false))
	_i_review.add_child(rj)
	insp.add_child(UI.label("Pose", "FieldLabel"))
	_i_pose = AiUi.text("", 64)
	insp.add_child(_i_pose)
	insp.add_child(UI.label("Expression", "FieldLabel"))
	_i_expr = AiUi.line()
	insp.add_child(_i_expr)
	insp.add_child(UI.label("Notes", "FieldLabel"))
	_i_notes = AiUi.line("", "e.g. left hand open, fingers spread")
	insp.add_child(_i_notes)
	var save_d := UI.button("Save description", "save", "Keep these words for this drawing (redraw to see them)")
	save_d.pressed.connect(_save_drawing_text)
	insp.add_child(save_d)
	_i_qc = AiUi.wrap_label("", "Small")
	_i_qc.add_theme_color_override("font_color", Palette.DANGER)
	insp.add_child(_i_qc)
	var edit := UI.button("Edit in Draw", "brush", "Open this frame on the timeline to fix it by hand (place the shot first)")
	edit.pressed.connect(_edit_in_draw)
	insp.add_child(edit)

	# ---- drawings grid
	var gh := UI.hbox(6)
	_main.add_child(gh)
	_sel_label = UI.label("", "FieldLabel")
	gh.add_child(_sel_label)
	_note = AiUi.line("", "Correction for the selected drawings, e.g. “the hand looks anatomically wrong”")
	_note.text_submitted.connect(func(_t: String) -> void: _redraw_selected())
	gh.add_child(_note)
	var rs := UI.button("Redraw selected", "reset", "New takes of the selected drawings with this correction", "AccentButton")
	rs.pressed.connect(_redraw_selected)
	gh.add_child(rs)
	var apall := UI.button("Approve", "check", "Approve the new takes of the selected drawings")
	apall.pressed.connect(func() -> void: _review_selected(true))
	gh.add_child(apall)
	var rjall := UI.button("Reject", "close", "Reject the new takes of the selected drawings")
	rjall.pressed.connect(func() -> void: _review_selected(false))
	gh.add_child(rjall)
	var gsc := ScrollContainer.new()
	gsc.custom_minimum_size.y = UI.px(190)
	gsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_main.add_child(gsc)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(UI.px(6)))
	_grid.add_theme_constant_override("v_separation", int(UI.px(6)))
	gsc.add_child(_grid)

	# ---- shot settings
	var right := AiUi.sidebar(root, 330)
	AiUi.head(right, "Shot settings")
	var sv := AiUi.scroll(right)
	var g := AiUi.grid(sv, 2)
	_s_fps = AiUi.row(g, "Frame rate", UI.option(FPS.map(func(x: Variant) -> String: return "%d fps" % int(x)))) as OptionButton
	_s_exp = AiUi.row(g, "Drawings", UI.option(EXPOSURES.map(func(x: Variant) -> String: return str((x as Array)[1])))) as OptionButton
	_s_frames = AiUi.row(g, "Length", UI.spin(1, 1800, 1, 24, " frames")) as SpinBox
	_s_preset = AiUi.row(g, "Camera move", UI.option(Studio.CAMERA_PRESETS.map(func(x: Variant) -> String: return str(x).replace("_", " ")))) as OptionButton
	_s_guide = AiUi.row(g, "Pose guide", UI.option(["none"])) as OptionButton
	_s_guide.tooltip_text = "A layer with your rough drawings: keys and breakdowns follow them (ControlNet if set in Setup)."
	_s_sep = CheckBox.new()
	_s_sep.text = "Background on its own layer"
	_s_sep.tooltip_text = "The character is drawn on a flat backdrop and the background plate once: no background flicker, real layers, parallax."
	sv.add_child(_s_sep)
	sv.add_child(UI.label("Action", "FieldLabel"))
	_s_action = AiUi.text("", 60)
	sv.add_child(_s_action)
	var g2 := AiUi.grid(sv, 2)
	_s_env = AiUi.row(g2, "Setting", AiUi.line()) as LineEdit
	_s_bg = AiUi.row(g2, "Background", AiUi.line("", "empty plate description")) as LineEdit
	_s_light = AiUi.row(g2, "Lighting", AiUi.line()) as LineEdit
	_s_camera = AiUi.row(g2, "Framing", AiUi.line("", "e.g. low angle medium shot, 35mm")) as LineEdit
	_s_mood = AiUi.row(g2, "Mood", AiUi.line()) as LineEdit
	_s_dialogue = AiUi.row(g2, "Dialogue", AiUi.line()) as LineEdit
	sv.add_child(UI.label("Characters", "FieldLabel"))
	_s_chars = UI.vbox(2)
	sv.add_child(_s_chars)
	sv.add_child(UI.label("Keys & breakdowns — one per line: frame | key/breakdown | pose | expression", "FieldLabel"))
	_s_keys = AiUi.text("", 150)
	sv.add_child(_s_keys)
	var apply := UI.button("Apply settings", "check", "Save these settings. Changed timing re-plans the in-betweens; changed descriptions mark drawings out of date.", "AccentButton")
	apply.pressed.connect(_apply_settings)
	apply.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sv.add_child(apply)
	AiUi.head(sv, "Background plate")
	_bg_thumb = TextureRect.new()
	_bg_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bg_thumb.custom_minimum_size = UI.size2(280, 158)
	sv.add_child(_bg_thumb)
	_bg_label = UI.label("", "Small")
	sv.add_child(_bg_label)
	var rbg := UI.button("Redraw background", "reset", "A new background plate (the newest one is used)")
	rbg.pressed.connect(func() -> void:
		var s := _shot()
		if not s.is_empty():
			(s["background"] as Dictionary)["chosen"] = -1
			Studio.queue_shot(s, [], "", true)
			AiJobs.kick())
	sv.add_child(rbg)

	Studio.changed.connect(func(kind: String) -> void:
		if kind in ["shots", "all", "cast"]:
			_queue_rebuild())
	ws.selection_changed.connect(func() -> void:
		_view_take = -1
		_rebuild())
	App.layers_changed.connect(_fill_guides)
	_rebuild()


func refresh() -> void:
	_rebuild()


func _shot() -> Dictionary:
	return Studio.find_shot(str(ws.selection.get("shot_id", "")))


func _selected() -> Array:
	return ws.selection.get("indices", [])


func _focus_index() -> int:
	var sel := _selected()
	return int(sel[-1]) if not sel.is_empty() else -1


func _queue_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	await get_tree().process_frame
	_rebuild_pending = false
	_rebuild()


# ================================================================ refresh

func _rebuild() -> void:
	if not is_visible_in_tree() and _list.item_count == Studio.shots().size():
		return
	_list.clear()
	_shot_ids.clear()
	var sid := str(ws.selection.get("shot_id", ""))
	for s in Studio.shots():
		var sd: Dictionary = s
		var c := Studio.counts(sd)
		_list.add_item("%s   %d/%d" % [sd["name"], c["done"], c["drawings"]])
		_shot_ids.append(str(sd["id"]))
		if str(sd["id"]) == sid:
			_list.select(_list.item_count - 1)
	var s := _shot()
	_empty.visible = s.is_empty()
	_main.visible = not s.is_empty()
	if s.is_empty():
		return
	_syncing = true
	_title.text = str(s["name"])
	var c := Studio.counts(s)
	var e := int(s["exposure"])
	_truth.text = "%d frames · %d fps · %s → %d separate drawings: %d keys, %d breakdowns, %d in-betweens · %d drawn.  Every drawing is generated as its own picture (keys from the description%s; in-betweens redrawn over a guide built from the drawings on both sides — not morphs or zooms). %s" % [
		s["frames"], s["fps"], ["", "on ones", "on twos", "on threes", "on fours"][clampi(e, 1, 4)],
		c["drawings"], c["key"], c["breakdown"], c["inbetween"], c["done"],
		" or your rough" if str(s.get("guide_layer", "")) != "" else "",
		"Held frames between drawings are not drawn again." if e > 1 else ""]
	_scrub.max_value = maxi(0, int(s["frames"]) - 1)
	_pframe = clampi(_pframe, 0, int(s["frames"]) - 1)
	_scrub.set_value_no_signal(_pframe)
	_fill_settings(s)
	_build_grid(s)
	_update_inspector()
	_show_frame()
	var bgd: Dictionary = s["background"]
	var takes: Array = bgd.get("takes", [])
	var ch := int(bgd.get("chosen", -1))
	_bg_thumb.texture = AiUi.thumb(str((takes[ch] as Dictionary)["file"]), 280) if ch >= 0 and ch < takes.size() else null
	_bg_label.text = ("%d take(s) · %s" % [takes.size(), AiUi.STATUS_TEXT.get(str(bgd.get("status", "pending")), "")]) if bool(s.get("separate_background", true)) else "Background is drawn into every frame (not separated)."
	_syncing = false


func _fill_settings(s: Dictionary) -> void:
	_s_fps.select(maxi(0, FPS.find(int(s["fps"]))))
	_s_exp.select(clampi(int(s["exposure"]) - 1, 0, 2))
	_s_frames.set_value_no_signal(int(s["frames"]))
	_s_preset.select(maxi(0, Studio.CAMERA_PRESETS.find(str(s["camera_preset"]))))
	_s_sep.set_pressed_no_signal(bool(s.get("separate_background", true)))
	_s_action.text = str(s["action"])
	_s_env.text = str(s["environment"])
	_s_bg.text = str((s["background"] as Dictionary).get("prompt", ""))
	_s_light.text = str(s["lighting"])
	_s_camera.text = str(s["camera"])
	_s_mood.text = str(s["mood"])
	_s_dialogue.text = str(s["dialogue"])
	for ch in _s_chars.get_children():
		ch.queue_free()
	for c in Studio.cast():
		var cd: Dictionary = c
		var cb := CheckBox.new()
		cb.text = str(cd["name"])
		cb.set_pressed_no_signal((s["characters"] as Array).has(str(cd["id"])))
		cb.set_meta("id", str(cd["id"]))
		_s_chars.add_child(cb)
	if Studio.cast().is_empty():
		_s_chars.add_child(UI.label("No characters yet — add them in Cast.", "Small"))
	var lines: Array[String] = []
	for d in s["drawings"]:
		var dd: Dictionary = d
		if str(dd["kind"]) != "inbetween":
			lines.append("%d | %s | %s | %s" % [int(dd["frame"]), dd["kind"], dd["pose"], dd["expression"]])
	_s_keys.text = "\n".join(lines)
	_fill_guides()


func _fill_guides() -> void:
	if _s_guide == null:
		return
	_s_guide.clear()
	_s_guide.add_item("none")
	var s := _shot()
	var cur := str(s.get("guide_layer", "")) if not s.is_empty() else ""
	if App.has_project():
		for l in App.current_scene().layers:
			if not l.is_character() and not l.name.begins_with("AI "):
				_s_guide.add_item(l.name)
				if l.name == cur:
					_s_guide.select(_s_guide.item_count - 1)


func _build_grid(s: Dictionary) -> void:
	for ch in _grid.get_children():
		ch.queue_free()
	_cards.clear()
	var sel := _selected()
	for d in s["drawings"]:
		var dd: Dictionary = d
		var i := int(dd["index"])
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = UI.size2(112, 86)
		b.icon = AiUi.thumb(AiUi.take_file(dd), 96)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var flags := ""
		if bool(dd.get("review", false)):
			flags += " ★"
		if not FrameQC.issues(dd).is_empty():
			flags += " ⚑"
		b.text = "F%d %s%s" % [int(dd["frame"]) + 1, AiUi.KIND_SHORT.get(str(dd["kind"]), "?"), flags]
		b.add_theme_font_size_override("font_size", int(UI.px(11)))
		b.add_theme_color_override("font_color", AiUi.KIND_COLORS.get(str(dd["kind"]), Palette.TEXT))
		b.add_theme_color_override("font_pressed_color", Palette.TEXT)
		b.tooltip_text = "Frame %d · %s · %s%s\n%s" % [int(dd["frame"]) + 1, dd["kind"], AiUi.STATUS_TEXT.get(str(dd.get("status", "pending")), ""),
			"\n★ a new take is waiting for your approval" if bool(dd.get("review", false)) else "", str(dd["pose"]).left(200)]
		if str(dd.get("status", "")) in ["queued", "rendering"]:
			b.modulate = Color(1, 1, 1, 0.55)
		elif str(dd.get("status", "")) == "failed":
			b.modulate = Color(1, 0.6, 0.6)
		b.set_pressed_no_signal(sel.has(i))
		b.pressed.connect(_on_card.bind(i))
		_grid.add_child(b)
		_cards[i] = b
	var n := sel.size()
	_sel_label.text = "%d selected" % n if n > 0 else "Click a drawing (Ctrl/Shift = several)"


func _on_card(i: int) -> void:
	var sel := _selected().duplicate()
	if Input.is_key_pressed(KEY_SHIFT) and _last_click >= 0:
		for k in range(mini(_last_click, i), maxi(_last_click, i) + 1):
			if not sel.has(k):
				sel.append(k)
	elif Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		if sel.has(i):
			sel.erase(i)
		else:
			sel.append(i)
	else:
		sel = [i]
	_last_click = i
	var s := _shot()
	var d := Studio.drawing(s, i)
	if not d.is_empty():
		_pframe = int(d["frame"])
	ws.select_shot(str(s["id"]), sel)


# ================================================================ preview

func _toggle_play() -> void:
	var s := _shot()
	if s.is_empty():
		return
	if _timer.is_stopped():
		_timer.wait_time = 1.0 / float(int(s["fps"]))
		_timer.start()
		_play.icon = Icons.tex("pause")
	else:
		_timer.stop()
		_play.icon = Icons.tex("play")


func _tick() -> void:
	var s := _shot()
	if s.is_empty() or not is_visible_in_tree():
		_timer.stop()
		_play.icon = Icons.tex("play")
		return
	_pframe = (_pframe + 1) % maxi(1, int(s["frames"]))
	_scrub.set_value_no_signal(_pframe)
	_show_frame()


func _show_frame() -> void:
	var s := _shot()
	if s.is_empty():
		return
	var d := Studio.drawing_at(s, _pframe)
	var rel := AiUi.take_file(d)
	var playing := not _timer.is_stopped()
	if not playing and _focus_index() >= 0 and int(d.get("index", -1)) == _focus_index() and _view_take >= 0:
		var takes: Array = d.get("takes", [])
		if _view_take < takes.size():
			rel = str((takes[_view_take] as Dictionary)["file"])
	_preview.texture = AiUi.thumb(rel, 900)
	var held := "" if int(d.get("frame", -1)) == _pframe else "  (held)"
	_frame_label.text = "frame %d / %d%s" % [_pframe + 1, int(s["frames"]), held]
	# background shown behind? the preview shows the drawing as generated.


# ================================================================ inspector

func _update_inspector() -> void:
	var s := _shot()
	var d := Studio.drawing(s, _focus_index())
	if d.is_empty():
		_i_title.text = "No drawing selected"
		_i_info.text = "Click a drawing below."
		_i_take.text = ""
		_i_pose.text = ""
		_i_expr.text = ""
		_i_notes.text = ""
		_i_qc.text = ""
		_i_review.visible = false
		return
	var takes: Array = d.get("takes", [])
	if _view_take < 0 or _view_take >= takes.size():
		_view_take = int(d.get("chosen", -1))
	_i_title.text = "Frame %d · %s" % [int(d["frame"]) + 1, str(d["kind"])]
	var src := ""
	if _view_take >= 0 and _view_take < takes.size():
		var tk: Dictionary = takes[_view_take]
		src = "\nTake from: %s%s\nSeed %s" % [str(tk.get("source", "text")), (" · correction: " + str(tk["note"])) if str(tk.get("note", "")) != "" else "", str(tk.get("seed", ""))]
	var what := {"key": "Key pose — an extreme of the action.", "breakdown": "Breakdown — shapes the arc between keys.",
		"inbetween": "In-between — redrawn over a guide made from the drawings on both sides (the figure moved along its path, or a blend)."}
	_i_info.text = "%s\nStatus: %s%s%s" % [what.get(str(d["kind"]), ""), AiUi.STATUS_TEXT.get(str(d.get("status", "pending")), ""),
		("\nError: " + str(d["error"])) if d.has("error") else "", src]
	_i_take.text = "take %d of %d%s" % [_view_take + 1, takes.size(), " (in use)" if _view_take == int(d.get("chosen", -1)) else ""] if not takes.is_empty() else "no takes yet"
	_i_pose.text = str(d["pose"])
	_i_expr.text = str(d["expression"])
	_i_notes.text = str(d.get("notes", ""))
	var iss := FrameQC.issues(d)
	_i_qc.text = ("QC: " + "\n• ".join(PackedStringArray(iss.map(func(x: Variant) -> String: return str(x))))) if not iss.is_empty() else ""
	_i_review.visible = bool(d.get("review", false))


func _step_take(delta: int) -> void:
	var d := Studio.drawing(_shot(), _focus_index())
	var takes: Array = d.get("takes", [])
	if takes.is_empty():
		return
	_view_take = posmod(_view_take + delta, takes.size())
	_pframe = int(d["frame"])
	_scrub.set_value_no_signal(_pframe)
	_update_inspector()
	_show_frame()


func _use_take() -> void:
	var d := Studio.drawing(_shot(), _focus_index())
	if d.is_empty() or _view_take < 0:
		return
	Studio.approve_take(d, _view_take)


func _review(approve: bool) -> void:
	var d := Studio.drawing(_shot(), _focus_index())
	if d.is_empty():
		return
	if approve:
		Studio.approve_take(d)
	else:
		Studio.reject_take(d)
	_view_take = -1


func _review_selected(approve: bool) -> void:
	var s := _shot()
	var n := 0
	for i in _selected():
		var d := Studio.drawing(s, int(i))
		if bool(d.get("review", false)):
			if approve:
				Studio.approve_take(d)
			else:
				Studio.reject_take(d)
			n += 1
	App.status("%s %d new take(s)" % ["Approved" if approve else "Rejected", n])


func _save_drawing_text() -> void:
	var d := Studio.drawing(_shot(), _focus_index())
	if d.is_empty():
		return
	d["pose"] = _i_pose.text.strip_edges()
	d["expression"] = _i_expr.text.strip_edges()
	d["notes"] = _i_notes.text.strip_edges()
	Studio.touch("shots")
	App.status("Saved. Use Redraw selected to draw it with the new description.")


func _edit_in_draw() -> void:
	var s := _shot()
	var d := Studio.drawing(s, _focus_index())
	var placed: Dictionary = s.get("placed", {})
	if d.is_empty() or placed.is_empty():
		App.status("Place the shot on the timeline first, then you can draw over any frame.")
		return
	App.set_frame(int(placed["start"]) + int(round(int(d["frame"]) * float(App.project.fps) / int(s["fps"]))))
	var scene := App.current_scene()
	for i in scene.layers.size():
		if scene.layers[i].id == str(placed.get("layer", "")):
			App.set_layer(i)
	App.workspace_requested.emit("draw")


# ================================================================ actions

func _change(changes: Dictionary) -> void:
	var s := _shot()
	if s.is_empty() or _syncing:
		return
	Studio.update_shot(str(s["id"]), changes)


func _new_shot() -> void:
	var s := Studio.create_shot({"name": "Shot %d" % (Studio.shots().size() + 1), "frames": 24,
		"fps": App.project.fps if [12, 18, 24, 30].has(App.project.fps) else 24, "exposure": 2,
		"action": "", "keys": []})
	ws.select_shot(str(s["id"]))


func _apply_settings() -> void:
	var s := _shot()
	if s.is_empty():
		return
	var chars: Array = []
	for cb in _s_chars.get_children():
		if cb is CheckBox and (cb as CheckBox).button_pressed:
			chars.append(str(cb.get_meta("id")))
	var keys: Array = []
	for ln in _s_keys.text.split("\n", false):
		var parts := ln.split("|")
		if parts.size() < 3 or not parts[0].strip_edges().is_valid_int():
			continue
		keys.append({"frame": int(parts[0].strip_edges()), "kind": parts[1].strip_edges().to_lower(), "pose": parts[2].strip_edges(),
			"expression": parts[3].strip_edges() if parts.size() > 3 else "", "notes": ""})
	var changes := {
		"fps": FPS[_s_fps.selected], "exposure": int((EXPOSURES[_s_exp.selected] as Array)[0]), "frames": int(_s_frames.value),
		"camera_preset": Studio.CAMERA_PRESETS[_s_preset.selected], "separate_background": _s_sep.button_pressed,
		"action": _s_action.text.strip_edges(), "environment": _s_env.text.strip_edges(), "background": _s_bg.text.strip_edges(),
		"lighting": _s_light.text.strip_edges(), "camera": _s_camera.text.strip_edges(), "mood": _s_mood.text.strip_edges(),
		"dialogue": _s_dialogue.text.strip_edges(), "characters": chars,
		"guide_layer": "" if _s_guide.selected <= 0 else _s_guide.get_item_text(_s_guide.selected),
	}
	if not keys.is_empty():
		changes["keys"] = keys
	Studio.update_shot(str(s["id"]), changes)
	App.status("Shot settings saved. Out-of-date drawings are marked; press Render to draw them.")


func _render_missing() -> void:
	var s := _shot()
	if s.is_empty():
		return
	var n := Studio.queue_shot(s)
	AiJobs.kick()
	App.status("Queued %d picture(s)." % n if n > 0 else "Every drawing already has a picture. Use Redraw to make new takes.")


func _redraw_all() -> void:
	var s := _shot()
	if s.is_empty():
		return
	var n := Studio.queue_shot(s, [], _note.text.strip_edges(), true)
	AiJobs.kick()
	App.status("Queued %d new take(s) — approve or reject them as they arrive." % n)


func _redraw_selected() -> void:
	var s := _shot()
	if s.is_empty() or _selected().is_empty():
		App.status("Select drawings first.")
		return
	var n := Studio.queue_shot(s, _selected(), _note.text.strip_edges(), true)
	_note.text = ""
	AiJobs.kick()
	App.status("Queued %d redraw(s)." % n)


func _place() -> void:
	var s := _shot()
	if s.is_empty():
		return
	var placed: Dictionary = s.get("placed", {})
	var start: int = int(placed["start"]) if not placed.is_empty() and str(placed.get("scene", "")) == App.current_scene().id else App.frame
	App.status(Studio.place_shot(s, start))


func _qc() -> void:
	var s := _shot()
	if s.is_empty():
		return
	var r := FrameQC.run(s)
	App.status("QC: " + str(r["notes"]) + (" Flagged drawings show ⚑; select them to read why." if not (r["flagged"] as Array).is_empty() else ""))


func _vision_qc() -> void:
	var s := _shot()
	if s.is_empty():
		return
	App.status("The director is looking at the drawings…")
	var r: Dictionary = await AiJobs.director.review_shot(s)
	if bool(r.get("ok", false)):
		App.status("Vision QC: %s (%d flagged)" % [str(r["notes"]).left(200), (r["flagged"] as Array).size()])
		Studio.add_chat("system", "Vision QC of “%s”: %s" % [s["name"], r["notes"]])
	else:
		App.status(str(r.get("error", "")))


func _fix_flagged() -> void:
	var s := _shot()
	if s.is_empty():
		return
	var n := AiJobs.fix_flagged(s)
	App.status("Queued %d fix(es); each arrives as a new take to approve or reject." % n if n > 0 else "Nothing is flagged. Run QC first.")
