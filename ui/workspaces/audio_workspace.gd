class_name AudioWorkspace
extends Control
## Audio Studio: import dialogue, music, effects and ambience; edit clips on
## a multitrack timeline; mix; and synchronise mouths to dialogue (manual
## keys with frame-by-frame scrubbing, or assisted lip-sync).

const SHAPE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

var timeline: AudioTimeline
var canvas: CanvasView
var _import_dialog: FileDialog
var _wav_dialog: FileDialog
var _clip_box: VBoxContainer
var _clip_title: Label
var _c_start: SpinBox
var _c_trim: SpinBox
var _c_len: SpinBox
var _c_gain: HSlider
var _c_fin: HSlider
var _c_fout: HSlider
var _c_loop: CheckBox
var _track_box: VBoxContainer
var _t_name: LineEdit
var _t_kind: OptionButton
var _t_vol: HSlider
var _master: HSlider
var _meter: ProgressBar
var _ls_layer: OptionButton
var _ls_part: LineEdit
var _ls_shapes: HFlowContainer
var _ls_advance: CheckBox
var _ls_layers: Array = []
var _syncing: bool = false


func _ready() -> void:
	var root := UI.hbox(10)
	UI.full_rect(root)
	add_child(root)

	var center := UI.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	center.add_child(HintBar.new("audio", "Import dialogue and music (or drag files onto the window). Drag clips to move them, drag their edges to trim. Step through frames with , and . to hear each frame, then press 1–9 to key mouth shapes — or try Auto lip-sync on a dialogue clip."))

	var bar := UI.hbox(6)
	center.add_child(bar)
	var imp := UI.button("Import audio…", "import", "WAV, OGG or MP3 — copied into the project", "AccentButton")
	imp.pressed.connect(func() -> void: _import_dialog.popup_centered_ratio(0.6))
	bar.add_child(imp)
	var add_track := MenuButton.new()
	add_track.text = "New track"
	add_track.icon = Icons.tex("plus")
	add_track.flat = false
	for k in AudioTrackData.KINDS:
		add_track.get_popup().add_item(str(AudioTrackData.KIND_LABELS[k]))
	add_track.get_popup().index_pressed.connect(func(i: int) -> void: Ops.add_audio_track(AudioTrackData.KINDS[i]))
	bar.add_child(add_track)
	bar.add_child(UI.vsep())
	var split := UI.button("Split", "insert", "Split the selected clip at the playhead")
	split.pressed.connect(func() -> void:
		if timeline.selected_clip != null:
			Ops.split_audio_clip(timeline.selected_track, timeline.selected_clip))
	bar.add_child(split)
	var dup := UI.icon_button("copy", "Duplicate the selected clip after itself")
	dup.pressed.connect(func() -> void:
		if timeline.selected_clip != null:
			Ops.duplicate_audio_clip(timeline.selected_track, timeline.selected_clip))
	bar.add_child(dup)
	var del := UI.icon_button("trash", "Delete the selected clip")
	del.pressed.connect(func() -> void:
		if timeline.selected_clip != null:
			Ops.delete_audio_clip(timeline.selected_track, timeline.selected_clip))
	bar.add_child(del)
	var marker := UI.button("Marker", "key", "Add a dialogue/timing marker at the playhead (M)", "FlatButton")
	marker.pressed.connect(func() -> void: Ops.toggle_marker())
	bar.add_child(marker)
	bar.add_child(UI.spacer())
	var scrub := CheckBox.new()
	scrub.text = "Hear frames while stepping"
	scrub.button_pressed = Audio.scrub_enabled
	scrub.focus_mode = Control.FOCUS_NONE
	scrub.toggled.connect(func(on: bool) -> void: Audio.scrub_enabled = on)
	bar.add_child(scrub)
	var zin := UI.icon_button("plus", "Zoom in (Ctrl+wheel)")
	zin.pressed.connect(func() -> void: timeline.zoom_by(1.3))
	bar.add_child(zin)
	var zout := UI.icon_button("remove_frame", "Zoom out")
	zout.pressed.connect(func() -> void: timeline.zoom_by(1.0 / 1.3))
	bar.add_child(zout)

	var vsplit := VSplitContainer.new()
	vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(vsplit)
	var preview := PanelContainer.new()
	preview.theme_type_variation = "CanvasFrame"
	preview.custom_minimum_size.y = UI.px(180)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vsplit.add_child(preview)
	canvas = CanvasView.new()
	preview.add_child(canvas)
	var tl_card := PanelContainer.new()
	tl_card.theme_type_variation = "Section"
	tl_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tl_card.size_flags_stretch_ratio = 1.3
	vsplit.add_child(tl_card)
	var tl_box := UI.vbox(6)
	tl_card.add_child(tl_box)
	tl_box.add_child(TransportBar.new(false))
	timeline = AudioTimeline.new()
	timeline.custom_minimum_size.y = UI.px(220)
	tl_box.add_child(timeline)
	timeline.clip_selected.connect(_sync_props)

	# ---------------------------------------------------------- sidebar
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = UI.px(320)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(side_scroll)
	var side := UI.vbox(10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)
	_build_lipsync(side)
	_build_clip(side)
	_build_track(side)
	_build_mixer(side)

	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.use_native_dialog = true
	_import_dialog.title = "Import audio"
	_import_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio"])
	_import_dialog.files_selected.connect(_on_import)
	add_child(_import_dialog)
	_wav_dialog = FileDialog.new()
	_wav_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_wav_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_wav_dialog.use_native_dialog = true
	_wav_dialog.title = "Export scene audio"
	_wav_dialog.filters = PackedStringArray(["*.wav ; WAV audio"])
	_wav_dialog.file_selected.connect(_export_wav)
	add_child(_wav_dialog)

	for sig: Signal in [App.project_opened, App.scene_switched, App.audio_changed, App.frame_changed]:
		sig.connect(_sync_props)
	for sig: Signal in [App.project_opened, App.scene_switched, App.layers_changed, App.characters_changed]:
		sig.connect(_rebuild_lipsync)
	_sync_props()
	_rebuild_lipsync()


