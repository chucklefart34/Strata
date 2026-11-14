class_name CharacterWorkspace
extends Control
## Character Studio: build reusable characters from body parts. Draw each
## part, set its joint (pivot) and parent to form a puppet rig, add swappable
## drawings (mouth shapes, eyes), save expressions, test the rig, then add the
## character to scenes as a linked instance.

var canvas: CanvasView
var provider: CharacterProvider
var _char_list: VBoxContainer
var _char_name: LineEdit
var _view_buttons: Dictionary = {}
var _pivot_btn: Button
var _parts_list: VBoxContainer
var _part_name: LineEdit
var _parent: OptionButton
var _pivot_x: SpinBox
var _pivot_y: SpinBox
var _variants: HFlowContainer
var _variant_name: LineEdit
var _expr_list: VBoxContainer
var _expr_name: LineEdit
var _new_part_name: LineEdit
var _rig: CharacterRig
var _rig_vp: SubViewport
var _wiggle: CheckBox
var _wiggle_t: float = 0.0
var _empty_note: Label
var _editor_box: Control
var _syncing: bool = false


func _ready() -> void:
	provider = CharacterProvider.new()
	var root := UI.hbox(10)
	UI.full_rect(root)
	add_child(root)

	# ---------------------------------------------------------- library
	var left := PanelContainer.new()
	left.theme_type_variation = "Sidebar"
	left.custom_minimum_size.x = UI.px(240)
	root.add_child(left)
	var lv := UI.vbox(8)
	left.add_child(lv)
	lv.add_child(UI.label("CHARACTERS", "SectionTitle"))
	var add_row := UI.hbox(6)
	lv.add_child(add_row)
	var add_t := UI.button("Body template", "plus", "New character with a ready-made body: legs, arms, body, head, eyes (3 states) and mouth (8 shapes)", "AccentButton")
	add_t.pressed.connect(func() -> void: _select_new(Ops.add_character(true)))
	add_row.add_child(add_t)
	var add_b := UI.button("Blank", "plus", "New character with a single part")
	add_b.pressed.connect(func() -> void: _select_new(Ops.add_character(false)))
	add_row.add_child(add_b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_char_list = UI.vbox(4)
	_char_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_char_list)
	lv.add_child(HSeparator.new())
	lv.add_child(UI.label("Name", "FieldLabel"))
	_char_name = LineEdit.new()
	_char_name.text_submitted.connect(_rename_character)
	_char_name.focus_exited.connect(func() -> void: _rename_character(_char_name.text))
	lv.add_child(_char_name)
	var manage := UI.hbox(4)
	lv.add_child(manage)
	var dup := UI.button("Duplicate", "copy", "", "FlatButton")
	dup.pressed.connect(func() -> void:
		if provider.character != null:
			_select_new(Ops.duplicate_character(provider.character)))
	manage.add_child(dup)
	var del := UI.icon_button("trash", "Delete character")
	del.pressed.connect(func() -> void:
		if provider.character != null:
			Ops.delete_character(provider.character))
	manage.add_child(UI.spacer())
	manage.add_child(del)
	var to_scene := UI.button("Add to current scene", "layers", "Adds a linked instance — editing the character later updates it everywhere", "AccentButton")
	to_scene.pressed.connect(func() -> void:
		if provider.character != null:
			Ops.add_character_instance(provider.character))
	lv.add_child(to_scene)

	root.add_child(ToolBar.new())

	# ---------------------------------------------------------- canvas
	var center := UI.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	center.add_child(HintBar.new("characters", "Start from the body template and draw each part on its own (pick it in Parts). Turn on “Set joint” and click where the part should rotate — the teal lines are the bones. Mouth and Eyes have several drawings for lip-sync and blinking. Then add the character to a scene and pose it in Animate."))
	var bar := UI.hbox(6)
	center.add_child(bar)
	var group := ButtonGroup.new()
	for v in CharacterData.VIEWS:
		var b := UI.button(str(v).capitalize(), "", "Draw the %s view" % v, "TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_set_view.bind(str(v)))
		bar.add_child(b)
		_view_buttons[v] = b
	var copy_front := UI.button("Copy front here", "copy", "Start this view from a copy of the front view's parts and joints", "FlatButton")
	copy_front.pressed.connect(func() -> void:
		if provider.character != null and provider.view != "front":
			Ops.copy_view(provider.character, "front", provider.view))
	bar.add_child(copy_front)
	bar.add_child(UI.spacer())
	_pivot_btn = UI.button("Set joint", "plus", "Click on the canvas to place the selected part's joint (pivot)", "DepthButton")
	_pivot_btn.toggle_mode = true
	_pivot_btn.toggled.connect(func(on: bool) -> void:
		provider.pivot_mode = on
		canvas.refresh())
	bar.add_child(_pivot_btn)
	var bones := UI.button("Bones", "", "Show joints and bones", "DepthButton")
	bones.toggle_mode = true
	bones.button_pressed = true
	bones.toggled.connect(func(on: bool) -> void:
		provider.show_bones = on
		canvas.refresh())
	bar.add_child(bones)
	var dim := UI.button("Focus part", "", "Fade the other parts while drawing", "DepthButton")
	dim.toggle_mode = true
	dim.toggled.connect(func(on: bool) -> void:
		provider.dim_others = on
		canvas.refresh())
	bar.add_child(dim)

	var frame := PanelContainer.new()
	frame.theme_type_variation = "CanvasFrame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(frame)
	canvas = CanvasView.new()
	canvas.provider = provider
	frame.add_child(canvas)
	provider.changed.connect(canvas.refresh)
	provider.context_changed.connect(canvas.commit_floating)
	_empty_note = UI.label("Create a character to get started — the body template is the quickest way.", "Lead")
	_empty_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_empty_note)

	# ---------------------------------------------------------- properties
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = UI.px(310)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(side_scroll)
	var side := UI.vbox(10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)
	_editor_box = side
	_build_parts(side)
	_build_variants(side)
	_build_expressions(side)
	_build_rig_preview(side)
	side.add_child(BrushPanel.new())

	for sig: Signal in [App.project_opened, App.characters_changed]:
		sig.connect(_refresh_all)
	App.pixels_changed.connect(_refresh_rig)
	_refresh_all()


