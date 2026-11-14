class_name DepthWorkspace
extends Control
## 3D staging: place every layer in depth, frame the shot with an animated
## camera, preview parallax and render the scene.

const PLACEMENTS := [
	["Far", 30.0], ["Back", 12.0], ["Mid", 5.0], ["Subject", 0.0], ["Front", -2.5],
]
const MOTION_PRESETS := [
	["Fade in", "fade_in"], ["Fade out", "fade_out"], ["Slide in ←", "slide_left"],
	["Slide in →", "slide_right"], ["Grow in", "grow"], ["Float", "bob"],
]
const PRESETS := [
	["Push in", "push_in"], ["Pull out", "pull_out"], ["Pan right", "pan_right"],
	["Pan left", "pan_left"], ["Parallax truck", "truck"], ["Crane up", "crane_up"],
	["Zoom in", "zoom_in"], ["Impact shake", "shake"],
]

var depth: DepthView
var exporter: RenderExporter
var _overlay: Control
var _mode_free: Button
var _mode_cam: Button
var _lens: OptionButton
var _layer_list: VBoxContainer
var _layer_title: Label
var _f: Dictionary = {}  # layer field sliders
var _keep_size: CheckBox
var _motion_state: Label
var _motion_ease: OptionButton
var _c: Dictionary = {}  # camera field sliders
var _ease: OptionButton
var _key_state: Label
var _transparent: CheckBox
var _mp4: CheckBox
var _progress: ProgressBar
var _render_status: Label
var _render_btn: Button
var _out_dialog: FileDialog
var _syncing: bool = false
var _list_key: String = ""
var _list_rows: Array = []  # [{layer, panel, slider, depth_label, name_label}]
var _list_dragging: bool = false
# 3D stage
var _lit: CheckBox
var _cast: CheckBox
var _st: Dictionary = {}  # stage widgets
var _light_dial: LightDial
var _meter: ShadowMeter
var _prop_box: VBoxContainer
var _prop_title: Label
var _pf: Dictionary = {}  # selected set piece widgets
var _lamp_box: VBoxContainer
var _sun_box: VBoxContainer
var _lp: Dictionary = {}  # low-poly widgets
var _lp_mode_block: Button
var _lp_mode_low: Button
var _lp_box: VBoxContainer
var _tabs: TabContainer
var _export_dialog: ExportDialog
var _shapes_tab: int = 1
var _shape_list: ItemList
var _shape_list_key: String = ""
var _tool_btns: Dictionary = {}  # gizmo mode / "paint" -> Button
var _paint_box: VBoxContainer
var _paint_toggle: Button
var _erase_toggle: CheckBox
var _pen_size: HSlider
var _pen_color: ColorPickerButton
var _prop_name: LineEdit


## Shows how dark a shadow will be against lit ground: the "shadow meter".
class ShadowMeter extends Control:
	var strength: float = 0.75
	var softness: float = 1.0
	var ambient: float = 0.55
	var floor_col: Color = Color("#343844")
	var light_col: Color = Color.WHITE
	var energy: float = 1.3

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var lit := floor_col * Color(light_col.r, light_col.g, light_col.b) * clampf(ambient + energy * 0.6, 0.0, 2.0)
		lit.a = 1.0
		var shade := floor_col * clampf(ambient + energy * 0.6 * (1.0 - strength), 0.0, 2.0)
		shade.a = 1.0
		draw_rect(r, lit)
		# Shadow blob with a soft edge proportional to softness.
		var cx := size.x * 0.62
		var w := size.x * 0.34
		var edge := clampf(softness, 0.0, 4.0) * size.x * 0.03 + 1.0
		var steps := 10
		for i in steps:
			var t := float(i) / steps
			var c := lit.lerp(shade, (t + 1.0 / steps))
			var grow := edge * (1.0 - t)
			draw_rect(Rect2(cx - w * 0.5 - grow, size.y * 0.25 - grow * 0.5, w + grow * 2.0, size.y * 0.5 + grow), c)
		draw_rect(r, Palette.BORDER, false, 1.0)
		var font := get_theme_default_font()
		var fs := int(UI.px(11))
		draw_string(font, Vector2(UI.px(6), size.y * 0.5 + fs * 0.35), "%d%%" % int(round(strength * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)


## Drag the sun around a little sky dome: left/right = direction, up/down = height.
class LightDial extends Control:
	signal changed(azimuth: float, elevation: float)
	signal released
	var azimuth: float = -35.0
	var elevation: float = 42.0
	var _down: bool = false

	func _draw() -> void:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.46
		draw_circle(c, rad, Palette.FIELD)
		draw_arc(c, rad, 0, TAU, 48, Palette.BORDER, 1.0)
		draw_arc(c, rad * 0.5, 0, TAU, 32, Color(Palette.BORDER, 0.6), 1.0)
		draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), Color(Palette.BORDER, 0.6), 1.0)
		draw_line(c - Vector2(0, rad), c + Vector2(0, rad), Color(Palette.BORDER, 0.6), 1.0)
		var p := _point()
		draw_line(c, p, Color("#ffd166", 0.5), 1.5)
		draw_circle(p, UI.px(6), Color("#ffd166"))
		var font := get_theme_default_font()
		var fs := int(UI.px(10))
		draw_string(font, Vector2(c.x - UI.px(14), size.y - UI.px(2)), "front", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.DIM)
		draw_string(font, Vector2(c.x - UI.px(12), fs), "back", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.DIM)

	func _point() -> Vector2:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.46
		var r := rad * (1.0 - clampf(elevation, 0.0, 90.0) / 90.0)
		var a := deg_to_rad(azimuth)
		return c + Vector2(-sin(a), cos(a)) * r

	func _gui_input(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			_down = mb.pressed
			if _down:
				_set_from(mb.position)
			else:
				released.emit()
			accept_event()
		var mm := e as InputEventMouseMotion
		if mm != null and _down:
			_set_from(mm.position)
			accept_event()

	func _set_from(pos: Vector2) -> void:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.46
		var d := pos - c
		var r := clampf(d.length() / rad, 0.0, 1.0)
		elevation = clampf((1.0 - r) * 90.0, 3.0, 90.0)
		azimuth = rad_to_deg(atan2(-d.x, d.y))
		queue_redraw()
		changed.emit(azimuth, elevation)


class FrameOverlay extends Control:
	var ws: DepthWorkspace

	func _draw() -> void:
		if ws == null or not ws.depth.through_camera or not App.has_project():
			return
		var aspect := float(App.project.width) / float(App.project.height)
		var r := Rect2(Vector2.ZERO, size)
		if size.x / maxf(size.y, 1.0) > aspect:
			var w := size.y * aspect
			r = Rect2((size.x - w) * 0.5, 0, w, size.y)
		else:
			var h := size.x / aspect
			r = Rect2(0, (size.y - h) * 0.5, size.x, h)
		var shade := Color(0, 0, 0, 0.55)
		draw_rect(Rect2(0, 0, size.x, r.position.y), shade)
		draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), shade)
		draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), shade)
		draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), shade)
		var guide := Color(1, 1, 1, 0.18)
		for i in range(1, 3):
			var gx := r.position.x + r.size.x * i / 3.0
			var gy := r.position.y + r.size.y * i / 3.0
			draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), guide, 1.0)
			draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), guide, 1.0)
		var safe := r.grow_individual(-r.size.x * 0.05, -r.size.y * 0.05, -r.size.x * 0.05, -r.size.y * 0.05)
		draw_rect(safe, Color(1, 1, 1, 0.12), false, 1.0)
		draw_rect(r, Color(0.31, 0.82, 0.77, 0.7), false, 1.5)


