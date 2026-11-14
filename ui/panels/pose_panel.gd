class_name PosePanel
extends VBoxContainer
## Puppet posing for a character instance: rotate parts (keyframed and
## interpolated), switch views, swap drawings (mouth shapes, eyes), apply
## expressions and save/apply reusable actions. Visible when the selected
## layer is a character.

var _box: VBoxContainer
var _title: Label
var _state: Label
var _ease: OptionButton
var _view: OptionButton
var _swaps: Dictionary = {}  # part name -> OptionButton
var _sliders: Dictionary = {}  # part name -> HSlider
var _action_name: LineEdit
var _from: SpinBox
var _to: SpinBox
var _repeat: SpinBox
var _structure: String = ""
var _syncing: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sig: Signal in [App.project_opened, App.scene_switched, App.layers_changed, App.layer_selected,
			App.frame_changed, App.characters_changed, App.timeline_changed]:
		sig.connect(_refresh)
	_refresh()


func _layer() -> LayerData:
	var l := App.current_layer()
	return l if l != null and l.is_character() else null


func _character() -> CharacterData:
	var l := _layer()
	if l == null or not App.has_project():
		return null
	return App.project.find_character(l.character_id)


func _structure_key() -> String:
	var l := _layer()
	var c := _character()
	if l == null or c == null:
		return ""
	var parts := []
	for p in c.part_names():
		parts.append(str(p))
	var sw := []
	for p in c.swappable_parts():
		var part: PartData = p
		sw.append(part.name + ":" + ",".join(part.variants))
	return "%s|%s|%s|%s|%s|%d" % [l.id, c.id, ",".join(PackedStringArray(parts)), ";".join(PackedStringArray(sw)), ",".join(PackedStringArray(c.expressions.keys())), c.actions.size()]


