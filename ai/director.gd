class_name Director
extends Node
## The AI animation director you chat with. It reads the project's context
## (style, cast, shots, what you have selected), answers, and returns
## structured actions the studio carries out: plan a shot (keys and
## breakdowns), revise drawings, relight, change timing or the camera,
## create characters and sheets, place shots, run QC.
##
## Providers:  Claude  — CLOUD (Anthropic API; needs your API key)
##             Ollama  — LOCAL (a model running on this computer)
## Image generation is never done by the director: ComfyUI draws.

const ACTION_TYPES := ["create_shot", "update_shot", "revise_frames", "render_shot", "place_shot",
	"run_qc", "fix_flagged", "update_style", "create_character", "update_character",
	"generate_character_sheet", "pause_queue", "resume_queue"]

var busy: bool = false


static func _messages_url() -> String:
	return AiConfig.s("anthropic_url").strip_edges().trim_suffix("/") + "/v1/messages"


static func _schema() -> Dictionary:
	var key_item := {"type": "object", "properties": {
		"frame": {"type": "integer", "description": "0-based frame within the shot"},
		"kind": {"type": "string", "enum": ["key", "breakdown"]},
		"pose": {"type": "string"}, "expression": {"type": "string"}, "notes": {"type": "string"}},
		"required": ["frame", "kind", "pose"]}
	var shot := {"type": "object", "properties": {
		"name": {"type": "string"}, "duration_seconds": {"type": "number"},
		"fps": {"type": "integer", "enum": [12, 18, 24, 30]},
		"exposure": {"type": "integer", "description": "1 = on ones (every frame drawn), 2 = on twos, 3 = on threes"},
		"action": {"type": "string"}, "environment": {"type": "string"}, "lighting": {"type": "string"},
		"camera": {"type": "string", "description": "framing / lens / angle"},
		"camera_preset": {"type": "string", "enum": StudioStore_presets()},
		"mood": {"type": "string"}, "dialogue": {"type": "string"},
		"characters": {"type": "array", "items": {"type": "string"}, "description": "character names or ids"},
		"background": {"type": "string", "description": "description of the empty background plate"},
		"separate_background": {"type": "boolean"},
		"keys": {"type": "array", "items": key_item}}}
	return {"type": "object", "properties": {
		"reply": {"type": "string", "description": "What you say to the user (short, concrete, like an animation director)."},
		"actions": {"type": "array", "items": {"type": "object", "properties": {
			"type": {"type": "string", "enum": ACTION_TYPES},
			"shot_id": {"type": "string"},
			"frames": {"type": "array", "items": {"type": "integer"}, "description": "1-based frame numbers within the shot, as shown in the Shots grid"},
			"note": {"type": "string", "description": "correction to apply when redrawing"},
			"changes": {"type": "object", "description": "fields to change (shot fields, style fields, character fields, or per-drawing pose/expression/notes for revise_frames)"},
			"regenerate": {"type": "boolean"},
			"shot": shot,
			"character_id": {"type": "string"},
			"character": {"type": "object", "properties": {
				"name": {"type": "string"}, "description": {"type": "string"}, "personality": {"type": "string"},
				"voice": {"type": "string"}, "proportions": {"type": "string"}, "movement": {"type": "string"},
				"outfits": {"type": "string"}}},
			"views": {"type": "array", "items": {"type": "string", "enum": ["front", "side", "back", "expressions"]}},
			"start_frame": {"type": "integer", "description": "1-based timeline frame"}},
			"required": ["type"]}}},
		"required": ["reply", "actions"]}


static func StudioStore_presets() -> Array:
	return ["none", "push_in", "pull_out", "pan_left", "pan_right", "truck", "crane_up", "zoom_in", "shake"]


