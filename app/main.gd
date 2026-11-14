extends Control
## MainApplication: builds the window shell (top bar, workspaces, status bar),
## routes keyboard shortcuts and handles save/quit flows.

const WORKSPACES := [
	["home", "Home", "home"],
	["capture", "Capture", "camera"],
	["characters", "Characters", "character"],
	["draw", "Draw", "brush"],
	["animate", "Animate", "film"],
	["depth", "Depth", "cube"],
	["audio", "Audio", "audio"],
	["scenes", "Scenes", "layers"],
	["episode", "Episode", "clapper"],
]

var _workspaces: Dictionary = {}
var _tabs: Dictionary = {}
var _current: String = ""
var _home: HomeWorkspace
var _title: Label
var _status: Label
var _info: Label
var _status_timer: Timer
var _save_btn: Button
var _undo_btn: Button
var _export_btn: Button
var _redo_btn: Button
var _menu: MenuButton
var _quit_dialog: ConfirmationDialog
var _save_as_dialog: FileDialog
var _error: AcceptDialog
var _video_dialog: VideoImportDialog


func _ready() -> void:
	UI.init_scale(float(ProjectIO.get_setting("ui_scale", 0.0)))
	var t := ThemeBuilder.build()
	theme = t
	get_tree().root.theme = t
	RenderingServer.set_default_clear_color(Palette.BG)
	get_tree().set_auto_accept_quit(false)
	get_window().min_size = Vector2i(int(UI.px(1280)), int(UI.px(720)))
	get_window().title = "Strata Animation Studio"
	UI.full_rect(self)
	_build()
	App.project_opened.connect(_on_project_state)
	App.project_closed.connect(_on_project_state)
	App.modified_changed.connect(_update_title)
	App.scene_switched.connect(_update_info)
	App.frame_changed.connect(_update_info)
	App.layer_selected.connect(_update_info)
	App.layers_changed.connect(_update_info)
	App.status_message.connect(_show_status)
	App.workspace_requested.connect(switch_to)
	get_window().files_dropped.connect(_on_files_dropped)
	_on_project_state()
	switch_to("home")
	_show_status("Welcome to Strata. Create a project or open one to begin.")


