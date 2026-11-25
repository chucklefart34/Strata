extends Node
## "AiJobs" autoload: the background render queue. One picture per job,
## sent to ComfyUI one at a time while you keep working anywhere in Strata.
##
## Jobs live in the project's studio.json, so the queue survives closing
## the app: on reopening, unfinished jobs go back in line and continue
## (unless the queue was paused). It only ever runs jobs you (or the
## director, on your request) put in the queue.
##
## Order: a shot's background plate, then keys and breakdowns, then the
## in-betweens (each needs the two drawings around it to exist first; it's
## redrawn over a guide made from them).

signal jobs_changed
signal job_progress(job_id: String, value: int, maximum: int)
signal job_finished(job_id: String, ok: bool)

const POLL_SECONDS := 1.0
const JOB_TIMEOUT := 900.0

var comfy: ComfyClient
var director: Director
var running: bool = false
var current_id: String = ""
var current_progress: Vector2i = Vector2i.ZERO
var waiting_reason: String = ""
var _current_prompt: String = ""
var _stop_now: bool = false
var _uploaded: Dictionary = {}  # ref id -> name in ComfyUI
var _ib: InbetweenProcessor = null
var _ib_pair: String = ""


func _ready() -> void:
	comfy = ComfyClient.new()
	comfy.name = "Comfy"
	add_child(comfy)
	director = Director.new()
	director.name = "Director"
	add_child(director)
	comfy.progress.connect(_on_progress)
	App.project_opened.connect(func() -> void:
		_uploaded.clear()
		await get_tree().create_timer(1.5).timeout
		kick())
	App.project_closed.connect(func() -> void: _stop_now = true)
	Studio.changed.connect(func(kind: String) -> void:
		if kind == "jobs" or kind == "all":
			jobs_changed.emit())


func _on_progress(prompt_id: String, value: int, maximum: int) -> void:
	if prompt_id == _current_prompt and current_id != "":
		current_progress = Vector2i(value, maximum)
		job_progress.emit(current_id, value, maximum)


# ================================================================ control

func kick() -> void:
	if running or not Studio.has_studio() or Studio.is_paused():
		jobs_changed.emit()
		return
	_run()


func pause_all(stop_current: bool = false) -> void:
	Studio.set_paused(true)
	if stop_current and current_id != "":
		_stop_now = true
		comfy.interrupt()
	jobs_changed.emit()


func resume_all() -> void:
	Studio.set_paused(false)
	kick()


func set_job_status(id: String, status: String) -> void:
	var j := Studio.find_job(id)
	if j.is_empty():
		return
	if id == current_id and status in ["paused", "canceled"]:
		_stop_now = true
		comfy.interrupt()
	j["status"] = status
	if status == "queued":
		j.erase("error")
		j["attempts"] = 0
	_sync_target_status(j, status)
	Studio.touch("jobs")
	if status == "queued":
		kick()


func _sync_target_status(j: Dictionary, status: String) -> void:
	var s := Studio.find_shot(str(j.get("shot_id", "")))
	if s.is_empty():
		return
	var target: Dictionary = s["background"] if str(j.get("kind", "")) == "background" else Studio.drawing(s, int(j.get("index", -1)))
	if target.is_empty():
		return
	match status:
		"canceled":
			target["status"] = "done" if not (target.get("takes", []) as Array).is_empty() else "pending"
		"paused", "queued":
			target["status"] = "queued"
		"failed":
			target["status"] = "failed"
	Studio.touch("shots")


func clear_finished() -> void:
	var keep: Array = []
	for j in Studio.jobs():
		if not (str((j as Dictionary)["status"]) in ["done", "canceled"]):
			keep.append(j)
	Studio.data["jobs"] = keep
	Studio.touch("jobs")


func summary() -> Dictionary:
	var c := {"queued": 0, "running": 0, "paused": 0, "done": 0, "failed": 0, "canceled": 0}
	for j in Studio.jobs():
		var st := str((j as Dictionary).get("status", ""))
		c[st] = int(c.get(st, 0)) + 1
	c["queue_paused"] = Studio.is_paused()
	c["current"] = str(Studio.find_job(current_id).get("label", "")) if current_id != "" else ""
	c["waiting"] = waiting_reason
	return c