func _system_prompt() -> String:
	var st: Dictionary = Studio.style()
	return """You are the animation director of a small personal 2D animation studio running inside the Strata app. You work with one artist (the user). You plan and supervise genuine frame-by-frame hand-drawn animation: every drawing is generated as its own picture by an image model (ComfyUI), then assembled on the timeline.

How the studio works:
- A shot has a length in frames, a frame rate (12/18/24/30) and an exposure: on ones (every frame is a new drawing) or on twos/threes (each drawing held 2-3 frames, the traditional choice for most acting; use ones for fast action, smears and fluid hero moments).
- You plan the KEY poses and BREAKDOWNS (frame numbers are 0-based within the shot and should sit on the exposure grid). The studio works out every in-between drawing from them and draws it from a blend of its neighbours. Plan enough keys: for a walk, contacts/passing positions; for a fight, anticipation, contact, follow-through; for dialogue, mouth shapes and gesture changes on accented syllables.
- Characters have reference sheets that keep them on-model; always list the characters who appear.
- With separate_background true (recommended), the character is drawn on a flat backdrop and the background plate is drawn once, so the background doesn't flicker. The camera move (camera_preset) is applied on the timeline.
- Revisions: use revise_frames with the frame numbers and a precise correction note (e.g. anatomy of the hand, expression). Lighting/camera/timing changes to a whole shot: update_shot with regenerate true when the drawings must be redrawn. New takes wait for the user's approval.
- Never claim something was rendered: rendering happens after your reply, in the background queue.

Artistic direction (the house style): %s
Keep everything original: never imitate named artists, studios, or existing copyrighted characters; describe qualities instead. Mature themes, horror, violence and morally complex characters are welcome when the story calls for them, staged cinematically like a sophisticated graphic novel, not a children's cartoon.

Be a good director: suggest improvements to pacing, staging, composition, silhouettes, acting and visual storytelling when useful, briefly. Reply concisely. Always respond by calling the studio_actions tool.""" % str(st.get("descriptors", ""))


## A compact picture of the project for the director.
func context(selection: Dictionary) -> Dictionary:
	var shots: Array = []
	for s in Studio.shots():
		var sd: Dictionary = s
		var c := Studio.counts(sd)
		var keys: Array = []
		for d in sd["drawings"]:
			var dd: Dictionary = d
			if str(dd["kind"]) != "inbetween":
				keys.append({"frame": int(dd["frame"]), "kind": dd["kind"], "pose": dd["pose"], "expression": dd["expression"]})
		var chars: Array = []
		for cid in sd.get("characters", []):
			chars.append(str(Studio.find_char(str(cid)).get("name", cid)))
		shots.append({"id": sd["id"], "name": sd["name"], "frames": sd["frames"], "fps": sd["fps"], "exposure": sd["exposure"],
			"drawings": c["drawings"], "finished": c["done"], "action": sd["action"], "environment": sd["environment"],
			"lighting": sd["lighting"], "camera": sd["camera"], "camera_preset": sd["camera_preset"], "mood": sd["mood"],
			"characters": chars, "keys": keys, "qc_flagged_frames": _flag_frames(sd),
			"placed_on_timeline": not (sd.get("placed", {}) as Dictionary).is_empty()})
	var cast: Array = []
	for c in Studio.cast():
		var cd: Dictionary = c
		cast.append({"id": cd["id"], "name": cd["name"], "description": cd["description"], "personality": cd["personality"],
			"movement": cd["movement"], "has_sheets": (cd.get("sheets", {}) as Dictionary).keys()})
	var st: Dictionary = Studio.style()
	var out := {"project": {"name": App.project.name, "fps": App.project.fps, "size": [App.project.width, App.project.height],
			"timeline_frame": App.frame + 1},
		"style": {"descriptors": st["descriptors"], "lighting": st["lighting"], "line": st["line"], "palette": st["palette"]},
		"cast": cast, "shots": shots, "selection": selection,
		"queue": AiJobs.summary()}
	return out


static func _flag_frames(s: Dictionary) -> Array:
	var out: Array = []
	for d in s["drawings"]:
		var dd: Dictionary = d
		if not FrameQC.issues(dd).is_empty():
			out.append(int(dd["frame"]) + 1)
	return out


# ================================================================ asking