func _build() -> void:
	var bg := Panel.new()
	UI.full_rect(bg)
	add_child(bg)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	UI.full_rect(root)
	add_child(root)

	# ---------------------------------------------------------- top bar
	var top := PanelContainer.new()
	top.theme_type_variation = "TopBar"
	root.add_child(top)
	var bar := UI.hbox(6)
	top.add_child(bar)
	var logo := TextureRect.new()
	logo.texture = Icons.tex("logo", 26)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bar.add_child(logo)
	bar.add_child(UI.label("Strata", "Brand"))
	var gap := Control.new()
	gap.custom_minimum_size.x = UI.px(18)
	bar.add_child(gap)
	var group := ButtonGroup.new()
	for w in WORKSPACES:
		var b := UI.button(w[1], w[2], "", "TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(switch_to.bind(w[0]))
		bar.add_child(b)
		_tabs[w[0]] = b
	bar.add_child(UI.spacer())
	_title = UI.label("", "Muted")
	bar.add_child(_title)
	bar.add_child(UI.vsep())
	_undo_btn = UI.icon_button("undo", "Undo (Ctrl+Z)")
	_undo_btn.pressed.connect(_undo)
	bar.add_child(_undo_btn)
	_redo_btn = UI.icon_button("redo", "Redo (Ctrl+Shift+Z)")
	_redo_btn.pressed.connect(_redo)
	bar.add_child(_redo_btn)
	_menu = MenuButton.new()
	_menu.icon = Icons.tex("menu")
	_menu.tooltip_text = "Project"
	_menu.flat = false
	var pm := _menu.get_popup()
	pm.add_item("New / open project…", 0)
	pm.add_separator()
	pm.add_item("Save   (Ctrl+S)", 1)
	pm.add_item("Save as…   (Ctrl+Shift+S)", 2)
	pm.add_item("Show project folder", 3)
	pm.add_separator()
	pm.add_item("Close project", 4)
	pm.id_pressed.connect(_on_menu)
	bar.add_child(_menu)
	_export_btn = UI.button("Export", "render", "Export a video of this scene (or the episode, in Episode) — Ctrl+E", "Button")
	_export_btn.pressed.connect(open_export)
	bar.add_child(_export_btn)
	_save_btn = UI.button("Save", "save", "Save project (Ctrl+S)", "AccentButton")
	_save_btn.pressed.connect(save)
	bar.add_child(_save_btn)

	# ---------------------------------------------------------- content
	var content_margin := MarginContainer.new()
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		content_margin.add_theme_constant_override("margin_" + side, int(UI.px(10)))
	root.add_child(content_margin)
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content)
	_home = HomeWorkspace.new()
	var ws := {
		"home": _home,
		"capture": CaptureWorkspace.new(),
		"characters": CharacterWorkspace.new(),
		"draw": StudioWorkspace.new(false),
		"animate": StudioWorkspace.new(true),
		"depth": DepthWorkspace.new(),
		"audio": AudioWorkspace.new(),
		"scenes": SceneWorkspace.new(),
		"episode": EpisodeWorkspace.new(),
	}
	(ws["episode"] as EpisodeWorkspace).depth_workspace = ws["depth"]
	for id in ws.keys():
		var c: Control = ws[id]
		UI.full_rect(c)
		c.visible = false
		content.add_child(c)
		_workspaces[id] = c

	# ---------------------------------------------------------- status bar
	var status := PanelContainer.new()
	status.theme_type_variation = "StatusBar"
	root.add_child(status)
	var sb := UI.hbox(12)
	status.add_child(sb)
	_status = UI.label("", "Small")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	sb.add_child(_status)
	_info = UI.label("", "Small")
	sb.add_child(_info)
	_status_timer = Timer.new()
	_status_timer.one_shot = true
	_status_timer.wait_time = 6.0
	_status_timer.timeout.connect(func() -> void: _status.text = "")
	add_child(_status_timer)

	# ---------------------------------------------------------- dialogs
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Unsaved changes"
	_quit_dialog.dialog_text = "Save your changes before quitting?"
	_quit_dialog.ok_button_text = "Save and quit"
	_quit_dialog.add_button("Quit without saving", true, "discard")
	_quit_dialog.confirmed.connect(func() -> void:
		if save():
			get_tree().quit())
	_quit_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			get_tree().quit())
	add_child(_quit_dialog)
	_save_as_dialog = FileDialog.new()
	_save_as_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_save_as_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_as_dialog.use_native_dialog = true
	_save_as_dialog.title = "Save project as — choose an empty folder"
	_save_as_dialog.dir_selected.connect(_save_as_to)
	add_child(_save_as_dialog)
	_error = AcceptDialog.new()
	_error.title = "Strata"
	add_child(_error)
	_video_dialog = VideoImportDialog.new()
	add_child(_video_dialog)
	App.video_import_requested.connect(func(path: String) -> void: _video_dialog.open(path))


# ================================================================ workspaces

func switch_to(id: String) -> void:
	if not _workspaces.has(id):
		return
	if App.has_project() and not workspaces_for(App.project.mode).has(id):
		id = "draw"
	if id != "home" and not App.has_project():
		id = "home"
	if id == _current:
		var tab: Button = _tabs[id]
		tab.set_pressed_no_signal(true)
		return
	App.stop()
	for k in _workspaces.keys():
		var c: Control = _workspaces[k]
		c.visible = k == id
	_current = id
	var b: Button = _tabs[id]
	b.set_pressed_no_signal(true)


## Applies any floating selection first so undo never fights with it.
func _commit_all_floating() -> void:
	for id in ["draw", "animate", "characters"]:
		var c: CanvasView = null
		var ws: Control = _workspaces[id]
		if ws is StudioWorkspace:
			c = (ws as StudioWorkspace).canvas
		elif ws is CharacterWorkspace:
			c = (ws as CharacterWorkspace).canvas
		if c != null:
			c.commit_floating()


func _undo() -> void:
	_commit_all_floating()
	History.undo()


func _redo() -> void:
	_commit_all_floating()
	History.redo()


func _active_canvas() -> CanvasView:
	var ws: Control = _workspaces.get(_current)
	if ws is StudioWorkspace:
		return (ws as StudioWorkspace).canvas
	if ws is CharacterWorkspace:
		return (ws as CharacterWorkspace).canvas
	return null


func _on_project_state() -> void:
	var has := App.has_project()
	for id in _tabs.keys():
		var b: Button = _tabs[id]
		b.disabled = id != "home" and not has
		if b.disabled:
			b.tooltip_text = "Create or open a project first"
		else:
			b.tooltip_text = ""
	_save_btn.disabled = not has
	_export_btn.disabled = not has
	_apply_project_kind()
	var pm := _menu.get_popup()
	for id in [1, 2, 3, 4]:
		pm.set_item_disabled(pm.get_item_index(id), not has)
	if not has:
		switch_to("home")
	_update_title()
	_update_info()


