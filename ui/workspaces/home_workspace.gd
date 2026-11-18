class_name HomeWorkspace
extends Control
## Project dashboard: create a project, open existing ones, a quick-start
## guide for beginners and interface settings.

const RESOLUTIONS := [
	["HD — 1280 × 720", 1280, 720],
	["Full HD — 1920 × 1080", 1920, 1080],
	["QHD — 2560 × 1440", 2560, 1440],
	["4K UHD — 3840 × 2160", 3840, 2160],
	["Square — 1080 × 1080", 1080, 1080],
	["Vertical — 1080 × 1920", 1080, 1920],
]
const FPS := [12, 15, 24, 25, 30]
const UI_SCALES := [["Automatic", 0.0], ["75%", 0.75], ["90%", 0.9], ["100%", 1.0], ["125%", 1.25], ["150%", 1.5], ["175%", 1.75], ["200%", 2.0]]
const STEPS := [
	["Draw", "Create a project, then draw your character and background on separate layers in Draw."],
	["Animate", "In Animate, add drawings frame by frame with onion skin, and retime them in the timeline."],
	["Stage in 3D", "In Depth, push the background far back and bring props forward — the layers become planes in 3D."],
	["Move the camera", "Pick a camera preset or set keys to pan, dolly and zoom. Parallax happens automatically."],
	["Render", "Render the scene through its camera to PNG frames (and MP4 when FFmpeg is available)."],
]

var _name_edit: LineEdit
var _res: OptionButton
var _fps: OptionButton
var _loc: LineEdit
var _recent: VBoxContainer
var _open_dialog: FileDialog
var _dir_dialog: FileDialog
var _error: AcceptDialog
var _ff_status: Label
var _ff_dialog: FileDialog


const PROJECT_KINDS := [
	["2d", "2D", "brush", "Draw and animate frame by frame, with layers,\nonion skin, characters and sound."],
	["2d3d", "2D + 3D", "cube", "Everything in 2D, plus the Depth stage: place\nlayers in 3D, build sets, light and move a camera."],
	["stopmotion", "Stop motion", "camera", "Shoot frames with a camera (or add photos),\nwith onion skin, then draw over them like 2D."],
]
var _kind: String = "2d"
var _kind_btns: Dictionary = {}


var _upd_status: Label
var _upd_check: Button
var _upd_install: Button
var _upd_page: Button
var _upd_timer_on: bool = false

