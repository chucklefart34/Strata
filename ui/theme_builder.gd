class_name ThemeBuilder
extends RefCounted
## Builds Strata's complete custom theme in code so it scales cleanly with
## the UI scale and doesn't look like the Godot editor.

const FONT_NAMES := ["Inter", "Segoe UI Variable Text", "Segoe UI", "SF Pro Text", "Helvetica Neue", "Roboto", "Noto Sans", "Ubuntu", "Cantarell", "Arial"]


static func _sb(bg: Color, radius: float = 8.0, margin_h: float = 10.0, margin_v: float = 6.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(UI.px(radius)))
	sb.content_margin_left = UI.px(margin_h)
	sb.content_margin_right = UI.px(margin_h)
	sb.content_margin_top = UI.px(margin_v)
	sb.content_margin_bottom = UI.px(margin_v)
	sb.anti_aliasing = true
	return sb


static func _bordered(sb: StyleBoxFlat, color: Color, width: float = 1.0) -> StyleBoxFlat:
	sb.set_border_width_all(maxi(1, int(UI.px(width))))
	sb.border_color = color
	return sb


static func _font(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONT_NAMES)
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


static func _label_variation(t: Theme, name: String, font: Font, size: float, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, int(UI.px(size)))
	t.set_color("font_color", name, color)


static func _button_type(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox, text: Color, text_hover: Color, text_pressed: Color) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	t.set_stylebox("focus", type, focus)
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, text_hover)
	t.set_color("font_pressed_color", type, text_pressed)
	t.set_color("font_hover_pressed_color", type, text_pressed)
	t.set_color("font_focus_color", type, text)
	t.set_color("font_disabled_color", type, Palette.DIM)
	t.set_color("icon_normal_color", type, text)
	t.set_color("icon_hover_color", type, text_hover)
	t.set_color("icon_pressed_color", type, text_pressed)
	t.set_color("icon_hover_pressed_color", type, text_pressed)
	t.set_color("icon_focus_color", type, text)
	t.set_color("icon_disabled_color", type, Palette.DIM)
	t.set_constant("h_separation", type, int(UI.px(7)))


