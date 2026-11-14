class_name EpisodeWorkspace
extends Control
## Episode production: assemble scenes (by reference — edits flow through),
## title cards and credits into an episode with trims, transitions and text
## overlays; plan with the storyboard and shot list; preview the whole
## episode with sound; render it to one MP4.

var depth_workspace: DepthWorkspace
var episode: EpisodeData = null
var _export_dialog: ExportDialog
var selected: int = -1

var _ep_list: VBoxContainer
var _ep_title: LineEdit
var _ep_number: SpinBox
var _ep_status: OptionButton
var _ep_desc: TextEdit
var _ep_info: Label
var _views: Dictionary = {}
var _view_buttons: Dictionary = {}
var _storyboard: HFlowContainer
var _shotlist: GridContainer
var _strip: EpisodeStrip
var _props: VBoxContainer
var _time_label: Label
var _play_btn: Button
var _preview_rect: TextureRect
var _comp: EpisodeCompositor
var _feed: SceneFeed
var _frozen: ImageTexture
var _last_primary: String = ""
var _frame: int = 0
var _playing: bool = false
var _play_start_usec: int = 0
var _play_start_frame: int = 0
var _renderer: EpisodeRenderer
var _render_btn: Button
var _render_mp4: CheckBox
var _render_progress: ProgressBar
var _render_status: Label
var _render_dialog: FileDialog
var _music_dialog: FileDialog
var _add_scene_menu: MenuButton
var _syncing: bool = false