func _ready() -> void:
	var root := UI.hbox(10)
	UI.full_rect(root)
	add_child(root)

	# ---------------------------------------------------------- left: depth list
	var left := PanelContainer.new()
	left.theme_type_variation = "Sidebar"
	left.custom_minimum_size.x = UI.px(250)
	root.add_child(left)
	var lv := UI.vbox(8)
	left.add_child(lv)
	lv.add_child(UI.label("LAYERS IN DEPTH", "SectionTitle"))
	var note := UI.label("Nearest at the top. Drag a slider to push a layer back.", "Small")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_layer_list = UI.vbox(6)
	_layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_layer_list)

	# ---------------------------------------------------------- center
	var center := UI.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	center.add_child(HintBar.new("depth", "Drag a layer to slide it, or drag the red/green/blue arrows to move it left-right, up-down or in depth. Click a set piece or the lamp to move it. Drag empty space to orbit (right-drag also orbits, middle-drag pans, wheel zooms). Switch to Camera view to see the final shot; any camera change adds a key at the current frame. Try a preset, then press Enter."))

	var bar := UI.hbox(6)
	center.add_child(bar)
	var group := ButtonGroup.new()
	_mode_free = UI.button("Free view", "orbit", "Orbit around the set to see the layers in depth", "DepthButton")
	_mode_free.toggle_mode = true
	_mode_free.button_group = group
	_mode_free.button_pressed = true
	_mode_free.pressed.connect(func() -> void: depth.set_through_camera(false))
	bar.add_child(_mode_free)
	_mode_cam = UI.button("Camera view", "camera", "Look through the scene camera — this is what gets rendered", "DepthButton")
	_mode_cam.toggle_mode = true
	_mode_cam.button_group = group
	_mode_cam.pressed.connect(func() -> void: depth.set_through_camera(true))
	bar.add_child(_mode_cam)
	var reset := UI.button("Reset view", "reset", "Reset the free view", "FlatButton")
	reset.pressed.connect(func() -> void: depth.reset_view())
	bar.add_child(reset)
	bar.add_child(UI.vsep())
	var tgroup := ButtonGroup.new()
	for t in [["move", "Move", "Move along an axis (W)"], ["rotate", "Rotate", "Spin around an axis (E)"], ["scale", "Scale", "Resize: drag an axis, or the centre box to resize evenly (R)"], ["paint", "Draw", "Draw on set pieces in 3D (B)"]]:
		var tb := UI.button(str(t[1]), "", str(t[2]), "FlatButton")
		tb.toggle_mode = true
		tb.button_group = tgroup
		tb.pressed.connect(_on_tool.bind(str(t[0])))
		bar.add_child(tb)
		_tool_btns[str(t[0])] = tb
	bar.add_child(UI.spacer())
	bar.add_child(UI.label("Lens", "FieldLabel"))
	_lens = UI.option(["Perspective (parallax)", "Orthographic (flat)"])
	_lens.tooltip_text = "Orthographic removes perspective, so layers don't parallax"
	_lens.item_selected.connect(func(i: int) -> void:
		if not _syncing and App.has_project():
			Ops.set_prop(App.current_scene(), "camera_ortho", i == 1, "Camera lens", "camera"))
	bar.add_child(_lens)

	var view_frame := PanelContainer.new()
	view_frame.theme_type_variation = "CanvasFrame"
	view_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(view_frame)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.clip_contents = true
	view_frame.add_child(stack)
	depth = DepthView.new()
	UI.full_rect(depth)
	stack.add_child(depth)
	var overlay := FrameOverlay.new()
	overlay.ws = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(overlay)
	stack.add_child(overlay)
	_overlay = overlay
	depth.camera_mode_changed.connect(_overlay.queue_redraw)
	depth.resized.connect(_overlay.queue_redraw)

	var tl_card := PanelContainer.new()
	tl_card.theme_type_variation = "Section"
	center.add_child(tl_card)
	var tl_box := UI.vbox(6)
	tl_card.add_child(tl_box)
	tl_box.add_child(TransportBar.new(false))
	var tl := TimelineView.new()
	tl.show_camera_row = true
	tl.custom_minimum_size.y = UI.px(130)
	tl_box.add_child(tl)

	# ---------------------------------------------------------- right: properties
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.x = UI.px(330)
	root.add_child(_tabs)
	var layer_tab := _tab("Layer")
	var shapes_tab := _tab("Shapes")
	var light_tab := _tab("Light")
	var cam_tab := _tab("Camera")
	_lamp_box = UI.vbox(8)
	_build_layer_section(layer_tab)
	_prop_box = UI.vbox(8)
	shapes_tab.add_child(_prop_box)
	_build_prop_section(_prop_box)
	_build_shape_list(shapes_tab)
	_build_stage_section(shapes_tab)
	_build_lowpoly_section(shapes_tab)
	_build_light_section(light_tab)
	_build_camera_section(cam_tab)
	_build_render_section(cam_tab)

	exporter = RenderExporter.new()
	add_child(exporter)
	exporter.progress.connect(_on_render_progress)
	exporter.finished.connect(_on_render_finished)

	for sig: Signal in [App.project_opened, App.scene_switched]:
		sig.connect(_rebuild_list)
	for sig: Signal in [App.layers_changed, App.layer_selected, App.frame_changed]:
		sig.connect(_refresh_list)
	for sig: Signal in [App.project_opened, App.scene_switched, App.layers_changed, App.layer_selected,
			App.frame_changed, App.camera_changed, App.timeline_changed, App.stage_changed]:
		sig.connect(_sync)
	depth.selection_changed.connect(_sync)
	depth.selection_changed.connect(func() -> void:
		if depth.select_kind == "prop":
			_tabs.current_tab = _shapes_tab
		elif depth.select_kind == "lamp":
			_tabs.current_tab = 2)
	depth.gizmo_mode_changed.connect(_sync_tools)
	_rebuild_list()
	_sync()


# ================================================================ sections

func _tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var v := UI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _on_tool(tool: String) -> void:
	if tool == "paint":
		depth.set_paint_mode(true)
		if depth.select_kind != "prop":
			App.status("Click a set piece and drag to draw on it. Make the piece clear to leave only your lines floating in 3D.")
		_tabs.current_tab = _shapes_tab
	else:
		depth.set_gizmo_mode(tool)


func _sync_tools() -> void:
	var key := "paint" if depth.paint_mode else depth.gizmo_mode
	for k in _tool_btns.keys():
		var b: Button = _tool_btns[k]
		b.set_pressed_no_signal(k == key)
	if _paint_toggle != null:
		_paint_toggle.set_pressed_no_signal(depth.paint_mode)


