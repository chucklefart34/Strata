class_name ComfyClient
extends Node
## Talks to a ComfyUI server running on this computer (LOCAL image
## generation). Uses its HTTP API: /prompt, /history, /view, /upload/image,
## /object_info, /system_stats, /interrupt, plus the /ws websocket for live
## step-by-step progress.

signal progress(prompt_id: String, value: int, maximum: int)

var client_id: String = "strata-%d" % (randi() % 1000000000)
var object_info: Dictionary = {}
var last_check: Dictionary = {}
var _ws: WebSocketPeer = null
var _ws_url: String = ""
var _ws_retry_at: int = 0  # msec; live progress is optional, so back off on failure


func base() -> String:
	return AiConfig.comfy_url()


# ================================================================ discovery

## Connects and lists what's installed. Returns
## {ok, error, checkpoints, loras, controlnets, ipadapter, ipadapter_presets,
##  samplers, schedulers, devices: [{name, vram_gb}], comfy_version}
func check() -> Dictionary:
	var out := {"ok": false, "error": "", "checkpoints": [], "loras": [], "controlnets": [],
		"ipadapter": false, "ipadapter_presets": [], "samplers": [], "schedulers": [], "devices": []}
	var stats := await AiHttp.get_json(self, base() + "/system_stats", PackedStringArray(), 10.0)
	if not stats["ok"]:
		out["error"] = str(stats["error"]) + "\n\nStart ComfyUI first (see Setup → How to install), then press Check again."
		last_check = out
		return out
	if typeof(stats["json"]) == TYPE_DICTIONARY:
		var sj: Dictionary = stats["json"]
		for d in sj.get("devices", []):
			var dd: Dictionary = d
			out["devices"].append({"name": str(dd.get("name", "?")), "vram_gb": float(dd.get("vram_total", 0)) / 1073741824.0})
		var sys: Dictionary = sj.get("system", {})
		out["comfy_version"] = str(sys.get("comfyui_version", ""))
	var info := await AiHttp.get_json(self, base() + "/object_info", PackedStringArray(), 60.0)
	if not info["ok"] or typeof(info["json"]) != TYPE_DICTIONARY:
		out["error"] = "ComfyUI answered, but its node list could not be read: " + str(info["error"])
		last_check = out
		return out
	object_info = info["json"]
	out["checkpoints"] = choices("CheckpointLoaderSimple", "ckpt_name")
	out["loras"] = choices("LoraLoader", "lora_name")
	out["controlnets"] = choices("ControlNetLoader", "control_net_name")
	out["samplers"] = choices("KSampler", "sampler_name")
	out["schedulers"] = choices("KSampler", "scheduler")
	out["ipadapter"] = has_class("IPAdapterUnifiedLoader") and has_class("IPAdapterAdvanced")
	out["ipadapter_presets"] = choices("IPAdapterUnifiedLoader", "preset")
	out["ok"] = true
	last_check = out
	return out


func has_class(cls: String) -> bool:
	return object_info.has(cls)


## The list of options ComfyUI offers for a node input (models, samplers…).
func choices(cls: String, input_name: String) -> Array:
	var spec := input_spec(cls, input_name)
	if spec.is_empty():
		return []
	var first: Variant = spec[0]
	if typeof(first) == TYPE_ARRAY:
		return (first as Array).duplicate()
	# Newer ComfyUI: ["COMBO", {"options": [...]}]
	if str(first) == "COMBO" and spec.size() > 1 and typeof(spec[1]) == TYPE_DICTIONARY:
		return ((spec[1] as Dictionary).get("options", []) as Array).duplicate()
	return []


func input_spec(cls: String, input_name: String) -> Array:
	if not object_info.has(cls):
		return []
	var node: Dictionary = object_info[cls]
	var inputs: Dictionary = node.get("input", {})
	for group in ["required", "optional"]:
		var g: Dictionary = inputs.get(group, {})
		if g.has(input_name):
			var v: Variant = g[input_name]
			return v if typeof(v) == TYPE_ARRAY else [v]
	return []