func _ready() -> void:
	var root := UI.hbox(10)
	UI.full_rect(root)
	add_child(root)
	_build_left(root)

	var center := UI.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	center.add_child(HintBar.new("episode", "An episode is a running order of your scenes (linked, not copied — edit a scene and the episode updates), plus title cards and credits. Drag shots in the strip to reorder, pick a shot to set its trim, transition and on-screen text, add music that runs across scenes, then press Play to watch the whole episode with sound."))
	var bar := UI.hbox(6)
	center.add_child(bar)
	var group := ButtonGroup.new()
	for v in [["preview", "Preview", "render"], ["storyboard", "Storyboard", "layers"], ["shots", "Shot list", "menu"]]:
		var b := UI.button(str(v[1]), str(v[2]), "", "TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_show_view.bind(str(v[0])))
		bar.add_child(b)
		_view_buttons[v[0]] = b
	bar.add_child(UI.spacer())
	_add_scene_menu = MenuButton.new()
	_add_scene_menu.text = "+ Scene"
	_add_scene_menu.flat = false
	_add_scene_menu.tooltip_text = "Add a scene to the episode (after the selected shot)"
	_add_scene_menu.about_to_popup.connect(_fill_scene_menu)
	_add_scene_menu.get_popup().index_pressed.connect(_on_add_scene)
	bar.add_child(_add_scene_menu)
	var add_title := UI.button("+ Title", "", "Add a title card after the selected shot")
	add_title.pressed.connect(func() -> void: _add_entry(EpisodeData.new_title_entry("Title")))
	bar.add_child(add_title)
	var add_credits := UI.button("+ Credits", "", "Add scrolling end credits")
	add_credits.pressed.connect(func() -> void: _add_entry(EpisodeData.new_title_entry("#Credits\n\nDirected by - You", true)))
	bar.add_child(add_credits)
	var add_music := UI.button("+ Music…", "audio", "Add music or sound that runs across scenes (starts at the playhead)")
	add_music.pressed.connect(func() -> void:
		if episode != null:
			_music_dialog.popup_centered_ratio(0.6))
	bar.add_child(add_music)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(stack)
	# preview
	var pv := PanelContainer.new()
	pv.theme_type_variation = "CanvasFrame"
	UI.full_rect(pv)
	stack.add_child(pv)
	_preview_rect = TextureRect.new()
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.add_child(_preview_rect)
	_views["preview"] = pv
	# storyboard
	var sb_scroll := ScrollContainer.new()
	UI.full_rect(sb_scroll)
	sb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(sb_scroll)
	_storyboard = HFlowContainer.new()
	_storyboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storyboard.add_theme_constant_override("h_separation", int(UI.px(12)))
	_storyboard.add_theme_constant_override("v_separation", int(UI.px(12)))
	sb_scroll.add_child(_storyboard)
	_views["storyboard"] = sb_scroll
	# shot list
	var sl_scroll := ScrollContainer.new()
	UI.full_rect(sl_scroll)
	stack.add_child(sl_scroll)
	_shotlist = GridContainer.new()
	_shotlist.columns = 7
	_shotlist.add_theme_constant_override("h_separation", int(UI.px(18)))
	_shotlist.add_theme_constant_override("v_separation", int(UI.px(8)))
	sl_scroll.add_child(_shotlist)
	_views["shots"] = sl_scroll

	var transport := UI.hbox(4)
	center.add_child(transport)
	var first := UI.icon_button("first", "Start of episode")
	first.pressed.connect(func() -> void: _seek(0))
	transport.add_child(first)
	var prev := UI.icon_button("prev", "Previous shot")
	prev.pressed.connect(func() -> void: _jump_shot(-1))
	transport.add_child(prev)
	_play_btn = UI.icon_button("play", "Play the episode with sound")
	_play_btn.pressed.connect(_toggle_play)
	transport.add_child(_play_btn)
	var next := UI.icon_button("next", "Next shot")
	next.pressed.connect(func() -> void: _jump_shot(1))
	transport.add_child(next)
	_time_label = UI.label("", "ValueLabel")
	transport.add_child(_time_label)
	transport.add_child(UI.spacer())
	var fit := UI.button("Fit", "fit", "Fit the whole episode in the strip", "FlatButton")
	fit.pressed.connect(func() -> void: _strip.fit())
	transport.add_child(fit)
	var strip_card := PanelContainer.new()
	strip_card.theme_type_variation = "Section"
	center.add_child(strip_card)
	_strip = EpisodeStrip.new()
	_strip.custom_minimum_size.y = UI.px(190)
	strip_card.add_child(_strip)
	_strip.entry_selected.connect(_select)
	_strip.frame_requested.connect(func(f: int) -> void:
		_stop()
		_seek(f))

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = UI.px(320)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(side_scroll)
	_props = UI.vbox(10)
	_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(_props)

	_comp = EpisodeCompositor.new()
	add_child(_comp)
	_feed = SceneFeed.new()
	add_child(_feed)
	_comp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_frozen = ImageTexture.new()
	_renderer = EpisodeRenderer.new()
	add_child(_renderer)
	_renderer.progress.connect(_on_render_progress)
	_renderer.finished.connect(_on_render_finished)

	_music_dialog = FileDialog.new()
	_music_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_music_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_music_dialog.use_native_dialog = true
	_music_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio"])
	_music_dialog.file_selected.connect(func(path: String) -> void:
		var err: String = Ops.import_episode_audio(episode, path, _frame)
		if err != "":
			App.status(err))
	add_child(_music_dialog)
	_render_dialog = FileDialog.new()
	_render_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_render_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_render_dialog.use_native_dialog = true
	_render_dialog.title = "Choose an output folder for the episode"
	_render_dialog.dir_selected.connect(_start_render)
	add_child(_render_dialog)

	for sig: Signal in [App.project_opened, App.episodes_changed, App.audio_changed]:
		sig.connect(_refresh)
	for sig: Signal in [App.pixels_changed, App.layers_changed, App.timeline_changed]:
		sig.connect(_on_scene_content_changed)
	visibility_changed.connect(_on_visibility)
	_show_view("preview")
	_refresh()


# ================================================================ left: episodes

func _build_left(root: Control) -> void:
	var left := PanelContainer.new()
	left.theme_type_variation = "Sidebar"
	left.custom_minimum_size.x = UI.px(250)
	root.add_child(left)
	var lv := UI.vbox(8)
	left.add_child(lv)
	var head := UI.hbox(4)
	lv.add_child(head)
	var t := UI.label("EPISODES", "SectionTitle")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var add := UI.icon_button("plus", "New episode (title card + every scene + credits)")
	add.pressed.connect(func() -> void:
		var ep := Ops.add_episode()
		if ep != null:
			episode = ep
			_refresh())
	head.add_child(add)
	var dup := UI.icon_button("copy", "Duplicate episode")
	dup.pressed.connect(func() -> void:
		if episode != null:
			episode = Ops.duplicate_episode(episode)
			_refresh())
	head.add_child(dup)
	var del := UI.icon_button("trash", "Delete episode (scenes are kept)")
	del.pressed.connect(func() -> void:
		if episode != null:
			Ops.delete_episode(episode))
	head.add_child(del)
	_ep_list = UI.vbox(3)
	lv.add_child(_ep_list)
	lv.add_child(HSeparator.new())
	lv.add_child(UI.label("Title", "FieldLabel"))
	_ep_title = LineEdit.new()
	_ep_title.text_submitted.connect(func(v: String) -> void: _ep_set("title", v.strip_edges()))
	_ep_title.focus_exited.connect(func() -> void: _ep_set("title", _ep_title.text.strip_edges()))
	lv.add_child(_ep_title)
	var row := UI.hbox(6)
	lv.add_child(row)
	row.add_child(UI.label("No.", "FieldLabel"))
	_ep_number = UI.spin(0, 999, 1, 1)
	_ep_number.value_changed.connect(func(v: float) -> void: _ep_set("number", int(v)))
	row.add_child(_ep_number)
	_ep_status = UI.option(EpisodeData.STATUSES)
	_ep_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ep_status.tooltip_text = "Production status"
	_ep_status.item_selected.connect(func(i: int) -> void: _ep_set("status", EpisodeData.STATUSES[i]))
	row.add_child(_ep_status)
	lv.add_child(UI.label("Description", "FieldLabel"))
	_ep_desc = TextEdit.new()
	_ep_desc.custom_minimum_size.y = UI.px(80)
	_ep_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_ep_desc.focus_exited.connect(func() -> void: _ep_set("description", _ep_desc.text))
	lv.add_child(_ep_desc)
	_ep_info = UI.label("", "Small")
	_ep_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_ep_info)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(spacer)
	lv.add_child(UI.label("EXPORT EPISODE", "SectionTitle"))
	_render_mp4 = CheckBox.new()
	_render_mp4.visible = false
	lv.add_child(_render_mp4)
	_render_btn = UI.button("Export episode…", "render", "Choose resolution, frame rate, quality and format, then export every shot with transitions, titles and the soundtrack", "AccentButton")
	_render_btn.pressed.connect(_choose_render)
	lv.add_child(_render_btn)
	_render_progress = ProgressBar.new()
	_render_progress.visible = false
	_render_progress.show_percentage = false
	_render_progress.custom_minimum_size.y = UI.px(6)
	lv.add_child(_render_progress)
	_render_status = UI.label("", "Small")
	_render_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_render_status)