func _build_shape_list(parent: Control) -> void:
	var sec := UI.section(parent, "Shapes in this set")
	var hint := UI.label("Click to select. W move · E rotate · R scale · B draw · Ctrl+D duplicate · Delete removes.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)
	_shape_list = ItemList.new()
	_shape_list.custom_minimum_size.y = UI.px(120)
	_shape_list.focus_mode = Control.FOCUS_NONE
	_shape_list.item_selected.connect(func(i: int) -> void:
		var id := str(_shape_list.get_item_metadata(i))
		depth.select_prop(id))
	sec.add_child(_shape_list)
	sec.add_child(UI.label("ADD A SHAPE", "SectionTitle"))
	var flow := _flow(sec)
	for i in ShapeMesh.TYPES.size():
		var b := UI.button(ShapeMesh.TYPE_NAMES[i], "", "Adds a %s in front of the camera" % ShapeMesh.TYPE_NAMES[i].to_lower(), "DepthButton")
		b.pressed.connect(_add_prop.bind(ShapeMesh.TYPES[i]))
		flow.add_child(b)
	var wall := UI.button("Wall", "", "A thin box for walls and floors", "DepthButton")
	wall.pressed.connect(_add_prop.bind("wall"))
	flow.add_child(wall)


func _sync_shape_list(s: SceneData) -> void:
	var ids := PackedStringArray()
	for item in s.stage_value("props"):
		var p: Dictionary = item
		ids.append(str(p.get("id", "")) + ":" + str(p.get("name", "")) + ":" + str(DepthView.prop_clear(p) >= 0.99) + str(s.prop_paint.has(str(p.get("id", "")))))
	var key := ",".join(ids)
	if key != _shape_list_key:
		_shape_list_key = key
		_shape_list.clear()
		for item in s.stage_value("props"):
			var p: Dictionary = item
			var id := str(p.get("id", ""))
			var label := str(p.get("name", "Piece"))
			if DepthView.prop_clear(p) >= 0.99:
				label += "  (clear)"
			if s.prop_paint.has(id):
				label += "  ✎"
			var idx := _shape_list.add_item(label)
			_shape_list.set_item_metadata(idx, id)
	_shape_list.deselect_all()
	if depth.select_kind == "prop":
		for i in _shape_list.item_count:
			if str(_shape_list.get_item_metadata(i)) == depth.selected_prop:
				_shape_list.select(i)


func _build_layer_section(parent: Control) -> void:
	var sec := UI.section(parent, "Selected layer")
	_layer_title = UI.label("", "Heading")
	sec.add_child(_layer_title)
	var place := HFlowContainer.new()
	place.add_theme_constant_override("h_separation", int(UI.px(5)))
	place.add_theme_constant_override("v_separation", int(UI.px(5)))
	sec.add_child(place)
	for p in PLACEMENTS:
		var b := UI.button(p[0], "", "Quick placement: depth %s" % str(p[1]), "DepthButton")
		b.pressed.connect(_motion_set.bind("depth", float(p[1])))
		place.add_child(b)
	_f["depth"] = _depth_slider(sec, "Depth", -8, 80, 0.1, "%.1f", "depth")
	_f["x"] = UI.slider(sec, "Horizontal", -4000, 4000, 1, 0, _on_layer_x, "%d px")
	_f["y"] = UI.slider(sec, "Vertical", -4000, 4000, 1, 0, _on_layer_y, "%d px")
	_f["scale"] = UI.slider(sec, "Scale", 5, 400, 1, 100, _on_layer_scale, "%d%%")
	_f["rotation"] = UI.slider(sec, "Rotation", -180, 180, 1, 0, _on_layer_rotation, "%d°")
	_f["opacity"] = UI.slider(sec, "Opacity", 0, 100, 1, 100, _on_layer_opacity, "%d%%")
	_keep_size = CheckBox.new()
	_keep_size.text = "Keep apparent size when moved in depth"
	_keep_size.focus_mode = Control.FOCUS_NONE
	_keep_size.tooltip_text = "On: pushing a layer back only changes parallax.\nOff: it also gets smaller, like a real object."
	_keep_size.toggled.connect(func(on: bool) -> void: _layer_set("keep_size", on))
	sec.add_child(_keep_size)
	_f["turn"] = UI.slider(sec, "Turn (face left / right)", -89, 89, 1, 0, _on_layer_float.bind("turn"), "%d°")
	_f["tilt"] = UI.slider(sec, "Tilt (lean back / forward)", -89, 89, 1, 0, _on_layer_float.bind("tilt"), "%d°")
	for k in ["turn", "tilt"]:
		var sl: HSlider = _f[k]
		sl.theme_type_variation = "DepthSlider"
	var light_row := UI.hbox(8)
	sec.add_child(light_row)
	_lit = CheckBox.new()
	_lit.text = "Lit by the light"
	_lit.focus_mode = Control.FOCUS_NONE
	_lit.tooltip_text = "On: the drawing is shaded by the stage light and receives shadows.\nOff: its colours stay exactly as drawn."
	_lit.toggled.connect(func(on: bool) -> void: _layer_set("lit", on))
	light_row.add_child(_lit)
	_cast = CheckBox.new()
	_cast.text = "Casts a shadow"
	_cast.focus_mode = Control.FOCUS_NONE
	_cast.tooltip_text = "The drawing casts a shadow shaped like its painted pixels"
	_cast.toggled.connect(func(on: bool) -> void: _layer_set("cast_shadow", on))
	light_row.add_child(_cast)
	var floor_row := UI.hbox(6)
	sec.add_child(floor_row)
	var stand := UI.button("Stand on floor", "", "Moves the layer up or down so the bottom of its drawing touches the floor", "DepthButton")
	stand.pressed.connect(_stand_on_floor)
	floor_row.add_child(stand)
	var upright := UI.button("Face camera", "", "Reset turn and tilt", "FlatButton")
	upright.pressed.connect(func() -> void:
		var l := App.current_layer()
		if l != null:
			Ops.set_layer_motion(l, {"turn": 0.0, "tilt": 0.0}, "Face camera (%s)" % l.name))
	floor_row.add_child(upright)

	sec.add_child(HSeparator.new())
	sec.add_child(UI.label("LAYER ANIMATION", "SectionTitle"))
	_motion_state = UI.label("", "Small")
	_motion_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_motion_state)
	var mk := UI.hbox(6)
	sec.add_child(mk)
	var add_key := UI.button("Add key", "key", "Start animating this layer: adds a motion key at this frame", "Button")
	add_key.pressed.connect(func() -> void: Ops.add_motion_key(App.current_layer()))
	mk.add_child(add_key)
	var del_key := UI.button("Delete key", "trash", "Delete this layer's motion key on this frame", "FlatButton")
	del_key.pressed.connect(func() -> void: Ops.delete_motion_key(App.current_layer()))
	mk.add_child(del_key)
	var clear_m := UI.icon_button("reset", "Remove all motion keys (keeps the current placement)")
	clear_m.pressed.connect(func() -> void: Ops.clear_motion(App.current_layer()))
	mk.add_child(clear_m)
	var ease_row := UI.hbox(6)
	sec.add_child(ease_row)
	ease_row.add_child(UI.label("Motion to next key", "FieldLabel"))
	_motion_ease = UI.option(["Smooth", "Linear", "Ease in", "Ease out", "Hold"])
	_motion_ease.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_motion_ease.item_selected.connect(_on_motion_ease)
	ease_row.add_child(_motion_ease)
	var mflow := HFlowContainer.new()
	mflow.add_theme_constant_override("h_separation", int(UI.px(5)))
	mflow.add_theme_constant_override("v_separation", int(UI.px(5)))
	sec.add_child(mflow)
	for mp in MOTION_PRESETS:
		var b := UI.button(mp[0], "", "Adds keys from the playhead over the next half second", "Button")
		b.pressed.connect(func() -> void: Ops.apply_motion_preset(App.current_layer(), str(mp[1])))
		mflow.add_child(b)


func _depth_slider(parent: Control, title: String, min_v: float, max_v: float, step: float, fmt: String, prop: String) -> HSlider:
	var s := UI.slider(parent, title, min_v, max_v, step, 0, _on_layer_float.bind(prop), fmt)
	s.theme_type_variation = "DepthSlider"
	return s