## Fills required inputs we didn't set with ComfyUI's own defaults, so the
## graph keeps working when a custom node adds a new required input.
func fill_defaults(graph: Dictionary) -> void:
	if object_info.is_empty():
		return
	for id in graph.keys():
		var node: Dictionary = graph[id]
		var cls := str(node.get("class_type", ""))
		if not object_info.has(cls):
			continue
		var inputs: Dictionary = node.get("inputs", {})
		var req: Dictionary = ((object_info[cls] as Dictionary).get("input", {}) as Dictionary).get("required", {})
		for key in req.keys():
			if inputs.has(key):
				continue
			var spec: Variant = req[key]
			if typeof(spec) != TYPE_ARRAY or (spec as Array).is_empty():
				continue
			var sa: Array = spec
			if typeof(sa[0]) == TYPE_ARRAY and not (sa[0] as Array).is_empty():
				inputs[key] = (sa[0] as Array)[0]
			elif sa.size() > 1 and typeof(sa[1]) == TYPE_DICTIONARY and (sa[1] as Dictionary).has("default"):
				inputs[key] = (sa[1] as Dictionary)["default"]
		node["inputs"] = inputs


# ================================================================ jobs

## Uploads a picture into ComfyUI's input folder. Returns its name or "".
func upload(img: Image, file_name: String) -> Dictionary:
	var mp := AiHttp.Multipart.new()
	mp.file("image", file_name, img.save_png_to_buffer())
	mp.field("overwrite", "true")
	mp.field("type", "input")
	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + mp.boundary])
	var r := await AiHttp.request(self, base() + "/upload/image", headers, HTTPClient.METHOD_POST, mp.finish(), 60.0)
	r = AiHttp._with_json(r)
	if not r["ok"]:
		return {"ok": false, "error": "Upload to ComfyUI failed: " + str(r["error"])}
	var j: Variant = r["json"]
	if typeof(j) != TYPE_DICTIONARY:
		return {"ok": false, "error": "ComfyUI's upload answer was unreadable."}
	var jd: Dictionary = j
	var n := str(jd.get("name", file_name))
	var sub := str(jd.get("subfolder", ""))
	return {"ok": true, "name": sub.path_join(n) if sub != "" else n}


## Queues a graph. Returns {ok, prompt_id, error}.
func queue(graph: Dictionary) -> Dictionary:
	_ensure_ws()
	fill_defaults(graph)
	var r := await AiHttp.post_json(self, base() + "/prompt", {"prompt": graph, "client_id": client_id}, PackedStringArray(), 30.0)
	if typeof(r["json"]) == TYPE_DICTIONARY:
		var j: Dictionary = r["json"]
		if j.has("prompt_id"):
			return {"ok": true, "prompt_id": str(j["prompt_id"])}
		if j.has("error") or j.has("node_errors"):
			return {"ok": false, "error": "ComfyUI refused the job: " + _explain_errors(j)}
	return {"ok": false, "error": str(r["error"])}


static func _explain_errors(j: Dictionary) -> String:
	var parts: Array[String] = []
	var e: Variant = j.get("error")
	if typeof(e) == TYPE_DICTIONARY:
		var ed: Dictionary = e
		parts.append(str(ed.get("message", "")) + " " + str(ed.get("details", "")))
	elif e != null:
		parts.append(str(e))
	var ne: Variant = j.get("node_errors")
	if typeof(ne) == TYPE_DICTIONARY:
		for nid in (ne as Dictionary).keys():
			var nd: Dictionary = (ne as Dictionary)[nid]
			for er in nd.get("errors", []):
				var erd: Dictionary = er
				parts.append("[%s] %s %s" % [str(nd.get("class_type", nid)), str(erd.get("message", "")), str(erd.get("details", ""))])
	return "; ".join(parts).strip_edges()


