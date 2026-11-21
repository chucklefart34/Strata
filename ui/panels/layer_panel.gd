class_name LayerPanel
extends VBoxContainer
## Layer list (top layer first) with visibility, lock, rename, opacity,
## add/duplicate/delete and reordering.

const ROLE_LABELS := {
	"background": "Background", "midground": "Midground", "character": "Character",
	"foreground": "Foreground", "effect": "Effect", "drawing": "Drawing",
	"reference": "Reference",
}

var _list: VBoxContainer
var _name_edit: LineEdit
var _opacity: HSlider
var _boil: HSlider
var _boil_speed: OptionButton
var _border: HSlider
var _border_color: ColorPickerButton
var _border_inner: CheckBox
var _role: OptionButton
var _import_dialog: FileDialog
var _import_as_reference: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sec := UI.section(self, "Layers")
	var bar := UI.hbox(2)
	sec.add_child(bar)
	var add := UI.icon_button("plus", "New layer")
	add.pressed.connect(func() -> void: Ops.add_layer("Layer %d" % (App.current_scene().layers.size() + 1)))
	var dup := UI.icon_button("copy", "Duplicate layer")
	dup.pressed.connect(func() -> void: Ops.duplicate_layer(App.layer_index))
	var up := UI.icon_button("up", "Move layer up")
	up.pressed.connect(func() -> void: Ops.move_layer(App.layer_index, 1))
	var down := UI.icon_button("down", "Move layer down")
	down.pressed.connect(func() -> void: Ops.move_layer(App.layer_index, -1))
	var del := UI.icon_button("trash", "Delete layer")
	del.pressed.connect(func() -> void: Ops.delete_layer(App.layer_index))
	var imp := UI.icon_button("image", "Import an image as a new layer")
	imp.pressed.connect(_open_import.bind(false))
	var ref := UI.icon_button("import", "Import a reference image (locked, shown faded, never rendered)")
	ref.pressed.connect(_open_import.bind(true))
	var vid := UI.icon_button("film", "Import a video as a layer (every frame becomes a drawing you can draw over)")
	vid.pressed.connect(func() -> void: App.video_import_requested.emit(""))
	for b in [add, dup, up, down, imp, ref, vid]:
		bar.add_child(b)
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.use_native_dialog = true
	_import_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.svg, *.bmp, *.tga ; Images"])
	_import_dialog.file_selected.connect(_on_import_file)
	add_child(_import_dialog)
	bar.add_child(UI.spacer())
	bar.add_child(del)

	_list = UI.vbox(3)
	sec.add_child(_list)

	var props := UI.vbox(6)
	sec.add_child(props)
	props.add_child(HSeparator.new())
	props.add_child(UI.label("Name", "FieldLabel"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Layer name"
	_name_edit.text_submitted.connect(_rename)
	_name_edit.focus_exited.connect(func() -> void: _rename(_name_edit.text))
	props.add_child(_name_edit)
	props.add_child(UI.label("Role", "FieldLabel"))
	_role = UI.option(ROLE_LABELS.values())
	_role.tooltip_text = "A role sets a sensible starting depth in the Depth view"
	_role.item_selected.connect(_on_role)
	props.add_child(_role)
	_opacity = UI.slider(props, "Opacity", 0, 100, 1, 100, _on_opacity, "%d%%")
	_boil = UI.slider(props, "Line boil (hand-drawn wobble)", 0, 100, 1, 0, _on_boil, "%d%%")
	_boil.tooltip_text = "Makes this layer's lines wobble slightly, with a new wobble every few frames — like each frame was traced again by hand. Held drawings stop looking frozen. 0 = still."
	var bs_row := UI.hbox(6)
	props.add_child(bs_row)
	bs_row.add_child(UI.label("New wobble every", "FieldLabel"))
	_boil_speed = UI.option(["1 frame", "2 frames", "3 frames", "4 frames"], 1)
	_boil_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boil_speed.item_selected.connect(func(i: int) -> void:
		var l := App.current_layer()
		if l != null:
			Ops.set_layer_prop(l, "boil_speed", i + 1))
	bs_row.add_child(_boil_speed)
	_border = UI.slider(props, "Border (auto outline)", 0, 16, 0.5, 0, _on_border, "%.1f px")
	_border.tooltip_text = "Draws a line around every shape on this layer, like Clip Studio's border effect. Block in colours with the Lasso tool (Shape mode) and the lineart appears by itself. 0 = off."
	var br := UI.hbox(6)
	props.add_child(br)
	_border_color = ColorPickerButton.new()
	_border_color.edit_alpha = false
	_border_color.custom_minimum_size = UI.size2(44, 28)
	_border_color.focus_mode = Control.FOCUS_NONE
	_border_color.tooltip_text = "Border colour"
	_border_color.popup_closed.connect(func() -> void:
		var l := App.current_layer()
		if l != null and l.border_color != _border_color.color:
			Ops.set_layer_prop(l, "border_color", _border_color.color))
	br.add_child(_border_color)
	_border_inner = CheckBox.new()
	_border_inner.text = "Also where colours meet"
	_border_inner.focus_mode = Control.FOCUS_NONE
	_border_inner.tooltip_text = "Draws the line between two different colours on the same layer too (hair against face), not only around the outside."
	_border_inner.toggled.connect(func(on: bool) -> void:
		var l := App.current_layer()
		if l != null and l.border_inner != on:
			Ops.set_layer_prop(l, "border_inner", on))
	br.add_child(_border_inner)

	for sig: Signal in [App.project_opened, App.scene_switched, App.layers_changed, App.layer_selected, App.stage_changed]:
		sig.connect(_rebuild)
	_rebuild()


var _guide_drag: bool = false


func _rebuild() -> void:
	if _guide_drag:
		return  # don't destroy the opacity slider while it's being dragged
	for c in _list.get_children():
		c.queue_free()
	var s := App.current_scene()
	if s == null:
		return
	var active := App.current_layer()
	var show_guide := DepthView.scene_has_set(s)
	var guide_front := bool(s.stage_value("draw_guide_front"))
	if show_guide and guide_front:
		_list.add_child(_make_guide_row(s))
	for i in range(s.layers.size() - 1, -1, -1):
		var layer: LayerData = s.layers[i]
		_list.add_child(_make_row(layer, i, layer == active))
	if show_guide and not guide_front:
		_list.add_child(_make_guide_row(s))
	if active != null:
		if not _name_edit.has_focus():
			_name_edit.text = active.name
		UI.set_slider(_opacity, float(active.motion_at(App.frame)["opacity"]) * 100.0)
		UI.set_slider(_boil, active.boil * 100.0)
		_boil_speed.select(clampi(active.boil_speed - 1, 0, 3))
		_boil.editable = not active.is_character()
		_boil_speed.disabled = active.is_character() or active.boil <= 0.001
		UI.set_slider(_border, active.border)
		_border.editable = not active.is_character()
		_border_color.color = active.border_color
		_border_color.disabled = active.is_character()
		_border_inner.set_pressed_no_signal(active.border_inner)
		_border_inner.disabled = active.is_character()
		var role_idx := ROLE_LABELS.keys().find(active.role)
		_role.select(maxi(0, role_idx))


func _make_row(layer: LayerData, index: int, selected: bool) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = "LayerRowSelected" if selected else "LayerRow"
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			App.set_layer(index))
	var h := UI.hbox(4)
	row.add_child(h)
	var eye := UI.icon_button("eye" if layer.visible else "eye_off", "Show / hide")
	eye.custom_minimum_size = UI.size2(28, 28)
	eye.pressed.connect(func() -> void: Ops.set_layer_prop(layer, "visible", not layer.visible))
	h.add_child(eye)
	var lock := UI.icon_button("lock" if layer.locked else "unlock", "Lock / unlock")
	lock.custom_minimum_size = UI.size2(28, 28)
	lock.modulate.a = 1.0 if layer.locked else 0.45
	lock.pressed.connect(func() -> void: Ops.set_layer_prop(layer, "locked", not layer.locked))
	h.add_child(lock)
	var name_label := UI.label(layer.name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not layer.visible:
		name_label.modulate.a = 0.5
	h.add_child(name_label)
	var role := UI.label(str(ROLE_LABELS.get(layer.role, "")), "Small")
	role.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(role)
	return row


## "3D set (from Depth)": shows the set built in the Depth workspace through
## the scene camera, so you can draw over it. A guide only — never exported.
func _make_guide_row(s: SceneData) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = "LayerRow"
	row.tooltip_text = "The 3D set from the Depth workspace, seen through the scene camera at this frame. A guide for drawing only: the final render uses the real 3D set."
	var v := UI.vbox(2)
	row.add_child(v)
	var h := UI.hbox(4)
	v.add_child(h)
	var on := bool(s.stage_value("draw_guide"))
	var eye := UI.icon_button("eye" if on else "eye_off", "Show / hide the 3D set while drawing")
	eye.custom_minimum_size = UI.size2(28, 28)
	eye.pressed.connect(func() -> void: Ops.set_stage_value("draw_guide", not on, "Show 3D set in Draw"))
	h.add_child(eye)
	var cube := TextureRect.new()
	cube.texture = Icons.tex("cube", 16)
	cube.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	cube.modulate = Palette.DEPTH
	cube.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cube)
	var name_label := UI.label("3D set (from Depth)")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.modulate = Palette.DEPTH if on else Color(Palette.DEPTH, 0.5)
	h.add_child(name_label)
	var front := bool(s.stage_value("draw_guide_front"))
	var place := UI.icon_button("down" if front else "up", "Put it behind your drawings" if front else "Put it in front of your drawings (to trace over it)")
	place.custom_minimum_size = UI.size2(28, 28)
	place.pressed.connect(func() -> void: Ops.set_stage_value("draw_guide_front", not front, "Move 3D set guide"))
	h.add_child(place)
	if on:
		var sl := HSlider.new()
		sl.min_value = 5
		sl.max_value = 100
		sl.step = 1
		sl.value = float(s.stage_value("draw_guide_opacity")) * 100.0
		sl.focus_mode = Control.FOCUS_NONE
		sl.tooltip_text = "How strongly the 3D set shows"
		sl.theme_type_variation = "DepthSlider"
		sl.value_changed.connect(_on_guide_opacity)
		sl.drag_started.connect(func() -> void: _guide_drag = true)
		sl.drag_ended.connect(func(_changed: bool) -> void:
			_guide_drag = false
			_rebuild.call_deferred())
		v.add_child(sl)
	return row


func _on_guide_opacity(v: float) -> void:
	Ops.set_stage_value("draw_guide_opacity", v / 100.0, "3D set guide opacity")


func _open_import(as_reference: bool) -> void:
	_import_as_reference = as_reference
	_import_dialog.title = "Import reference image" if as_reference else "Import image as layer"
	_import_dialog.popup_centered_ratio(0.6)


func _on_import_file(path: String) -> void:
	var err: String = Ops.import_image(path, _import_as_reference)
	if err != "":
		App.status(err.replace("\n", " "))


func _rename(new_text: String) -> void:
	var l := App.current_layer()
	new_text = new_text.strip_edges()
	if l == null or new_text == "" or new_text == l.name:
		return
	Ops.set_layer_prop(l, "name", new_text)


func _on_role(idx: int) -> void:
	var l := App.current_layer()
	if l == null:
		return
	var role: String = ROLE_LABELS.keys()[idx]
	Ops.set_layer_prop(l, "role", role)


func _on_border(v: float) -> void:
	var l := App.current_layer()
	if l != null and not l.is_character() and absf(l.border - v) > 0.001:
		Ops.set_layer_prop(l, "border", v)


func _on_boil(v: float) -> void:
	var l := App.current_layer()
	if l != null and not l.is_character():
		Ops.set_layer_prop(l, "boil", v / 100.0)


func _on_opacity(v: float) -> void:
	var l := App.current_layer()
	if l != null:
		Ops.set_layer_motion(l, {"opacity": v / 100.0})
