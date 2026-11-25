class_name AiSetupPage
extends Control
## This computer, the image generator (ComfyUI, LOCAL) and the director
## (Claude = CLOUD, Ollama = LOCAL).

const INSTALL := """[b]1. Image generation — ComfyUI (runs on your computer)[/b]
• Download ComfyUI for Windows (the portable build or ComfyUI Desktop) from github.com/comfyanonymous/ComfyUI and start it. It listens on http://127.0.0.1:8188.
• Put a checkpoint in ComfyUI/models/checkpoints. An SDXL-based illustration or anime-style model works best for this look (8 GB+ VRAM); SD 1.5 models also work on smaller GPUs (set Frame size to 768).
• For character consistency install [b]ComfyUI_IPAdapter_plus[/b] (ComfyUI Manager → Install Custom Nodes) and its models (ipadapter + CLIP vision). Strata uses the “Unified Loader” and picks the preset you choose here.
• To draw from your roughs, add a lineart or scribble ControlNet to models/controlnet and choose it below.
• Optional: a style LoRA in models/loras for your own house look.
• Press [b]Check[/b] to list what's installed.

[b]2. The director[/b]
• [b]Claude (cloud)[/b]: create an API key at console.anthropic.com and paste it below. Messages, project context and (for Vision QC / Describe) frames are sent to Anthropic.
• [b]Ollama (local)[/b]: install Ollama, run e.g. “ollama pull qwen3” (any model good at JSON), then choose it below. Nothing leaves your computer. Vision QC needs Claude.

[b]3. Use it[/b]
Cast → describe your characters and generate their sheets. Style & references → add references. Director → ask for a scene. Shots → watch drawings arrive, approve, fix, and Place on timeline. Then Animate / Export as usual (MP4, WebM, GIF, PNG frames)."""

var ws: AiStudioWorkspace
var _sys: Label
var _url: LineEdit
var _check_label: Label
var _ckpt: OptionButton
var _lora: OptionButton
var _cn: OptionButton
var _ip: CheckBox
var _ip_preset: OptionButton
var _sampler: OptionButton
var _sched: OptionButton
var _size: OptionButton
var _workflow: LineEdit
var _dir: OptionButton
var _key: LineEdit
var _model: LineEdit
var _ollama_url: LineEdit
var _ollama_model: OptionButton
var _dir_label: Label
var _wf_dialog: FileDialog

const SIZES := [768, 1024, 1280]
const DIRECTORS := [["claude", "Claude — cloud (best; needs API key)"], ["ollama", "Ollama — local, on this computer"], ["off", "Off"]]