## Queues redraws of a shot's flagged drawings, with what QC found as the note.
func fix_flagged(s: Dictionary) -> int:
	var n := 0
	for d in s["drawings"]:
		var dd: Dictionary = d
		var iss := FrameQC.issues(dd)
		if iss.is_empty():
			continue
		var note := "fix: " + "; ".join(PackedStringArray(iss.map(func(x: Variant) -> String: return str(x))))
		n += Studio.queue_shot(s, [int(dd["index"])], note.left(400), true)
	kick()
	return n


# ================================================================ the loop

func _next_job() -> Dictionary:
	var blocked_any := false
	for pass_kind in ["background", "sheet", "key", "inbetween"]:
		for j in Studio.jobs():
			var jd: Dictionary = j
			if str(jd["status"]) != "queued":
				continue
			var kind := str(jd.get("kind", ""))
			if pass_kind == "background" and kind != "background":
				continue
			if pass_kind == "sheet" and kind != "sheet":
				continue
			if pass_kind in ["key", "inbetween"]:
				if kind != "drawing":
					continue
				var s := Studio.find_shot(str(jd.get("shot_id", "")))
				var d := Studio.drawing(s, int(jd.get("index", -1))) if not s.is_empty() else {}
				if d.is_empty():
					jd["status"] = "failed"
					jd["error"] = "The drawing no longer exists."
					continue
				var is_ib := str(d["kind"]) == "inbetween"
				if (pass_kind == "key") == is_ib:
					continue
				if is_ib:
					var dep := _inbetween_deps(s, d)
					if dep == "wait":
						blocked_any = true
						continue
					if dep != "":
						jd["status"] = "failed"
						jd["error"] = dep
						_sync_target_status(jd, "failed")
						continue
			return jd
	waiting_reason = "In-betweens are waiting for their keys." if blocked_any else ""
	return {}


## "" = ready, "wait" = its keys are still coming, else why it can't run.
func _inbetween_deps(s: Dictionary, d: Dictionary) -> String:
	var nb := _neighbours(s, d)
	var a: Dictionary = nb[0]
	var b: Dictionary = nb[1]
	for side in [a, b]:
		var sd: Dictionary = side
		if sd.is_empty():
			continue
		if int(sd.get("chosen", -1)) >= 0:
			continue
		if Studio.has_open_job(str(s["id"]), int(sd["index"])):
			return "wait"
		return "Draw frame %d (%s) first — this in-between is drawn from it." % [int(sd["frame"]) + 1, sd["kind"]]
	return ""


## The key/breakdown drawings before and after an in-between ({} = none).
func _neighbours(s: Dictionary, d: Dictionary) -> Array:
	var a: Dictionary = {}
	var b: Dictionary = {}
	for x in s["drawings"]:
		var xd: Dictionary = x
		if str(xd["kind"]) == "inbetween":
			continue
		if int(xd["frame"]) < int(d["frame"]):
			a = xd
		elif int(xd["frame"]) > int(d["frame"]) and b.is_empty():
			b = xd
	return [a, b]


func _run() -> void:
	running = true
	_stop_now = false
	while Studio.has_studio() and not Studio.is_paused() and not _stop_now:
		var j := _next_job()
		if j.is_empty():
			break
		current_id = str(j["id"])
		current_progress = Vector2i.ZERO
		j["status"] = "running"
		j["started"] = Time.get_datetime_string_from_system()
		_sync_target_status_running(j)
		Studio.touch("jobs")
		var res: Dictionary = await _process_job(j)
		if not Studio.has_studio():
			break
		if _stop_now:
			# paused or canceled while drawing: leave its new status alone
			if str(j["status"]) == "running":
				j["status"] = "queued"
			_stop_now = false
			current_id = ""
			Studio.touch("jobs")
			if Studio.is_paused():
				break
			continue
		if res.get("ok", false):
			j["status"] = "done"
			j["finished"] = Time.get_datetime_string_from_system()
			j.erase("prompt_id")
		elif bool(res.get("unreachable", false)):
			# ComfyUI isn't answering: keep the job, wait, try again.
			j["status"] = "queued"
			j.erase("prompt_id")
			waiting_reason = str(res.get("error", ""))
			current_id = ""
			Studio.touch("jobs")
			job_finished.emit(str(j["id"]), false)
			await get_tree().create_timer(10.0).timeout
			continue
		else:
			j["attempts"] = int(j.get("attempts", 0)) + 1
			j["error"] = str(res.get("error", "Unknown error"))
			j["status"] = "failed"
			j.erase("prompt_id")
			_sync_target_status(j, "failed")
		waiting_reason = ""
		current_id = ""
		Studio.touch("jobs")
		job_finished.emit(str(j["id"]), bool(res.get("ok", false)))
	running = false
	current_id = ""
	jobs_changed.emit()