func _refresh() -> void:
	var key := _structure_key()
	if key != _structure:
		_structure = key
		_rebuild()
	_sync()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_swaps.clear()
	_sliders.clear()
	var l := _layer()
	var c := _character()
	visible = l != null
	if l == null:
		return
	var sec := UI.section(self, "Pose")
	if c == null:
		sec.add_child(UI.label("This layer's character was deleted from the library.", "Small"))
		return
	_title = UI.label(c.name, "Heading")
	sec.add_child(_title)
	var edit := UI.button("Edit artwork in Characters", "character", "", "FlatButton")
	edit.pressed.connect(func() -> void: App.workspace_requested.emit("characters"))
	sec.add_child(edit)
	_state = UI.label("", "Small")
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_state)
	var keys := UI.hbox(4)
	sec.add_child(keys)
	var add := UI.button("Key", "key", "Add a pose key at this frame (any change also adds one)")
	add.pressed.connect(func() -> void: Ops.add_pose_key(_layer()))
	keys.add_child(add)
	var del := UI.button("Delete", "trash", "Delete this character's keys on this frame", "FlatButton")
	del.pressed.connect(func() -> void: Ops.delete_character_keys(_layer()))
	keys.add_child(del)
	var reset := UI.icon_button("reset", "Reset every joint to 0° on this frame")
	reset.pressed.connect(func() -> void: Ops.reset_pose(_layer()))
	keys.add_child(reset)
	var ease_row := UI.hbox(6)
	sec.add_child(ease_row)
	ease_row.add_child(UI.label("Motion to next key", "FieldLabel"))
	_ease = UI.option(["Smooth", "Linear", "Ease in", "Ease out", "Hold"])
	_ease.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ease.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			Ops.set_pose_ease(_layer(), KeyTrack.EASES[i]))
	ease_row.add_child(_ease)

	var view_row := UI.hbox(6)
	sec.add_child(view_row)
	view_row.add_child(UI.label("View", "FieldLabel"))
	_view = OptionButton.new()
	_view.focus_mode = Control.FOCUS_NONE
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for v in CharacterData.VIEWS:
		_view.add_item(str(v).capitalize())
		_view.set_item_disabled(_view.item_count - 1, c.parts(str(v)).is_empty())
	_view.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			Ops.set_view_key(_layer(), CharacterData.VIEWS[i]))
	view_row.add_child(_view)

	if not c.expressions.is_empty():
		sec.add_child(UI.label("EXPRESSIONS", "SectionTitle"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", int(UI.px(5)))
		flow.add_theme_constant_override("v_separation", int(UI.px(5)))
		sec.add_child(flow)
		for e in c.expressions.keys():
			var b := UI.button(str(e), "", "Apply on this frame")
			b.pressed.connect(func() -> void: Ops.apply_expression(_layer(), str(e)))
			flow.add_child(b)

	var swappable := c.swappable_parts()
	if not swappable.is_empty():
		sec.add_child(UI.label("DRAWINGS (LIP-SYNC, BLINKS)", "SectionTitle"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", int(UI.px(10)))
		grid.add_theme_constant_override("v_separation", int(UI.px(6)))
		sec.add_child(grid)
		for p in swappable:
			var part: PartData = p
			grid.add_child(UI.label(part.name, "FieldLabel"))
			var o := UI.option(Array(part.variants))
			o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			o.item_selected.connect(func(i: int) -> void:
				if not _syncing:
					Ops.set_swap(_layer(), part.name, part.variants[i]))
			grid.add_child(o)
			_swaps[part.name] = o

	sec.add_child(UI.label("JOINTS", "SectionTitle"))
	for n in c.part_names():
		var pname := str(n)
		_sliders[pname] = UI.slider(sec, pname, -180, 180, 0.5, 0, _on_joint.bind(pname), "%.1f°")

	var act := UI.section(self, "Actions")
	var ah := UI.label("Save a stretch of posing (a wave, a nod, a walk) and reuse it on any instance of this character.", "Small")
	ah.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	act.add_child(ah)
	_action_name = LineEdit.new()
	_action_name.placeholder_text = "Action name"
	act.add_child(_action_name)
	var rr := UI.hbox(6)
	act.add_child(rr)
	rr.add_child(UI.label("Frames", "FieldLabel"))
	_from = UI.spin(1, 100000, 1, 1)
	_from.custom_minimum_size.x = UI.px(72)
	rr.add_child(_from)
	rr.add_child(UI.label("to", "FieldLabel"))
	_to = UI.spin(1, 100000, 1, maxi(1, App.frame_count()))
	_to.custom_minimum_size.x = UI.px(72)
	rr.add_child(_to)
	var save := UI.button("Save action", "save")
	save.pressed.connect(func() -> void:
		Ops.save_action(_layer(), int(_from.value) - 1, int(_to.value) - 1, _action_name.text)
		_action_name.text = "")
	act.add_child(save)
	if not c.actions.is_empty():
		var head := UI.hbox(6)
		act.add_child(head)
		var lt := UI.label("LIBRARY", "SectionTitle")
		lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(lt)
		head.add_child(UI.label("Repeat", "FieldLabel"))
		_repeat = UI.spin(1, 99, 1, 1, "×")
		_repeat.custom_minimum_size.x = UI.px(70)
		head.add_child(_repeat)
		for i in c.actions.size():
			var a: Dictionary = c.actions[i]
			var row := UI.hbox(4)
			var nl := UI.label("%s · %d fr" % [str(a.get("name", "Action")), int(a.get("length", 1))])
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.clip_text = true
			row.add_child(nl)
			var apply := UI.button("Apply", "plus", "Apply at the playhead")
			apply.pressed.connect(func() -> void:
				Ops.apply_action(_layer(), i, App.frame, int(_repeat.value)))
			row.add_child(apply)
			var rm := UI.icon_button("trash", "Delete action")
			rm.pressed.connect(func() -> void: Ops.delete_action(_character(), i))
			row.add_child(rm)
			act.add_child(row)


func _sync() -> void:
	var l := _layer()
	var c := _character()
	if l == null or c == null or _state == null or not is_instance_valid(_state):
		return
	_syncing = true
	var f: int = App.frame
	var pose := l.pose_at(f, c.part_names())
	for n in _sliders.keys():
		var sl: HSlider = _sliders[n]
		if is_instance_valid(sl):
			UI.set_slider(sl, float(pose.get(n, 0.0)))
	var swaps := l.swaps_at(f)
	for n in _swaps.keys():
		var o: OptionButton = _swaps[n]
		if not is_instance_valid(o):
			continue
		var part: PartData = null
		for p in c.swappable_parts():
			if (p as PartData).name == n:
				part = p
		if part != null:
			o.select(part.variant_index(str(swaps.get(n, part.variants[0]))))
	_view.select(maxi(0, CharacterData.VIEWS.find(l.view_at(f))))
	_ease.select(maxi(0, KeyTrack.EASES.find(str(pose.get("ease", "smooth")))))
	var has_key := l.pose_keys.has(f) or l.view_keys.has(f) or l.swap_keys.has(f)
	if has_key:
		_state.text = "◆ Keys on frame %d. Changes edit them." % (f + 1)
		_state.modulate = Palette.ACCENT
	elif l.pose_keys.is_empty() and l.swap_keys.is_empty() and l.view_keys.is_empty():
		_state.text = "Not posed yet. Move a joint slider to create the first pose."
		_state.modulate = Palette.MUTED
	else:
		_state.text = "Between keys. Any change adds a key on frame %d." % (f + 1)
		_state.modulate = Palette.MUTED
	_syncing = false


func _on_joint(v: float, part_name: String) -> void:
	if _syncing:
		return
	Ops.set_pose(_layer(), part_name, v)
