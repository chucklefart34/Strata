class_name CameraPanel
extends VBoxContainer
## The scene camera in Animate, so 2D projects can pan, zoom, rotate and
## shake over their drawings without the Depth tab. Values are keyframed:
## changing one adds/edits a key on the current frame. "View through camera"
## shows the canvas framed as the final picture (you can keep drawing).

const PRESETS := [
	["Push in", "zoom_in"], ["Pull out", "pull_out"], ["Pan right", "pan_right"],
	["Pan left", "pan_left"], ["Impact shake", "shake"],
]

var _c: Dictionary = {}
var _state: Label
var _ease: OptionButton
var _view: CheckBox
var _syncing: bool = false


func _ready() -> void:
	var sec := UI.section(self, "Camera")
	_view = CheckBox.new()
	_view.text = "View through camera"
	_view.tooltip_text = "Show the canvas framed exactly like the final picture (pan, zoom, rotation, shake). You can still draw."
	_view.focus_mode = Control.FOCUS_NONE
	_view.toggled.connect(func(on: bool) -> void: App.set_camera_view(on))
	sec.add_child(_view)
	_state = UI.label("", "Small")
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_state)
	var keys := UI.hbox(6)
	sec.add_child(keys)
	var add := UI.button("Add key", "key", "Add a camera key at this frame", "Button")
	add.pressed.connect(Ops.add_camera_key)
	keys.add_child(add)
	var del := UI.button("Delete key", "trash", "Delete the camera key on this frame", "FlatButton")
	del.pressed.connect(Ops.delete_camera_key)
	keys.add_child(del)
	var clr := UI.icon_button("reset", "Remove all camera keys")
	clr.pressed.connect(Ops.clear_camera)
	keys.add_child(clr)
	_c["x"] = UI.slider(sec, "Pan left / right", -3000, 3000, 1, 0, _set.bind("x"), "%d px")
	_c["y"] = UI.slider(sec, "Pan up / down", -3000, 3000, 1, 0, _set.bind("y"), "%d px")
	_c["zoom"] = UI.slider(sec, "Zoom", 25, 400, 1, 100, _on_zoom, "%d%%")
	_c["roll"] = UI.slider(sec, "Rotate", -45, 45, 0.5, 0, _set.bind("roll"), "%.1f°")
	_c["shake"] = UI.slider(sec, "Shake", 0, 60, 0.5, 0, _set.bind("shake"), "%.1f px")
	var ease_row := UI.hbox(6)
	sec.add_child(ease_row)
	ease_row.add_child(UI.label("Motion to next key", "FieldLabel"))
	_ease = UI.option(["Smooth", "Linear", "Ease in", "Ease out", "Hold"])
	_ease.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ease.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			Ops.set_camera_field("ease", SceneData.EASES[i]))
	ease_row.add_child(_ease)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(UI.px(5)))
	flow.add_theme_constant_override("v_separation", int(UI.px(5)))
	sec.add_child(flow)
	for p in PRESETS:
		var b := UI.button(str(p[0]), "", "Replaces the camera keys with a ready-made move over the whole scene", "FlatButton")
		b.pressed.connect(Ops.apply_camera_preset.bind(str(p[1])))
		flow.add_child(b)
	for sig: Signal in [App.project_opened, App.scene_switched, App.frame_changed, App.camera_changed, App.camera_view_changed]:
		sig.connect(_sync)
	_sync()


func _set(value: Variant, field: String) -> void:
	if not _syncing and App.has_project():
		Ops.set_camera_field(field, value)


func _on_zoom(v: float) -> void:
	_set(v / 100.0, "zoom")


func _sync() -> void:
	if not App.has_project() or App.current_scene() == null:
		return
	_syncing = true
	var s := App.current_scene()
	var st := s.camera_at(App.frame)
	for k in _c.keys():
		var v: float = st[k]
		if k == "zoom":
			v *= 100.0
		UI.set_slider(_c[k], v)
	_ease.select(maxi(0, SceneData.EASES.find(str(st.get("ease", "smooth")))))
	_view.set_pressed_no_signal(App.camera_view)
	if s.camera_keys.has(App.frame):
		_state.text = "◆ Camera key on frame %d — changes edit this key." % (App.frame + 1)
		_state.modulate = Palette.ACCENT
	elif s.camera_keys.is_empty():
		_state.text = "Not animated. Change a value (or pick a move below) to start animating the camera."
		_state.modulate = Palette.MUTED
	else:
		_state.text = "Between keys — changing a value adds a key on frame %d." % (App.frame + 1)
		_state.modulate = Palette.MUTED
	_syncing = false
