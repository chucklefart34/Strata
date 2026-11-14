class_name SceneWorkspace
extends Control
## Scene manager and scene editor: the project's scenes as cards (with
## thumbnails), plus the selected scene's settings and its layer stack,
## where layers can be added by role (background, character, ...).

const ROLE_BUTTONS := [
	["Background", "background"], ["Midground", "midground"], ["Character", "character"],
	["Foreground", "foreground"], ["Effect", "effect"],
]

var _cards: VBoxContainer
var _name: LineEdit
var _length: SpinBox
var _seconds: Label
var _bg: ColorPickerButton
var _stack: VBoxContainer
var _title: Label
var _syncing: bool = false
var _thumb_cache: Dictionary = {}  # scene.id -> ImageTexture


func _ready() -> void:
	var root := UI.hbox(14)
	UI.full_rect(root)
	add_child(root)

	# ---------------------------------------------------------- scene list
	var left := PanelContainer.new()
	left.theme_type_variation = "Sidebar"
	left.custom_minimum_size.x = UI.px(330)
	root.add_child(left)
	var lv := UI.vbox(10)
	left.add_child(lv)
	var head := UI.hbox(4)
	lv.add_child(head)
	var t := UI.label("SCENES", "SectionTitle")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var add := UI.icon_button("plus", "New scene")
	add.pressed.connect(Ops.add_scene)
	head.add_child(add)
	var dup := UI.icon_button("copy", "Duplicate scene (copies all drawings)")
	dup.pressed.connect(func() -> void: Ops.duplicate_scene(App.scene_index))
	head.add_child(dup)
	var up := UI.icon_button("up", "Move scene earlier")
	up.pressed.connect(func() -> void: Ops.move_scene(App.scene_index, -1))
	head.add_child(up)
	var down := UI.icon_button("down", "Move scene later")
	down.pressed.connect(func() -> void: Ops.move_scene(App.scene_index, 1))
	head.add_child(down)
	var del := UI.icon_button("trash", "Delete scene")
	del.pressed.connect(func() -> void: Ops.delete_scene(App.scene_index))
	head.add_child(del)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_cards = UI.vbox(8)
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards)

	# ---------------------------------------------------------- scene editor
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(right_scroll)
	var rv := UI.vbox(14)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(rv)
	rv.add_child(HintBar.new("scenes", "A project holds any number of scenes. Each scene has its own layers, length, background color and camera. Select a scene here, then draw and animate it in the other workspaces."))
	_title = UI.label("", "Title")
	rv.add_child(_title)

	var settings := UI.section(rv, "Scene settings")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(UI.px(14)))
	grid.add_theme_constant_override("v_separation", int(UI.px(10)))
	settings.add_child(grid)
	grid.add_child(UI.label("Name", "FieldLabel"))
	_name = LineEdit.new()
	_name.custom_minimum_size.x = UI.px(320)
	_name.text_submitted.connect(_rename)
	_name.focus_exited.connect(func() -> void: _rename(_name.text))
	grid.add_child(_name)
	grid.add_child(UI.label("Length", "FieldLabel"))
	var len_row := UI.hbox(8)
	grid.add_child(len_row)
	_length = UI.spin(1, 100000, 1, 48, " frames")
	_length.custom_minimum_size.x = UI.px(150)
	_length.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			Ops.set_prop(App.current_scene(), "frame_count", int(v), "Scene length", "timeline"))
	len_row.add_child(_length)
	_seconds = UI.label("", "Muted")
	len_row.add_child(_seconds)
	grid.add_child(UI.label("Background", "FieldLabel"))
	_bg = ColorPickerButton.new()
	_bg.custom_minimum_size = UI.size2(80, 32)
	_bg.edit_alpha = false
	_bg.tooltip_text = "Color behind all layers in renders and thumbnails"
	_bg.popup_closed.connect(func() -> void:
		if App.has_project():
			Ops.set_prop(App.current_scene(), "bg_color", _bg.color, "Background color", "scene"))
	grid.add_child(_bg)

	var go := UI.hbox(8)
	settings.add_child(go)
	var to_draw := UI.button("Draw this scene", "brush", "", "AccentButton")
	to_draw.pressed.connect(func() -> void: App.workspace_requested.emit("draw"))
	go.add_child(to_draw)
	var to_anim := UI.button("Animate", "film")
	to_anim.pressed.connect(func() -> void: App.workspace_requested.emit("animate"))
	go.add_child(to_anim)
	var to_depth := UI.button("Stage in 3D", "cube", "", "DepthButton")
	to_depth.pressed.connect(func() -> void: App.workspace_requested.emit("depth"))
	go.add_child(to_depth)

	var layers := UI.section(rv, "Layer stack")
	var add_row := HFlowContainer.new()
	add_row.add_theme_constant_override("h_separation", int(UI.px(6)))
	add_row.add_theme_constant_override("v_separation", int(UI.px(6)))
	layers.add_child(add_row)
	add_row.add_child(UI.label("Add layer:", "FieldLabel"))
	for rb in ROLE_BUTTONS:
		var b := UI.button(rb[0], "plus", "Adds a %s layer at a suitable depth" % str(rb[0]).to_lower())
		b.pressed.connect(func() -> void: Ops.add_layer(str(rb[0]), str(rb[1])))
		add_row.add_child(b)
	_stack = UI.vbox(4)
	layers.add_child(_stack)

	for sig: Signal in [App.project_opened, App.scene_switched, App.layers_changed, App.timeline_changed, App.pixels_changed]:
		sig.connect(_queue_refresh)
	visibility_changed.connect(_queue_refresh)
	_refresh()