func _ep_set(prop: String, value: Variant) -> void:
	if _syncing or episode == null:
		return
	if prop == "title" and str(value) == "":
		return
	Ops.set_episode_prop(episode, prop, value, "Episode %s" % prop)


# ================================================================ refresh

func _refresh() -> void:
	if not App.has_project():
		episode = null
		return
	var list := App.project.episodes
	if episode == null or not list.has(episode):
		episode = list[0] if not list.is_empty() else null
	_syncing = true
	for c in _ep_list.get_children():
		c.queue_free()
	for ep in list:
		var b := UI.button("%d. %s" % [ep.number, ep.title], "", ep.status, "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = ep == episode
		b.pressed.connect(func() -> void:
			_stop()
			episode = ep
			selected = -1
			_refresh())
		_ep_list.add_child(b)
	if list.is_empty():
		_ep_list.add_child(UI.label("No episodes yet — click + to create one from your scenes.", "Small"))
	if episode != null:
		if not _ep_title.has_focus():
			_ep_title.text = episode.title
		_ep_number.set_value_no_signal(episode.number)
		_ep_status.select(maxi(0, EpisodeData.STATUSES.find(episode.status)))
		if not _ep_desc.has_focus():
			_ep_desc.text = episode.description
		var sched := episode.schedule(App.project)
		var total := EpisodeData.total_frames(sched)
		var secs := total / float(App.project.fps)
		_ep_info.text = "%d shots · %d:%02d · %d frames at %d fps" % [episode.entries.size(), int(secs) / 60, int(secs) % 60, total, App.project.fps]
		selected = clampi(selected, -1, episode.entries.size() - 1)
	_syncing = false
	_strip.selected = selected
	_strip.set_episode(episode)
	_frame = clampi(_frame, 0, maxi(0, _total() - 1))
	_strip.playhead = _frame
	_rebuild_storyboard()
	_rebuild_shotlist()
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not _props.is_ancestor_of(focus):
		_rebuild_props()
	_update_time()
	if is_visible_in_tree() and not _playing:
		_render_preview()


func _on_scene_content_changed() -> void:
	if _playing or not is_visible_in_tree():
		return
	_strip.invalidate_thumbs()


func _on_visibility() -> void:
	# Only spend GPU time on the preview viewports while the workspace is shown.
	var mode := SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	_comp.render_target_update_mode = mode
	_feed.render_target_update_mode = mode
	if is_visible_in_tree():
		_strip.invalidate_thumbs()
		_refresh()
		_strip.fit.call_deferred()
	else:
		_stop()


func _show_view(v: String) -> void:
	for k in _views.keys():
		var c: Control = _views[k]
		c.visible = k == v
		var b: Button = _view_buttons[k]
		b.set_pressed_no_signal(k == v)


func _total() -> int:
	if episode == null or not App.has_project():
		return 0
	return EpisodeData.total_frames(episode.schedule(App.project))


func _update_time() -> void:
	if not App.has_project():
		return
	var fps: int = App.project.fps
	var t := _frame / float(fps)
	var total := _total() / float(fps)
	_time_label.text = "%d:%05.2f / %d:%05.2f" % [int(t) / 60, fmod(t, 60.0), int(total) / 60, fmod(total, 60.0)]


# ================================================================ storyboard & shot list

func _entry_label(e: Dictionary) -> String:
	match str(e.get("type", "")):
		"scene":
			var s := EpisodeData._find_scene(App.project, str(e.get("scene_id", "")))
			return s.name if s != null else "(missing scene)"
		"credits":
			return "Credits"
		_:
			return "Title: " + str(e.get("text", "")).split("\n")[0]


func _rebuild_storyboard() -> void:
	for c in _storyboard.get_children():
		c.queue_free()
	if episode == null:
		return
	var sched := episode.schedule(App.project)
	var fps: int = App.project.fps
	for item in sched:
		var s: Dictionary = item
		var e: Dictionary = s["entry"]
		var idx: int = s["index"]
		var card := PanelContainer.new()
		card.theme_type_variation = "SceneCardSelected" if idx == selected else "SceneCard"
		card.custom_minimum_size.x = UI.px(230)
		card.gui_input.connect(_on_card_input.bind(idx))
		var v := UI.vbox(6)
		card.add_child(v)
		var thumb_h := UI.px(120)
		var scene: SceneData = s["scene"]
		if scene != null:
			var tr := TextureRect.new()
			tr.texture = Thumbs.scene_frame(scene, int(e.get("trim_in", 0)), 200, maxi(1, int(200.0 * App.project.height / App.project.width)))
			tr.custom_minimum_size = Vector2(UI.px(210), thumb_h)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(tr)
		else:
			var cr := ColorRect.new()
			cr.color = Color.from_string(str(e.get("bg", "101116ff")), Color.BLACK)
			cr.custom_minimum_size = Vector2(UI.px(210), thumb_h)
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var l := UI.label(str(e.get("text", "")).split("\n")[0], "Heading")
			l.add_theme_color_override("font_color", Color.from_string(str(e.get("color", "ffffffff")), Color.WHITE))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			UI.full_rect(l)
			cr.add_child(l)
			v.add_child(cr)
		var name_l := UI.label("%d. %s" % [idx + 1, _entry_label(e)], "Heading")
		name_l.clip_text = true
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name_l)
		var meta := UI.label("%.1fs · in: %s" % [int(s["length"]) / float(fps), EpisodeData.TRANSITION_LABELS.get(str(e.get("transition", "cut")), "Cut")], "Small")
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(meta)
		var notes := LineEdit.new()
		notes.theme_type_variation = "FlatLineEdit"
		notes.placeholder_text = "Notes / action / dialogue"
		notes.text = str(e.get("notes", ""))
		notes.text_submitted.connect(func(txt: String) -> void: Ops.set_entry_field(episode, idx, "notes", txt))
		notes.focus_exited.connect(func() -> void: Ops.set_entry_field(episode, idx, "notes", notes.text))
		v.add_child(notes)
		_storyboard.add_child(card)