# ================================================================ builders

func _build_parts(parent: Control) -> void:
	var sec := UI.section(parent, "Parts")
	var bar := UI.hbox(2)
	sec.add_child(bar)
	_new_part_name = LineEdit.new()
	_new_part_name.placeholder_text = "New part name"
	_new_part_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_part_name.text_submitted.connect(func(_t: String) -> void: _add_part())
	bar.add_child(_new_part_name)
	var add := UI.icon_button("plus", "Add part above the selected one")
	add.pressed.connect(_add_part)
	bar.add_child(add)
	var up := UI.icon_button("up", "Draw in front")
	up.pressed.connect(func() -> void: _move_part(1))
	bar.add_child(up)
	var down := UI.icon_button("down", "Draw behind")
	down.pressed.connect(func() -> void: _move_part(-1))
	bar.add_child(down)
	var del := UI.icon_button("trash", "Delete part")
	del.pressed.connect(func() -> void:
		if provider.character != null:
			Ops.delete_part(provider.character, provider.view, provider.part_index))
	bar.add_child(del)
	_parts_list = UI.vbox(3)
	sec.add_child(_parts_list)
	sec.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(UI.px(10)))
	grid.add_theme_constant_override("v_separation", int(UI.px(6)))
	sec.add_child(grid)
	grid.add_child(UI.label("Name", "FieldLabel"))
	_part_name = LineEdit.new()
	_part_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_part_name.text_submitted.connect(_rename_part)
	_part_name.focus_exited.connect(func() -> void: _rename_part(_part_name.text))
	grid.add_child(_part_name)
	grid.add_child(UI.label("Attached to", "FieldLabel"))
	_parent = OptionButton.new()
	_parent.focus_mode = Control.FOCUS_NONE
	_parent.tooltip_text = "The part this one moves with (its parent bone)"
	_parent.item_selected.connect(_on_parent)
	grid.add_child(_parent)
	grid.add_child(UI.label("Joint", "FieldLabel"))
	var pr := UI.hbox(4)
	grid.add_child(pr)
	_pivot_x = UI.spin(-10000, 10000, 1, 0, " x")
	_pivot_x.value_changed.connect(func(_v: float) -> void: _on_pivot_spin())
	pr.add_child(_pivot_x)
	_pivot_y = UI.spin(-10000, 10000, 1, 0, " y")
	_pivot_y.value_changed.connect(func(_v: float) -> void: _on_pivot_spin())
	pr.add_child(_pivot_y)


