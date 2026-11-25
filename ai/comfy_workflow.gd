class_name ComfyWorkflow
extends RefCounted
## Builds the ComfyUI graph (API format) for one drawing.
##
##   checkpoint ─ LoRA ─ IP-Adapter (character / style references) ─┐
##   prompt + negative ─ ControlNet (your rough, optional) ──────────┼─ KSampler ─ decode ─ save
##   empty latent, or an init picture (blend guide / rough) ─────────┘
##
## Any model ComfyUI can load works: change the checkpoint in Setup, or
## point "Custom workflow" at your own graph (exported with "Save (API
## Format)") that uses these placeholders as whole string values:
##   {{positive}} {{negative}} {{seed}} {{width}} {{height}} {{steps}}
##   {{cfg}} {{denoise}} {{init_image}} {{control_image}} {{ref_image}}

const OUTPUT_NODE := "9"


## req: {positive, negative, seed, width, height, denoise, init_image,
##       control_image, ref_images: Array[String], ref_weight}
## Image fields are names already uploaded to ComfyUI ("" = none).
## Returns {graph, output, error}.
static func build(req: Dictionary, client: ComfyClient) -> Dictionary:
	var custom := AiConfig.s("custom_workflow").strip_edges()
	if custom != "":
		return _custom(custom, req)
	var ckpt := AiConfig.s("checkpoint")
	if ckpt == "":
		var list: Array = client.last_check.get("checkpoints", [])
		if list.is_empty():
			return {"error": "No checkpoint chosen. Open AI Studio → Setup, press Check, and pick a model."}
		ckpt = str(list[0])
	var g := {}
	g["1"] = _n("CheckpointLoaderSimple", {"ckpt_name": ckpt})
	var model: Array = ["1", 0]
	var clip: Array = ["1", 1]
	var vae: Array = ["1", 2]
	var lora := AiConfig.s("lora")
	if lora != "":
		var ls := AiConfig.f("lora_strength")
		g["2"] = _n("LoraLoader", {"model": model, "clip": clip, "lora_name": lora, "strength_model": ls, "strength_clip": ls})
		model = ["2", 0]
		clip = ["2", 1]
	g["3"] = _n("CLIPTextEncode", {"text": str(req.get("positive", "")), "clip": clip})
	g["4"] = _n("CLIPTextEncode", {"text": str(req.get("negative", "")), "clip": clip})
	var pos: Array = ["3", 0]
	var neg: Array = ["4", 0]

	# ---- reference images (character sheet / style) through IP-Adapter
	var refs: Array = req.get("ref_images", [])
	var use_ip := AiConfig.b("ipadapter") and not refs.is_empty() and client.has_class("IPAdapterUnifiedLoader") and client.has_class("IPAdapterAdvanced")
	if use_ip:
		var ref_img: Array = []
		for k in mini(refs.size(), 3):
			var id := str(20 + k)
			g[id] = _n("LoadImage", {"image": str(refs[k])})
			if ref_img.is_empty():
				ref_img = [id, 0]
			else:
				var bid := str(25 + k)
				g[bid] = _n("ImageBatch", {"image1": ref_img, "image2": [id, 0]})
				ref_img = [bid, 0]
		var preset := AiConfig.s("ipadapter_preset")
		var presets: Array = client.choices("IPAdapterUnifiedLoader", "preset")
		if not presets.is_empty() and not presets.has(preset):
			preset = str(presets[0])
		g["28"] = _n("IPAdapterUnifiedLoader", {"model": model, "preset": preset})
		g["29"] = _n("IPAdapterAdvanced", {
			"model": ["28", 0], "ipadapter": ["28", 1], "image": ref_img,
			"weight": float(req.get("ref_weight", AiConfig.f("ipadapter_weight"))),
			"weight_type": "linear", "combine_embeds": "concat",
			"start_at": 0.0, "end_at": 1.0, "embeds_scaling": "V only",
		})
		model = ["29", 0]

	# ---- your rough drawing through ControlNet
	var ctrl := str(req.get("control_image", ""))
	var cn := AiConfig.s("controlnet")
	if ctrl != "" and cn != "":
		g["30"] = _n("LoadImage", {"image": ctrl})
		g["31"] = _n("ControlNetLoader", {"control_net_name": cn})
		g["32"] = _n("ControlNetApplyAdvanced", {
			"positive": pos, "negative": neg, "control_net": ["31", 0], "image": ["30", 0],
			"strength": float(req.get("control_strength", AiConfig.f("controlnet_strength"))),
			"start_percent": 0.0, "end_percent": 0.85,
		})
		pos = ["32", 0]
		neg = ["32", 1]

	# ---- start from noise, or from a picture (blend guide / rough)
	var w := int(req.get("width", 1024))
	var h := int(req.get("height", 576))
	var latent: Array
	var denoise := 1.0
	var init := str(req.get("init_image", ""))
	if init != "":
		g["40"] = _n("LoadImage", {"image": init})
		g["41"] = _n("VAEEncode", {"pixels": ["40", 0], "vae": vae})
		latent = ["41", 0]
		denoise = clampf(float(req.get("denoise", 0.6)), 0.05, 1.0)
	else:
		g["40"] = _n("EmptyLatentImage", {"width": w, "height": h, "batch_size": 1})
		latent = ["40", 0]

	var sampler := AiConfig.s("sampler")
	var samplers: Array = client.choices("KSampler", "sampler_name")
	if not samplers.is_empty() and not samplers.has(sampler):
		sampler = "euler"
	var sched := AiConfig.s("scheduler")
	var scheds: Array = client.choices("KSampler", "scheduler")
	if not scheds.is_empty() and not scheds.has(sched):
		sched = "normal"
	g["5"] = _n("KSampler", {
		"model": model, "seed": int(req.get("seed", 0)) & 0x7fffffffffff, "steps": AiConfig.i("steps"),
		"cfg": AiConfig.f("cfg"), "sampler_name": sampler, "scheduler": sched,
		"positive": pos, "negative": neg, "latent_image": latent, "denoise": denoise,
	})
	g["6"] = _n("VAEDecode", {"samples": ["5", 0], "vae": vae})
	g[OUTPUT_NODE] = _n("SaveImage", {"images": ["6", 0], "filename_prefix": "strata_ai"})
	return {"graph": g, "output": OUTPUT_NODE, "error": ""}