func _build_light_section(parent: Control) -> void:
	var sec := UI.section(parent, "Light & shadows")
	var type_row := UI.hbox(6)
	sec.add_child(type_row)
	type_row.add_child(UI.label("Light", "FieldLabel"))
	var lt := UI.option(["Sun (even, far away)", "Lamp (a bulb you place)", "No light (flat)"])
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lt.item_selected.connect(func(i: int) -> void: _stage_set("light", ["sun", "lamp", "none"][i]))
	type_row.add_child(lt)
	_st["light"] = lt

	_sun_box = UI.vbox(6)
	sec.add_child(_sun_box)
	var dial_row := UI.hbox(10)
	_sun_box.add_child(dial_row)
	_light_dial = LightDial.new()
	_light_dial.custom_minimum_size = UI.size2(96, 96)
	_light_dial.tooltip_text = "Drag the sun: around = direction, toward the middle = higher in the sky"
	_light_dial.changed.connect(_on_dial)
	dial_row.add_child(_light_dial)
	var dial_side := UI.vbox(4)
	dial_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dial_row.add_child(dial_side)
	_st["azimuth"] = UI.slider(dial_side, "Direction", -180, 180, 1, -35, _stage_float.bind("azimuth"), "%d°")
	_st["elevation"] = UI.slider(dial_side, "Height", 3, 90, 1, 42, _stage_float.bind("elevation"), "%d°")

	sec.add_child(_lamp_box)
	var lamp_note := UI.label("Click the yellow lamp in the view and drag its arrows to move it.", "Small")
	lamp_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lamp_box.add_child(lamp_note)
	var sel_lamp := UI.button("Select lamp", "", "Show the move arrows on the lamp", "DepthButton")
	sel_lamp.pressed.connect(func() -> void:
		depth.select_kind = "lamp"
		depth.refresh()
		_sync())
	_lamp_box.add_child(sel_lamp)
	_st["lamp_range"] = UI.slider(_lamp_box, "Reach", 2, 80, 0.5, 25, _stage_float.bind("lamp_range"), "%.1f")

	var col_row := UI.hbox(6)
	sec.add_child(col_row)
	col_row.add_child(UI.label("Colour", "FieldLabel"))
	var lc := ColorPickerButton.new()
	lc.custom_minimum_size = UI.size2(60, 26)
	lc.edit_alpha = false
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.color_changed.connect(func(c: Color) -> void: _stage_set("light_color", c.to_html(true)))
	col_row.add_child(lc)
	_st["light_color"] = lc
	_st["energy"] = UI.slider(sec, "Brightness", 0, 4, 0.05, 1.3, _stage_float.bind("energy"), "%.2f")
	_st["ambient"] = UI.slider(sec, "Fill light (ambient)", 0, 2, 0.05, 0.55, _stage_float.bind("ambient"), "%.2f")

	sec.add_child(HSeparator.new())
	var sh := CheckBox.new()
	sh.text = "Cast shadows"
	sh.focus_mode = Control.FOCUS_NONE
	sh.toggled.connect(func(on: bool) -> void: _stage_set("shadows", on))
	sec.add_child(sh)
	_st["shadows"] = sh
	sec.add_child(UI.label("SHADOW METER", "SectionTitle"))
	_meter = ShadowMeter.new()
	_meter.custom_minimum_size.y = UI.px(34)
	_meter.tooltip_text = "Preview of a shadow on the floor: left is lit ground, right is in shadow"
	sec.add_child(_meter)
	_st["shadow_strength"] = UI.slider(sec, "Shadow darkness", 0, 100, 1, 75, _on_shadow_strength, "%d%%")
	_st["shadow_softness"] = UI.slider(sec, "Shadow softness", 0, 4, 0.05, 1.0, _stage_float.bind("shadow_softness"), "%.2f")
	var hint := UI.label("Turn on “Lit by the light” on a layer to shade it; any layer with “Casts a shadow” throws its drawing's shape onto the floor and set pieces.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)


func _build_stage_section(parent: Control) -> void:
	var sec := UI.section(parent, "3D set")
	var fl := CheckBox.new()
	fl.text = "Show floor"
	fl.focus_mode = Control.FOCUS_NONE
	fl.toggled.connect(func(on: bool) -> void: _stage_set("floor", on))
	sec.add_child(fl)
	_st["floor"] = fl
	var fc_row := UI.hbox(6)
	sec.add_child(fc_row)
	fc_row.add_child(UI.label("Floor colour", "FieldLabel"))
	var fc := ColorPickerButton.new()
	fc.custom_minimum_size = UI.size2(60, 26)
	fc.edit_alpha = false
	fc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fc.color_changed.connect(func(c: Color) -> void: _stage_set("floor_color", c.to_html(true)))
	fc_row.add_child(fc)
	_st["floor_color"] = fc
	_st["floor_offset"] = UI.slider(sec, "Floor height", -10, 10, 0.05, 0, _stage_float.bind("floor_offset"), "%.2f")
	var how := UI.label("Rough out the space with shapes, then press “Make low-poly set” below to turn them into a finished low-poly set.", "Small")
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(how)
	sec.add_child(UI.label("QUICK SETS — start from a rough layout", "SectionTitle"))
	var qflow := _flow(sec)
	for t in ["Street", "Room", "Forest", "Hills"]:
		var b := UI.button(t, "", "Replaces the set pieces with a rough %s layout you can then move around (undo brings yours back)" % t.to_lower(), "Button")
		b.pressed.connect(_apply_template.bind(t))
		qflow.add_child(b)
	var clear := UI.button("Clear", "trash", "Remove every set piece", "FlatButton")
	clear.pressed.connect(func() -> void:
		Ops.set_stage_value("props", [], "Clear set pieces")
		depth.select_kind = "layer"
		_sync())
	qflow.add_child(clear)
	sec.add_child(UI.label("READY PIECES", "SectionTitle"))
	var rflow := _flow(sec)
	for t in [["Building", "building"], ["Tree", "tree"], ["Bush", "bush"], ["Rock", "rock"], ["Hill", "hill"]]:
		var b := UI.button(t[0], "", "A blockout shape that becomes a %s in the low-poly set" % str(t[0]).to_lower(), "DepthButton")
		b.pressed.connect(_add_role.bind(str(t[1])))
		rflow.add_child(b)
	var snap := CheckBox.new()
	snap.text = "Snap to grid when dragging (hold Alt to move freely)"
	snap.focus_mode = Control.FOCUS_NONE
	snap.toggled.connect(func(on: bool) -> void: _stage_set("snap", on))
	sec.add_child(snap)
	_st["snap"] = snap


func _flow(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", int(UI.px(5)))
	f.add_theme_constant_override("v_separation", int(UI.px(5)))
	parent.add_child(f)
	return f


func _build_lowpoly_section(parent: Control) -> void:
	var sec := UI.section(parent, "Low-poly set")
	var modes := UI.hbox(6)
	sec.add_child(modes)
	var group := ButtonGroup.new()
	_lp_mode_block = UI.button("Blockout", "", "Show the rough shapes", "DepthButton")
	_lp_mode_block.toggle_mode = true
	_lp_mode_block.button_group = group
	_lp_mode_block.pressed.connect(_lp_set.bind(false, "on"))
	modes.add_child(_lp_mode_block)
	_lp_mode_low = UI.button("Make low-poly set", "", "Turn the shapes into a faceted, toon-shaded set with ink outlines", "AccentButton")
	_lp_mode_low.toggle_mode = true
	_lp_mode_low.button_group = group
	_lp_mode_low.pressed.connect(_lp_set.bind(true, "on"))
	modes.add_child(_lp_mode_low)
	_lp_box = UI.vbox(6)
	sec.add_child(_lp_box)
	var pr := UI.hbox(6)
	_lp_box.add_child(pr)
	pr.add_child(UI.label("Palette", "FieldLabel"))
	var pal := UI.option(LowPolyBuilder.PALETTES.keys())
	pal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pal.tooltip_text = "Colours for ground, rocks, trees and buildings. Shapes you coloured yourself keep their colour."
	pal.item_selected.connect(func(i: int) -> void: _lp_set(str(LowPolyBuilder.PALETTES.keys()[i]), "palette"))
	pr.add_child(pal)
	_lp["palette"] = pal
	var sr := UI.hbox(6)
	_lp_box.add_child(sr)
	sr.add_child(UI.label("Shading", "FieldLabel"))
	var sh := UI.option(["Toon (flat bands, like the drawings)", "Soft (smooth light)"])
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.item_selected.connect(func(i: int) -> void: _lp_set("toon" if i == 0 else "soft", "shading"))
	sr.add_child(sh)
	_lp["shading"] = sh
	_lp["bands"] = UI.slider(_lp_box, "Light bands", 1, 5, 1, 3, _lp_float.bind("bands"), "%d")
	_lp["detail"] = UI.slider(_lp_box, "Detail (more facets)", 0.4, 2.5, 0.1, 1.0, _lp_float.bind("detail"), "%.1f")
	_lp["rough"] = UI.slider(_lp_box, "Hand-made wobble", 0, 1.5, 0.05, 0.5, _lp_float.bind("rough"), "%.2f")
	_lp["variation"] = UI.slider(_lp_box, "Colour variation", 0, 0.4, 0.01, 0.12, _lp_float.bind("variation"), "%.2f")
	_lp["outline"] = UI.slider(_lp_box, "Ink outline", 0, 0.25, 0.01, 0.06, _lp_float.bind("outline"), "%.2f")
	var ir := UI.hbox(6)
	_lp_box.add_child(ir)
	ir.add_child(UI.label("Ink colour", "FieldLabel"))
	var ink := ColorPickerButton.new()
	ink.custom_minimum_size = UI.size2(60, 26)
	ink.edit_alpha = false
	ink.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ink.popup_closed.connect(func() -> void: _lp_set(ink.color.to_html(true), "ink"))
	ir.add_child(ink)
	_lp["ink"] = ink
	var terr := CheckBox.new()
	terr.text = "Rolling ground instead of the flat floor"
	terr.focus_mode = Control.FOCUS_NONE
	terr.toggled.connect(func(on: bool) -> void: _lp_set(on, "terrain"))
	_lp_box.add_child(terr)
	_lp["terrain"] = terr
	_lp["hills"] = UI.slider(_lp_box, "Hills in the distance", 0, 3, 0.05, 1.0, _lp_float.bind("hills"), "%.2f")
	var reshuffle := UI.button("Reshuffle", "reset", "Same shapes, a different hand-made variation", "Button")
	reshuffle.pressed.connect(func() -> void:
		var lps: Dictionary = App.current_scene().stage_value("lowpoly")
		_lp_set(int(LowPolyBuilder.setting(lps, "seed")) + 1, "seed"))
	_lp_box.add_child(reshuffle)
	sec.add_child(HSeparator.new())
	_st["haze"] = UI.slider(sec, "Distance haze (blends 3D and drawings)", 0, 1, 0.01, 0, _stage_float.bind("haze"), "%.2f")
	var tip := UI.label("Tip: matching the Ink colour and line thickness to your drawings (or to the auto-rotoscope lines) makes the set read as part of the same picture. Haze fades far things toward the scene background colour.", "Small")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(tip)


func _lp_set(value: Variant, key: String) -> void:
	if _syncing or not App.has_project():
		return
	var s := App.current_scene()
	var cur: Dictionary = s.stage_value("lowpoly")
	var lps := cur.duplicate(true)
	lps[key] = value
	var label := "Low-poly set" if key != "on" else ("Make low-poly set" if bool(value) else "Back to blockout")
	Ops.set_stage_value("lowpoly", lps, label)


func _lp_float(v: float, key: String) -> void:
	_lp_set(v, key)


func _apply_template(t: String) -> void:
	if not App.has_project():
		return
	Ops.apply_set_template(t)
	depth.select_kind = "layer"
	App.status("Rough %s layout added. Drag pieces with the arrows, then press “Make low-poly set”." % t.to_lower())
	_sync()


func _add_role(role: String) -> void:
	if not App.has_project():
		return
	var id := Ops.add_prop("", role)
	depth.select_kind = "prop"
	depth.selected_prop = id
	depth.refresh()
	_sync()


func _build_prop_section(parent: Control) -> void:
	var sec := UI.section(parent, "Selected shape")
	_prop_title = UI.label("", "Heading")
	sec.add_child(_prop_title)
	_prop_name = LineEdit.new()
	_prop_name.placeholder_text = "Name"
	_prop_name.text_submitted.connect(func(t: String) -> void:
		Ops.set_prop_field(depth.selected_prop, "name", t)
		_prop_name.release_focus())
	_prop_name.focus_exited.connect(func() -> void:
		if not _syncing and depth.select_kind == "prop" and _prop_name.text != "":
			var p := depth.find_prop(depth.selected_prop)
			if str(p.get("name", "")) != _prop_name.text:
				Ops.set_prop_field(depth.selected_prop, "name", _prop_name.text))
	sec.add_child(_prop_name)
	var type_row := UI.hbox(6)
	sec.add_child(type_row)
	type_row.add_child(UI.label("Shape", "FieldLabel"))
	var ty := UI.option(ShapeMesh.TYPE_NAMES)
	ty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ty.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			Ops.set_prop_field(depth.selected_prop, "type", ShapeMesh.TYPES[i]))
	type_row.add_child(ty)
	_pf["type"] = ty
	var role_row := UI.hbox(6)
	sec.add_child(role_row)
	role_row.add_child(UI.label("Becomes", "FieldLabel"))
	var role := UI.option(LowPolyBuilder.ROLE_NAMES)
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role.tooltip_text = "What this shape turns into in the low-poly set"
	role.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			Ops.set_prop_field(depth.selected_prop, "role", LowPolyBuilder.ROLES[i]))
	role_row.add_child(role)
	_pf["role"] = role

	sec.add_child(UI.label("POSITION", "SectionTitle"))
	_pf["px"] = UI.slider(sec, "Left / right", -60, 60, 0.05, 0, _prop_vec.bind("pos", 0), "%.2f")
	_pf["py"] = UI.slider(sec, "Lift off floor", -5, 40, 0.05, 0, _prop_vec.bind("pos", 1), "%.2f")
	_pf["pz"] = UI.slider(sec, "Depth (away from camera)", -14, 120, 0.05, 6, _prop_vec.bind("pos", 2), "%.2f")
	sec.add_child(UI.label("ROTATION", "SectionTitle"))
	_pf["ry"] = UI.slider(sec, "Turn", -180, 180, 1, 0, _prop_vec.bind("rot", 1), "%d°")
	_pf["rx"] = UI.slider(sec, "Tip forward / back", -180, 180, 1, 0, _prop_vec.bind("rot", 0), "%d°")
	_pf["rz"] = UI.slider(sec, "Lean left / right", -180, 180, 1, 0, _prop_vec.bind("rot", 2), "%d°")
	var rrow := UI.hbox(6)
	sec.add_child(rrow)
	var upright := UI.button("Upright", "", "Reset the rotation", "FlatButton")
	upright.pressed.connect(func() -> void: Ops.set_prop_field(depth.selected_prop, "rot", [0.0, 0.0, 0.0]))
	rrow.add_child(upright)
	sec.add_child(UI.label("SIZE", "SectionTitle"))
	_pf["sx"] = UI.slider(sec, "Width", 0.1, 80, 0.05, 2, _prop_vec.bind("size", 0), "%.2f")
	_pf["sy"] = UI.slider(sec, "Height", 0.1, 60, 0.05, 2, _prop_vec.bind("size", 1), "%.2f")
	_pf["sz"] = UI.slider(sec, "Depth", 0.1, 80, 0.05, 2, _prop_vec.bind("size", 2), "%.2f")
	var srow := UI.hbox(6)
	sec.add_child(srow)
	for f in [["½×", 0.5], ["0.9×", 0.9], ["1.1×", 1.1], ["2×", 2.0]]:
		var b := UI.button(str(f[0]), "", "Resize evenly", "FlatButton")
		b.pressed.connect(_scale_prop.bind(float(f[1])))
		srow.add_child(b)

	sec.add_child(UI.label("LOOK", "SectionTitle"))
	var c_row := UI.hbox(6)
	sec.add_child(c_row)
	c_row.add_child(UI.label("Colour", "FieldLabel"))
	var pc := ColorPickerButton.new()
	pc.custom_minimum_size = UI.size2(60, 26)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.edit_alpha = false
	pc.popup_closed.connect(func() -> void:
		Ops.set_prop_field(depth.selected_prop, "color", pc.color.to_html(true)))
	c_row.add_child(pc)
	_pf["color"] = pc
	_pf["clear"] = UI.slider(sec, "See-through (solid → clear)", 0, 100, 1, 0, _on_prop_clear, "%d%%")
	var clear_note := UI.label("At 100% the shape disappears from the picture (a faint blue ghost stays in the editor) — anything you draw on it stays, floating in 3D.", "Small")
	clear_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(clear_note)
	var cast := CheckBox.new()
	cast.text = "Casts a shadow (even when clear)"
	cast.focus_mode = Control.FOCUS_NONE
	cast.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			Ops.set_prop_field(depth.selected_prop, "cast_shadow", on))
	sec.add_child(cast)
	_pf["cast"] = cast

	sec.add_child(UI.label("DRAW ON THIS SHAPE", "SectionTitle"))
	_paint_toggle = UI.button("Draw on shapes (B)", "brush", "Drag on any set piece to draw on its surface in 3D", "DepthButton")
	_paint_toggle.toggle_mode = true
	_paint_toggle.toggled.connect(func(on: bool) -> void:
		depth.set_paint_mode(on))
	sec.add_child(_paint_toggle)
	_paint_box = UI.vbox(4)
	sec.add_child(_paint_box)
	var pen_row := UI.hbox(6)
	_paint_box.add_child(pen_row)
	pen_row.add_child(UI.label("Pen colour", "FieldLabel"))
	_pen_color = ColorPickerButton.new()
	_pen_color.custom_minimum_size = UI.size2(60, 26)
	_pen_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pen_color.color = App.color
	_pen_color.color_changed.connect(func(c: Color) -> void: App.set_color(c))
	pen_row.add_child(_pen_color)
	_pen_size = UI.slider(_paint_box, "Pen size", 0.01, 1.5, 0.01, 0.12, _on_pen_size, "%.2f")
	_erase_toggle = CheckBox.new()
	_erase_toggle.text = "Eraser"
	_erase_toggle.focus_mode = Control.FOCUS_NONE
	_erase_toggle.toggled.connect(func(on: bool) -> void: depth.paint_erase = on)
	_paint_box.add_child(_erase_toggle)
	var clear_paint := UI.button("Clear drawing", "trash", "Remove everything drawn on this shape", "FlatButton")
	clear_paint.pressed.connect(func() -> void: Ops.clear_prop_paint(depth.selected_prop))
	_paint_box.add_child(clear_paint)
	var how := UI.label("Tip: build a rough form from shapes, draw your details onto them, then make the shapes clear — the lines stay put in 3D and turn with the camera, no sculpting needed.", "Small")
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paint_box.add_child(how)

	var row := UI.hbox(6)
	sec.add_child(row)
	var dup := UI.button("Duplicate", "", "Copy this shape (Ctrl+D)", "Button")
	dup.pressed.connect(_duplicate_prop)
	row.add_child(dup)
	var del := UI.button("Delete", "trash", "Remove this shape (Delete)", "FlatButton")
	del.pressed.connect(func() -> void:
		Ops.delete_prop(depth.selected_prop)
		depth.select_kind = "layer"
		_sync())
	row.add_child(del)
	var back := UI.button("Done", "", "Deselect (Esc)", "FlatButton")
	back.pressed.connect(func() -> void:
		depth.select_kind = "layer"
		depth.set_paint_mode(false)
		depth.refresh()
		_sync())
	row.add_child(back)