func _build_variants(parent: Control) -> void:
	var sec := UI.section(parent, "Drawings of this part")
	var hint := UI.label("Swappable drawings, e.g. mouth shapes or open/closed eyes. Click one to draw it.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)
	_variants = HFlowContainer.new()
	_variants.add_theme_constant_override("h_separation", int(UI.px(5)))
	_variants.add_theme_constant_override("v_separation", int(UI.px(5)))
	sec.add_child(_variants)
	var row := UI.hbox(4)
	sec.add_child(row)
	_variant_name = LineEdit.new()
	_variant_name.placeholder_text = "New drawing name"
	_variant_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_name.text_submitted.connect(func(_t: String) -> void: _add_variant())
	row.add_child(_variant_name)
	var add := UI.icon_button("plus", "Add a drawing to this part")
	add.pressed.connect(_add_variant)
	row.add_child(add)
	var del := UI.icon_button("trash", "Delete the selected drawing")
	del.pressed.connect(func() -> void:
		var p := provider.part()
		if p != null:
			Ops.delete_variant(p, provider.variant_index_of(p)))
	row.add_child(del)


func _build_expressions(parent: Control) -> void:
	var sec := UI.section(parent, "Expressions")
	var hint := UI.label("An expression remembers which drawing each swappable part shows. Pick drawings above, then save.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)
	_expr_list = UI.vbox(3)
	sec.add_child(_expr_list)
	var row := UI.hbox(4)
	sec.add_child(row)
	_expr_name = LineEdit.new()
	_expr_name.placeholder_text = "Expression name"
	_expr_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_expr_name)
	var save := UI.button("Save", "save", "Save the current drawings of swappable parts as an expression")
	save.pressed.connect(func() -> void:
		if provider.character != null:
			Ops.save_expression(provider.character, _expr_name.text, provider.preview_swaps())
			_expr_name.text = "")
	row.add_child(save)


func _build_rig_preview(parent: Control) -> void:
	var sec := UI.section(parent, "Rig test")
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = UI.size2(280, 160)
	sec.add_child(container)
	_rig_vp = SubViewport.new()
	_rig_vp.disable_3d = true
	container.add_child(_rig_vp)
	var bg := ColorRect.new()
	bg.color = Color("#ececf0")
	bg.size = Vector2(4000, 4000)
	_rig_vp.add_child(bg)
	_rig = CharacterRig.new()
	_rig_vp.add_child(_rig)
	container.resized.connect(_fit_rig)
	_wiggle = CheckBox.new()
	_wiggle.text = "Wiggle every joint (checks your pivots)"
	_wiggle.focus_mode = Control.FOCUS_NONE
	sec.add_child(_wiggle)


# ================================================================ refresh

func _select_new(c: CharacterData) -> void:
	if c != null:
		provider.character = c
		provider.part_index = 0
		_refresh_all()


func _refresh_all() -> void:
	if not App.has_project():
		provider.character = null
		return
	var list := App.project.characters
	if provider.character == null or not list.has(provider.character):
		provider.character = list[0] if not list.is_empty() else null
	_syncing = true
	for c in _char_list.get_children():
		c.queue_free()
	for ch in list:
		var b := UI.button(ch.name, "", "", "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = ch == provider.character
		b.pressed.connect(func() -> void:
			provider.character = ch
			provider.part_index = 0
			provider.context_changed.emit()
			_refresh_all())
		_char_list.add_child(b)
	var has := provider.character != null
	_empty_note.visible = not has
	canvas.visible = has
	_editor_box.modulate.a = 1.0 if has else 0.4
	if has:
		_char_name.text = provider.character.name
		for v in _view_buttons.keys():
			var vb: Button = _view_buttons[v]
			vb.set_pressed_no_signal(v == provider.view)
			vb.text = str(v).capitalize() + ("" if not provider.character.parts(str(v)).is_empty() else " (empty)")
	_refresh_parts()
	_syncing = false
	_rebuild_rig()
	canvas.refresh()


func _refresh_parts() -> void:
	for c in _parts_list.get_children():
		c.queue_free()
	for c in _variants.get_children():
		c.queue_free()
	for c in _expr_list.get_children():
		c.queue_free()
	var ch := provider.character
	if ch == null:
		return
	var parts := provider.parts()
	var active := provider.part()
	for i in range(parts.size() - 1, -1, -1):
		var p: PartData = parts[i]
		var row := PanelContainer.new()
		row.theme_type_variation = "LayerRowSelected" if p == active else "LayerRow"
		row.gui_input.connect(_on_part_row.bind(i))
		var h := UI.hbox(6)
		row.add_child(h)
		var n := UI.label(p.name)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(n)
		var info := ("on " + p.parent) if p.parent != "" else "root"
		if p.has_variants():
			info += " · %d drawings" % p.variants.size()
		var il := UI.label(info, "Small")
		il.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(il)
		_parts_list.add_child(row)
	if parts.is_empty():
		_parts_list.add_child(UI.label("No parts in this view yet. Add one, or use “Copy front here”.", "Small"))

	if active != null:
		if not _part_name.has_focus():
			_part_name.text = active.name
		_parent.clear()
		_parent.add_item("(nothing — root)")
		var sel := 0
		for item in parts:
			var other: PartData = item
			if other == active:
				continue
			_parent.add_item(other.name)
			if other.name == active.parent:
				sel = _parent.item_count - 1
		_parent.select(sel)
		_pivot_x.set_value_no_signal(active.pivot.x)
		_pivot_y.set_value_no_signal(active.pivot.y)
		var current_v := provider.variant_index_of(active)
		for vi in active.variants.size():
			var vb := UI.button(active.variants[vi], "", "", "DepthButton")
			vb.toggle_mode = true
			vb.button_pressed = vi == current_v
			if not active.layer.cels.has(vi):
				vb.modulate.a = 0.6
				vb.tooltip_text = "Not drawn yet"
			vb.pressed.connect(func() -> void:
				provider.set_variant(vi)
				_refresh_parts())
			_variants.add_child(vb)

	for e in ch.expressions.keys():
		var row := UI.hbox(4)
		var preview := UI.button(str(e), "", "Preview this expression", "FlatButton")
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.alignment = HORIZONTAL_ALIGNMENT_LEFT
		preview.pressed.connect(_preview_expression.bind(str(e)))
		row.add_child(preview)
		var del := UI.icon_button("close", "Delete expression")
		del.custom_minimum_size = UI.size2(26, 26)
		del.pressed.connect(func() -> void: Ops.delete_expression(ch, str(e)))
		row.add_child(del)
		_expr_list.add_child(row)


func _rebuild_rig() -> void:
	if _rig == null:
		return
	_rig.build(provider.character, provider.view)
	_fit_rig()
	_refresh_rig()


func _refresh_rig() -> void:
	if _rig == null or provider.character == null:
		return
	_rig.apply({}, provider.preview_swaps())


func _fit_rig() -> void:
	if _rig_vp == null or not App.has_project():
		return
	var vs := Vector2(_rig_vp.size)
	var cs := Vector2(App.project.width, App.project.height)
	var k := minf(vs.x / cs.x, vs.y / cs.y)
	_rig.scale = Vector2(k, k)
	_rig.position = (vs - cs * k) * 0.5


func _process(delta: float) -> void:
	if _wiggle == null or not _wiggle.button_pressed or not is_visible_in_tree() or provider.character == null:
		return
	_wiggle_t += delta
	var pose := {}
	var i := 0
	for item in provider.parts():
		var p: PartData = item
		if p.parent != "":
			pose[p.name] = sin(_wiggle_t * 2.6 + i * 1.3) * 18.0
		i += 1
	_rig.apply(pose, provider.preview_swaps())


# ================================================================ actions

func _set_view(v: String) -> void:
	provider.set_view(v)
	_refresh_all()


func _on_part_row(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		provider.select_part(index)
		_refresh_parts()


func _add_part() -> void:
	var ch := provider.character
	if ch == null:
		return
	var n := _new_part_name.text.strip_edges()
	if n == "":
		n = "Part %d" % (provider.parts().size() + 1)
	if ch.find_part(provider.view, n) != null:
		App.status("A part called “%s” already exists in this view" % n)
		return
	var active := provider.part()
	var parent_name := active.name if active != null else ""
	Ops.add_part(ch, provider.view, n, provider.part_index + 1, parent_name)
	_new_part_name.text = ""
	provider.select_part(provider.part_index + 1)
	_refresh_parts()


func _move_part(delta: int) -> void:
	var ch := provider.character
	if ch == null:
		return
	var to := provider.part_index + delta
	if to < 0 or to >= provider.parts().size():
		return
	Ops.move_part(ch, provider.view, provider.part_index, delta)
	provider.select_part(to)
	_refresh_parts()


func _rename_part(t: String) -> void:
	var p := provider.part()
	t = t.strip_edges()
	if p == null or t == "" or t == p.name or _syncing:
		return
	if provider.character.find_part(provider.view, t) != null:
		App.status("Another part is already called “%s”" % t)
		return
	# Keep children attached to the renamed part.
	for item in provider.parts():
		var other: PartData = item
		if other.parent == p.name:
			Ops.set_char_prop(other, "parent", t, "Re-attach %s" % other.name)
	Ops.set_char_prop(p, "name", t, "Rename part %s" % p.name)


func _on_parent(idx: int) -> void:
	var p := provider.part()
	if p == null or _syncing:
		return
	var parent_name := "" if idx == 0 else _parent.get_item_text(idx)
	Ops.set_char_prop(p, "parent", parent_name, "Attach %s" % p.name)


func _on_pivot_spin() -> void:
	var p := provider.part()
	if p == null or _syncing:
		return
	Ops.set_char_prop(p, "pivot", Vector2(_pivot_x.value, _pivot_y.value), "Move joint (%s)" % p.name)


func _add_variant() -> void:
	var p := provider.part()
	if p == null:
		return
	Ops.add_variant(p, _variant_name.text)
	_variant_name.text = ""


func _preview_expression(e: String) -> void:
	var ch := provider.character
	if ch == null or not ch.expressions.has(e):
		return
	var map: Dictionary = ch.expressions[e]
	for part_name in map.keys():
		var p := ch.find_part(provider.view, str(part_name))
		if p != null:
			provider.preview_variants[p.name] = p.variant_index(str(map[part_name]))
	provider.changed.emit()
	_refresh_parts()
	_refresh_rig()


func _rename_character(t: String) -> void:
	t = t.strip_edges()
	if provider.character == null or t == "" or t == provider.character.name or _syncing:
		return
	Ops.set_char_prop(provider.character, "name", t, "Rename character")