func _ready() -> void:
	var scroll := ScrollContainer.new()
	UI.full_rect(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(UI.px(40)))
	margin.add_theme_constant_override("margin_top", int(UI.px(28)))
	margin.add_theme_constant_override("margin_bottom", int(UI.px(28)))
	scroll.add_child(margin)
	var col := UI.vbox(22)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	# ---------------------------------------------------------- hero
	var hero := UI.hbox(18)
	col.add_child(hero)
	var logo := TextureRect.new()
	logo.texture = Icons.tex("logo", 64)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	hero.add_child(logo)
	var hv := UI.vbox(2)
	hero.add_child(hv)
	hv.add_child(UI.label("Strata", "Title"))
	hv.add_child(UI.label("Make 2D animation, 2D with a real 3D stage, or stop motion — all in one place.", "Lead"))

	# ---------------------------------------------------------- new / open
	var row := UI.hbox(18)
	col.add_child(row)

	var new_card := _card(row, "Start a new project")
	(new_card.get_parent() as Control).size_flags_stretch_ratio = 1.4
	new_card.add_child(UI.label("WHAT ARE YOU MAKING?", "SectionTitle"))
	var kinds := UI.hbox(10)
	new_card.add_child(kinds)
	var kind_group := ButtonGroup.new()
	for k in PROJECT_KINDS:
		var b := Button.new()
		b.text = "%s\n%s" % [str(k[1]), str(k[3])]
		b.icon = Icons.tex(str(k[2]), 28)
		b.toggle_mode = true
		b.button_group = kind_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = UI.size2(150, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "TabButton"
		b.button_pressed = k[0] == _kind
		b.pressed.connect(_set_kind.bind(str(k[0])))
		kinds.add_child(b)
		_kind_btns[str(k[0])] = b
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", int(UI.px(14)))
	form.add_theme_constant_override("v_separation", int(UI.px(10)))
	new_card.add_child(form)
	form.add_child(UI.label("Name", "FieldLabel"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "My Animation"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_name_edit)
	form.add_child(UI.label("Canvas", "FieldLabel"))
	var res_names := []
	for r in RESOLUTIONS:
		res_names.append(r[0])
	_res = UI.option(res_names, 1)
	_res.tooltip_text = "Every drawing is stored at this size. 4K uses about 33 MB of memory per loaded drawing."
	form.add_child(_res)
	form.add_child(UI.label("Frame rate", "FieldLabel"))
	var fps_names := []
	for f in FPS:
		fps_names.append("%d fps%s" % [f, "  (classic animation)" if f == 12 else ""])
	_fps = UI.option(fps_names, 2)
	form.add_child(_fps)
	form.add_child(UI.label("Location", "FieldLabel"))
	var loc_row := UI.hbox(6)
	loc_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(loc_row)
	_loc = LineEdit.new()
	_loc.text = ProjectIO.default_projects_dir()
	_loc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_row.add_child(_loc)
	var browse := UI.button("Browse…", "folder")
	browse.pressed.connect(func() -> void:
		_dir_dialog.current_dir = _loc.text
		_dir_dialog.popup_centered_ratio(0.6))
	loc_row.add_child(browse)
	var create := UI.button("Create project", "plus", "", "AccentButton")
	create.size_flags_horizontal = Control.SIZE_SHRINK_END
	create.pressed.connect(_on_create)
	new_card.add_child(create)

	var open_card := _card(row, "Open")
	var open_btn := UI.button("Open project…", "folder", "Open a project.strata.json file")
	open_btn.pressed.connect(func() -> void: _open_dialog.popup_centered_ratio(0.6))
	open_card.add_child(open_btn)
	open_card.add_child(UI.label("RECENT", "SectionTitle"))
	_recent = UI.vbox(2)
	open_card.add_child(_recent)

	# ---------------------------------------------------------- quick start
	var guide := _card(col, "How making a shot works")
	var steps := HFlowContainer.new()
	steps.add_theme_constant_override("h_separation", int(UI.px(14)))
	steps.add_theme_constant_override("v_separation", int(UI.px(14)))
	guide.add_child(steps)
	for i in STEPS.size():
		var box := UI.vbox(4)
		box.custom_minimum_size.x = UI.px(200)
		box.add_child(UI.label("%d  %s" % [i + 1, STEPS[i][0]], "StepNumber"))
		var body := UI.label(STEPS[i][1], "Muted")
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = UI.px(200)
		box.add_child(body)
		steps.add_child(box)
	var keys := UI.label("Shortcuts: B brush · P pencil · E eraser · G fill · I picker · L/U/O shapes · S/A select · V move · H hand · [ ] size · , . step frames · ← → previous/next drawing · ↓ ↑ next/previous frame · Ctrl/Shift-click drawings on the timeline to select several, then drag to move them · Enter play · N new drawing · D duplicate · M marker · Ctrl+C/V copy/paste · Ctrl+Z undo · Ctrl+S save", "Small")
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_child(keys)

	# ---------------------------------------------------------- settings
	var prefs := _card(col, "Interface")
	var pr := UI.hbox(10)
	prefs.add_child(pr)
	pr.add_child(UI.label("Interface size", "FieldLabel"))
	var current: float = float(ProjectIO.get_setting("ui_scale", 0.0))
	var sel := 0
	for i in UI_SCALES.size():
		if is_equal_approx(float(UI_SCALES[i][1]), current):
			sel = i
	var scale_names := []
	for sc in UI_SCALES:
		var label := str(sc[0])
		if Platform.is_mobile():
			# On phones/tablets sizes are relative to "fits the screen".
			label = "Fit screen" if float(sc[1]) <= 0.0 else label + " of fit"
		scale_names.append(label)
	var scale_opt := UI.option(scale_names, sel)
	scale_opt.item_selected.connect(func(i: int) -> void:
		ProjectIO.set_setting("ui_scale", UI_SCALES[i][1])
		App.status("Interface size changes apply the next time Strata starts" + (" (swipe it closed, then open it again)" if Platform.is_mobile() else "")))
	pr.add_child(scale_opt)
	var reset_tips := UI.button("Show all tips again", "help", "", "FlatButton")
	reset_tips.pressed.connect(func() -> void:
		for k in ["draw", "animate", "depth", "scenes"]:
			ProjectIO.set_setting("hint_hidden_" + str(k), false)
		App.status("Tips will show again the next time Strata starts"))
	pr.add_child(reset_tips)

	var ff_row := UI.hbox(10)
	prefs.add_child(ff_row)
	ff_row.add_child(UI.label("FFmpeg", "FieldLabel"))
	_ff_status = UI.label("", "Small")
	_ff_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ff_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ff_row.add_child(_ff_status)
	var ff_locate := UI.button("Locate…", "folder", "Choose the ffmpeg executable, or the folder you unzipped it to")
	ff_locate.pressed.connect(func() -> void: _ff_dialog.popup_centered_ratio(0.6))
	ff_row.add_child(ff_locate)
	var ff_detect := UI.button("Detect again", "reset", "Search common locations and PATH again", "FlatButton")
	ff_detect.pressed.connect(func() -> void:
		FFmpeg.find(true)
		_update_ffmpeg_status())
	ff_row.add_child(ff_detect)
	_ff_dialog = FileDialog.new()
	_ff_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_ff_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_ff_dialog.use_native_dialog = true
	_ff_dialog.title = "Locate ffmpeg"
	_ff_dialog.file_selected.connect(_on_ff_located)
	_ff_dialog.dir_selected.connect(_on_ff_located)
	add_child(_ff_dialog)
	_update_ffmpeg_status()

	# ---------------------------------------------------------- updates
	var upd := _card(col, "Updates")
	var ur := UI.hbox(10)
	upd.add_child(ur)
	_upd_status = UI.label("", "Small")
	_upd_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upd_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ur.add_child(_upd_status)
	_upd_check = UI.button("Check for updates", "reset", "Ask GitHub whether there's a newer build")
	_upd_check.pressed.connect(Updater.check)
	ur.add_child(_upd_check)
	_upd_install = UI.button("Install update", "save", "Download the new build, save your project, and restart into it", "AccentButton")
	_upd_install.pressed.connect(Updater.install)
	ur.add_child(_upd_install)
	_upd_page = UI.button("Open download page", "folder", "", "FlatButton")
	_upd_page.pressed.connect(func() -> void: OS.shell_open(Updater.release_page()))
	ur.add_child(_upd_page)
	var auto := CheckBox.new()
	auto.text = "Check for updates when Strata starts"
	auto.button_pressed = Updater.auto_check()
	auto.toggled.connect(func(on: bool) -> void: ProjectIO.set_setting("update_auto_check", on))
	upd.add_child(auto)
	Updater.state_changed.connect(_update_updates)
	_update_updates()

	# ---------------------------------------------------------- dialogs
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.use_native_dialog = true
	_open_dialog.title = "Open a Strata project"
	_open_dialog.filters = PackedStringArray(["*.strata.json ; Strata project"])
	_open_dialog.file_selected.connect(_open_path)
	add_child(_open_dialog)
	_dir_dialog = FileDialog.new()
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.use_native_dialog = true
	_dir_dialog.title = "Where should new projects be saved?"
	_dir_dialog.dir_selected.connect(func(d: String) -> void: _loc.text = d)
	add_child(_dir_dialog)
	_error = AcceptDialog.new()
	_error.title = "Strata"
	add_child(_error)

	visibility_changed.connect(_refresh_recent)
	App.project_opened.connect(_refresh_recent)
	_refresh_recent()


func _update_ffmpeg_status() -> void:
	var path := FFmpeg.find()
	if path != "":
		_ff_status.text = "Ready — " + path + "  (used for video import and MP4 export)"
		_ff_status.modulate = Palette.DEPTH
	else:
		_ff_status.text = "Not found. Needed for video import and MP4 export. " + FFmpeg.help_text()
		_ff_status.modulate = Palette.DANGER


func _on_ff_located(path: String) -> void:
	if FFmpeg.set_custom(path):
		App.status("FFmpeg found: " + FFmpeg.find())
	else:
		show_error("That doesn't look like a working ffmpeg:\n%s\n\n%s" % [path, FFmpeg.help_text()])
	_update_ffmpeg_status()


func _update_updates() -> void:
	var st := Updater.state
	var txt := "This is %s." % Updater.current_text()
	if Updater.message != "":
		txt += " " + Updater.message
	if st == Updater.DOWNLOADING:
		var p := Updater.progress()
		if p.y > 0:
			txt += " %d of %d MB" % [p.x / 1048576, p.y / 1048576]
		if not _upd_timer_on:
			_upd_timer_on = true
			_poll_download()
	_upd_status.text = txt
	_upd_check.disabled = Updater.busy()
	_upd_install.visible = st == Updater.AVAILABLE and Updater.can_install()
	_upd_install.disabled = Updater.busy()
	_upd_page.visible = st == Updater.AVAILABLE and not Updater.can_install() or st == Updater.FAILED


func _poll_download() -> void:
	while Updater.state == Updater.DOWNLOADING and is_inside_tree():
		_update_updates_text()
		await get_tree().create_timer(0.5).timeout
	_upd_timer_on = false


func _update_updates_text() -> void:
	var p := Updater.progress()
	_upd_status.text = "Downloading the update… %d of %d MB" % [p.x / 1048576, maxi(p.y, p.x) / 1048576] if p.y > 0 else "Downloading the update… %d MB" % (p.x / 1048576)


func _card(parent: Control, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)
	v.add_child(UI.label(title, "Heading"))
	return v


func _refresh_recent() -> void:
	if _recent == null:
		return
	for c in _recent.get_children():
		c.queue_free()
	var list := ProjectIO.recent_projects()
	if list.is_empty():
		_recent.add_child(UI.label("Projects you open will appear here.", "Small"))
		return
	for p in list:
		var path := str(p)
		var b := UI.button(path.get_base_dir().get_file(), "folder", path, "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.pressed.connect(_open_path.bind(path))
		_recent.add_child(b)


func show_error(message: String) -> void:
	_error.dialog_text = message
	_error.popup_centered()


func open_dialog() -> void:
	_open_dialog.popup_centered_ratio(0.6)


func _on_create() -> void:
	var project_name := _name_edit.text.strip_edges()
	if project_name == "":
		project_name = "My Animation"
	var r: Array = RESOLUTIONS[_res.selected]
	var err: String = ProjectIO.create_project(project_name, _loc.text.strip_edges(), int(r[1]), int(r[2]), int(FPS[_fps.selected]), _kind)
	if err != "":
		show_error(err)
		return
	_name_edit.text = ""
	App.workspace_requested.emit("capture" if _kind == "stopmotion" else "draw")


func _set_kind(kind: String) -> void:
	_kind = kind
	# Stop motion is usually shot at 12 fps (each photo held 2 frames at 24).
	if kind == "stopmotion" and FPS.has(12):
		_fps.select(FPS.find(12))


func _open_path(path: String) -> void:
	var err: String = ProjectIO.open_project(path)
	if err != "":
		show_error(err)
		return
	App.workspace_requested.emit("draw")