## Looks a job up. Returns {state: "pending"|"done"|"error", image: Image, error}.
func poll(prompt_id: String, output_node: String) -> Dictionary:
	var r := await AiHttp.get_json(self, base() + "/history/" + prompt_id, PackedStringArray(), 20.0)
	if not r["ok"]:
		return {"state": "unreachable", "error": str(r["error"])}
	if typeof(r["json"]) != TYPE_DICTIONARY or not (r["json"] as Dictionary).has(prompt_id):
		return {"state": "pending"}
	var h: Dictionary = (r["json"] as Dictionary)[prompt_id]
	var status: Dictionary = h.get("status", {})
	if str(status.get("status_str", "")) == "error":
		var msg := "ComfyUI reported an error while drawing."
		for m in status.get("messages", []):
			var ma: Array = m
			if ma.size() > 1 and str(ma[0]) == "execution_error" and typeof(ma[1]) == TYPE_DICTIONARY:
				var md: Dictionary = ma[1]
				msg = "ComfyUI: %s (%s)" % [str(md.get("exception_message", "")).strip_edges(), str(md.get("node_type", ""))]
		return {"state": "error", "error": msg}
	var outputs: Dictionary = h.get("outputs", {})
	var picked: Dictionary = {}
	var order := [output_node]
	order.append_array(outputs.keys())
	for nid in order:
		if not outputs.has(nid):
			continue
		var imgs: Array = (outputs[nid] as Dictionary).get("images", [])
		if not imgs.is_empty():
			picked = imgs[0]
			break
	if picked.is_empty():
		if bool(status.get("completed", false)):
			return {"state": "error", "error": "ComfyUI finished but produced no picture."}
		return {"state": "pending"}
	var url := "%s/view?filename=%s&subfolder=%s&type=%s" % [base(), str(picked.get("filename", "")).uri_encode(), str(picked.get("subfolder", "")).uri_encode(), str(picked.get("type", "output")).uri_encode()]
	var dl := await AiHttp.request(self, url, PackedStringArray(), HTTPClient.METHOD_GET, PackedByteArray(), 120.0)
	if not dl["ok"]:
		return {"state": "error", "error": "Couldn't download the picture: " + str(dl["error"])}
	var img := Image.new()
	var body: PackedByteArray = dl["body"]
	var err := img.load_png_from_buffer(body)
	if err != OK:
		err = img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_webp_from_buffer(body)
	if err != OK:
		return {"state": "error", "error": "The picture from ComfyUI couldn't be read."}
	img.convert(Image.FORMAT_RGBA8)
	return {"state": "done", "image": img}


func interrupt() -> void:
	await AiHttp.request(self, base() + "/interrupt", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, "{}".to_utf8_buffer(), 10.0)


## Removes a queued (not yet running) job from ComfyUI's queue.
func delete_queued(prompt_id: String) -> void:
	await AiHttp.post_json(self, base() + "/queue", {"delete": [prompt_id]}, PackedStringArray(), 10.0)


# ================================================================ live progress

func _ensure_ws() -> void:
	var url := base().replace("http://", "ws://").replace("https://", "wss://") + "/ws?clientId=" + client_id
	if _ws != null and _ws_url == url and _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return
	if Time.get_ticks_msec() < _ws_retry_at:
		return
	_ws = WebSocketPeer.new()
	_ws_url = url
	if _ws.connect_to_url(url) != OK:
		_ws = null


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_ws = null
		_ws_retry_at = Time.get_ticks_msec() + 60000
		return
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if not _ws.was_string_packet():
			continue  # live preview images
		var j: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(j) != TYPE_DICTIONARY:
			continue
		var jd: Dictionary = j
		if str(jd.get("type", "")) == "progress":
			var d: Dictionary = jd.get("data", {})
			progress.emit(str(d.get("prompt_id", "")), int(d.get("value", 0)), int(d.get("max", 1)))