static func build() -> Theme:
	var t := Theme.new()
	var regular := _font(400)
	var medium := _font(500)
	var bold := _font(650)
	t.default_font = regular
	t.default_font_size = int(UI.px(14))

	# ---------------------------------------------------------- panels
	t.set_stylebox("panel", "Panel", _sb(Palette.BG, 0, 0, 0))
	t.set_stylebox("panel", "PanelContainer", _sb(Palette.PANEL, 10, 10, 10))

	var variations := {
		"TopBar": _sb(Color("#17181d"), 0, 12, 7),
		"StatusBar": _sb(Color("#111216"), 0, 14, 5),
		"Toolbar": _sb(Palette.PANEL, 12, 6, 8),
		"Sidebar": _sb(Palette.PANEL, 12, 10, 10),
		"Section": _sb(Palette.PANEL, 12, 14, 12),
		"Card": _bordered(_sb(Palette.RAISED, 16, 22, 20), Palette.BORDER),
		"Hint": _bordered(_sb(Color("#1d1f26"), 10, 12, 7), Palette.BORDER),
		"CanvasFrame": _sb(Palette.DESK, 12, 0, 0),
		"LayerRow": _sb(Color(0, 0, 0, 0), 8, 6, 3),
		"LayerRowSelected": _bordered(_sb(Palette.ACCENT_SOFT, 8, 6, 3), Color(1.0, 0.478, 0.349, 0.55)),
		"SceneCard": _bordered(_sb(Palette.RAISED, 12, 8, 8), Palette.BORDER),
		"SceneCardSelected": _bordered(_sb(Color("#2a2523"), 12, 8, 8), Palette.ACCENT, 1.5),
		"Overlay": _sb(Color(0.07, 0.075, 0.09, 0.86), 10, 8, 6),
	}
	for v in variations.keys():
		t.set_type_variation(v, "PanelContainer")
		t.set_stylebox("panel", v, variations[v])
	var top: StyleBoxFlat = variations["TopBar"]
	top.border_width_bottom = maxi(1, int(UI.px(1)))
	top.border_color = Palette.BORDER
	var status: StyleBoxFlat = variations["StatusBar"]
	status.border_width_top = maxi(1, int(UI.px(1)))
	status.border_color = Palette.BORDER
	var card: StyleBoxFlat = variations["Card"]
	card.shadow_color = Color(0, 0, 0, 0.35)
	card.shadow_size = int(UI.px(14))
	card.shadow_offset = Vector2(0, UI.px(4))

	# ---------------------------------------------------------- labels
	t.set_color("font_color", "Label", Palette.TEXT)
	_label_variation(t, "Brand", bold, 17, Palette.TEXT)
	_label_variation(t, "Title", bold, 30, Palette.TEXT)
	_label_variation(t, "Heading", bold, 17, Palette.TEXT)
	_label_variation(t, "SectionTitle", bold, 11, Palette.MUTED)
	_label_variation(t, "Muted", regular, 13, Palette.MUTED)
	_label_variation(t, "Small", regular, 12, Palette.DIM)
	_label_variation(t, "FieldLabel", medium, 13, Palette.MUTED)
	_label_variation(t, "ValueLabel", medium, 13, Palette.TEXT)
	_label_variation(t, "Lead", regular, 16, Palette.MUTED)
	_label_variation(t, "StepNumber", bold, 13, Palette.ACCENT)

	# ---------------------------------------------------------- buttons
	var btn_normal := _sb(Palette.RAISED, 8, 12, 7)
	var btn_hover := _sb(Palette.HOVER, 8, 12, 7)
	var btn_pressed := _bordered(_sb(Palette.ACCENT_DARK, 8, 12, 7), Color(1.0, 0.478, 0.349, 0.7))
	var btn_disabled := _sb(Color("#1d1e24"), 8, 12, 7)
	_button_type(t, "Button", btn_normal, btn_hover, btn_pressed, btn_disabled, Palette.TEXT, Color.WHITE, Color.WHITE)
	t.set_font("font", "Button", medium)

	# Accent (primary action)
	t.set_type_variation("AccentButton", "Button")
	_button_type(t, "AccentButton", _sb(Palette.ACCENT, 8, 16, 8), _sb(Color("#ff8f73"), 8, 16, 8), _sb(Color("#e8664a"), 8, 16, 8), _sb(Color("#5a3b33"), 8, 16, 8), Color("#1a1210"), Color("#1a1210"), Color("#1a1210"))
	t.set_font("font", "AccentButton", bold)

	# Icon-only and tool buttons
	var clear := _sb(Color(0, 0, 0, 0), 8, 6, 6)
	t.set_type_variation("IconButton", "Button")
	_button_type(t, "IconButton", clear, _sb(Palette.HOVER, 8, 6, 6), _bordered(_sb(Palette.ACCENT_DARK, 8, 6, 6), Color(1.0, 0.478, 0.349, 0.6)), clear, Palette.MUTED, Palette.TEXT, Palette.ACCENT)
	t.set_type_variation("ToolButton", "Button")
	_button_type(t, "ToolButton", _sb(Color(0, 0, 0, 0), 9, 8, 8), _sb(Palette.HOVER, 9, 8, 8), _sb(Palette.ACCENT, 9, 8, 8), clear, Palette.MUTED, Palette.TEXT, Color("#1a1210"))
	t.set_type_variation("DepthButton", "Button")
	_button_type(t, "DepthButton", _sb(Palette.RAISED, 8, 10, 6), _sb(Palette.HOVER, 8, 10, 6), _bordered(_sb(Palette.DEPTH_SOFT, 8, 10, 6), Palette.DEPTH), btn_disabled, Palette.TEXT, Color.WHITE, Palette.DEPTH)

	# Workspace tabs
	t.set_type_variation("TabButton", "Button")
	var tab_pressed := _sb(Palette.RAISED, 8, 14, 7)
	tab_pressed.border_width_bottom = maxi(2, int(UI.px(2)))
	tab_pressed.border_color = Palette.ACCENT
	_button_type(t, "TabButton", _sb(Color(0, 0, 0, 0), 8, 14, 7), _sb(Palette.HOVER, 8, 14, 7), tab_pressed, _sb(Color(0, 0, 0, 0), 8, 14, 7), Palette.MUTED, Palette.TEXT, Palette.TEXT)

	# Flat text buttons (lists, links)
	t.set_type_variation("FlatButton", "Button")
	_button_type(t, "FlatButton", _sb(Color(0, 0, 0, 0), 8, 10, 6), _sb(Palette.HOVER, 8, 10, 6), _sb(Palette.ACCENT_SOFT, 8, 10, 6), _sb(Color(0, 0, 0, 0), 8, 10, 6), Palette.TEXT, Color.WHITE, Palette.ACCENT)
	t.set_constant("align_to_largest_stylebox", "FlatButton", 0)

	# OptionButton / MenuButton / CheckBox share button looks
	_button_type(t, "OptionButton", btn_normal, btn_hover, btn_hover, btn_disabled, Palette.TEXT, Color.WHITE, Color.WHITE)
	_button_type(t, "MenuButton", _sb(Color(0, 0, 0, 0), 8, 10, 6), btn_hover, btn_hover, btn_disabled, Palette.TEXT, Color.WHITE, Color.WHITE)
	_button_type(t, "CheckBox", clear, clear, clear, clear, Palette.TEXT, Color.WHITE, Palette.TEXT)
	_button_type(t, "CheckButton", clear, clear, clear, clear, Palette.TEXT, Color.WHITE, Palette.TEXT)
	t.set_type_variation("Swatch", "Button")
	var sw := _bordered(_sb(Color(0, 0, 0, 0), 6, 0, 0), Color(1, 1, 1, 0.12))
	var sw_hover := _bordered(_sb(Color(0, 0, 0, 0), 6, 0, 0), Color(1, 1, 1, 0.7), 1.5)
	_button_type(t, "Swatch", sw, sw_hover, sw_hover, sw, Palette.TEXT, Palette.TEXT, Palette.TEXT)

	# ---------------------------------------------------------- text fields
	var field := _bordered(_sb(Palette.FIELD, 7, 10, 6), Palette.BORDER)
	var field_focus := _bordered(_sb(Palette.FIELD, 7, 10, 6), Palette.ACCENT)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, field)
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_placeholder_color", type, Palette.DIM)
		t.set_color("caret_color", type, Palette.ACCENT)
		t.set_color("selection_color", type, Color(1.0, 0.478, 0.349, 0.35))
	t.set_type_variation("FlatLineEdit", "LineEdit")
	t.set_stylebox("normal", "FlatLineEdit", _sb(Color(0, 0, 0, 0), 6, 4, 2))
	t.set_stylebox("focus", "FlatLineEdit", _bordered(_sb(Palette.FIELD, 6, 4, 2), Palette.ACCENT))

	# ---------------------------------------------------------- sliders
	var track := _sb(Color("#2b2e38"), 3, 0, 0)
	track.content_margin_top = UI.px(2)
	track.content_margin_bottom = UI.px(2)
	var track_fill := _sb(Palette.ACCENT, 3, 0, 0)
	track_fill.content_margin_top = UI.px(2)
	track_fill.content_margin_bottom = UI.px(2)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", track_fill)
	t.set_icon("grabber", "HSlider", Icons.tex("grabber", 14))
	t.set_icon("grabber_highlight", "HSlider", Icons.tex("grabber_hl", 14))
	t.set_icon("grabber_disabled", "HSlider", Icons.tex("grabber", 14))
	t.set_type_variation("DepthSlider", "HSlider")
	var depth_fill := _sb(Palette.DEPTH, 3, 0, 0)
	depth_fill.content_margin_top = UI.px(2)
	depth_fill.content_margin_bottom = UI.px(2)
	t.set_stylebox("grabber_area", "DepthSlider", depth_fill)
	t.set_stylebox("grabber_area_highlight", "DepthSlider", depth_fill)

	# ---------------------------------------------------------- scrollbars
	for type in ["VScrollBar", "HScrollBar"]:
		var scroll := _sb(Color(0, 0, 0, 0), 4, 3, 3)
		t.set_stylebox("scroll", type, scroll)
		t.set_stylebox("scroll_focus", type, scroll)
		t.set_stylebox("grabber", type, _sb(Color("#30333d"), 4, 3, 3))
		t.set_stylebox("grabber_highlight", type, _sb(Color("#3c404b"), 4, 3, 3))
		t.set_stylebox("grabber_pressed", type, _sb(Color("#4a4e5a"), 4, 3, 3))

	# ---------------------------------------------------------- popups, tooltips, dialogs
	var popup := _bordered(_sb(Palette.RAISED, 10, 6, 6), Palette.BORDER)
	popup.shadow_color = Color(0, 0, 0, 0.4)
	popup.shadow_size = int(UI.px(10))
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _sb(Palette.HOVER, 6, 8, 4))
	t.set_color("font_color", "PopupMenu", Palette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Palette.DIM)
	t.set_color("font_separator_color", "PopupMenu", Palette.MUTED)
	t.set_constant("v_separation", "PopupMenu", int(UI.px(8)))
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "TooltipPanel", _bordered(_sb(Color("#0c0d10"), 7, 10, 7), Palette.BORDER))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT)
	t.set_font_size("font_size", "TooltipLabel", int(UI.px(13)))

	var win := _bordered(_sb(Palette.PANEL, 12, 0, 0), Palette.BORDER)
	win.expand_margin_top = UI.px(32)
	win.expand_margin_left = UI.px(4)
	win.expand_margin_right = UI.px(4)
	win.expand_margin_bottom = UI.px(4)
	win.shadow_color = Color(0, 0, 0, 0.45)
	win.shadow_size = int(UI.px(18))
	t.set_stylebox("embedded_border", "Window", win)
	t.set_stylebox("embedded_unfocused_border", "Window", win)
	t.set_constant("title_height", "Window", int(UI.px(32)))
	t.set_color("title_color", "Window", Palette.TEXT)
	t.set_font("title_font", "Window", bold)
	t.set_stylebox("panel", "AcceptDialog", _sb(Palette.PANEL, 0, 18, 16))

	# ---------------------------------------------------------- misc
	var sep := StyleBoxLine.new()
	sep.color = Palette.BORDER
	sep.thickness = maxi(1, int(UI.px(1)))
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = Palette.BORDER
	vsep.vertical = true
	vsep.thickness = maxi(1, int(UI.px(1)))
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_stylebox("background", "ProgressBar", _sb(Palette.FIELD, 6, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _sb(Palette.ACCENT, 6, 0, 0))
	t.set_color("font_color", "ProgressBar", Palette.TEXT)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	return t
