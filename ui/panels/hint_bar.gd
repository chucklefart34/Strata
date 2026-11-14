class_name HintBar
extends PanelContainer
## A dismissible beginner tip shown at the top of a workspace.

var key: String = ""
var text: String = ""


func _init(p_key: String = "", p_text: String = "") -> void:
	key = p_key
	text = p_text


func _ready() -> void:
	theme_type_variation = "Hint"
	if ProjectIO.get_setting("hint_hidden_" + key, false):
		visible = false
	var h := UI.hbox(10)
	add_child(h)
	var icon := TextureRect.new()
	icon.texture = Icons.tex("help", 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.modulate = Palette.ACCENT
	h.add_child(icon)
	var l := UI.label(text, "Muted")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var close := UI.icon_button("close", "Hide this tip")
	close.custom_minimum_size = UI.size2(26, 26)
	close.pressed.connect(func() -> void:
		visible = false
		ProjectIO.set_setting("hint_hidden_" + key, true))
	h.add_child(close)