# ================================================================ sections

func _build_clip(parent: Control) -> void:
	_clip_box = UI.section(parent, "Selected clip")
	_clip_title = UI.label("Click a clip in the timeline", "Small")
	_clip_box.add_child(_clip_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(UI.px(10)))
	grid.add_theme_constant_override("v_separation", int(UI.px(6)))
	_clip_box.add_child(grid)
	grid.add_child(UI.label("Starts at frame", "FieldLabel"))
	_c_start = UI.spin(1, 1000000, 1, 1)
	_c_start.value_changed.connect(func(v: float) -> void: _clip_set("start_frame", int(v) - 1))
	grid.add_child(_c_start)
	grid.add_child(UI.label("Trim start", "FieldLabel"))
	_c_trim = UI.spin(0, 36000, 0.01, 0, " s")
	_c_trim.value_changed.connect(func(v: float) -> void: _clip_set("trim_in", v))
	grid.add_child(_c_trim)
	grid.add_child(UI.label("Length", "FieldLabel"))
	_c_len = UI.spin(0.05, 36000, 0.01, 1, " s")
	_c_len.value_changed.connect(func(v: float) -> void: _clip_set("length", v))
	grid.add_child(_c_len)
	_c_gain = UI.slider(_clip_box, "Clip gain", -30, 12, 0.5, 0, _clip_set_float.bind("gain_db"), "%+.1f dB")
	_c_fin = UI.slider(_clip_box, "Fade in", 0, 10, 0.05, 0, _clip_set_float.bind("fade_in"), "%.2f s")
	_c_fout = UI.slider(_clip_box, "Fade out", 0, 10, 0.05, 0, _clip_set_float.bind("fade_out"), "%.2f s")
	_c_loop = CheckBox.new()
	_c_loop.text = "Loop (repeat to fill the clip length)"
	_c_loop.focus_mode = Control.FOCUS_NONE
	_c_loop.toggled.connect(func(on: bool) -> void: _clip_set("loop", on))
	_clip_box.add_child(_c_loop)