func _on_card_input(event: InputEvent, idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_select(idx)
		if mb.double_click:
			_show_view("preview")


func _rebuild_shotlist() -> void:
	for c in _shotlist.get_children():
		c.queue_free()
	if episode == null:
		return
	for h in ["#", "Shot", "Type", "Starts", "Length", "Transition in", "Notes"]:
		_shotlist.add_child(UI.label(h.to_upper(), "SectionTitle"))
	var fps: int = App.project.fps
	for item in episode.schedule(App.project):
		var s: Dictionary = item
		var e: Dictionary = s["entry"]
		var idx: int = s["index"]
		var start_s := int(s["start"]) / float(fps)
		var cells := [
			str(idx + 1), _entry_label(e), str(e.get("type", "")).capitalize(),
			"%d:%05.2f" % [int(start_s) / 60, fmod(start_s, 60.0)],
			"%.2fs (%d fr)" % [int(s["length"]) / float(fps), int(s["length"])],
			str(EpisodeData.TRANSITION_LABELS.get(str(e.get("transition", "cut")), "Cut")),
			str(e.get("notes", "")),
		]
		for i in cells.size():
			var b := UI.button(str(cells[i]), "", "", "FlatButton")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if idx == selected:
				b.add_theme_color_override("font_color", Palette.ACCENT)
			b.pressed.connect(_select.bind(idx))
			_shotlist.add_child(b)


# ================================================================ shot properties

func _select(idx: int) -> void:
	selected = idx
	_strip.selected = idx
	_strip.queue_redraw()
	if episode != null and idx >= 0:
		var sched := episode.schedule(App.project)
		if idx < sched.size():
			var s: Dictionary = sched[idx]
			_stop()
			_seek(int(s["start"]))
	_rebuild_props()
	_rebuild_storyboard()
	_rebuild_shotlist()


func _add_entry(entry: Dictionary) -> void:
	if episode == null:
		App.status("Create an episode first")
		return
	var at := selected + 1 if selected >= 0 else episode.entries.size()
	Ops.add_entry(episode, entry, at)
	selected = at
	_refresh()


func _fill_scene_menu() -> void:
	var pm := _add_scene_menu.get_popup()
	pm.clear()
	for s in App.project.scenes:
		pm.add_item(s.name)
	pm.add_separator()
	pm.add_item("All scenes, in order")


func _on_add_scene(i: int) -> void:
	if episode == null:
		App.status("Create an episode first")
		return
	var scenes := App.project.scenes
	if i < scenes.size():
		_add_entry(EpisodeData.new_scene_entry(scenes[i].id))
	else:
		for s in scenes:
			Ops.add_entry(episode, EpisodeData.new_scene_entry(s.id))
		_refresh()


func _rebuild_props() -> void:
	for c in _props.get_children():
		c.queue_free()
	if episode == null:
		return
	if selected < 0 or selected >= episode.entries.size():
		var sec := UI.section(_props, "Shot")
		var l := UI.label("Select a shot in the strip, storyboard or shot list.", "Small")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sec.add_child(l)
		return
	var e: Dictionary = episode.entries[selected]
	var idx := selected
	var type := str(e.get("type", ""))
	var sec := UI.section(_props, "Shot %d" % (idx + 1))
	var tools := UI.hbox(4)
	sec.add_child(tools)
	var left := UI.icon_button("prev", "Move earlier")
	left.pressed.connect(func() -> void:
		Ops.move_entry(episode, idx, idx - 1)
		_select(maxi(0, idx - 1)))
	tools.add_child(left)
	var right := UI.icon_button("next", "Move later")
	right.pressed.connect(func() -> void:
		Ops.move_entry(episode, idx, idx + 1)
		_select(mini(episode.entries.size() - 1, idx + 1)))
	tools.add_child(right)
	var dup := UI.icon_button("copy", "Duplicate shot")
	dup.pressed.connect(func() -> void: Ops.duplicate_entry(episode, idx))
	tools.add_child(dup)
	tools.add_child(UI.spacer())
	var rm := UI.button("Remove", "trash", "Remove from the episode (the scene itself is kept)", "FlatButton")
	rm.pressed.connect(func() -> void:
		Ops.remove_entry(episode, idx)
		selected = -1
		_refresh())
	tools.add_child(rm)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(UI.px(10)))
	grid.add_theme_constant_override("v_separation", int(UI.px(8)))
	sec.add_child(grid)

	if type == "scene":
		grid.add_child(UI.label("Scene", "FieldLabel"))
		var so := OptionButton.new()
		so.focus_mode = Control.FOCUS_NONE
		var cur := 0
		for i in App.project.scenes.size():
			so.add_item(App.project.scenes[i].name)
			if App.project.scenes[i].id == str(e.get("scene_id", "")):
				cur = i
		so.select(cur)
		so.item_selected.connect(func(i: int) -> void: _set_field(idx, "scene_id", App.project.scenes[i].id))
		grid.add_child(so)
		_spin_field(grid, idx, "Trim start", "trim_in", 0, 100000, " fr")
		_spin_field(grid, idx, "Trim end", "trim_out", 0, 100000, " fr")
	else:
		grid.add_child(UI.label("Text", "FieldLabel"))
		var te := TextEdit.new()
		te.text = str(e.get("text", ""))
		te.custom_minimum_size.y = UI.px(110 if type == "credits" else 60)
		te.focus_exited.connect(func() -> void: _set_field(idx, "text", te.text))
		te.tooltip_text = "Credits: one line each. “#Heading” for a heading, “Role - Name” for two columns." if type == "credits" else ""
		grid.add_child(te)
		if type == "title":
			grid.add_child(UI.label("Subtitle", "FieldLabel"))
			var st := LineEdit.new()
			st.text = str(e.get("subtitle", ""))
			st.text_submitted.connect(func(v: String) -> void: _set_field(idx, "subtitle", v))
			st.focus_exited.connect(func() -> void: _set_field(idx, "subtitle", st.text))
			grid.add_child(st)
			_option_field(grid, idx, "Style", "preset", EpisodeData.TITLE_PRESETS)
			_option_field(grid, idx, "Animation", "animation", EpisodeData.TITLE_ANIMS)
		_spin_field(grid, idx, "Duration", "duration", 1, 100000, " fr")
		grid.add_child(UI.label("Background", "FieldLabel"))
		var bg := ColorPickerButton.new()
		bg.color = Color.from_string(str(e.get("bg", "101116ff")), Color.BLACK)
		bg.custom_minimum_size = UI.size2(60, 30)
		bg.popup_closed.connect(func() -> void: _set_field(idx, "bg", bg.color.to_html(true)))
		grid.add_child(bg)
		grid.add_child(UI.label("Text color", "FieldLabel"))
		var fg := ColorPickerButton.new()
		fg.color = Color.from_string(str(e.get("color", "ffffffff")), Color.WHITE)
		fg.custom_minimum_size = UI.size2(60, 30)
		fg.popup_closed.connect(func() -> void: _set_field(idx, "color", fg.color.to_html(true)))
		grid.add_child(fg)

	var tsec := UI.section(_props, "Transition into this shot")
	var tg := GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", int(UI.px(10)))
	tg.add_theme_constant_override("v_separation", int(UI.px(8)))
	tsec.add_child(tg)
	var labels := []
	for tname in EpisodeData.TRANSITIONS:
		labels.append(EpisodeData.TRANSITION_LABELS[tname])
	tg.add_child(UI.label("Type", "FieldLabel"))
	var to := UI.option(labels, maxi(0, EpisodeData.TRANSITIONS.find(str(e.get("transition", "cut")))))
	to.item_selected.connect(func(i: int) -> void: _set_field(idx, "transition", EpisodeData.TRANSITIONS[i]))
	tg.add_child(to)
	_spin_field(tg, idx, "Length", "transition_frames", 1, 240, " fr")

	if type == "scene":
		var osec := UI.section(_props, "On-screen text")
		var oh := UI.label("Lower third (name + role on two lines), subtitle or caption over this shot.", "Small")
		oh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		osec.add_child(oh)
		var ot := TextEdit.new()
		ot.text = str(e.get("overlay_text", ""))
		ot.custom_minimum_size.y = UI.px(56)
		ot.focus_exited.connect(func() -> void: _set_field(idx, "overlay_text", ot.text))
		osec.add_child(ot)
		var og := GridContainer.new()
		og.columns = 2
		og.add_theme_constant_override("h_separation", int(UI.px(10)))
		og.add_theme_constant_override("v_separation", int(UI.px(8)))
		osec.add_child(og)
		_option_field(og, idx, "Style", "overlay_style", EpisodeData.OVERLAY_STYLES)
		_spin_field(og, idx, "From frame", "overlay_start", 0, 100000, "")
		_spin_field(og, idx, "To frame", "overlay_end", 0, 100000, "")
		var open := UI.button("Open this scene in Animate", "film", "", "FlatButton")
		open.pressed.connect(func() -> void:
			var s := EpisodeData._find_scene(App.project, str(e.get("scene_id", "")))
			if s != null:
				_stop()
				App.set_scene(App.project.scenes.find(s))
				App.workspace_requested.emit("animate"))
		osec.add_child(open)

	if not episode.audio_tracks.is_empty():
		var msec := UI.section(_props, "Episode soundtrack")
		for t in episode.audio_tracks:
			var row := UI.hbox(4)
			var nl := UI.label("♪ " + t.name)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.clip_text = true
			row.add_child(nl)
			var mute := UI.icon_button("eye_off" if t.muted else "eye", "Mute / unmute")
			mute.pressed.connect(func() -> void: Ops.set_audio_prop(t, "muted", not t.muted, "Mute %s" % t.name))
			row.add_child(mute)
			var del := UI.icon_button("trash", "Remove from the episode")
			del.pressed.connect(func() -> void: Ops.delete_episode_track(episode, t))
			row.add_child(del)
			msec.add_child(row)
			UI.slider(msec, "Volume", -40, 12, 0.5, t.volume_db, _on_track_volume.bind(t), "%+.1f dB")


