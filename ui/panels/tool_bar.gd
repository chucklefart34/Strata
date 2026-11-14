class_name ToolBar
extends PanelContainer
## Vertical tool palette for the drawing canvas.

const TOOL_INFO := [
	["brush", "brush", "Brush (B)\nSoft, pressure-sensitive brush"],
	["pencil", "pencil", "Pencil (P)\nHard-edged lines for sketching and ink"],
	["eraser", "eraser", "Eraser (E)"],
	["fill", "fill", "Fill (G)\nClick inside a closed shape to color it"],
	["picker", "picker", "Color picker (I)\nPick a color from the canvas"],
	["", "", ""],
	["line", "line", "Line (L)\nHold Shift to snap to 45°"],
	["rect", "rect", "Rectangle (U)\nHold Shift for a square"],
	["ellipse", "ellipse", "Ellipse (O)\nHold Shift for a circle"],
	["", "", ""],
	["select", "select", "Rectangle select (S)\nDrag to select · drag inside to move · corners scale\nCtrl+C/X/V copy, cut, paste · Delete clears · Enter applies · Esc cancels"],
	["lasso", "lasso", "Lasso select (A)\nDraw around an area to select it freehand"],
	["move", "move", "Move drawing (V)\nDrag to reposition the current drawing"],
	["hand", "hand", "Hand (H)\nPan the view — or hold Space"],
]

var _buttons: Dictionary = {}


func _ready() -> void:
	theme_type_variation = "Toolbar"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(4)
	add_child(v)
	var group := ButtonGroup.new()
	for info in TOOL_INFO:
		var tool_id: String = info[0]
		if tool_id == "":
			var sep := HSeparator.new()
			sep.custom_minimum_size.y = UI.px(8)
			v.add_child(sep)
			continue
		var b := UI.icon_button(info[1], info[2], true, "ToolButton")
		b.custom_minimum_size = UI.size2(40, 40)
		b.button_group = group
		b.pressed.connect(App.set_tool.bind(tool_id))
		v.add_child(b)
		_buttons[tool_id] = b
	App.tool_changed.connect(_sync)
	_sync()


func _sync() -> void:
	for id in _buttons.keys():
		var b: Button = _buttons[id]
		b.set_pressed_no_signal(id == App.tool)
