class_name ExportDialog
extends ConfirmationDialog
## The Export sheet, laid out like CapCut's: pick resolution, frame rate,
## quality and format, see the size estimate, press Export, watch the
## progress, then open or show the finished file.
##
## Works for a scene (RenderExporter.export_scene) or an episode
## (EpisodeRenderer.export_episode): call open_scene() / open_episode().

var _renderer: Node = null   # RenderExporter or EpisodeRenderer
var _episode: EpisodeData = null
var _frames: int = 0
var _has_audio: bool = false
var _opts: Dictionary = ExportSettings.defaults()
var _last_output: String = ""

var _name: LineEdit
var _groups: Dictionary = {}  # setting -> {value: Button}
var _estimate: Label
var _detail: Label
var _dir_label: Label
var _transparent: CheckBox
var _audio: CheckBox
var _note: Label
var _settings_box: VBoxContainer
var _progress_box: VBoxContainer
var _progress: ProgressBar
var _progress_label: Label
var _done_box: VBoxContainer
var _done_label: Label
var _dir_dialog: FileDialog


func _ready() -> void:
	title = "Export"
	ok_button_text = "Export"
	dialog_hide_on_ok = false
	exclusive = true
	get_ok_button().custom_minimum_size = UI.size2(160, 40)
	confirmed.connect(_on_export)
	canceled.connect(_on_cancel)

	var v := UI.vbox(12)
	v.custom_minimum_size = UI.size2(560, 0)
	add_child(v)

	_settings_box = UI.vbox(12)
	v.add_child(_settings_box)
	var name_row := UI.hbox(8)
	_settings_box.add_child(name_row)
	name_row.add_child(UI.label("Name", "FieldLabel"))
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name)

	var res_items: Array = []
	for r in ExportSettings.RESOLUTIONS:
		res_items.append([int(r[0]), str(r[1])])
	_segment("res", "Resolution", res_items)
	var fps_items: Array = []
	for f in ExportSettings.FRAME_RATES:
		fps_items.append([int(f), str(f)])
	_segment("fps", "Frame rate", fps_items)
	_segment("quality", "Quality", ExportSettings.QUALITIES)
	_segment("format", "Format", ExportSettings.FORMATS)

	var opt_row := UI.hbox(14)
	_settings_box.add_child(opt_row)
	_audio = CheckBox.new()
	_audio.text = "Include sound"
	_audio.button_pressed = true
	_audio.focus_mode = Control.FOCUS_NONE
	_audio.toggled.connect(func(on: bool) -> void:
		_opts["audio"] = on
		_update())
	opt_row.add_child(_audio)
	_transparent = CheckBox.new()
	_transparent.text = "Transparent background"
	_transparent.focus_mode = Control.FOCUS_NONE
	_transparent.tooltip_text = "PNG frames only"
	_transparent.toggled.connect(func(on: bool) -> void: _opts["transparent"] = on)
	opt_row.add_child(_transparent)

	var est_card := PanelContainer.new()
	est_card.theme_type_variation = "Section"
	_settings_box.add_child(est_card)
	var est := UI.vbox(2)
	est_card.add_child(est)
	_estimate = UI.label("", "Heading")
	est.add_child(_estimate)
	_detail = UI.label("", "Muted")
	est.add_child(_detail)

	var dir_row := UI.hbox(8)
	_settings_box.add_child(dir_row)
	dir_row.add_child(UI.label("Save to", "FieldLabel"))
	_dir_label = UI.label("", "Small")
	_dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dir_label.clip_text = true
	dir_row.add_child(_dir_label)
	var change := UI.button("Change…", "folder", "Choose where the file is saved", "FlatButton")
	change.pressed.connect(func() -> void:
		_dir_dialog.current_dir = str(_opts["dir"])
		_dir_dialog.popup_centered_ratio(0.6))
	dir_row.add_child(change)
	_note = UI.label("", "Small")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.modulate = Color("#ffd166")
	_settings_box.add_child(_note)

	_progress_box = UI.vbox(10)
	_progress_box.visible = false
	v.add_child(_progress_box)
	_progress_label = UI.label("Exporting…", "Heading")
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_box.add_child(_progress_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = UI.px(10)
	_progress.show_percentage = false
	_progress_box.add_child(_progress)
	var keep := UI.label("Keep Strata open until the export finishes.", "Small")
	keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_box.add_child(keep)

	_done_box = UI.vbox(10)
	_done_box.visible = false
	v.add_child(_done_box)
	_done_label = UI.label("", "Heading")
	_done_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_done_box.add_child(_done_label)
	var done_row := UI.hbox(8)
	_done_box.add_child(done_row)
	var play := UI.button("Open", "play", "Open the exported file", "AccentButton")
	play.pressed.connect(func() -> void:
		if _last_output != "":
			if Platform.is_mobile():
				Platform.reveal(_last_output)
			else:
				OS.shell_open(_last_output))
	done_row.add_child(play)
	var show_btn := UI.button("Show in folder", "folder", "", "Button")
	show_btn.pressed.connect(func() -> void:
		if _last_output != "":
			if Platform.is_mobile() or DirAccess.dir_exists_absolute(_last_output):
				Platform.reveal(_last_output)
			else:
				OS.shell_show_in_file_manager(_last_output))
	done_row.add_child(show_btn)
	var again := UI.button("Export another", "", "", "FlatButton")
	again.pressed.connect(func() -> void: _show_state("settings"))
	done_row.add_child(again)

	_dir_dialog = FileDialog.new()
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.use_native_dialog = true
	_dir_dialog.dir_selected.connect(func(d: String) -> void:
		_opts["dir"] = d
		_update())
	add_child(_dir_dialog)


func _segment(key: String, label: String, items: Array) -> void:
	var row := UI.vbox(4)
	_settings_box.add_child(row)
	row.add_child(UI.label(label.to_upper(), "SectionTitle"))
	var h := UI.hbox(4)
	row.add_child(h)
	var group := ButtonGroup.new()
	var buttons := {}
	for it in items:
		var item: Array = it
		var b := UI.button(str(item[1]), "", "", "FlatButton")
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = UI.px(34)
		b.pressed.connect(_pick.bind(key, item[0]))
		h.add_child(b)
		buttons[item[0]] = b
	_groups[key] = buttons


func _pick(key: String, value: Variant) -> void:
	_opts[key] = value
	_update()


# ---------------------------------------------------------------- open

func open_scene(exporter: RenderExporter) -> void:
	if not App.has_project():
		return
	var s := App.current_scene()
	_renderer = exporter
	_episode = null
	_frames = s.frame_count
	_has_audio = not s.audio_tracks.is_empty()
	_open_common(s.name)


func open_episode(renderer: EpisodeRenderer, ep: EpisodeData) -> void:
	if not App.has_project():
		return
	_renderer = renderer
	_episode = ep
	_frames = EpisodeData.total_frames(ep.schedule(App.project))
	_has_audio = true
	_open_common("Episode %d %s" % [ep.number, ep.title])


func _open_common(default_name: String) -> void:
	var p: ProjectData = App.project
	_name.text = default_name.strip_edges()
	if str(_opts["dir"]) == "":
		_opts["dir"] = p.root_dir.path_join("exports")
	# Start at the project's own size and frame rate (nearest preset).
	var short_side := mini(p.width, p.height)
	var best := 1080
	for r in ExportSettings.RESOLUTIONS:
		if absi(int(r[0]) - short_side) < absi(best - short_side):
			best = int(r[0])
	_opts["res"] = best
	_opts["fps"] = p.fps if ExportSettings.FRAME_RATES.has(p.fps) else 24
	if not ExportSettings.can_encode_video():
		_opts["format"] = "png"
	_audio.visible = _has_audio
	_show_state("settings")
	_update()
	popup_centered()


func _show_state(state: String) -> void:
	_settings_box.visible = state == "settings"
	_progress_box.visible = state == "progress"
	_done_box.visible = state == "done"
	get_ok_button().visible = state == "settings"
	get_cancel_button().text = "Cancel" if state != "done" else "Close"
	reset_size()


# ---------------------------------------------------------------- estimate

func _update() -> void:
	if not App.has_project():
		return
	for key in _groups.keys():
		var buttons: Dictionary = _groups[key]
		for val in buttons.keys():
			var b: Button = buttons[val]
			b.set_pressed_no_signal(val == _opts[key])
	var can_video := ExportSettings.can_encode_video()
	var fmt_buttons: Dictionary = _groups["format"]
	for val in fmt_buttons.keys():
		var b: Button = fmt_buttons[val]
		b.disabled = str(val) != "png" and not can_video
	var fmt := str(_opts["format"])
	var is_video := fmt != "png"
	var q_buttons: Dictionary = _groups["quality"]
	for val in q_buttons.keys():
		var qb: Button = q_buttons[val]
		qb.disabled = not (fmt == "mp4" or fmt == "mov" or fmt == "webm")
	_transparent.disabled = is_video
	if is_video:
		_transparent.set_pressed_no_signal(false)
		_opts["transparent"] = false
	_audio.disabled = fmt == "gif"
	var sz := ExportSettings.output_size(_opts)
	var bytes := ExportSettings.estimate_bytes(_opts, _frames, _has_audio)
	_estimate.text = "≈ %s" % ExportSettings.human_size(bytes)
	var parts := PackedStringArray([
		ExportSettings.human_time(_frames),
		"%d × %d" % [sz.x, sz.y],
		"%d fps" % ExportSettings.output_fps(_opts),
	])
	match fmt:
		"mp4", "mov":
			parts.append("H.264 %.1f Mbps" % (ExportSettings.video_bitrate(_opts) / 1000000.0))
		"webm":
			parts.append("VP9 %.1f Mbps" % (ExportSettings.video_bitrate(_opts) / 1000000.0))
		"gif":
			parts.append("GIF (up to 960 px wide, 25 fps)")
		"png":
			parts.append("%d PNG files" % _frames)
	_detail.text = " · ".join(parts)
	_dir_label.text = str(_opts["dir"])
	_dir_label.tooltip_text = str(_opts["dir"])
	if can_video:
		_note.text = ""
	elif not Platform.can_run_programs():
		_note.text = "iPhone and iPad don't allow apps to run FFmpeg, so on this device exports are PNG frames (plus the sound as WAV). Open the project on desktop to export MP4, MOV or GIF."
	else:
		_note.text = "MP4, MOV and GIF need FFmpeg (set its location in Home → Interface → FFmpeg). PNG frames always work."
	get_ok_button().disabled = _frames <= 0


# ---------------------------------------------------------------- export

func _on_export() -> void:
	if _renderer == null or _frames <= 0 or bool(_renderer.get("busy")):
		return
	_opts["name"] = _name.text.strip_edges()
	_show_state("progress")
	_progress.value = 0
	_progress_label.text = "Exporting 0%"
	if not _renderer.is_connected("progress", _on_progress):
		_renderer.connect("progress", _on_progress)
	if not _renderer.is_connected("finished", _on_finished):
		_renderer.connect("finished", _on_finished)
	if _episode != null:
		var er: EpisodeRenderer = _renderer
		er.export_episode(_episode, DepthView.instance, _opts.duplicate())
	else:
		var re: RenderExporter = _renderer
		re.export_scene(DepthView.instance, _opts.duplicate())


func _on_progress(done: int, total: int, message: String) -> void:
	if not visible:
		return
	_progress.max_value = maxi(1, total)
	_progress.value = done
	_progress_label.text = "Exporting %d%%" % int(100.0 * done / maxf(1.0, total)) if message.begins_with("Render") else message


func _on_finished(ok: bool, message: String, output: String) -> void:
	if _renderer != null:
		if _renderer.is_connected("progress", _on_progress):
			_renderer.disconnect("progress", _on_progress)
		if _renderer.is_connected("finished", _on_finished):
			_renderer.disconnect("finished", _on_finished)
	App.status(message)
	if not visible:
		return
	if ok:
		_last_output = output
		_done_label.text = "✓  " + message
		_show_state("done")
	else:
		_note.text = message
		_show_state("settings")


func _on_cancel() -> void:
	if _progress_box.visible and _renderer != null:
		_renderer.call("cancel")