func _on_track_volume(v: float, t: AudioTrackData) -> void:
	Ops.set_audio_prop(t, "volume_db", v, "Episode music volume")


func _set_field(idx: int, field: String, value: Variant) -> void:
	if episode != null:
		Ops.set_entry_field(episode, idx, field, value)


func _spin_field(grid: Control, idx: int, title: String, field: String, min_v: float, max_v: float, suffix: String) -> void:
	grid.add_child(UI.label(title, "FieldLabel"))
	var e: Dictionary = episode.entries[idx]
	var sp := UI.spin(min_v, max_v, 1, int(e.get(field, 0)), suffix)
	sp.value_changed.connect(func(v: float) -> void: _set_field(idx, field, int(v)))
	grid.add_child(sp)


func _option_field(grid: Control, idx: int, title: String, field: String, values: Array) -> void:
	grid.add_child(UI.label(title, "FieldLabel"))
	var e: Dictionary = episode.entries[idx]
	var labels := []
	for v in values:
		labels.append(str(v).replace("_", " ").capitalize())
	var o := UI.option(labels, maxi(0, values.find(str(e.get(field, values[0])))))
	o.item_selected.connect(func(i: int) -> void: _set_field(idx, field, values[i]))
	grid.add_child(o)


# ================================================================ preview & playback