func _build_track(parent: Control) -> void:
	_track_box = UI.section(parent, "Track")
	_t_name = LineEdit.new()
	_t_name.placeholder_text = "Track name"
	_t_name.text_submitted.connect(func(t: String) -> void: _track_set("name", t.strip_edges()))
	_track_box.add_child(_t_name)
	var labels := []
	for k in AudioTrackData.KINDS:
		labels.append(AudioTrackData.KIND_LABELS[k])
	_t_kind = UI.option(labels)
	_t_kind.item_selected.connect(func(i: int) -> void: _track_set("kind", AudioTrackData.KINDS[i]))
	_track_box.add_child(_t_kind)
	_t_vol = UI.slider(_track_box, "Track volume", -40, 12, 0.5, 0, _on_track_volume, "%+.1f dB")
	var row := UI.hbox(4)
	_track_box.add_child(row)
	var up := UI.icon_button("up", "Move track up")
	up.pressed.connect(func() -> void:
		if timeline.selected_track != null:
			Ops.move_audio_track(timeline.selected_track, -1))
	row.add_child(up)
	var down := UI.icon_button("down", "Move track down")
	down.pressed.connect(func() -> void:
		if timeline.selected_track != null:
			Ops.move_audio_track(timeline.selected_track, 1))
	row.add_child(down)
	row.add_child(UI.spacer())
	var del := UI.button("Delete track", "trash", "", "FlatButton")
	del.pressed.connect(func() -> void:
		if timeline.selected_track != null:
			Ops.delete_audio_track(timeline.selected_track))
	row.add_child(del)


func _build_mixer(parent: Control) -> void:
	var sec := UI.section(parent, "Mix")
	_master = UI.slider(sec, "Master volume", -40, 6, 0.5, 0, _on_master, "%+.1f dB")
	sec.add_child(UI.label("Output level", "FieldLabel"))
	_meter = ProgressBar.new()
	_meter.show_percentage = false
	_meter.max_value = 1.0
	_meter.custom_minimum_size.y = UI.px(8)
	sec.add_child(_meter)
	var exp := UI.button("Export scene audio (WAV)…", "save", "Mix all audible tracks down to one WAV file")
	exp.pressed.connect(func() -> void:
		_wav_dialog.current_file = App.current_scene().name.validate_filename() + ".wav"
		_wav_dialog.popup_centered_ratio(0.6))
	sec.add_child(exp)


func _build_lipsync(parent: Control) -> void:
	var sec := UI.section(parent, "Lip-sync")
	var hint := UI.label("Pick the character, step to a frame, then click a mouth (or press 1–9). Auto lip-sync keys the selected dialogue clip for you.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)
	_ls_layer = OptionButton.new()
	_ls_layer.focus_mode = Control.FOCUS_NONE
	_ls_layer.item_selected.connect(func(_i: int) -> void: _rebuild_shapes())
	sec.add_child(_ls_layer)
	var pr := UI.hbox(6)
	sec.add_child(pr)
	pr.add_child(UI.label("Part", "FieldLabel"))
	_ls_part = LineEdit.new()
	_ls_part.text = "Mouth"
	_ls_part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ls_part.text_submitted.connect(func(_t: String) -> void: _rebuild_shapes())
	pr.add_child(_ls_part)
	_ls_shapes = HFlowContainer.new()
	_ls_shapes.add_theme_constant_override("h_separation", int(UI.px(5)))
	_ls_shapes.add_theme_constant_override("v_separation", int(UI.px(5)))
	sec.add_child(_ls_shapes)
	_ls_advance = CheckBox.new()
	_ls_advance.text = "Step to the next frame after each key"
	_ls_advance.button_pressed = true
	_ls_advance.focus_mode = Control.FOCUS_NONE
	sec.add_child(_ls_advance)
	var auto := UI.button("Auto lip-sync selected clip", "film", "Analyse the clip's loudness and key mouth shapes over its length", "DepthButton")
	auto.pressed.connect(func() -> void:
		var l := _ls_target()
		if timeline.selected_clip == null:
			App.status("Select a dialogue clip in the timeline first")
		elif l == null:
			App.status("Add a character to this scene first (Characters → Add to current scene)")
		else:
			Ops.auto_lipsync(l, _ls_part.text.strip_edges(), timeline.selected_clip))
	sec.add_child(auto)


# ================================================================ sync

func _sync_props() -> void:
	if not App.has_project():
		return
	_syncing = true
	var c := timeline.selected_clip
	_clip_box.modulate.a = 1.0 if c != null else 0.45
	if c != null:
		var len_s := Audio.length_of(c.file)
		_clip_title.text = "%s — source %.2f s" % [c.name, len_s]
		_c_start.set_value_no_signal(c.start_frame + 1)
		_c_trim.set_value_no_signal(c.trim_in)
		_c_len.set_value_no_signal(c.length)
		UI.set_slider(_c_gain, c.gain_db)
		UI.set_slider(_c_fin, c.fade_in)
		UI.set_slider(_c_fout, c.fade_out)
		_c_loop.set_pressed_no_signal(c.loop)
	else:
		_clip_title.text = "Click a clip in the timeline"
	var t := timeline.selected_track
	_track_box.modulate.a = 1.0 if t != null else 0.45
	if t != null:
		if not _t_name.has_focus():
			_t_name.text = t.name
		_t_kind.select(maxi(0, AudioTrackData.KINDS.find(t.kind)))
		UI.set_slider(_t_vol, t.volume_db)
	UI.set_slider(_master, App.project.master_volume_db)
	_syncing = false


func _clip_set_float(v: float, prop: String) -> void:
	_clip_set(prop, v)


func _on_track_volume(v: float) -> void:
	_track_set("volume_db", v)


func _on_master(v: float) -> void:
	if not _syncing and App.has_project():
		Ops.set_prop(App.project, "master_volume_db", v, "Master volume", "audio")


func _clip_set(prop: String, value: Variant) -> void:
	var c := timeline.selected_clip
	if _syncing or c == null:
		return
	Ops.set_audio_prop(c, prop, value, "Clip %s (%s)" % [prop.replace("_", " "), c.name])


func _track_set(prop: String, value: Variant) -> void:
	var t := timeline.selected_track
	if _syncing or t == null or (prop == "name" and str(value) == ""):
		return
	Ops.set_audio_prop(t, prop, value, "Track %s (%s)" % [prop.replace("_", " "), t.name])


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _meter == null:
		return
	var db := maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0))
	var target := clampf((db + 60.0) / 60.0, 0.0, 1.0)
	_meter.value = maxf(target, _meter.value - 0.04)