func _ready() -> void:
	var root := UI.hbox(14)
	UI.full_rect(root)
	add_child(root)
	var left := AiUi.scroll(root)
	var right := AiUi.sidebar(root, 460)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = false
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.text = INSTALL
	AiUi.head(right, "How to install")
	right.add_child(info)

	# ---- this computer
	var sc := UI.section(left, "This computer")
	_sys = AiUi.wrap_label("", "Label")
	sc.add_child(_sys)

	# ---- ComfyUI
	var cs := UI.section(left, "Image generation — ComfyUI · LOCAL")
	var g := AiUi.grid(cs, 2)
	_url = AiUi.row(g, "Address", AiUi.line(AiConfig.s("comfy_url"))) as LineEdit
	_url.text_changed.connect(func(t: String) -> void: AiConfig.set_value("comfy_url", t.strip_edges()))
	var chk := UI.button("Check connection", "check", "Connect to ComfyUI and list its models", "AccentButton")
	chk.pressed.connect(_check)
	chk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cs.add_child(chk)
	_check_label = AiUi.wrap_label("Not checked yet.", "Small")
	cs.add_child(_check_label)
	var g2 := AiUi.grid(cs, 2)
	_ckpt = AiUi.row(g2, "Model (checkpoint)", _opt([AiConfig.s("checkpoint")], "checkpoint")) as OptionButton
	_lora = AiUi.row(g2, "Style LoRA", _opt(["", AiConfig.s("lora")], "lora")) as OptionButton
	_slider(cs, "LoRA strength", "lora_strength", 0.0, 1.5)
	_cn = AiUi.row(AiUi.grid(cs, 2), "ControlNet (for roughs)", _opt(["", AiConfig.s("controlnet")], "controlnet")) as OptionButton
	_slider(cs, "ControlNet strength", "controlnet_strength", 0.1, 1.5)
	_ip = CheckBox.new()
	_ip.text = "Use IP-Adapter for character sheets and style references"
	_ip.button_pressed = AiConfig.b("ipadapter")
	_ip.toggled.connect(func(on: bool) -> void: AiConfig.set_value("ipadapter", on))
	cs.add_child(_ip)
	var g3 := AiUi.grid(cs, 2)
	_ip_preset = AiUi.row(g3, "IP-Adapter preset", _opt([AiConfig.s("ipadapter_preset")], "ipadapter_preset")) as OptionButton
	_slider(cs, "Default reference pull", "ipadapter_weight", 0.1, 1.2)
	var g4 := AiUi.grid(cs, 2)
	_sampler = AiUi.row(g4, "Sampler", _opt([AiConfig.s("sampler")], "sampler")) as OptionButton
	_sched = AiUi.row(g4, "Scheduler", _opt([AiConfig.s("scheduler")], "scheduler")) as OptionButton
	_size = AiUi.row(g4, "Frame size (long side)", UI.option(SIZES.map(func(x: Variant) -> String: return "%d px" % int(x)))) as OptionButton
	_size.select(maxi(0, SIZES.find(AiConfig.i("base_size"))))
	_size.item_selected.connect(func(i: int) -> void: AiConfig.set_value("base_size", SIZES[i]))
	_slider(cs, "Steps", "steps", 8, 60, 1.0, "%d")
	_slider(cs, "CFG (prompt strength)", "cfg", 1.0, 12.0, 0.5)
	_slider(cs, "In-between redraw amount (lower = closer to the blend)", "inbetween_denoise", 0.2, 0.9)
	_slider(cs, "Rough redraw amount (without ControlNet)", "rough_denoise", 0.3, 0.95)
	var mg := CheckBox.new()
	mg.text = "Guide in-betweens with Strata's motion in-betweener (moves the figure along its path; otherwise a cross-fade)"
	mg.button_pressed = AiConfig.b("motion_guides")
	mg.toggled.connect(func(on: bool) -> void: AiConfig.set_value("motion_guides", on))
	cs.add_child(mg)
	var wf := UI.hbox(6)
	cs.add_child(wf)
	wf.add_child(UI.label("Custom workflow", "FieldLabel"))
	_workflow = AiUi.line(AiConfig.s("custom_workflow"), "optional: your ComfyUI graph (API format) with {{placeholders}}")
	_workflow.text_changed.connect(func(t: String) -> void: AiConfig.set_value("custom_workflow", t.strip_edges()))
	wf.add_child(_workflow)
	var browse := UI.button("Browse…", "folder")
	browse.pressed.connect(func() -> void: _wf_dialog.popup_centered_ratio(0.6))
	wf.add_child(browse)
	_wf_dialog = FileDialog.new()
	_wf_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_wf_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_wf_dialog.filters = PackedStringArray(["*.json ; ComfyUI API workflow"])
	_wf_dialog.use_native_dialog = true
	_wf_dialog.file_selected.connect(func(p: String) -> void:
		_workflow.text = p
		AiConfig.set_value("custom_workflow", p))
	add_child(_wf_dialog)
	cs.add_child(AiUi.wrap_label("Placeholders: {{positive}} {{negative}} {{seed}} {{width}} {{height}} {{steps}} {{cfg}} {{denoise}} {{init_image}} {{control_image}} {{ref_image}}. Use this to swap in any model ComfyUI supports.", "Small"))

	# ---- director
	var ds := UI.section(left, "Director")
	var g5 := AiUi.grid(ds, 2)
	_dir = AiUi.row(g5, "Director", UI.option(DIRECTORS.map(func(x: Variant) -> String: return str((x as Array)[1])))) as OptionButton
	var dvals: Array = DIRECTORS.map(func(x: Variant) -> String: return str((x as Array)[0]))
	AiUi.option_select(_dir, AiConfig.s("director"), dvals)
	_dir.item_selected.connect(func(i: int) -> void:
		AiConfig.set_value("director", dvals[i])
		_update_dir())
	_key = AiUi.row(g5, "Anthropic API key", AiUi.line(AiConfig.s("claude_key"), "sk-ant-…")) as LineEdit
	_key.secret = true
	_key.text_changed.connect(func(t: String) -> void: AiConfig.set_value("claude_key", t.strip_edges()))
	_model = AiUi.row(g5, "Claude model", AiUi.line(AiConfig.s("claude_model"))) as LineEdit
	_model.text_changed.connect(func(t: String) -> void: AiConfig.set_value("claude_model", t.strip_edges()))
	_ollama_url = AiUi.row(g5, "Ollama address", AiUi.line(AiConfig.s("ollama_url"))) as LineEdit
	_ollama_url.text_changed.connect(func(t: String) -> void: AiConfig.set_value("ollama_url", t.strip_edges()))
	_ollama_model = AiUi.row(g5, "Ollama model", _opt([AiConfig.s("ollama_model")], "ollama_model")) as OptionButton
	var oh := UI.hbox(6)
	ds.add_child(oh)
	var olist := UI.button("List Ollama models", "reset")
	olist.pressed.connect(_list_ollama)
	oh.add_child(olist)
	var test := UI.button("Test the director", "chat")
	test.pressed.connect(_test_director)
	oh.add_child(test)
	for spec in [["vision_qc", "Allow Vision QC and reference descriptions (sends frames to Claude)"], ["auto_queue", "Start rendering what the director plans right away"]]:
		var cb := CheckBox.new()
		cb.text = spec[1]
		cb.button_pressed = AiConfig.b(spec[0])
		cb.toggled.connect(func(on: bool) -> void: AiConfig.set_value(spec[0], on))
		ds.add_child(cb)
	_dir_label = AiUi.wrap_label("", "Small")
	ds.add_child(_dir_label)
	_update_dir()
	_update_sys({})


