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


func _sync() -> void:
	UI.set_slider(_size, App.brush_size)
	UI.set_slider(_opacity, App.brush_opacity * 100.0)
	UI.set_slider(_hardness, App.brush_hardness * 100.0)
	UI.set_slider(_stab, App.stabilizer * 100.0)
	_color_btn.color = App.color