func _on_pen_size(v: float) -> void:
	depth.paint_size = v


func _on_prop_clear(v: float) -> void:
	if not _syncing:
		Ops.set_prop_field(depth.selected_prop, "clear", v / 100.0)


func _scale_prop(f: float) -> void:
	var p := depth.find_prop(depth.selected_prop)
	if p.is_empty():
		return
	var sz := DepthView._vec3(p.get("size"), Vector3.ONE) * f
	Ops.set_prop_field(depth.selected_prop, "size", [maxf(0.1, sz.x), maxf(0.1, sz.y), maxf(0.1, sz.z)])


func _stage_set(key: String, value: Variant) -> void:
	if _syncing or not App.has_project():
		return
	Ops.set_stage_value(key, value)


func _stage_float(v: float, key: String) -> void:
	_stage_set(key, v)


func _on_shadow_strength(v: float) -> void:
	_stage_set("shadow_strength", v / 100.0)


func _on_dial(az: float, el: float) -> void:
	if _syncing or not App.has_project():
		return
	# Same label, so a whole drag merges into one undo step.
	Ops.set_stage_value("azimuth", az, "Move sun")
	Ops.set_stage_value("elevation", el, "Move sun")


func _add_prop(type: String) -> void:
	if not App.has_project():
		return
	var id := Ops.add_prop(type)
	depth.select_kind = "prop"
	depth.selected_prop = id
	depth.refresh()
	_sync()