func refresh() -> void:
	var r: Dictionary = AiJobs.comfy.last_check
	if bool(r.get("ok", false)):
		_apply_check(r)
	else:
		_update_sys(r)


## An OptionButton bound to a setting; items are replaced after Check.
func _opt(items: Array, key: String) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.set_meta("key", key)
	_set_items(o, items, AiConfig.s(key))
	o.item_selected.connect(func(i: int) -> void:
		var v := str(o.get_item_metadata(i))
		AiConfig.set_value(key, v))
	return o


func _set_items(o: OptionButton, items: Array, current: String) -> void:
	o.clear()
	var seen := {}
	var list := items.duplicate()
	if current != "" and not list.has(current):
		list.push_front(current)
	for it in list:
		var v := str(it)
		if seen.has(v):
			continue
		seen[v] = true
		o.add_item(v if v != "" else "— none —")
		o.set_item_metadata(o.item_count - 1, v)
		if v == current:
			o.select(o.item_count - 1)


func _slider(parent: Control, title: String, key: String, lo: float, hi: float, step: float = 0.05, fmt: String = "%.2f") -> void:
	UI.slider(parent, title, lo, hi, step, AiConfig.f(key), func(v: float) -> void:
		AiConfig.set_value(key, int(v) if fmt == "%d" else v), fmt)


func _check() -> void:
	_check_label.text = "Connecting to %s…" % AiConfig.comfy_url()
	var r: Dictionary = await AiJobs.comfy.check()
	if not bool(r["ok"]):
		_check_label.text = "✗ " + str(r["error"])
		_update_sys(r)
		return
	_apply_check(r)
	AiJobs.kick()


