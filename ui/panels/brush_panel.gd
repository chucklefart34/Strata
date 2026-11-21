class_name BrushPanel
extends VBoxContainer
## Brush settings, presets, color and palette.

const PRESETS := [
	# name, tool, size, opacity, hardness, stabilizer
	["Sketch", "pencil", 3.0, 0.7, 1.0, 0.1],
	["Ink", "brush", 6.0, 1.0, 0.9, 0.45],
	["Paint", "brush", 28.0, 1.0, 0.55, 0.15],
	["Airbrush", "brush", 80.0, 0.25, 0.0, 0.1],
]

var _size: HSlider
var _opacity: HSlider
var _hardness: HSlider
var _stab: HSlider
var _pressure: CheckBox
var _color_btn: ColorPickerButton
var _swatches: GridContainer


const LASSO_MODES := ["shape", "trace", "outline", "fill"]
const LASSO_LABELS := ["Shape (colour + auto outline)", "Trace lines inside", "Clean outline", "Fill"]
var _lasso_box: VBoxContainer
var _lasso_mode: OptionButton
var _lasso_hint: Label
var _lasso_detail: HSlider
var _lasso_behind: CheckBox
var _lasso_new_layer: CheckBox

func _ready() -> void:
	add_theme_constant_override("separation", int(UI.px(10)))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var brush := UI.section(self, "Brush")
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", int(UI.px(6)))
	presets.add_theme_constant_override("v_separation", int(UI.px(6)))
	brush.add_child(presets)
	for p in PRESETS:
		var b := UI.button(p[0], "", "Preset: %s" % p[0])
		b.pressed.connect(_apply_preset.bind(p))
		presets.add_child(b)
	_size = UI.slider(brush, "Size", 1, 300, 1, App.brush_size, _on_size, "%d px")
	_opacity = UI.slider(brush, "Opacity", 1, 100, 1, App.brush_opacity * 100.0, _on_opacity, "%d%%")
	_hardness = UI.slider(brush, "Hardness", 0, 100, 1, App.brush_hardness * 100.0, _on_hardness, "%d%%")
	_stab = UI.slider(brush, "Stabilizer", 0, 100, 1, App.stabilizer * 100.0, _on_stab, "%d%%")
	_pressure = CheckBox.new()
	_pressure.text = "Pen pressure controls size"
	_pressure.button_pressed = App.pressure_size
	_pressure.focus_mode = Control.FOCUS_NONE
	_pressure.toggled.connect(func(on: bool) -> void: App.pressure_size = on)
	brush.add_child(_pressure)

	_lasso_box = UI.section(self, "Lasso lineart")
	var lh := UI.label("Draw a loop around something on the canvas.", "Small")
	lh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lasso_box.add_child(lh)
	_lasso_mode = UI.option(LASSO_LABELS, maxi(0, LASSO_MODES.find(App.lasso_mode)))
	_lasso_mode.item_selected.connect(func(i: int) -> void:
		App.lasso_mode = LASSO_MODES[i]
		_sync_lasso())
	_lasso_box.add_child(_lasso_mode)
	_lasso_hint = UI.label("", "Small")
	_lasso_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lasso_box.add_child(_lasso_hint)
	_lasso_detail = UI.slider(_lasso_box, "Line detail", 1, 20, 1, App.lasso_detail, _on_lasso_detail, "%d")
	_lasso_behind = CheckBox.new()
	_lasso_behind.text = "Fill behind my lines"
	_lasso_behind.button_pressed = App.lasso_behind
	_lasso_behind.focus_mode = Control.FOCUS_NONE
	_lasso_behind.toggled.connect(func(on: bool) -> void: App.lasso_behind = on)
	_lasso_box.add_child(_lasso_behind)
	_lasso_new_layer = CheckBox.new()
	_lasso_new_layer.text = "Each shape on a new layer"
	_lasso_new_layer.tooltip_text = "Puts every shape on its own layer, so even two shapes of the same colour get a line between them. Off: shapes share the layer and lines appear where colours meet."
	_lasso_new_layer.button_pressed = App.lasso_new_layer
	_lasso_new_layer.focus_mode = Control.FOCUS_NONE
	_lasso_new_layer.toggled.connect(func(on: bool) -> void: App.lasso_new_layer = on)
	_lasso_box.add_child(_lasso_new_layer)

	var color := UI.section(self, "Color")
	var row := UI.hbox(8)
	color.add_child(row)
	_color_btn = ColorPickerButton.new()
	_color_btn.color = App.color
	_color_btn.edit_alpha = false
	_color_btn.custom_minimum_size = UI.size2(54, 34)
	_color_btn.focus_mode = Control.FOCUS_NONE
	_color_btn.tooltip_text = "Current color — click to mix a new one"
	_color_btn.color_changed.connect(func(c: Color) -> void: App.set_color(c))
	row.add_child(_color_btn)
	var hint := UI.label("Right-click a swatch to store the current color in it.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	_swatches = GridContainer.new()
	_swatches.columns = 8
	_swatches.add_theme_constant_override("h_separation", int(UI.px(5)))
	_swatches.add_theme_constant_override("v_separation", int(UI.px(5)))
	color.add_child(_swatches)
	_build_swatches()

	App.brush_changed.connect(_sync)
	App.tool_changed.connect(_sync)
	_sync_lasso()


func _on_size(v: float) -> void:
	App.brush_size = v
	App.brush_changed.emit()


func _on_opacity(v: float) -> void:
	App.brush_opacity = v / 100.0
	App.brush_changed.emit()


func _on_hardness(v: float) -> void:
	App.brush_hardness = v / 100.0
	App.brush_changed.emit()


func _on_stab(v: float) -> void:
	App.stabilizer = v / 100.0
	App.brush_changed.emit()


func _build_swatches() -> void:
	for c in _swatches.get_children():
		c.queue_free()
	for i in App.palette.size():
		var sw := Button.new()
		sw.theme_type_variation = "Swatch"
		sw.custom_minimum_size = UI.size2(26, 26)
		sw.focus_mode = Control.FOCUS_NONE
		sw.tooltip_text = "#" + App.palette[i].to_html(false)
		var bg := StyleBoxFlat.new()
		bg.bg_color = App.palette[i]
		bg.set_corner_radius_all(int(UI.px(6)))
		sw.add_theme_stylebox_override("normal", bg)
		var hover := bg.duplicate() as StyleBoxFlat
		hover.set_border_width_all(maxi(1, int(UI.px(2))))
		hover.border_color = Color.WHITE
		sw.add_theme_stylebox_override("hover", hover)
		sw.add_theme_stylebox_override("pressed", hover)
		sw.gui_input.connect(_on_swatch_input.bind(i))
		_swatches.add_child(sw)


func _on_swatch_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		App.set_color(App.palette[index])
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		App.palette[index] = App.color
		_build_swatches()
		App.status("Saved color to palette")


func _apply_preset(p: Array) -> void:
	App.set_tool(p[1])
	App.brush_size = p[2]
	App.brush_opacity = p[3]
	App.brush_hardness = p[4]
	App.stabilizer = p[5]
	App.brush_changed.emit()
	App.status("Brush preset: " + str(p[0]))


func _on_lasso_detail(v: float) -> void:
	App.lasso_detail = v


func _sync_lasso() -> void:
	var card: Control = _lasso_box.get_parent()
	card.visible = App.tool == "lassoline"
	var mode := App.lasso_mode
	_lasso_detail.get_parent().visible = mode == "trace"
	_lasso_behind.visible = mode == "fill"
	_lasso_new_layer.visible = mode == "shape"
	_lasso_hint.text = {
		"shape": "Lasso a solid colour shape. The layer's Border draws the lineart around it automatically (turned on for you; set width and colour in the Layers panel). Block in shapes over a sketch — newer shapes sit on top, and lines appear where colours meet.",
		"trace": "Traces clean lines from the picture inside the loop — an imported video frame, a reference or the 3D guide (everything visible except this layer). Line thickness = brush Size, colour = current colour.",
		"outline": "Your rough loop becomes a smooth, even ink line in the current colour and brush size. Great for quick shapes, eyes, props.",
		"fill": "Fills the loop with the current colour. With “behind my lines” on, it colours under the lines already on this layer.",
	}.get(mode, "")


func _sync() -> void:
	_sync_lasso()
	UI.set_slider(_size, App.brush_size)
	UI.set_slider(_opacity, App.brush_opacity * 100.0)
	UI.set_slider(_hardness, App.brush_hardness * 100.0)
	UI.set_slider(_stab, App.stabilizer * 100.0)
	_color_btn.color = App.color