## Sends a message. Returns {ok, reply, actions, error}.
func ask(text: String, selection: Dictionary, images: Array = []) -> Dictionary:
	var provider := AiConfig.s("director")
	if provider == "off":
		return {"ok": false, "error": "The director is switched off (AI Studio → Setup)."}
	busy = true
	var ctx := JSON.stringify(context(selection))
	var history: Array = Studio.chat().slice(maxi(0, Studio.chat().size() - 16))
	var res: Dictionary
	if provider == "ollama":
		res = await _ask_ollama(text, ctx, history)
	else:
		res = await _ask_claude(text, ctx, history, images)
	busy = false
	return res


func _ask_claude(text: String, ctx: String, history: Array, images: Array) -> Dictionary:
	var key := AiConfig.s("claude_key").strip_edges()
	if key == "":
		return {"ok": false, "error": "Add your Anthropic API key in AI Studio → Setup (or switch the director to Ollama to stay local)."}
	var msgs: Array = _history_messages(history)
	var content: Array = []
	for img in images:
		content.append(_image_block(img))
	content.append({"type": "text", "text": "PROJECT CONTEXT (JSON):\n%s\n\nUSER:\n%s" % [ctx, text]})
	_push(msgs, "user", content)
	var body := {
		"model": AiConfig.s("claude_model"), "max_tokens": 8000,
		"system": _system_prompt(), "messages": msgs,
		"tools": [{"name": "studio_actions", "description": "Reply to the user and give the studio actions to carry out.", "input_schema": _schema()}],
		"tool_choice": {"type": "tool", "name": "studio_actions"},
	}
	var headers := PackedStringArray(["x-api-key: " + key, "anthropic-version: 2023-06-01"])
	var r := await AiHttp.post_json(self, _messages_url(), body, headers, 180.0)
	if not r["ok"]:
		return {"ok": false, "error": _claude_error(r)}
	return _parse_claude(r["json"])


static func _claude_error(r: Dictionary) -> String:
	if typeof(r.get("json")) == TYPE_DICTIONARY:
		var e: Variant = (r["json"] as Dictionary).get("error")
		if typeof(e) == TYPE_DICTIONARY:
			return "Claude: " + str((e as Dictionary).get("message", r["error"]))
	return str(r["error"])


static func _parse_claude(j: Variant) -> Dictionary:
	if typeof(j) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Claude sent back something unreadable."}
	for block in (j as Dictionary).get("content", []):
		var b: Dictionary = block
		if str(b.get("type", "")) == "tool_use":
			var inp: Dictionary = b.get("input", {})
			return {"ok": true, "reply": str(inp.get("reply", "")), "actions": inp.get("actions", [])}
	for block in (j as Dictionary).get("content", []):
		var b: Dictionary = block
		if str(b.get("type", "")) == "text":
			return {"ok": true, "reply": str(b.get("text", "")), "actions": []}
	return {"ok": false, "error": "Claude gave no answer."}


func _ask_ollama(text: String, ctx: String, history: Array) -> Dictionary:
	var model := AiConfig.s("ollama_model").strip_edges()
	if model == "":
		return {"ok": false, "error": "Choose an Ollama model in AI Studio → Setup."}
	var msgs: Array = [{"role": "system", "content": _system_prompt() + "\n\nAnswer ONLY with a JSON object matching this schema:\n" + JSON.stringify(_schema())}]
	for m in _history_messages(history):
		var md: Dictionary = m
		var t := ""
		for blk in md["content"]:
			if str((blk as Dictionary).get("type", "")) == "text":
				t += str((blk as Dictionary)["text"])
		msgs.append({"role": md["role"], "content": t})
	msgs.append({"role": "user", "content": "PROJECT CONTEXT (JSON):\n%s\n\nUSER:\n%s" % [ctx, text]})
	var body := {"model": model, "messages": msgs, "stream": false, "format": _schema(), "options": {"temperature": 0.6}}
	var url := AiConfig.s("ollama_url").strip_edges().trim_suffix("/") + "/api/chat"
	var r := await AiHttp.post_json(self, url, body, PackedStringArray(), 600.0)
	if not r["ok"]:
		return {"ok": false, "error": "Ollama: " + str(r["error"])}
	var j: Variant = r["json"]
	if typeof(j) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Ollama sent back something unreadable."}
	var content := str(((j as Dictionary).get("message", {}) as Dictionary).get("content", ""))
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": true, "reply": content, "actions": []}
	var pd: Dictionary = parsed
	return {"ok": true, "reply": str(pd.get("reply", "")), "actions": pd.get("actions", [])}


