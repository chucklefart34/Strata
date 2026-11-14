class_name ClipsPanel
extends VBoxContainer
## Animation clip library (reusable cycles), the timing builder and markers.

var _from: SpinBox
var _to: SpinBox
var _clip_name: LineEdit
var _repeat: SpinBox
var _list: VBoxContainer
var _count: SpinBox
var _spacing: OptionButton
var _markers: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", int(UI.px(10)))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ---------------------------------------------------------- timing builder
	var tb := UI.section(self, "Timing builder")
	var tb_hint := UI.label("Lay out blank drawings for a cycle, then draw each one with onion skin.", "Small")
	tb_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tb.add_child(tb_hint)
	var tb_row := UI.hbox(6)
	tb.add_child(tb_row)
	_count = UI.spin(1, 64, 1, 8, " drawings")
	_count.custom_minimum_size.x = UI.px(120)
	tb_row.add_child(_count)
	_spacing = UI.option(["on 1s", "on 2s", "on 3s", "on 4s"], 1)
	_spacing.tooltip_text = "On 2s = each drawing is held for 2 frames (classic 12 drawings per second at 24 fps)"
	tb_row.add_child(_spacing)
	var build := UI.button("Add", "plus", "Add blank drawings from the playhead")
	build.pressed.connect(func() -> void:
		Ops.add_blank_drawings(App.current_layer(), int(_count.value), _spacing.selected + 1))
	tb_row.add_child(build)

	# ---------------------------------------------------------- clips
	var sec := UI.section(self, "Animation clips")
	var hint := UI.label("Save a run of drawings (a walk, a blink…) and reuse it in any layer or scene.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)
	_clip_name = LineEdit.new()
	_clip_name.placeholder_text = "Clip name, e.g. Walk cycle"
	sec.add_child(_clip_name)
	var range_row := UI.hbox(6)
	sec.add_child(range_row)
	range_row.add_child(UI.label("Frames", "FieldLabel"))
	_from = UI.spin(1, 100000, 1, 1)
	_from.custom_minimum_size.x = UI.px(74)
	range_row.add_child(_from)
	range_row.add_child(UI.label("to", "FieldLabel"))
	_to = UI.spin(1, 100000, 1, 1)
	_to.custom_minimum_size.x = UI.px(74)
	range_row.add_child(_to)
	var whole := UI.icon_button("fit", "Use this layer's whole animation")
	whole.pressed.connect(_use_layer_range)
	range_row.add_child(whole)
	var save := UI.button("Save as clip", "save", "Save these frames of the current layer to the clip library")
	save.pressed.connect(_save_clip)
	sec.add_child(save)
	sec.add_child(HSeparator.new())
	var lib_head := UI.hbox(6)
	sec.add_child(lib_head)
	var lib_title := UI.label("LIBRARY", "SectionTitle")
	lib_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib_head.add_child(lib_title)
	lib_head.add_child(UI.label("Repeat", "FieldLabel"))
	_repeat = UI.spin(1, 99, 1, 1, "×")
	_repeat.custom_minimum_size.x = UI.px(70)
	_repeat.tooltip_text = "How many times to repeat the clip when inserting (cycles)"
	lib_head.add_child(_repeat)
	_list = UI.vbox(4)
	sec.add_child(_list)

	# ---------------------------------------------------------- markers
	var msec := UI.section(self, "Markers")
	var mrow := UI.hbox(6)
	msec.add_child(mrow)
	var mh := UI.label("Mark story beats or dialogue cues. M toggles a marker; double-click the ruler too.", "Small")
	mh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(mh)
	var add_m := UI.icon_button("plus", "Add / remove a marker at the playhead (M)")
	add_m.pressed.connect(func() -> void: Ops.toggle_marker())
	mrow.add_child(add_m)
	_markers = UI.vbox(4)
	msec.add_child(_markers)

	for sig: Signal in [App.project_opened, App.clips_changed]:
		sig.connect(_rebuild_clips)
	for sig: Signal in [App.project_opened, App.scene_switched, App.markers_changed]:
		sig.connect(_rebuild_markers)
	App.layer_selected.connect(_use_layer_range)
	App.scene_switched.connect(_use_layer_range)
	_rebuild_clips()
	_rebuild_markers()


func _use_layer_range() -> void:
	var l := App.current_layer()
	if l == null or l.cels.is_empty():
		return
	var keys := l.sorted_keys()
	var first: int = keys[0]
	var last: int = keys[keys.size() - 1]
	var end := l.exposure_end(last, App.frame_count()) - 1
	_from.set_value_no_signal(first + 1)
	_to.set_value_no_signal(end + 1)


func _save_clip() -> void:
	var l := App.current_layer()
	if l == null:
		App.status("Select a layer first")
		return
	var a := int(_from.value) - 1
	var b := int(_to.value) - 1
	if b < a:
		App.status("“To” must be after “From”")
		return
	if Ops.save_clip(l, a, b, _clip_name.text) != null:
		_clip_name.text = ""


func _rebuild_clips() -> void:
	for c in _list.get_children():
		c.queue_free()
	if not App.has_project():
		return
	if App.project.clips.is_empty():
		_list.add_child(UI.label("No clips yet.", "Small"))
		return
	for clip in App.project.clips:
		var row := UI.hbox(4)
		var v := UI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var name_edit := LineEdit.new()
		name_edit.theme_type_variation = "FlatLineEdit"
		name_edit.text = clip.name
		name_edit.text_submitted.connect(func(t: String) -> void: Ops.rename_clip(clip, t.strip_edges()))
		v.add_child(name_edit)
		v.add_child(UI.label("%d drawings · %d frames" % [clip.drawing_count(), clip.length], "Small"))
		var ins := UI.button("Insert", "plus", "Insert at the playhead on the current layer (replaces drawings in that range)")
		ins.pressed.connect(func() -> void:
			Ops.insert_clip(clip, App.current_layer(), App.frame, int(_repeat.value)))
		row.add_child(ins)
		var del := UI.icon_button("trash", "Delete clip from the library")
		del.pressed.connect(func() -> void: Ops.delete_clip(clip))
		row.add_child(del)
		_list.add_child(row)


func _rebuild_markers() -> void:
	for c in _markers.get_children():
		c.queue_free()
	var s := App.current_scene()
	if s == null:
		return
	var keys := s.markers.keys()
	keys.sort()
	for k in keys:
		var f: int = k
		var row := UI.hbox(4)
		var go := UI.button(str(f + 1), "", "Go to frame %d" % (f + 1), "FlatButton")
		go.custom_minimum_size.x = UI.px(52)
		go.pressed.connect(func() -> void: App.set_frame(f))
		row.add_child(go)
		var edit := LineEdit.new()
		edit.theme_type_variation = "FlatLineEdit"
		edit.text = str(s.markers[k])
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_submitted.connect(func(t: String) -> void: Ops.rename_marker(f, t.strip_edges()))
		edit.focus_exited.connect(func() -> void: Ops.rename_marker(f, edit.text.strip_edges()))
		row.add_child(edit)
		var del := UI.icon_button("close", "Remove marker")
		del.custom_minimum_size = UI.size2(26, 26)
		del.pressed.connect(func() -> void: Ops.delete_marker(f))
		row.add_child(del)
		_markers.add_child(row)
