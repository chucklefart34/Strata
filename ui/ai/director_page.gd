class_name AiDirectorPage
extends Control
## Chat with the AI director. It sees the project (style, cast, shots, your
## selection), answers, and its requests go to the render queue.

const QUICK := [
	["Plan a 10-second walk", "Create a 10-second scene of my main character walking through a rainy city at night. Slow, heavy steps; low camera; the camera slowly moves toward them."],
	["More fluid movement", "The movement in this shot feels too robotic. Make the animation more natural and fluid: better arcs, overlap and follow-through, and animate the fast part on ones."],
	["More sinister expression", "Give the character a more sinister expression in the selected frames."],
	["Dim red light", "Change the lighting of this shot to a dim red light from a single source low on the left."],
	["Review this shot", "Review this shot as an animation director: pacing, staging, composition, silhouettes, acting and visual storytelling. Suggest concrete improvements; don't change anything yet."],
	["Check the drawings", "Run quality control on this shot and fix what's clearly wrong."],
]

var ws: AiStudioWorkspace
var _log: RichTextLabel
var _input: TextEdit
var _send: Button
var _busy: Label
var _ctx: Label
var _attach_list: Label
var _attachments: Array = []  # [Image]
var _attach_paths: Array = []
var _dialog: FileDialog


func _ready() -> void:
	var root := UI.hbox(12)
	UI.full_rect(root)
	add_child(root)
	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(card)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(_log)
	_attach_list = UI.label("", "Small")
	left.add_child(_attach_list)
	var in_row := UI.hbox(8)
	left.add_child(in_row)
	_input = AiUi.text("", 84, "Tell the director what you want — e.g. “Redraw frame 42, his hand looks wrong”. Ctrl+Enter sends.")
	_input.gui_input.connect(_on_input_key)
	in_row.add_child(_input)
	var btns := UI.vbox(6)
	in_row.add_child(btns)
	_send = UI.button("Send", "chat", "Send to the director (Ctrl+Enter)", "AccentButton")
	_send.pressed.connect(_on_send)
	btns.add_child(_send)
	var attach := UI.button("Image…", "image", "Attach reference images to this message (they're also saved to the reference library)")
	attach.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.6))
	btns.add_child(attach)
	_busy = UI.label("", "Small")
	left.add_child(_busy)
	_dialog = AiUi.image_dialog(self, true, _on_attach)

	var right := AiUi.sidebar(root, 300)
	AiUi.head(right, "Working on")
	_ctx = AiUi.wrap_label("")
	right.add_child(_ctx)
	AiUi.head(right, "Quick requests")
	for q in QUICK:
		var b := UI.button(q[0], "spark", q[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			_input.text = q[1]
			_input.grab_focus())
		right.add_child(b)
	right.add_child(UI.spacer())
	right.add_child(AiUi.wrap_label("The director only plans and asks: drawings are made by ComfyUI on your computer, in the Queue. Revised drawings arrive as new takes for you to approve.", "Small"))
	var clear := UI.button("Clear conversation", "trash")
	clear.pressed.connect(func() -> void:
		Studio.chat().clear()
		Studio.touch("chat"))
	right.add_child(clear)
	Studio.changed.connect(func(kind: String) -> void:
		if kind in ["chat", "all"]:
			_render_log()
		if kind in ["shots", "all"]:
			_update_ctx())
	ws.selection_changed.connect(_update_ctx)
	_render_log()
	_update_ctx()


func refresh() -> void:
	_render_log()
	_update_ctx()


func _on_input_key(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and k.pressed and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and (k.ctrl_pressed or k.meta_pressed):
		_input.accept_event()
		_on_send()


func _on_attach(paths: Array) -> void:
	for p in paths:
		var img := Image.load_from_file(str(p))
		if img != null and not img.is_empty():
			_attachments.append(img)
			_attach_paths.append(str(p))
	_attach_list.text = "Attached: " + ", ".join(PackedStringArray(_attach_paths.map(func(x: Variant) -> String: return str(x).get_file()))) if not _attach_paths.is_empty() else ""


func _update_ctx() -> void:
	if _ctx == null:
		return
	var s := Studio.find_shot(str(ws.selection.get("shot_id", "")))
	if s.is_empty():
		_ctx.text = "No shot selected. New shots the director plans are selected automatically."
		return
	var c := Studio.counts(s)
	var sel: Array = ws.selection.get("indices", [])
	var frames: Array[String] = []
	for i in sel:
		var d := Studio.drawing(s, int(i))
		if not d.is_empty():
			frames.append(str(int(d["frame"]) + 1))
	_ctx.text = "%s — %d/%d drawings done%s" % [s["name"], c["done"], c["drawings"], ("\nSelected frames: " + ", ".join(frames)) if not frames.is_empty() else ""]


func _render_log() -> void:
	if _log == null:
		return
	var out := ""
	if Studio.chat().is_empty():
		out = "[color=#9a9caa]Describe a scene, a character, an action or a change. The director knows your style profile, cast and shots.\n\nExamples:\n• Create a 10-second scene of Mara walking through a rainy city at night.\n• Give her a more sinister expression in frames 12–20.\n• Redraw frame 42 — his hand looks anatomically incorrect.\n• Make the camera slowly move toward the character.[/color]"
	for m in Studio.chat():
		var md: Dictionary = m
		match str(md.get("role", "")):
			"user":
				out += "\n[b]You[/b]\n%s\n" % AiUi.bb(str(md["text"]))
			"director":
				out += "\n[b][color=#ff7a59]Director[/color][/b]\n%s\n" % AiUi.bb(str(md["text"]))
			_:
				out += "[color=#4fd1c5][i]%s[/i][/color]\n" % AiUi.bb(str(md["text"]))
	_log.text = out


func _on_send() -> void:
	var t := _input.text.strip_edges()
	if t == "" or AiJobs.director.busy or not Studio.has_studio():
		return
	_input.text = ""
	Studio.add_chat("user", t + ("\n(attached: %d image(s))" % _attachments.size() if not _attachments.is_empty() else ""))
	var imgs := _attachments.duplicate()
	for i in imgs.size():
		Studio.add_reference_image(imgs[i], str(_attach_paths[i]).get_file().get_basename(), "style", "", "attached in the director chat")
	_attachments.clear()
	_attach_paths.clear()
	_attach_list.text = ""
	_send.disabled = true
	_busy.text = "The director is thinking… (%s)" % AiConfig.director_label()
	var res: Dictionary = await AiJobs.director.ask(t, ws.selection.duplicate(true), imgs)
	_send.disabled = false
	_busy.text = ""
	if not bool(res.get("ok", false)):
		Studio.add_chat("system", "⚠ " + str(res.get("error", "No answer.")))
		return
	Studio.add_chat("director", str(res.get("reply", "")))
	var sel := ws.selection.duplicate(true)
	var lines: Array = AiJobs.director.apply(res.get("actions", []), sel)
	for l in lines:
		Studio.add_chat("system", str(l))
	if str(sel.get("shot_id", "")) != str(ws.selection.get("shot_id", "")):
		ws.select_shot(str(sel["shot_id"]))
