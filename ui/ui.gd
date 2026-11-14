class_name UI
extends RefCounted
## Small UI factory helpers so every panel is built the same way, plus the
## global interface scale (HiDPI aware).

static var scale: float = 1.0


## Design size the whole interface is laid out for. On phones and tablets
## the UI is scaled so this fits the screen (landscape), instead of being
## sized from the screen's pixel density.
const MOBILE_FIT := Vector2(1440, 840)


static func init_scale(override: float = 0.0) -> void:
	if Platform.is_mobile():
		var win := Vector2(DisplayServer.window_get_size())
		if win.x <= 0.0 or win.y <= 0.0:
			win = Vector2(DisplayServer.screen_get_size())
		var safe := Vector2(DisplayServer.get_display_safe_area().size)
		if safe.x > 0.0 and safe.y > 0.0:
			win = win.min(safe)
		var w := maxf(win.x, win.y)
		var h := minf(win.x, win.y)
		var fit := minf(w / MOBILE_FIT.x, h / MOBILE_FIT.y)
		# The Interface size setting is relative to "fits the screen" here.
		var rel := override if override > 0.0 else 1.0
		scale = clampf(fit * rel, 0.6, 4.0)
		return
	if override > 0.0:
		scale = clampf(override, 0.75, 3.0)
		return
	var s := DisplayServer.screen_get_scale()
	var dpi := DisplayServer.screen_get_dpi()
	var from_dpi := float(dpi) / 96.0 if dpi > 0 else 1.0
	scale = clampf(snappedf(maxf(s, from_dpi), 0.25), 1.0, 2.5)


static func px(v: float) -> float:
	return v * scale


static func size2(x: float, y: float) -> Vector2:
	return Vector2(px(x), px(y))


static func button(text: String, icon_name: String = "", tip: String = "", variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = Icons.tex(icon_name)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	return b


static func icon_button(icon_name: String, tip: String, toggle: bool = false, variation: String = "IconButton") -> Button:
	var b := Button.new()
	b.icon = Icons.tex(icon_name)
	b.tooltip_text = tip
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = variation
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = size2(32, 32)
	return b


static func label(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l


static func hbox(sep: float = 8.0) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", int(px(sep)))
	return b


static func vbox(sep: float = 8.0) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", int(px(sep)))
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func vsep() -> VSeparator:
	var s := VSeparator.new()
	s.custom_minimum_size = Vector2(px(6), 0)
	return s


## A titled panel. Returns the content VBox to add rows to.
static func section(parent: Control, title: String, variation: String = "Section") -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = variation
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var v := vbox(8)
	card.add_child(v)
	if title != "":
		v.add_child(label(title.to_upper(), "SectionTitle"))
	return v


## Label + value readout above a slider. `fmt` formats the readout.
static func slider(parent: Control, title: String, min_v: float, max_v: float, step: float, value: float, on_change: Callable, fmt: String = "%d") -> HSlider:
	var row := vbox(2)
	parent.add_child(row)
	var top := hbox(4)
	row.add_child(top)
	var name_label := label(title, "FieldLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var value_label := label(fmt % value, "ValueLabel")
	top.add_child(value_label)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	s.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt % v
		on_change.call(v))
	s.set_meta("value_label", value_label)
	s.set_meta("fmt", fmt)
	return s


## Updates a slider made by UI.slider() without firing its callback.
static func set_slider(s: HSlider, v: float) -> void:
	s.set_value_no_signal(v)
	var lbl: Label = s.get_meta("value_label") as Label
	if lbl != null:
		lbl.text = str(s.get_meta("fmt")) % v


static func spin(min_v: float, max_v: float, step: float, value: float, suffix: String = "") -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.value = value
	sb.suffix = suffix
	sb.select_all_on_focus = true
	sb.custom_minimum_size.x = px(84)
	return sb


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = selected
	o.focus_mode = Control.FOCUS_NONE
	return o


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c