var _refresh_queued: bool = false


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	if not App.has_project() or not is_visible_in_tree():
		return
	_syncing = true
	var current := App.current_scene()
	_title.text = current.name
	if not _name.has_focus():
		_name.text = current.name
	_length.set_value_no_signal(current.frame_count)
	_seconds.text = "%.1f seconds at %d fps" % [current.duration_seconds(App.project.fps), App.project.fps]
	_bg.color = current.bg_color
	_syncing = false

	for c in _cards.get_children():
		c.queue_free()
	for i in App.project.scenes.size():
		var s: SceneData = App.project.scenes[i]
		_cards.add_child(_make_card(s, i, i == App.scene_index))

	for c in _stack.get_children():
		c.queue_free()
	for i in range(current.layers.size() - 1, -1, -1):
		var l: LayerData = current.layers[i]
		var row := UI.hbox(10)
		var n := UI.label(l.name)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(UI.label(str(LayerPanel.ROLE_LABELS.get(l.role, "")), "Muted"))
		row.add_child(UI.label("depth %.1f" % l.depth, "Small"))
		row.add_child(UI.label("linked character" if l.is_character() else "%d drawing(s)" % l.cels.size(), "Small"))
		_stack.add_child(row)


func _make_card(s: SceneData, index: int, selected: bool) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "SceneCardSelected" if selected else "SceneCard"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			App.set_scene(index)
			if mb.double_click:
				App.workspace_requested.emit("draw"))
	var h := UI.hbox(10)
	card.add_child(h)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = UI.size2(112, 63)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only the selected scene's thumbnail is regenerated; others use the cache.
	if selected or not _thumb_cache.has(s.id):
		_thumb_cache[s.id] = Thumbs.scene_frame(s, 0, 160, maxi(1, int(160.0 * App.project.height / App.project.width)))
	thumb.texture = _thumb_cache[s.id]
	h.add_child(thumb)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var n := UI.label("%d. %s" % [index + 1, s.name], "Heading")
	n.clip_text = true
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var meta := UI.label("%d frames · %.1fs · %d layers" % [s.frame_count, s.duration_seconds(App.project.fps), s.layers.size()], "Small")
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(meta)
	return card


func _rename(new_text: String) -> void:
	new_text = new_text.strip_edges()
	if not App.has_project() or new_text == "" or new_text == App.current_scene().name:
		return
	Ops.set_prop(App.current_scene(), "name", new_text, "Rename scene", "scene")