func _sync_target_status_running(j: Dictionary) -> void:
	var s := Studio.find_shot(str(j.get("shot_id", "")))
	if s.is_empty():
		return
	var target: Dictionary = s["background"] if str(j.get("kind", "")) == "background" else Studio.drawing(s, int(j.get("index", -1)))
	if not target.is_empty():
		target["status"] = "rendering"
		Studio.touch("shots")


# ================================================================ one job

func _process_job(j: Dictionary) -> Dictionary:
	if comfy.object_info.is_empty():
		var chk := await comfy.check()
		if not chk["ok"]:
			return {"ok": false, "unreachable": true, "error": str(chk["error"])}
	var req := await _build_request(j)
	if req.has("error"):
		return {"ok": false, "error": str(req["error"])}
	var built := ComfyWorkflow.build(req, comfy)
	if str(built.get("error", "")) != "":
		return {"ok": false, "error": str(built["error"])}
	# Recovery: a job that was on the GPU when the app closed may be finished.
	var pid := str(j.get("prompt_id", ""))
	if pid != "":
		var early := await comfy.poll(pid, str(built["output"]))
		if str(early.get("state", "")) == "done":
			return _store_result(j, early["image"], req)
		pid = ""
	var q := await comfy.queue(built["graph"])
	if not q["ok"]:
		var err := str(q["error"])
		return {"ok": false, "error": err, "unreachable": err.begins_with("Can't connect")}
	pid = str(q["prompt_id"])
	j["prompt_id"] = pid
	_current_prompt = pid
	Studio.touch("jobs")
	var started := Time.get_ticks_msec()
	while true:
		await get_tree().create_timer(POLL_SECONDS).timeout
		if _stop_now or not Studio.has_studio():
			comfy.delete_queued(pid)
			return {"ok": false, "error": "stopped"}
		var p := await comfy.poll(pid, str(built["output"]))
		match str(p.get("state", "")):
			"done":
				_current_prompt = ""
				return _store_result(j, p["image"], req)
			"error":
				_current_prompt = ""
				return {"ok": false, "error": str(p["error"])}
			"unreachable":
				_current_prompt = ""
				return {"ok": false, "unreachable": true, "error": str(p["error"])}
		if Time.get_ticks_msec() - started > JOB_TIMEOUT * 1000.0:
			comfy.interrupt()
			return {"ok": false, "error": "Timed out after %d minutes." % int(JOB_TIMEOUT / 60)}
	return {"ok": false, "error": "unreachable"}


