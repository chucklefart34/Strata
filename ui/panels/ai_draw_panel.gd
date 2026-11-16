class_name AiDrawPanel
extends VBoxContainer
## "Draw from a prompt": type what you want and an image model draws it on
## the current layer. More words → more detail (a higher quality setting).
## Your own drawings steer it: a sketch on this frame sets the pose, your
## other keyframes keep the character consistent, and "Fill in-betweens"
## draws the frames between your keyframes.

var _ai: AiDraw
var _prompt: TextEdit
var _detail: Label
var _style: OptionButton
var _use_sketch: CheckBox
var _use_keys: CheckBox
var _follow: HSlider
var _target: OptionButton
var _step: SpinBox
var _status: Label
var _go: Button
var _fill: Button
var _stop: Button
var _service: OptionButton
var _key: LineEdit
var _model: LineEdit
var _model_label: Label
var _busy: bool = false
var _cancel: bool = false


func _ready() -> void:
	_ai = AiDraw.new()
	add_child(_ai)
	var sec := UI.section(self, "Draw from a prompt")
	var hint := UI.label("Describe what to draw. The more detail you write, the more detailed the drawing. Your own drawings guide it: a rough sketch on this frame sets the pose, and your other keyframes on the layer keep the character the same.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)
	_prompt = TextEdit.new()
	_prompt.placeholder_text = "e.g. a scruffy orange cat in a red hoodie, leaning on a lamp post at night, side view, smirking, hands in pockets"
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt.custom_minimum_size.y = UI.px(96)
	_prompt.text = str(ProjectIO.get_setting("ai_last_prompt", ""))
	_prompt.text_changed.connect(_update_detail)
	sec.add_child(_prompt)
	_detail = UI.label("", "Small")
	sec.add_child(_detail)

	sec.add_child(UI.label("Draw as", "FieldLabel"))
	_style = UI.option(AiDraw.STYLE_LABELS, maxi(0, AiDraw.STYLES.find(str(ProjectIO.get_setting("ai_style", "lines")))))
	_style.item_selected.connect(func(i: int) -> void: ProjectIO.set_setting("ai_style", AiDraw.STYLES[i]))
	sec.add_child(_style)

	_use_sketch = CheckBox.new()
	_use_sketch.text = "Use my drawing on this frame as the sketch"
	_use_sketch.button_pressed = true
	_use_sketch.tooltip_text = "If this frame already has a drawing (even a rough one), it sets the pose, layout and framing."
	sec.add_child(_use_sketch)
	_follow = UI.slider(sec, "Follow my sketch", 0, 100, 1, 70, _on_follow, "%d%%")
	_use_keys = CheckBox.new()
	_use_keys.text = "Match my other keyframes on this layer"
	_use_keys.button_pressed = true
	_use_keys.tooltip_text = "Sends the nearest keyframes before and after this frame so the character, colours and style stay the same. More hand-drawn keyframes = more consistent results."
	sec.add_child(_use_keys)

	sec.add_child(UI.label("Put it on", "FieldLabel"))
	_target = UI.option(["This layer, this frame", "A new layer"])
	sec.add_child(_target)

	_go = UI.button("Draw it", "brush", "Draw this frame from the prompt", "Button")
	_go.pressed.connect(_draw_one)
	sec.add_child(_go)

	var fill_row := UI.hbox(6)
	sec.add_child(fill_row)
	_fill = UI.button("Fill in-betweens", "", "Draw the frames between your keyframes on this layer, using the two keyframes around each one", "Button")
	_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill.pressed.connect(_fill_inbetweens)
	fill_row.add_child(_fill)
	fill_row.add_child(UI.label("every", "Small"))
	_step = UI.spin(1, 12, 1, 2, " fr")
	fill_row.add_child(_step)
	_stop = UI.button("Stop", "", "Stop after the current picture", "Button")
	_stop.visible = false
	_stop.pressed.connect(func() -> void:
		_cancel = true
		_status.text = "Stopping after this picture…")
	sec.add_child(_stop)
	_status = UI.label("", "Small")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_status)

	# ---- service
	var svc := UI.section(self, "AI service")
	var sh := UI.label("Drawing from a prompt needs an image model. Use an online service with your own key (each picture costs a little), or run Automatic1111 / Forge on your computer for free. Keys stay on this device and are never saved in projects.", "Small")
	sh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	svc.add_child(sh)
	_service = UI.option(AiDraw.SERVICE_LABELS, maxi(0, AiDraw.SERVICES.find(AiDraw.service())))
	_service.item_selected.connect(_on_service)
	svc.add_child(_service)
	_key = LineEdit.new()
	_key.secret = true
	_key.text_changed.connect(_save_service_fields)
	svc.add_child(_key)
	_model_label = UI.label("", "FieldLabel")
	svc.add_child(_model_label)
	_model = LineEdit.new()
	_model.text_changed.connect(_save_service_fields)
	svc.add_child(_model)

	_load_service_fields()
	_update_detail()


func _on_follow(_v: float) -> void:
	pass


func _update_detail() -> void:
	var words := _prompt.text.strip_edges().split(" ", false).size()
	var lvl := AiDraw.detail_level(_prompt.text)
	var names := ["Simple", "Detailed", "Very detailed"]
	_detail.text = "%d words · %s (%s)" % [words, names[lvl], ["add more words for more detail", "keep going for the most detail", "highest quality"][lvl]]


func _on_service(i: int) -> void:
	ProjectIO.set_setting("ai_service", AiDraw.SERVICES[i])
	_load_service_fields()