func _duplicate_prop() -> void:
	var id := Ops.duplicate_prop(depth.selected_prop)
	if id != "":
		depth.select_prop(id)
	_sync()


func _prop_vec(v: float, field: String, axis: int) -> void:
	if _syncing:
		return
	var p := depth.find_prop(depth.selected_prop)
	if p.is_empty():
		return
	var fallback := [1.0, 1.0, 1.0] if field == "size" else [0.0, 0.0, 0.0]
	var got: Array = p.get(field, fallback)
	var arr: Array = got.duplicate()
	while arr.size() < 3:
		arr.append(fallback[arr.size()])
	arr[axis] = v
	Ops.set_prop_field(depth.selected_prop, field, arr)


func _stand_on_floor() -> void:
	var l := App.current_layer()
	if l == null:
		return
	if l.is_character():
		App.status("Stand on floor works on drawn layers; move characters with the arrows")
		return
	var y := depth.floor_offset_for(l)
	if is_nan(y):
		App.status("Nothing drawn on this frame to stand on the floor")
		return
	Ops.set_layer_motion(l, {"y": y}, "Stand on floor (%s)" % l.name)


func _build_camera_section(parent: Control) -> void:
	var sec := UI.section(parent, "Scene camera")
	_key_state = UI.label("", "Small")
	_key_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_key_state)
	var keys := UI.hbox(6)
	sec.add_child(keys)
	var add := UI.button("Add key", "key", "Add a camera key at this frame", "DepthButton")
	add.pressed.connect(Ops.add_camera_key)
	keys.add_child(add)
	var del := UI.button("Delete key", "trash", "Delete the camera key on this frame", "FlatButton")
	del.pressed.connect(Ops.delete_camera_key)
	keys.add_child(del)
	var clr := UI.icon_button("reset", "Remove all camera keys")
	clr.pressed.connect(Ops.clear_camera)
	keys.add_child(clr)
	_c["x"] = UI.slider(sec, "Pan horizontal", -3000, 3000, 1, 0, _cam_set.bind("x"), "%d px")
	_c["y"] = UI.slider(sec, "Pan vertical", -3000, 3000, 1, 0, _cam_set.bind("y"), "%d px")
	_c["dolly"] = UI.slider(sec, "Dolly (move forward)", -30, 12, 0.1, 0, _cam_set.bind("dolly"), "%.1f")
	_c["zoom"] = UI.slider(sec, "Zoom", 25, 400, 1, 100, _on_cam_zoom, "%d%%")
	_c["roll"] = UI.slider(sec, "Roll", -45, 45, 0.5, 0, _cam_set.bind("roll"), "%.1f°")
	_c["shake"] = UI.slider(sec, "Shake", 0, 60, 0.5, 0, _cam_set.bind("shake"), "%.1f px")
	for k in _c.keys():
		var sl: HSlider = _c[k]
		sl.theme_type_variation = "DepthSlider"
	var ease_row := UI.hbox(6)
	sec.add_child(ease_row)
	ease_row.add_child(UI.label("Motion to next key", "FieldLabel"))
	_ease = UI.option(["Smooth", "Linear", "Ease in", "Ease out", "Hold"])
	_ease.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ease.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			_cam_set(SceneData.EASES[i], "ease"))
	ease_row.add_child(_ease)
	sec.add_child(UI.label("PRESETS", "SectionTitle"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(UI.px(5)))
	flow.add_theme_constant_override("v_separation", int(UI.px(5)))
	sec.add_child(flow)
	for p in PRESETS:
		var b := UI.button(p[0], "", "Replaces the camera keys with a ready-made move over the whole scene", "DepthButton")
		b.pressed.connect(Ops.apply_camera_preset.bind(p[1]))
		flow.add_child(b)


func _build_render_section(parent: Control) -> void:
	var sec := UI.section(parent, "Render")
	var info := UI.label("Renders this scene through the camera at project resolution as a PNG sequence.", "Small")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(info)
	_transparent = CheckBox.new()
	_transparent.text = "Transparent background"
	_transparent.focus_mode = Control.FOCUS_NONE
	sec.add_child(_transparent)
	_mp4 = CheckBox.new()
	_mp4.text = "Also encode MP4 (uses FFmpeg if found)"
	_mp4.focus_mode = Control.FOCUS_NONE
	_mp4.button_pressed = true
	sec.add_child(_mp4)
	_transparent.visible = false
	_mp4.visible = false
	info.text = "Export this scene through the camera: choose resolution, frame rate, quality and format."
	_render_btn = UI.button("Export…", "render", "", "AccentButton")
	_render_btn.pressed.connect(func() -> void:
		if _export_dialog == null:
			_export_dialog = ExportDialog.new()
			add_child(_export_dialog)
		depth.set_through_camera(true)
		_mode_cam.set_pressed_no_signal(true)
		_export_dialog.open_scene(exporter))
	sec.add_child(_render_btn)
	_progress = ProgressBar.new()
	_progress.visible = false
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = UI.px(6)
	sec.add_child(_progress)
	_render_status = UI.label("", "Small")
	_render_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_render_status)
	_out_dialog = FileDialog.new()
	_out_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_out_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_out_dialog.use_native_dialog = true
	_out_dialog.title = "Choose an output folder"
	_out_dialog.dir_selected.connect(_start_render)
	add_child(_out_dialog)