static func _image_block(img: Image) -> Dictionary:
	var t := img.duplicate() as Image
	var k := minf(1.0, 1280.0 / maxi(t.get_width(), t.get_height()))
	if k < 1.0:
		t.resize(int(t.get_width() * k), int(t.get_height() * k), Image.INTERPOLATE_LANCZOS)
	return {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": Marshalls.raw_to_base64(t.save_png_to_buffer())}}


## Chat history → alternating user/assistant messages (text only).
static func _history_messages(history: Array) -> Array:
	var msgs: Array = []
	for m in history:
		var md: Dictionary = m
		var role := "assistant" if str(md.get("role", "")) == "director" else "user"
		if str(md.get("role", "")) == "system":
			continue
		_push(msgs, role, [{"type": "text", "text": str(md.get("text", ""))}])
	while not msgs.is_empty() and str((msgs[0] as Dictionary)["role"]) != "user":
		msgs.pop_front()
	return msgs


static func _push(msgs: Array, role: String, content: Array) -> void:
	if not msgs.is_empty() and str((msgs[-1] as Dictionary)["role"]) == role:
		((msgs[-1] as Dictionary)["content"] as Array).append_array(content)
	else:
		msgs.append({"role": role, "content": content})


# ================================================================ vision review (QC)

## Asks Claude to look at a shot's drawings. Writes `qc.vision` issues.
## Returns {ok, notes, flagged, error}.
func review_shot(s: Dictionary) -> Dictionary:
	if AiConfig.s("director") != "claude" or AiConfig.s("claude_key") == "":
		return {"ok": false, "error": "Vision review needs the Claude director (cloud) and an API key. The local checks still ran."}
	var imgs: Array = []
	var frames: Array = []
	var ds: Array = []
	for d in s["drawings"]:
		var dd: Dictionary = d
		var img := Studio.chosen_image(dd)
		if img != null:
			imgs.append(img)
			frames.append(int(dd["frame"]) + 1)
			ds.append(dd)
	if imgs.is_empty():
		return {"ok": false, "error": "No finished drawings to review."}
	var content: Array = []
	var flagged: Array = []
	var notes := ""
	# 12 drawings per sheet keeps them big enough to judge hands and faces.
	var start := 0
	busy = true
	while start < imgs.size():
		var part := imgs.slice(start, start + 12)
		var labels := frames.slice(start, start + 12)
		var sheet := AiImage.contact_sheet(part, labels, 300)
		var refs_text := ""
		var ref_blocks: Array = []
		for cid in s.get("characters", []):
			var c := Studio.find_char(str(cid))
			var ids := Studio.character_ref_ids(c) if not c.is_empty() else []
			if not ids.is_empty():
				var rimg := Studio.ref_image(str(ids[0]))
				if rimg != null:
					ref_blocks.append(_image_block(rimg))
					refs_text += "Reference sheet for %s comes first. " % c["name"]
		content = ref_blocks.duplicate()
		content.append(_image_block(sheet))
		content.append({"type": "text", "text": "%sThe last image is a contact sheet of consecutive animation drawings, left to right, top to bottom. They are shot frames %s. Check each drawing for: anatomy problems (hands, limbs), facial distortion, character inconsistency against the reference, costume changes, broken continuity, background changes. Report only real problems. Call the qc_report tool." % [refs_text, _join_ints(labels)]})
		var body := {
			"model": AiConfig.s("claude_model"), "max_tokens": 3000,
			"messages": [{"role": "user", "content": content}],
			"tools": [{"name": "qc_report", "description": "Problems found per frame.", "input_schema": {"type": "object", "properties": {
				"summary": {"type": "string"},
				"problems": {"type": "array", "items": {"type": "object", "properties": {
					"frame": {"type": "integer"}, "issue": {"type": "string"}, "fix": {"type": "string"}}, "required": ["frame", "issue"]}}},
				"required": ["summary", "problems"]}}],
			"tool_choice": {"type": "tool", "name": "qc_report"},
		}
		var headers := PackedStringArray(["x-api-key: " + AiConfig.s("claude_key").strip_edges(), "anthropic-version: 2023-06-01"])
		var r := await AiHttp.post_json(self, _messages_url(), body, headers, 180.0)
		if not r["ok"]:
			busy = false
			return {"ok": false, "error": _claude_error(r)}
		var parsed := _tool_input(r["json"])
		notes += str(parsed.get("summary", "")) + " "
		for p in parsed.get("problems", []):
			var pd: Dictionary = p
			var fr := int(pd.get("frame", -1))
			var pos := frames.find(fr)
			if pos < 0:
				continue
			var dd: Dictionary = ds[pos]
			var qc: Dictionary = dd.get("qc", {})
			var vis: Array = qc.get("vision", [])
			var line := str(pd.get("issue", ""))
			if str(pd.get("fix", "")) != "":
				line += " → " + str(pd["fix"])
			vis.append(line)
			qc["vision"] = vis
			dd["qc"] = qc
			if not flagged.has(int(dd["index"])):
				flagged.append(int(dd["index"]))
		start += 12
	busy = false
	Studio.touch("shots")
	return {"ok": true, "notes": notes.strip_edges(), "flagged": flagged}


static func _join_ints(v: Array) -> String:
	var p := PackedStringArray()
	for x in v:
		p.append(str(x))
	return ", ".join(p)


static func _tool_input(j: Variant) -> Dictionary:
	if typeof(j) != TYPE_DICTIONARY:
		return {}
	for block in (j as Dictionary).get("content", []):
		var b: Dictionary = block
		if str(b.get("type", "")) == "tool_use":
			return b.get("input", {})
	return {}


## Describes a reference picture's style in words (Claude, cloud).
func describe_reference(img: Image) -> Dictionary:
	if AiConfig.s("director") != "claude" or AiConfig.s("claude_key") == "":
		return {"ok": false, "error": "Describing references with AI needs the Claude director and an API key. The local analysis is already there."}
	var body := {
		"model": AiConfig.s("claude_model"), "max_tokens": 800,
		"messages": [{"role": "user", "content": [_image_block(img), {"type": "text", "text": "Describe this reference's VISUAL STYLE for an image-generation prompt, as one comma-separated line of qualities: line thickness and quality, shading technique, colour palette, lighting, composition, texture, level of background detail, character proportions and facial design if any. Describe qualities only: do not name artists, studios, titles or characters. No preamble."}]}],
	}
	var headers := PackedStringArray(["x-api-key: " + AiConfig.s("claude_key").strip_edges(), "anthropic-version: 2023-06-01"])
	var r := await AiHttp.post_json(self, _messages_url(), body, headers, 120.0)
	if not r["ok"]:
		return {"ok": false, "error": _claude_error(r)}
	var p := _parse_claude(r["json"])
	return {"ok": p.get("ok", false), "text": str(p.get("reply", "")).strip_edges(), "error": str(p.get("error", ""))}


# ================================================================ carrying out actions

## Applies the director's actions. Returns lines describing what happened.
func apply(actions: Array, selection: Dictionary) -> Array:
	var lines: Array = []
	var auto := AiConfig.b("auto_queue")
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ad: Dictionary = a
		var t := str(ad.get("type", ""))
		var sid := str(ad.get("shot_id", selection.get("shot_id", "")))
		var s := Studio.find_shot(sid)
		match t:
			"create_shot":
				var spec: Dictionary = ad.get("shot", {})
				var ns := Studio.create_shot(spec)
				var c := Studio.counts(ns)
				var line := "New shot “%s”: %d frames at %d fps %s → %d drawings (%d keys, %d breakdowns, %d in-betweens)." % [
					ns["name"], ns["frames"], ns["fps"], _exposure_word(int(ns["exposure"])), c["drawings"], c["key"], c["breakdown"], c["inbetween"]]
				if auto:
					line += " Queued %d pictures." % Studio.queue_shot(ns)
				lines.append(line)
				selection["shot_id"] = ns["id"]
			"update_shot":
				if s.is_empty():
					lines.append("(couldn't find the shot to change)")
					continue
				Studio.update_shot(sid, ad.get("changes", {}))
				var line := "Updated “%s”." % s["name"]
				if bool(ad.get("regenerate", false)):
					line += " Redrawing: queued %d new takes (approve or reject them in Shots)." % Studio.queue_shot(s, [], str(ad.get("note", "")), true)
				elif auto:
					var q := Studio.queue_shot(s)
					if q > 0:
						line += " Queued %d drawings." % q
				lines.append(line)
			"revise_frames":
				if s.is_empty():
					lines.append("(couldn't find the shot to revise)")
					continue
				var idx := frames_to_indices(s, ad.get("frames", []))
				if idx.is_empty():
					idx = selection.get("indices", [])
				var ch: Dictionary = ad.get("changes", {})
				for i in idx:
					var d := Studio.drawing(s, int(i))
					for k in ["pose", "expression", "notes"]:
						if ch.has(k):
							d[k] = str(ch[k])
				var n := Studio.queue_shot(s, idx, str(ad.get("note", "")), true)
				lines.append("Redrawing %d drawing(s) of “%s”%s — new takes will wait for your approval." % [n, s["name"], (": " + str(ad["note"])) if str(ad.get("note", "")) != "" else ""])
			"render_shot":
				if not s.is_empty():
					lines.append("Queued %d drawings of “%s”." % [Studio.queue_shot(s), s["name"]])
			"place_shot":
				if not s.is_empty():
					var start := maxi(0, int(ad.get("start_frame", App.frame + 1)) - 1)
					lines.append(Studio.place_shot(s, start))
			"run_qc":
				if not s.is_empty():
					var r := FrameQC.run(s)
					lines.append("QC “%s”: %s" % [s["name"], r["notes"]])
			"fix_flagged":
				if not s.is_empty():
					lines.append("Fixing flagged drawings: queued %d." % AiJobs.fix_flagged(s))
			"update_style":
				Studio.set_style(ad.get("changes", {}))
				lines.append("Updated the style profile.")
			"create_character":
				var c := Studio.add_character(ad.get("character", {}))
				lines.append("New character: %s." % c["name"])
			"update_character":
				var c := Studio.find_char(str(ad.get("character_id", "")))
				if not c.is_empty():
					var changes: Dictionary = ad.get("changes", ad.get("character", {}))
					Studio.update_character(str(c["id"]), changes)
					lines.append("Updated %s." % c["name"])
			"generate_character_sheet":
				var c := Studio.find_char(str(ad.get("character_id", "")))
				if not c.is_empty():
					var views: Array = ad.get("views", Studio.SHEET_VIEWS)
					lines.append("Queued %d sheet drawings for %s." % [Studio.queue_sheet(c, views), c["name"]])
			"pause_queue":
				AiJobs.pause_all()
				lines.append("Render queue paused.")
			"resume_queue":
				AiJobs.resume_all()
				lines.append("Render queue resumed.")
	AiJobs.kick()
	return lines


static func _exposure_word(e: int) -> String:
	return ["", "on ones", "on twos", "on threes", "on fours"][clampi(e, 1, 4)]


## 1-based shot frames → indices of the drawings shown on those frames.
static func frames_to_indices(s: Dictionary, frames: Array) -> Array:
	var out: Array = []
	for f in frames:
		var d := Studio.drawing_at(s, int(f) - 1)
		if not d.is_empty() and not out.has(int(d["index"])):
			out.append(int(d["index"]))
	return out