## CapCut-style Export: the episode in Episode, otherwise the current scene.
func open_export() -> void:
	if not App.has_project():
		return
	if _current == "episode":
		var ew: Node = _workspaces["episode"]
		if ew.has_method("open_export"):
			ew.call("open_export")
			return
	var anim: Node = _workspaces["animate"]
	anim.call("open_export")


## Which workspaces a kind of project uses.
static func workspaces_for(mode: String) -> Array:
	match mode:
		"2d":
			return ["home", "characters", "draw", "animate", "audio", "scenes", "episode"]
		"stopmotion":
			return ["home", "capture", "draw", "animate", "audio", "scenes", "episode"]
	return ["home", "characters", "draw", "animate", "depth", "audio", "scenes", "episode"]


## Shows only the tabs this project uses (all but Capture when none is open).
func _apply_project_kind() -> void:
	var mode := App.project.mode if App.has_project() else "2d3d"
	var used := workspaces_for(mode)
	for id in _tabs.keys():
		var b: Button = _tabs[id]
		b.visible = used.has(id)
	if _current != "" and not used.has(_current):
		switch_to("draw" if App.has_project() else "home")


# ---------------------------------------------------------------- touch: long-press = right-click

var _lp_index: int = -1
var _lp_pos: Vector2 = Vector2.ZERO
var _lp_timer: Timer = null


## On touch screens, holding a finger still for a moment acts as a
## right-click (context menus, colour swatch options).
func _input(event: InputEvent) -> void:
	if not Platform.is_mobile():
		return
	var st := event as InputEventScreenTouch
	if st != null:
		if st.pressed and _lp_index < 0:
			_lp_index = st.index
			_lp_pos = st.position
			if _lp_timer == null:
				_lp_timer = Timer.new()
				_lp_timer.one_shot = true
				_lp_timer.wait_time = 0.55
				_lp_timer.timeout.connect(_long_press)
				add_child(_lp_timer)
			_lp_timer.start()
		elif st.pressed:
			_cancel_long_press()  # a second finger: it's a gesture
		elif st.index == _lp_index:
			_cancel_long_press()
		return
	var sd := event as InputEventScreenDrag
	if sd != null and sd.index == _lp_index and sd.position.distance_to(_lp_pos) > UI.px(12):
		_cancel_long_press()


func _cancel_long_press() -> void:
	_lp_index = -1
	if _lp_timer != null:
		_lp_timer.stop()


func _long_press() -> void:
	if _lp_index < 0:
		return
	_lp_index = -1
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		mb.pressed = pressed
		mb.position = _lp_pos
		mb.global_position = _lp_pos
		Input.parse_input_event(mb)


func _update_title() -> void:
	if not App.has_project():
		_title.text = "No project open"
		get_window().title = "Strata Animation Studio"
		return
	var mark := "  •  unsaved" if App.modified else ""
	_title.text = App.project.name + mark
	get_window().title = "%s%s — Strata" % [App.project.name, " *" if App.modified else ""]


func _update_info() -> void:
	if not App.has_project():
		_info.text = ""
		return
	var s := App.current_scene()
	var l := App.current_layer()
	_info.text = "%s  ·  %s  ·  frame %d / %d  ·  %d fps  ·  %d × %d" % [
		s.name, l.name if l != null else "no layer", App.frame + 1, s.frame_count,
		App.project.fps, App.project.width, App.project.height]


func _show_status(text: String) -> void:
	_status.text = text
	_status_timer.start()


## Drag & drop: audio files go to the Audio Studio, images become layers.
func _on_files_dropped(files: PackedStringArray) -> void:
	if not App.has_project():
		_show_status("Create or open a project first, then drop files onto the window")
		return
	var audio_count := 0
	for f in files:
		var ext := f.get_extension().to_lower()
		var err := ""
		if Audio.is_audio_file(f):
			err = Ops.import_audio(f)
			if err == "":
				audio_count += 1
		elif ext in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]:
			err = Ops.import_image(f, false)
		elif VideoImportDialog.is_video_file(f):
			_video_dialog.open(f)
		else:
			err = "Can't import “%s” (unsupported type)" % f.get_file()
		if err != "":
			_show_status(err.replace("\n", " "))
	if audio_count > 0:
		switch_to("audio")