# ================================================================ layer list

func _structure_key() -> String:
	var s := App.current_scene()
	if s == null:
		return ""
	var ids := PackedStringArray()
	for l in s.layers:
		ids.append(l.id)
	ids.sort()
	return ",".join(ids)


## Updates rows in place (so a slider being dragged is never destroyed);
## rebuilds only when layers were added or removed.
func _refresh_list() -> void:
	if _structure_key() != _list_key:
		_rebuild_list()
		return
	var active := App.current_layer()
	for r in _list_rows:
		var row: Dictionary = r
		var layer: LayerData = row["layer"]
		var panel: PanelContainer = row["panel"]
		panel.theme_type_variation = "LayerRowSelected" if layer == active else "LayerRow"
		var n: Label = row["name_label"]
		n.text = layer.name
		n.modulate.a = 1.0 if layer.visible else 0.45
		var dl: Label = row["depth_label"]
		var dep: float = layer.motion_at(App.frame)["depth"]
		dl.text = "%.1f" % dep
		var sl: HSlider = row["slider"]
		if not _list_dragging:
			sl.set_value_no_signal(dep)


func _rebuild_list() -> void:
	for c in _layer_list.get_children():
		c.queue_free()
	_list_rows.clear()
	_list_key = _structure_key()
	var s := App.current_scene()
	if s == null:
		return
	var order: Array = []
	for i in s.layers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return s.layers[a].depth < s.layers[b].depth)
	var active := App.current_layer()
	for i: int in order:
		var layer: LayerData = s.layers[i]
		var row := PanelContainer.new()
		row.theme_type_variation = "LayerRowSelected" if layer == active else "LayerRow"
		row.gui_input.connect(_on_row_input.bind(layer))
		_layer_list.add_child(row)
		var v := UI.vbox(2)
		row.add_child(v)
		var top := UI.hbox(4)
		v.add_child(top)
		var n := UI.label(layer.name)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not layer.visible:
			n.modulate.a = 0.45
		top.add_child(n)
		var dep: float = layer.motion_at(App.frame)["depth"]
		var dl := UI.label("%.1f" % dep, "Small")
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(dl)
		var sl := HSlider.new()
		sl.theme_type_variation = "DepthSlider"
		sl.min_value = -8
		sl.max_value = 80
		sl.step = 0.1
		sl.value = dep
		sl.focus_mode = Control.FOCUS_NONE
		sl.value_changed.connect(_on_list_depth.bind(layer))
		sl.drag_started.connect(func() -> void:
			_list_dragging = true
			App.set_layer(App.current_scene().layers.find(layer)))
		sl.drag_ended.connect(func(_changed: bool) -> void:
			_list_dragging = false
			_rebuild_list.call_deferred())
		v.add_child(sl)
		_list_rows.append({"layer": layer, "panel": row, "slider": sl, "depth_label": dl, "name_label": n})


func _on_row_input(e: InputEvent, layer: LayerData) -> void:
	var mb := e as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		App.set_layer(App.current_scene().layers.find(layer))


func _on_list_depth(val: float, layer: LayerData) -> void:
	Ops.set_layer_motion(layer, {"depth": val})


# ================================================================ sync

func _sync() -> void:
	if not App.has_project():
		return
	_syncing = true
	var l := App.current_layer()
	if l != null:
		var m := l.motion_at(App.frame)
		_layer_title.text = l.name + ("  (reference — not rendered)" if l.is_reference() else "")
		UI.set_slider(_f["depth"], float(m["depth"]))
		UI.set_slider(_f["x"], float(m["x"]))
		UI.set_slider(_f["y"], float(m["y"]))
		UI.set_slider(_f["scale"], float(m["scale"]) * 100.0)
		UI.set_slider(_f["rotation"], float(m["rotation"]))
		UI.set_slider(_f["opacity"], float(m["opacity"]) * 100.0)
		_keep_size.set_pressed_no_signal(l.keep_size)
		UI.set_slider(_f["turn"], float(m.get("turn", 0.0)))
		UI.set_slider(_f["tilt"], float(m.get("tilt", 0.0)))
		_lit.set_pressed_no_signal(l.lit)
		_cast.set_pressed_no_signal(l.cast_shadow)
		_motion_ease.select(maxi(0, KeyTrack.EASES.find(str(m.get("ease", "smooth")))))
		if l.motion_keys.has(App.frame):
			_motion_state.text = "◆ Motion key on frame %d. Changes edit this key." % (App.frame + 1)
			_motion_state.modulate = Palette.ACCENT
		elif l.motion_keys.is_empty():
			_motion_state.text = "Not animated. Values above place the layer for the whole scene. Add a key (or a preset) to animate it."
			_motion_state.modulate = Palette.MUTED
		else:
			_motion_state.text = "Animated (%d keys). Changing a value adds a key on frame %d." % [l.motion_keys.size(), App.frame + 1]
			_motion_state.modulate = Palette.MUTED
	else:
		_layer_title.text = "No layer"
	var s := App.current_scene()
	_sync_stage(s)
	var st := s.camera_at(App.frame)
	for k in SceneData.CAMERA_FIELDS:
		var v: float = st[k]
		if k == "zoom":
			v *= 100.0
		UI.set_slider(_c[k], v)
	_ease.select(maxi(0, SceneData.EASES.find(str(st.get("ease", "smooth")))))
	_lens.select(1 if s.camera_ortho else 0)
	if s.camera_keys.has(App.frame):
		_key_state.text = "◆ Camera key on frame %d. Edits change this key." % (App.frame + 1)
		_key_state.modulate = Palette.DEPTH
	elif s.camera_keys.is_empty():
		_key_state.text = "No camera keys yet. Change any value below (or pick a preset) to start animating the camera."
		_key_state.modulate = Palette.MUTED
	else:
		_key_state.text = "Between keys. Changing a value adds a key on frame %d." % (App.frame + 1)
		_key_state.modulate = Palette.MUTED
	_syncing = false