func _load_service_fields() -> void:
	var svc := AiDraw.service()
	_key.set_block_signals(true)
	_model.set_block_signals(true)
	_key.visible = svc != "local"
	_key.placeholder_text = "OpenAI API key (sk-…)" if svc == "openai" else "Stability AI API key (sk-…)"
	_key.text = AiDraw.setting("key_" + svc)
	match svc:
		"openai":
			_model_label.text = "Model"
			_model.text = AiDraw.setting("model_openai", "gpt-image-1.5")
		"stability":
			_model_label.text = ""
		_:
			_model_label.text = "Address of Automatic1111 / Forge (started with --api)"
			_model.text = AiDraw.setting("url_local", "http://127.0.0.1:7860")
	_model_label.visible = svc != "stability"
	_model.visible = svc != "stability"
	_key.set_block_signals(false)
	_model.set_block_signals(false)


func _save_service_fields(_t: String = "") -> void:
	var svc := AiDraw.service()
	if svc != "local":
		ProjectIO.set_setting("ai_key_" + svc, _key.text.strip_edges())
	if svc == "openai":
		ProjectIO.set_setting("ai_model_openai", _model.text.strip_edges())
	elif svc == "local":
		ProjectIO.set_setting("ai_url_local", _model.text.strip_edges())


func _style_id() -> String:
	return AiDraw.STYLES[clampi(_style.selected, 0, AiDraw.STYLES.size() - 1)]


func _layer_ok(layer: LayerData) -> bool:
	if layer == null:
		_status.text = "Pick a drawing layer first."
		return false
	if layer.is_character():
		_status.text = "Character layers are posed, not drawn — pick a drawing layer."
		return false
	return true


func _set_busy(on: bool) -> void:
	_busy = on
	_go.disabled = on
	_fill.disabled = on
	_stop.visible = on
	if on:
		_cancel = false


## The keyframes on `layer` nearest to `frame` (one before, one after),
## not counting `frame` itself.
func _nearest_keys(layer: LayerData, frame: int) -> Array:
	var before := -1
	var after := -1
	for k in layer.sorted_keys():
		var f := int(k)
		if f < frame:
			before = f
		elif f > frame and after < 0:
			after = f
	var out: Array = []
	for f in [before, after]:
		if f >= 0:
			var cel: CelData = layer.cels[f]
			var img := cel.get_image()
			if img != null and not img.is_invisible():
				out.append(img)
	return out


func _draw_one() -> void:
	if _busy or not App.has_project():
		return
	var layer := App.current_layer()
	if not _layer_ok(layer):
		return
	ProjectIO.set_setting("ai_last_prompt", _prompt.text)
	var frame := App.frame
	var sketch: Image = null
	if _use_sketch.button_pressed and layer.cels.has(frame):
		var cel: CelData = layer.cels[frame]
		var img := cel.get_image()
		if img != null and not img.is_invisible():
			sketch = img
	var refs: Array = _nearest_keys(layer, frame) if _use_keys.button_pressed else []
	_set_busy(true)
	var uses := []
	if sketch != null:
		uses.append("your sketch")
	if not refs.is_empty():
		uses.append("%d keyframe%s" % [refs.size(), "" if refs.size() == 1 else "s"])
	_status.text = "Drawing%s… this can take up to a minute." % ("" if uses.is_empty() else " from " + " and ".join(uses))
	var out := await _ai.generate(_prompt.text, _style_id(), sketch, refs, [], _follow.value / 100.0, App.project.width, App.project.height)
	_set_busy(false)
	if out == null:
		_status.text = _ai.last_error
		return
	var dest := layer
	if _target.selected == 1:
		dest = Ops.add_layer("AI drawing")
	Ops.add_drawings(dest, {frame: out}, "Draw from prompt")
	_status.text = "Done — on frame %d of “%s”. Undo removes it." % [frame + 1, dest.name]


func _fill_inbetweens() -> void:
	if _busy or not App.has_project():
		return
	var layer := App.current_layer()
	if not _layer_ok(layer):
		return
	ProjectIO.set_setting("ai_last_prompt", _prompt.text)
	var keys: Array = layer.sorted_keys()
	var step := int(_step.value)
	var jobs: Array = []  # [frame, key_a, key_b, t]
	for i in range(keys.size() - 1):
		var a := int(keys[i])
		var b := int(keys[i + 1])
		var f := a + step
		while f < b:
			jobs.append([f, a, b, float(f - a) / float(b - a)])
			f += step
	if jobs.is_empty():
		_status.text = "Draw at least two keyframes on this layer with room between them (more than %d frame%s apart)." % [step, "" if step == 1 else "s"]
		return
	_set_busy(true)
	var made := {}
	for n in jobs.size():
		if _cancel:
			break
		var job: Array = jobs[n]
		_status.text = "In-between %d of %d (frame %d)…" % [n + 1, jobs.size(), int(job[0]) + 1]
		var ca: CelData = layer.cels[int(job[1])]
		var cb: CelData = layer.cels[int(job[2])]
		var out := await _ai.generate(_prompt.text, _style_id(), null, [], [ca.get_image(), cb.get_image(), float(job[3])], 0.7, App.project.width, App.project.height)
		if out == null:
			_status.text = _ai.last_error
			break
		made[int(job[0])] = out
	_set_busy(false)
	if made.is_empty():
		return
	var dest := layer
	if _target.selected == 1:
		dest = Ops.add_layer("AI in-betweens")
	Ops.add_drawings(dest, made, "Fill in-betweens")
	if made.size() == jobs.size():
		_status.text = "Drew %d in-betweens. Undo removes them all." % made.size()
	else:
		_status.text = "Drew %d of %d in-betweens. %s" % [made.size(), jobs.size(), _status.text if not _cancel else "Stopped."]