static func _n(cls: String, inputs: Dictionary) -> Dictionary:
	return {"class_type": cls, "inputs": inputs}


# ================================================================ custom workflow

static func _custom(path: String, req: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "Custom workflow file not found: " + path}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "Custom workflow is not valid JSON (export it with “Save (API Format)”)."}
	var refs: Array = req.get("ref_images", [])
	var values := {
		"{{positive}}": str(req.get("positive", "")),
		"{{negative}}": str(req.get("negative", "")),
		"{{seed}}": int(req.get("seed", 0)) & 0x7fffffffffff,
		"{{width}}": int(req.get("width", 1024)),
		"{{height}}": int(req.get("height", 576)),
		"{{steps}}": AiConfig.i("steps"),
		"{{cfg}}": AiConfig.f("cfg"),
		"{{denoise}}": float(req.get("denoise", 1.0)) if str(req.get("init_image", "")) != "" else 1.0,
		"{{init_image}}": str(req.get("init_image", "")),
		"{{control_image}}": str(req.get("control_image", "")),
		"{{ref_image}}": str(refs[0]) if not refs.is_empty() else "",
	}
	var g: Dictionary = _substitute(data, values)
	var out := ""
	for id in g.keys():
		var node: Variant = g[id]
		if typeof(node) == TYPE_DICTIONARY and str((node as Dictionary).get("class_type", "")) == "SaveImage":
			out = str(id)
	if out == "":
		return {"error": "Custom workflow has no SaveImage node."}
	return {"graph": g, "output": out, "error": ""}


static func _substitute(v: Variant, values: Dictionary) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in (v as Dictionary).keys():
				d[k] = _substitute((v as Dictionary)[k], values)
			return d
		TYPE_ARRAY:
			var a := []
			for item in v:
				a.append(_substitute(item, values))
			return a
		TYPE_STRING:
			var sv := str(v)
			if values.has(sv):
				return values[sv]
			for key in values.keys():
				if sv.contains(str(key)):
					sv = sv.replace(str(key), str(values[key]))
			return sv
	return v