# ================================================================ save / menu

func save() -> bool:
	if not App.has_project():
		return false
	_commit_all_floating()
	var err: String = ProjectIO.save_project()
	if err != "":
		_show_error(err)
		return false
	_show_status("Saved to " + App.project.root_dir)
	return true


func _save_as_to(dir: String) -> void:
	var err: String = ProjectIO.save_project_as(dir)
	if err != "":
		_show_error(err)
	else:
		_show_status("Saved a copy to " + dir + " — you're now working in the copy")
		_update_title()


func _show_error(message: String) -> void:
	_error.dialog_text = message
	_error.popup_centered()


func _on_menu(id: int) -> void:
	match id:
		0:
			switch_to("home")
		1:
			save()
		2:
			_save_as_dialog.popup_centered_ratio(0.6)
		3:
			if App.has_project():
				Platform.reveal(App.project.root_dir)
		4:
			if App.modified:
				save()
			App.close_project()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if App.has_project() and App.modified:
			_quit_dialog.popup_centered()
		else:
			get_tree().quit()


# ================================================================ shortcuts

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var ctrl := k.ctrl_pressed or k.meta_pressed
	var handled := true
	if ctrl:
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
			KEY_C:
				var c := _active_canvas()
				if c != null:
					c.copy_selection()
				else:
					handled = false
			KEY_X:
				var c := _active_canvas()
				if c != null:
					c.cut_selection()
				else:
					handled = false
			KEY_V:
				var c := _active_canvas()
				if c != null:
					c.paste()
				else:
					handled = false
			KEY_A:
				var c := _active_canvas()
				if c != null:
					c.select_all()
				else:
					handled = false
			KEY_D:
				var c := _active_canvas()
				if c != null:
					c.deselect()
				else:
					handled = false
			KEY_S:
				if k.shift_pressed:
					if App.has_project():
						_save_as_dialog.popup_centered_ratio(0.6)
				else:
					save()
			KEY_O:
				switch_to("home")
				_home.open_dialog()
			KEY_E:
				open_export()
			KEY_0:
				var c := _active_canvas()
				if c != null:
					c.fit_view()
			KEY_1:
				var c := _active_canvas()
				if c != null:
					c.set_zoom(1.0)
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
		return
	if not App.has_project() or _current == "home":
		return
	var canvas := _active_canvas()
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if k.echo:
				pass
			elif canvas != null and canvas.floating != null:
				canvas.commit_floating()
			else:
				App.toggle_play()
		KEY_ESCAPE:
			if canvas != null and canvas.floating != null:
				canvas.cancel_floating()
			elif canvas != null and canvas.has_selection():
				canvas.deselect()
			else:
				handled = false
		KEY_DELETE, KEY_BACKSPACE:
			if canvas != null and canvas.has_selection():
				canvas.delete_selection()
			else:
				handled = false
		KEY_COMMA:
			App.stop()
			App.step_frame(-1)
		KEY_PERIOD:
			App.stop()
			App.step_frame(1)
		KEY_HOME:
			App.set_frame(0)
		KEY_END:
			App.set_frame(App.frame_count() - 1)
		KEY_N:
			if not k.echo:
				Ops.new_drawing()
		KEY_D:
			if not k.echo:
				Ops.duplicate_drawing()
		KEY_M:
			if not k.echo:
				Ops.toggle_marker()
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			Ops.insert_frame()
		KEY_MINUS, KEY_KP_SUBTRACT:
			Ops.remove_frame()
		KEY_BRACKETLEFT:
			App.brush_size = maxf(1.0, App.brush_size / 1.2)
			App.brush_changed.emit()
		KEY_BRACKETRIGHT:
			App.brush_size = minf(300.0, App.brush_size * 1.2)
			App.brush_changed.emit()
		_:
			handled = _tool_key(k)
	if handled:
		get_viewport().set_input_as_handled()


func _tool_key(k: InputEventKey) -> bool:
	if k.echo or not (_current in ["draw", "animate", "characters"]):
		return false
	var map := {
		KEY_B: "brush", KEY_P: "pencil", KEY_E: "eraser", KEY_G: "fill", KEY_I: "picker",
		KEY_L: "line", KEY_U: "rect", KEY_O: "ellipse", KEY_V: "move", KEY_H: "hand",
		KEY_S: "select", KEY_A: "lasso",
	}
	if map.has(k.keycode):
		App.set_tool(map[k.keycode])
		return true
	return false