## Works out the prompt and guide pictures for a job and uploads them.
func _build_request(j: Dictionary) -> Dictionary:
	var pw: int = App.project.width
	var ph: int = App.project.height
	var size := AiImage.gen_size(pw, ph, AiConfig.i("base_size"))
	var kind := str(j.get("kind", ""))
	var note := str(j.get("note", ""))
	var req := {"width": size.x, "height": size.y, "ref_images": []}
	var ref_ids: Array = []
	var extra_refs: Array = []  # Images not in the library (shot anchors)
	if kind == "sheet":
		var c := Studio.find_char(str(j.get("char_id", "")))
		if c.is_empty():
			return {"error": "The character no longer exists."}
		var view := str(j.get("view", "front"))
		var pr := Studio.sheet_prompt(c, view)
		req["positive"] = pr["positive"]
		req["negative"] = pr["negative"]
		var base := AiConfig.i("base_size")
		if view == "expressions":
			req["width"] = base
			req["height"] = base
		else:
			req["width"] = int(round(base * 0.75 / 64.0)) * 64
			req["height"] = base
		req["seed"] = int(c.get("seed", 0)) + Studio.SHEET_VIEWS.find(view) * 101
		var sheets: Dictionary = c.get("sheets", {})
		for id in Studio.character_ref_ids(c):
			if str(sheets.get(view, "")) != str(id):
				ref_ids.append(id)
		ref_ids = ref_ids.slice(0, 2)
		req["ref_weight"] = float(c.get("consistency", 0.75))
	else:
		var s := Studio.find_shot(str(j.get("shot_id", "")))
		if s.is_empty():
			return {"error": "The shot no longer exists."}
		var st: Dictionary = Studio.style()
		if kind == "background":
			var pr := Studio.background_prompt(s)
			req["positive"] = pr["positive"] + (", " + note if note != "" else "")
			req["negative"] = pr["negative"]
			req["seed"] = int(s["seed"]) + 1 + (s["background"]["takes"] as Array).size() * 7919
			for id in st.get("ref_ids", []):
				ref_ids.append(str(id))
			ref_ids = ref_ids.slice(0, 2)
			req["ref_weight"] = float(st.get("style_weight", 0.45))
		else:
			var d := Studio.drawing(s, int(j.get("index", -1)))
			if d.is_empty():
				return {"error": "The drawing no longer exists."}
			var pr := Studio.prompt_for(s, d, note)
			req["positive"] = pr["positive"]
			req["negative"] = pr["negative"]
			# Same seed across a shot keeps drawings alike; new takes vary it.
			req["seed"] = int(s["seed"]) + (d["takes"] as Array).size() * 7919
			var weight := 0.0
			for cid in s.get("characters", []):
				var c := Studio.find_char(str(cid))
				if c.is_empty():
					continue
				var ids := Studio.character_ref_ids(c)
				if not ids.is_empty():
					ref_ids.append(ids[0])
					weight = maxf(weight, float(c.get("consistency", 0.75)))
			ref_ids = ref_ids.slice(0, 2)
			if ref_ids.size() < 2:
				for id in st.get("ref_ids", []):
					if ref_ids.size() < 2:
						ref_ids.append(str(id))
			if ref_ids.is_empty():
				# no sheets yet: the shot's first key keeps the rest consistent
				var first := Studio.drawing(s, 0)
				var anchor := Studio.chosen_image(first) if int(d["index"]) != 0 else null
				if anchor != null:
					extra_refs.append(anchor)
			req["ref_weight"] = weight if weight > 0.0 else AiConfig.f("ipadapter_weight")
			var placed: Dictionary = s.get("placed", {})
			var start := int(placed.get("start", 0))
			var tl_frame := start + int(round(int(d["frame"]) * float(App.project.fps) / int(s["fps"])))
			if str(d["kind"]) == "inbetween":
				var nb := _neighbours(s, d)
				var ia: Image = Studio.chosen_image(nb[0]) if not (nb[0] as Dictionary).is_empty() else null
				var ib: Image = Studio.chosen_image(nb[1]) if not (nb[1] as Dictionary).is_empty() else null
				var guide: Image = null
				j["source"] = "blend"
				if ia != null and ib != null:
					var t := float(int(d["frame"]) - int((nb[0] as Dictionary)["frame"])) / float(int((nb[1] as Dictionary)["frame"]) - int((nb[0] as Dictionary)["frame"]))
					if bool(s.get("separate_background", true)):
						var pair := AiUi_take_key(nb[0]) + "|" + AiUi_take_key(nb[1])
						guide = await _motion_guide(ia, ib, t, size, pair)
						if guide != null:
							j["source"] = "motion guide"
					if guide == null:
						guide = AiImage.mix(AiImage.cover(ia, size.x, size.y), AiImage.cover(ib, size.x, size.y), t)
				elif ia != null:
					guide = AiImage.cover(ia, size.x, size.y)
				if guide != null:
					var up := await comfy.upload(guide, "strata_guide_%s.png" % str(j["id"]))
					if not up["ok"]:
						return {"error": up["error"]}
					req["init_image"] = up["name"]
					req["denoise"] = AiConfig.f("inbetween_denoise")
			else:
				var rough := Studio.guide_from_layer(str(s.get("guide_layer", "")), tl_frame)
				if rough != null:
					var g := AiImage.cover(AiImage.flatten(rough), size.x, size.y)
					var up := await comfy.upload(g, "strata_rough_%s.png" % str(j["id"]))
					if not up["ok"]:
						return {"error": up["error"]}
					if AiConfig.s("controlnet") != "":
						req["control_image"] = up["name"]
					else:
						req["init_image"] = up["name"]
						req["denoise"] = AiConfig.f("rough_denoise")
					j["source"] = "rough"
				elif str(d["kind"]) == "breakdown":
					var nb := _neighbours(s, d)
					var ia: Image = Studio.chosen_image(nb[0]) if not (nb[0] as Dictionary).is_empty() else null
					if ia != null:
						var up := await comfy.upload(AiImage.cover(ia, size.x, size.y), "strata_guide_%s.png" % str(j["id"]))
						if up["ok"]:
							req["init_image"] = up["name"]
							req["denoise"] = 0.8
							j["source"] = "previous key"
				if not j.has("source"):
					j["source"] = "text"
	# upload references
	for id in ref_ids:
		var rid := str(id)
		if not _uploaded.has(rid):
			var rimg := Studio.ref_image(rid)
			if rimg == null:
				continue
			var up := await comfy.upload(AiImage.contain(rimg, 768, 768), "strata_ref_%s.png" % rid)
			if not up["ok"]:
				return {"error": up["error"]}
			_uploaded[rid] = up["name"]
		(req["ref_images"] as Array).append(_uploaded[rid])
	for img in extra_refs:
		var up := await comfy.upload(AiImage.contain(img, 768, 768), "strata_anchor_%s.png" % str(j.get("shot_id", "")))
		if up["ok"]:
			(req["ref_images"] as Array).append(up["name"])
	return req