func _apply_check(r: Dictionary) -> void:
	var ck: Array = r["checkpoints"]
	if AiConfig.s("checkpoint") == "" and not ck.is_empty():
		AiConfig.set_value("checkpoint", str(ck[0]))
	_set_items(_ckpt, ck, AiConfig.s("checkpoint"))
	var lo: Array = [""]
	lo.append_array(r["loras"])
	_set_items(_lora, lo, AiConfig.s("lora"))
	var cn: Array = [""]
	cn.append_array(r["controlnets"])
	_set_items(_cn, cn, AiConfig.s("controlnet"))
	_set_items(_ip_preset, r["ipadapter_presets"], AiConfig.s("ipadapter_preset"))
	_set_items(_sampler, r["samplers"], AiConfig.s("sampler"))
	_set_items(_sched, r["schedulers"], AiConfig.s("scheduler"))
	_check_label.text = "✓ Connected%s. %d checkpoint(s), %d LoRA(s), %d ControlNet(s). IP-Adapter: %s." % [
		(" to ComfyUI " + str(r.get("comfy_version", ""))) if str(r.get("comfy_version", "")) != "" else "",
		ck.size(), (r["loras"] as Array).size(), (r["controlnets"] as Array).size(),
		"installed" if bool(r["ipadapter"]) else "not installed (characters will rely on descriptions and the shot's first key)"]
	if ck.is_empty():
		_check_label.text += "\nNo checkpoint found: put a model in ComfyUI/models/checkpoints and press Check again."
	_update_sys(r)


func _update_sys(r: Dictionary) -> void:
	var mem: Dictionary = OS.get_memory_info()
	var ram := float(mem.get("physical", 0)) / 1073741824.0
	var t := "Graphics: %s (%s)\nProcessor: %s, %d threads\nMemory: %.0f GB\nSystem: %s" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		OS.get_processor_name(), OS.get_processor_count(), ram, OS.get_name()]
	var devs: Array = r.get("devices", [])
	var vram := 0.0
	for d in devs:
		var dd: Dictionary = d
		t += "\nComfyUI device: %s — %.1f GB VRAM" % [dd["name"], float(dd["vram_gb"])]
		vram = maxf(vram, float(dd["vram_gb"]))
	if vram > 0.0:
		if vram >= 12.0:
			t += "\n→ Plenty for SDXL at 1024 px with IP-Adapter and ControlNet together (≈5–15 s a drawing)."
		elif vram >= 8.0:
			t += "\n→ Good for SDXL at 1024 px; IP-Adapter + ControlNet together may be slower."
		elif vram >= 6.0:
			t += "\n→ Use SD 1.5 models at 768 px, or SDXL with ComfyUI's low-VRAM mode."
		else:
			t += "\n→ Small GPU: SD 1.5 at 768 px, few steps; expect slow drawings."
	elif devs.is_empty():
		t += "\nGPU memory is shown after a successful ComfyUI check."
	t += "\nRough timing: a 10-second shot at 24 fps on twos is 120 drawings."
	_sys.text = t


func _update_dir() -> void:
	var p := AiConfig.s("director")
	_key.editable = p == "claude"
	_model.editable = p == "claude"
	_dir_label.text = {"claude": "CLOUD: your messages, the project summary and (for vision checks) frames go to Anthropic.",
		"ollama": "LOCAL: everything stays on this computer. Vision QC and AI reference descriptions are not available.",
		"off": "No director: plan shots yourself in Shots."}.get(p, "")


func _list_ollama() -> void:
	var url := AiConfig.s("ollama_url").strip_edges().trim_suffix("/") + "/api/tags"
	var r := await AiHttp.get_json(self, url, PackedStringArray(), 10.0)
	if not r["ok"] or typeof(r["json"]) != TYPE_DICTIONARY:
		_dir_label.text = "Ollama: " + str(r["error"])
		return
	var names: Array = []
	for m in (r["json"] as Dictionary).get("models", []):
		names.append(str((m as Dictionary).get("name", "")))
	if AiConfig.s("ollama_model") == "" and not names.is_empty():
		AiConfig.set_value("ollama_model", str(names[0]))
	_set_items(_ollama_model, names, AiConfig.s("ollama_model"))
	_dir_label.text = "Ollama: %d model(s) installed." % names.size() if not names.is_empty() else "Ollama is running but has no models: run “ollama pull qwen3” in a terminal."


func _test_director() -> void:
	if not App.has_project():
		_dir_label.text = "Open a project first."
		return
	_dir_label.text = "Asking the director…"
	var r: Dictionary = await AiJobs.director.ask("This is a connection test. Reply with one short sentence introducing yourself, and no actions.", {})
	_dir_label.text = ("✓ " + str(r.get("reply", ""))) if bool(r.get("ok", false)) else ("✗ " + str(r.get("error", "")))