func _ensure_preview_setup() -> void:
	if depth_workspace == null or depth_workspace.depth == null:
		return
	var p := App.project
	var k := minf(1.0, 960.0 / maxf(1.0, float(p.width)))
	var w := int(p.width * k)
	var h := int(p.height * k)
	if _comp.size != Vector2i(w, h):
		_comp.setup(w, h)
	if _feed.depth == null or _feed.size != Vector2i(w, h):
		_feed.setup(depth_workspace.depth, w, h)
		_feed.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	_preview_rect.texture = _comp.get_texture()


func _seek(f: int) -> void:
	_frame = clampi(f, 0, maxi(0, _total() - 1))
	_strip.playhead = _frame
	_strip.queue_redraw()
	_update_time()
	_render_preview()


func _jump_shot(dir: int) -> void:
	if episode == null:
		return
	var sched := episode.schedule(App.project)
	if sched.is_empty():
		return
	var cur := 0
	for i in sched.size():
		var s: Dictionary = sched[i]
		if _frame >= int(s["start"]):
			cur = i
	var target := clampi(cur + dir, 0, sched.size() - 1)
	_select(target)


func _render_preview() -> void:
	if episode == null or not App.has_project() or depth_workspace == null:
		return
	_ensure_preview_setup()
	var sched := episode.schedule(App.project)
	if sched.is_empty():
		_comp.set_picture(_comp.slot_a, null)
		_comp.compose({"a": null, "b": null}, "", "", 0.0)
		return
	var st := EpisodeData.frame_state(sched, _frame)
	var ov_text := ""
	var ov_style := "lower_third"
	var ov_alpha := 0.0
	var a_state: Variant = st["a"]
	if a_state != null:
		var sd: Dictionary = a_state
		var sch: Dictionary = sd["sched"]
		var e: Dictionary = sch["entry"]
		var key := str(e.get("id", ""))
		if key != _last_primary and _last_primary != "" and _feed.depth != null:
			# Freeze the outgoing picture for dissolves/wipes in the live preview.
			var img := _feed.get_texture().get_image()
			if img != null and not img.is_empty():
				_frozen.set_image(img)
		_last_primary = key
		var scene: SceneData = sch["scene"]
		if str(e.get("type", "")) == "scene":
			if scene != null:
				_feed.show_scene_frame(App.project.scenes.find(scene), int(sd["local"]))
				_comp.set_picture(_comp.slot_a, _feed.get_texture())
				ov_text = str(e.get("overlay_text", ""))
				ov_style = str(e.get("overlay_style", "lower_third"))
				ov_alpha = EpisodeRenderer.overlay_alpha(e, _frame - int(sch["start"]))
				Audio.external_time = int(sd["local"]) / float(App.project.fps) if _playing else Audio.external_time
			else:
				_comp.set_picture(_comp.slot_a, null)
		else:
			_comp.set_title(_comp.slot_a, e, int(sd["local"]), App.project.fps)
			if _playing:
				Audio.external_time = 1.0e9  # silence scene audio during title cards
	var b_state: Variant = st["b"]
	if b_state != null:
		var bd: Dictionary = b_state
		var bsch: Dictionary = bd["sched"]
		var be: Dictionary = bsch["entry"]
		if str(be.get("type", "")) == "scene":
			_comp.set_picture(_comp.slot_b, _frozen)
		else:
			_comp.set_title(_comp.slot_b, be, int(bd["local"]), App.project.fps)
	_comp.compose(st, ov_text, ov_style, ov_alpha)


