class_name TransportBar
extends HBoxContainer
## Playback controls, frame readout, frame rate, scene length, onion skin and
## drawing/exposure editing — shown above every timeline.

const FPS_CHOICES := [12, 15, 18, 24, 25, 30]

var full: bool = true
var _play: Button
var _loop: Button
var _onion: Button
var _frame_label: Label
var _fps: OptionButton
var _length: SpinBox
var _before: SpinBox
var _after: SpinBox
var _syncing: bool = false


func _init(p_full: bool = true) -> void:
	full = p_full


func _ready() -> void:
	add_theme_constant_override("separation", int(UI.px(4)))
	var first := UI.icon_button("first", "First frame (Home)")
	first.pressed.connect(func() -> void: App.set_frame(0))
	var prev := UI.icon_button("prev", "Previous frame ( , )")
	prev.pressed.connect(func() -> void: App.step_frame(-1))
	_play = UI.icon_button("play", "Play / pause (Enter)")
	_play.pressed.connect(App.toggle_play)
	var next := UI.icon_button("next", "Next frame ( . )")
	next.pressed.connect(func() -> void: App.step_frame(1))
	var last := UI.icon_button("last", "Last frame (End)")
	last.pressed.connect(func() -> void: App.set_frame(App.frame_count() - 1))
	_loop = UI.icon_button("loop", "Loop playback", true)
	_loop.toggled.connect(func(on: bool) -> void: App.loop_playback = on)
	for b in [first, prev, _play, next, last, _loop]:
		add_child(b)

	_frame_label = UI.label("", "ValueLabel")
	_frame_label.custom_minimum_size.x = UI.px(96)
	_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_frame_label)
	add_child(UI.vsep())

	var fps_names := []
	for f in FPS_CHOICES:
		fps_names.append("%d fps" % f)
	_fps = UI.option(fps_names)
	_fps.tooltip_text = "Project frame rate"
	_fps.item_selected.connect(_on_fps)
	add_child(_fps)
	_length = UI.spin(1, 100000, 1, 48, " fr")
	_length.tooltip_text = "Scene length in frames"
	_length.value_changed.connect(_on_length)
	add_child(_length)

	if full:
		add_child(UI.vsep())
		_onion = UI.icon_button("onion", "Onion skin — see neighbouring drawings", true)
		_onion.toggled.connect(func(on: bool) -> void:
			App.onion_enabled = on
			App.onion_changed.emit())
		add_child(_onion)
		_before = UI.spin(0, 6, 1, App.onion_before)
		_before.custom_minimum_size.x = UI.px(64)
		_before.tooltip_text = "Drawings shown before (red)"
		_before.value_changed.connect(func(v: float) -> void:
			App.onion_before = int(v)
			App.onion_changed.emit())
		add_child(_before)
		_after = UI.spin(0, 6, 1, App.onion_after)
		_after.custom_minimum_size.x = UI.px(64)
		_after.tooltip_text = "Drawings shown after (green)"
		_after.value_changed.connect(func(v: float) -> void:
			App.onion_after = int(v)
			App.onion_changed.emit())
		add_child(_after)

	add_child(UI.spacer())
	var new_d := UI.icon_button("new_frame", "New drawing (N)\nOn this frame, or the next one if this frame already has a drawing")
	new_d.pressed.connect(func() -> void: Ops.new_drawing())
	var dup_d := UI.icon_button("copy", "Duplicate drawing (D)\nCopies the current drawing to the next frame")
	dup_d.pressed.connect(Ops.duplicate_drawing)
	var ins := UI.icon_button("insert", "Insert frame (+)\nHold the current drawing one frame longer")
	ins.pressed.connect(Ops.insert_frame)
	var rem := UI.icon_button("remove_frame", "Remove frame (−)\nShorten the current drawing by one frame")
	rem.pressed.connect(Ops.remove_frame)
	var del := UI.icon_button("trash", "Delete drawing on this frame")
	del.pressed.connect(Ops.delete_drawing)
	for b in [new_d, dup_d, ins, rem, del]:
		add_child(b)

	for sig: Signal in [App.project_opened, App.scene_switched, App.frame_changed, App.timeline_changed,
			App.playback_changed, App.onion_changed]:
		sig.connect(_sync)
	_sync()


func _sync() -> void:
	if not App.has_project():
		return
	_syncing = true
	_play.icon = Icons.tex("pause" if App.playing else "play")
	_loop.set_pressed_no_signal(App.loop_playback)
	_frame_label.text = "%d / %d" % [App.frame + 1, App.frame_count()]
	var fps_idx := FPS_CHOICES.find(App.project.fps)
	if fps_idx >= 0:
		_fps.select(fps_idx)
	_length.set_value_no_signal(App.frame_count())
	if full:
		_onion.set_pressed_no_signal(App.onion_enabled)
		_before.set_value_no_signal(App.onion_before)
		_after.set_value_no_signal(App.onion_after)
	_syncing = false


func _on_fps(idx: int) -> void:
	if _syncing or not App.has_project():
		return
	Ops.set_prop(App.project, "fps", FPS_CHOICES[idx], "Frame rate", "timeline")


func _on_length(v: float) -> void:
	if _syncing or not App.has_project():
		return
	Ops.set_prop(App.current_scene(), "frame_count", int(v), "Scene length", "timeline")