func _sync_stage(s: SceneData) -> void:
	var light := str(s.stage_value("light"))
	(_st["light"] as OptionButton).select(maxi(0, ["sun", "lamp", "none"].find(light)))
	_sun_box.visible = light == "sun"
	_lamp_box.visible = light == "lamp"
	for k in ["azimuth", "elevation", "energy", "ambient", "shadow_softness", "floor_offset", "lamp_range"]:
		UI.set_slider(_st[k], float(s.stage_value(k)))
	UI.set_slider(_st["shadow_strength"], float(s.stage_value("shadow_strength")) * 100.0)
	(_st["shadows"] as CheckBox).set_pressed_no_signal(bool(s.stage_value("shadows")))
	(_st["floor"] as CheckBox).set_pressed_no_signal(bool(s.stage_value("floor")))
	(_st["snap"] as CheckBox).set_pressed_no_signal(bool(s.stage_value("snap")))
	UI.set_slider(_st["haze"], float(s.stage_value("haze")))
	var lps: Dictionary = s.stage_value("lowpoly")
	var lp_on := bool(LowPolyBuilder.setting(lps, "on"))
	_lp_mode_low.set_pressed_no_signal(lp_on)
	_lp_mode_block.set_pressed_no_signal(not lp_on)
	_lp_box.visible = lp_on
	(_lp["palette"] as OptionButton).select(maxi(0, LowPolyBuilder.PALETTES.keys().find(str(LowPolyBuilder.setting(lps, "palette")))))
	(_lp["shading"] as OptionButton).select(0 if str(LowPolyBuilder.setting(lps, "shading")) == "toon" else 1)
	for k in ["bands", "detail", "rough", "variation", "outline", "hills"]:
		UI.set_slider(_lp[k], float(LowPolyBuilder.setting(lps, k)))
	(_lp["terrain"] as CheckBox).set_pressed_no_signal(bool(LowPolyBuilder.setting(lps, "terrain")))
	(_lp["ink"] as ColorPickerButton).color = Color.from_string(str(LowPolyBuilder.setting(lps, "ink")), Color.BLACK)
	var lcol := Color.from_string(str(s.stage_value("light_color")), Color.WHITE)
	var fcol := Color.from_string(str(s.stage_value("floor_color")), Color("#343844"))
	(_st["light_color"] as ColorPickerButton).color = lcol
	(_st["floor_color"] as ColorPickerButton).color = fcol
	_light_dial.azimuth = float(s.stage_value("azimuth"))
	_light_dial.elevation = float(s.stage_value("elevation"))
	_light_dial.queue_redraw()
	_meter.strength = float(s.stage_value("shadow_strength")) if bool(s.stage_value("shadows")) and light != "none" else 0.0
	_meter.softness = float(s.stage_value("shadow_softness"))
	_meter.ambient = float(s.stage_value("ambient"))
	_meter.energy = float(s.stage_value("energy")) if light != "none" else 0.0
	_meter.floor_col = fcol
	_meter.light_col = lcol
	_meter.queue_redraw()
	var p: Dictionary = depth.find_prop(depth.selected_prop) if depth.select_kind == "prop" else {}
	_prop_box.visible = not p.is_empty()
	_sync_shape_list(s)
	_sync_tools()
	_paint_box.visible = depth.paint_mode
	_pen_color.color = App.color
	UI.set_slider(_pen_size, depth.paint_size)
	if not p.is_empty():
		var sz: Array = p.get("size", [1.0, 1.0, 1.0])
		var rot: Array = p.get("rot", [0.0, 0.0, 0.0])
		var pos: Array = p.get("pos", [0.0, 0.0, 0.0])
		_prop_title.text = str(p.get("name", "Set piece"))
		if not _prop_name.has_focus():
			_prop_name.text = str(p.get("name", ""))
		(_pf["role"] as OptionButton).select(maxi(0, LowPolyBuilder.ROLES.find(str(p.get("role", "auto")))))
		(_pf["type"] as OptionButton).select(maxi(0, ShapeMesh.TYPES.find(str(p.get("type", "box")))))
		UI.set_slider(_pf["px"], float(pos[0]))
		UI.set_slider(_pf["pz"], float(pos[2]))
		UI.set_slider(_pf["rx"], float(rot[0]))
		UI.set_slider(_pf["rz"], float(rot[2]))
		UI.set_slider(_pf["clear"], DepthView.prop_clear(p) * 100.0)
		(_pf["cast"] as CheckBox).set_pressed_no_signal(bool(p.get("cast_shadow", true)))
		UI.set_slider(_pf["sx"], float(sz[0]))
		UI.set_slider(_pf["sy"], float(sz[1]))
		UI.set_slider(_pf["sz"], float(sz[2]))
		UI.set_slider(_pf["ry"], float(rot[1]))
		UI.set_slider(_pf["py"], float(pos[1]))
		(_pf["color"] as ColorPickerButton).color = Color.from_string(str(p.get("color", "8a8f9cff")), Color.GRAY)


func _on_layer_x(v: float) -> void:
	_motion_set("x", v)


func _on_layer_y(v: float) -> void:
	_motion_set("y", v)


func _on_layer_scale(v: float) -> void:
	_motion_set("scale", v / 100.0)


func _on_layer_rotation(v: float) -> void:
	_motion_set("rotation", v)


func _on_layer_opacity(v: float) -> void:
	_motion_set("opacity", v / 100.0)


func _on_layer_float(v: float, prop: String) -> void:
	_motion_set(prop, v)


func _motion_set(field: String, value: float) -> void:
	if _syncing:
		return
	var l := App.current_layer()
	if l != null:
		Ops.set_layer_motion(l, {field: value})


func _on_motion_ease(i: int) -> void:
	if _syncing:
		return
	var l := App.current_layer()
	if l == null:
		return
	if l.motion_keys.is_empty():
		App.status("Add a motion key first")
		return
	Ops.set_layer_motion(l, {"ease": KeyTrack.EASES[i]}, "Change motion easing (%s)" % l.name)


func _on_cam_zoom(v: float) -> void:
	_cam_set(v / 100.0, "zoom")


func _layer_set(prop: String, value: Variant) -> void:
	if _syncing:
		return
	var l := App.current_layer()
	if l != null:
		Ops.set_layer_prop(l, prop, value)


func _cam_set(value: Variant, field: String) -> void:
	if _syncing:
		return
	Ops.set_camera_field(field, value)


# ================================================================ render

func _choose_output() -> void:
	if exporter.busy:
		exporter.cancel()
		return
	if not App.has_project():
		return
	var default_dir := App.project.root_dir.path_join("renders")
	DirAccess.make_dir_recursive_absolute(default_dir)
	_out_dialog.current_dir = default_dir
	_out_dialog.popup_centered_ratio(0.6)


func _start_render(dir: String) -> void:
	_progress.visible = true
	_progress.value = 0
	_render_btn.text = "Cancel render"
	_render_status.text = "Starting…"
	depth.set_through_camera(true)
	_mode_cam.set_pressed_no_signal(true)
	exporter.render_scene(depth, dir, _transparent.button_pressed, _mp4.button_pressed)


func _on_render_progress(done: int, total: int, message: String) -> void:
	_progress.max_value = total
	_progress.value = done
	_render_status.text = message


func _on_render_finished(ok: bool, message: String, output_dir: String) -> void:
	_progress.visible = false
	_render_btn.text = "Render scene…"
	_render_status.text = message + ("\n" + output_dir if ok else "")
	App.status(message)
	if ok:
		Platform.reveal(output_dir)