# ================================================================ lip-sync

func _rebuild_lipsync() -> void:
	if _ls_layer == null:
		return
	var keep := _ls_target()
	_ls_layer.clear()
	_ls_layers.clear()
	var s := App.current_scene()
	if s != null:
		for l in s.layers:
			if l.is_character():
				_ls_layers.append(l)
				_ls_layer.add_item(l.name)
	if _ls_layers.is_empty():
		_ls_layer.add_item("(no characters in this scene)")
		_ls_layer.disabled = true
	else:
		_ls_layer.disabled = false
		var idx := _ls_layers.find(keep)
		_ls_layer.select(maxi(0, idx))
	_rebuild_shapes()


func _ls_target() -> LayerData:
	if _ls_layer == null or _ls_layers.is_empty():
		return null
	var i := clampi(_ls_layer.selected, 0, _ls_layers.size() - 1)
	return _ls_layers[i]


func _ls_part_data() -> PartData:
	var l := _ls_target()
	if l == null or not App.has_project():
		return null
	var c := App.project.find_character(l.character_id)
	if c == null:
		return null
	for v in CharacterData.VIEWS:
		var p := c.find_part(str(v), _ls_part.text.strip_edges())
		if p != null:
			return p
	return null


func _rebuild_shapes() -> void:
	for ch in _ls_shapes.get_children():
		ch.queue_free()
	var p := _ls_part_data()
	if p == null:
		_ls_shapes.add_child(UI.label("No part with that name on this character.", "Small"))
		return
	for i in p.variants.size():
		var vname: String = p.variants[i]
		var b := UI.button("%d  %s" % [i + 1, vname] if i < 9 else vname, "", "Key “%s” on this frame" % vname)
		b.pressed.connect(_key_shape.bind(i))
		_ls_shapes.add_child(b)


func _key_shape(index: int) -> void:
	var l := _ls_target()
	var p := _ls_part_data()
	if l == null or p == null or index >= p.variants.size():
		return
	Ops.set_swap(l, p.name, p.variants[index])
	if _ls_advance.button_pressed:
		App.set_frame(App.frame + 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.ctrl_pressed or k.meta_pressed:
		return
	var i := SHAPE_KEYS.find(k.keycode)
	if i >= 0:
		_key_shape(i)
		get_viewport().set_input_as_handled()


# ================================================================ files

func _on_import(paths: PackedStringArray) -> void:
	for p in paths:
		var err: String = Ops.import_audio(p)
		if err != "":
			App.status(err.replace("\n", " "))


func _export_wav(path: String) -> void:
	App.status("Mixing scene audio…")
	var ok: bool = await Audio.mixdown(App.current_scene(), path)
	App.status("Exported %s" % path.get_file() if ok else "Nothing to export (no audible clips) or the mix failed")