func _toggle_play() -> void:
	if _playing:
		_stop()
	else:
		_play()


func _play() -> void:
	if episode == null or _total() <= 0:
		return
	_show_view("preview")
	if _frame >= _total() - 1:
		_frame = 0
	App.stop()
	_playing = true
	_play_start_frame = _frame
	_play_start_usec = Time.get_ticks_usec()
	Audio.begin_external(episode)
	_play_btn.icon = Icons.tex("pause")


func _stop() -> void:
	if not _playing:
		return
	_playing = false
	Audio.end_external()
	_play_btn.icon = Icons.tex("play")


func _process(_delta: float) -> void:
	if not _playing or not App.has_project():
		return
	var elapsed := (Time.get_ticks_usec() - _play_start_usec) / 1000000.0
	var f := _play_start_frame + int(elapsed * App.project.fps)
	var total := _total()
	if f >= total:
		_stop()
		_seek(total - 1)
		return
	Audio.episode_time = (_play_start_frame / float(App.project.fps)) + elapsed
	if f != _frame:
		_frame = f
		_strip.playhead = f
		_strip.queue_redraw()
		_update_time()
		_render_preview()


# ================================================================ render

func _choose_render() -> void:
	open_export()


## Opens the CapCut-style Export sheet for this episode.
func open_export() -> void:
	if episode == null:
		App.status("Create an episode first")
		return
	_stop()
	if _export_dialog == null:
		_export_dialog = ExportDialog.new()
		add_child(_export_dialog)
	_export_dialog.open_episode(_renderer, episode)


func _choose_render_folder() -> void:
	if _renderer.busy:
		_renderer.cancel()
		return
	if episode == null:
		return
	_stop()
	var d := App.project.root_dir.path_join("renders").path_join(("episode_%02d" % episode.number))
	DirAccess.make_dir_recursive_absolute(d)
	_render_dialog.current_dir = d
	_render_dialog.popup_centered_ratio(0.6)


func _start_render(dir: String) -> void:
	if depth_workspace == null or depth_workspace.depth == null:
		App.status("The 3D stage isn't ready yet — open the Depth workspace once, then try again")
		return
	_render_progress.visible = true
	_render_btn.text = "Cancel render"
	_renderer.render(episode, depth_workspace.depth, dir, _render_mp4.button_pressed)


func _on_render_progress(done: int, total: int, message: String) -> void:
	_render_progress.max_value = total
	_render_progress.value = done
	_render_status.text = message


func _on_render_finished(ok: bool, message: String, _output: String) -> void:
	_render_progress.visible = false
	_render_btn.text = "Export episode…"
	_render_status.text = message