static func AiUi_take_key(d: Dictionary) -> String:
	var takes: Array = d.get("takes", [])
	var ch := int(d.get("chosen", -1))
	return str((takes[ch] as Dictionary).get("file", "")) if ch >= 0 and ch < takes.size() else ""


## An in-between guide made by Strata's own motion in-betweener: the figure
## from both neighbouring drawings is moved along its path to time `t`
## (instead of a cross-fade, which leaves two ghost figures for the model to
## sort out). Needs the GPU; returns null where that isn't available.
func _motion_guide(ia: Image, ib: Image, t: float, size: Vector2i, pair: String) -> Image:
	if not AiConfig.b("motion_guides") or DisplayServer.get_name() == "headless":
		return null
	var ca := AiImage.cover(ia, size.x, size.y)
	var backdrop := ca.get_pixel(2, 2)
	backdrop.a = 1.0
	if _ib == null:
		_ib = InbetweenProcessor.new()
		add_child(_ib)
	if pair != _ib_pair:
		var ka := AiImage.key_backdrop(ca)
		var kb := AiImage.key_backdrop(AiImage.cover(ib, size.x, size.y))
		await _ib.prepare(ka, kb)
		_ib_pair = pair
	var mid := _ib.frame(t, "motion", 0.0)
	if not AiImage.has_content(mid):
		return null
	return AiImage.flatten(mid, backdrop)


func _store_result(j: Dictionary, img: Image, req: Dictionary) -> Dictionary:
	var kind := str(j.get("kind", ""))
	var meta := {"seed": req.get("seed", 0), "note": str(j.get("note", "")), "source": str(j.get("source", "text")),
		"prompt": str(req.get("positive", "")).left(2000)}
	if kind == "sheet":
		var c := Studio.find_char(str(j.get("char_id", "")))
		if c.is_empty():
			return {"ok": false, "error": "The character no longer exists."}
		var view := str(j.get("view", "front"))
		var r := Studio.add_reference_image(img, "%s — %s" % [c["name"], view], "character", str(c["id"]), "generated sheet")
		if r.is_empty():
			return {"ok": false, "error": "Couldn't save the sheet."}
		var sheets: Dictionary = c.get("sheets", {})
		sheets[view] = r["id"]
		c["sheets"] = sheets
		Studio.touch("cast")
		return {"ok": true}
	var s := Studio.find_shot(str(j.get("shot_id", "")))
	if s.is_empty():
		return {"ok": false, "error": "The shot no longer exists."}
	if kind == "background":
		var bg: Dictionary = s["background"]
		var rel := "renders/%s/background_%02d_%s.png" % [str(s["id"]), (bg["takes"] as Array).size() + 1, Ids.make()]
		if not Studio.save_image(img, rel):
			return {"ok": false, "error": "Couldn't save the background."}
		meta["file"] = rel
		(bg["takes"] as Array).append(meta)
		if int(bg.get("chosen", -1)) < 0 or str(j.get("note", "")) == "":
			bg["chosen"] = (bg["takes"] as Array).size() - 1
		bg["status"] = "done"
		Studio.touch("shots")
		return {"ok": true}
	var d := Studio.drawing(s, int(j.get("index", -1)))
	if d.is_empty():
		return {"ok": false, "error": "The drawing no longer exists."}
	# The first picture of a drawing is used at once; later takes wait for
	# your approve / reject in Shots.
	var auto_use := int(d.get("chosen", -1)) < 0
	var qc: Dictionary = d.get("qc", {})
	qc.erase("auto")
	qc.erase("vision")
	d["qc"] = qc
	Studio.add_take(s, d, img, meta, auto_use)
	return {"ok": true}
