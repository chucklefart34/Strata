extends Node
## End-to-end test of the AI Studio against tools/mock_ai_server.py (a fake
## ComfyUI + Anthropic API). Run:
##   python3 tools/mock_ai_server.py 8199 &
##   godot --headless --path . res://tools/ai_studio_test.tscn
## Prints "AITEST ok …" / "AITEST FAIL …" lines and "AITEST done".

const MOCK := "http://127.0.0.1:8199"
var fails := 0


func _ready() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		print("AITEST ok   ", what)
	else:
		fails += 1
		print("AITEST FAIL ", what)


func wait_queue(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await get_tree().create_timer(0.3).timeout
		var s: Dictionary = AiJobs.summary()
		if int(s["queued"]) == 0 and int(s["running"]) == 0 and not AiJobs.running:
			return


func _run() -> void:
	var root := OS.get_user_data_dir().path_join("ai_test_%d" % Time.get_ticks_msec())
	AiConfig.use_file("user://ai_studio_test.cfg")
	AiConfig.set_value("comfy_url", MOCK)
	AiConfig.set_value("anthropic_url", MOCK)
	AiConfig.set_value("director", "claude")
	AiConfig.set_value("claude_key", "test-key")
	AiConfig.set_value("checkpoint", "")
	AiConfig.set_value("controlnet", "sdxl_lineart.safetensors")
	AiConfig.set_value("lora", "noir_ink.safetensors")
	AiConfig.set_value("base_size", 768)
	AiConfig.set_value("auto_queue", true)
	var err: String = ProjectIO.create_project("AI test", root, 960, 540, 24, "2d")
	check(err == "", "project created " + err)
	check(Studio.has_studio(), "studio folder ready")

	# the whole workspace builds (every page)
	var ws := AiStudioWorkspace.new()
	ws.size = Vector2(1600, 900)
	get_tree().root.add_child(ws)
	await get_tree().process_frame
	for p in ["director", "shots", "refs", "cast", "queue", "setup"]:
		ws.show_page(p)
		await get_tree().process_frame
	check(true, "workspace pages build")

	var chk: Dictionary = await AiJobs.comfy.check()
	check(bool(chk["ok"]) and (chk["checkpoints"] as Array).size() == 2 and bool(chk["ipadapter"]), "ComfyUI check lists models + IP-Adapter")
	check((chk["ipadapter_presets"] as Array).size() == 3, "COMBO options read (new ComfyUI format)")

	# reference + character
	var ref_img := Image.create_empty(300, 400, false, Image.FORMAT_RGBA8)
	ref_img.fill(Color(0.1, 0.1, 0.12))
	for y in range(100, 300):
		for x in range(100, 200):
			ref_img.set_pixel(x, y, Color(0.6, 0.1, 0.1))
	var r: Dictionary = Studio.add_reference_image(ref_img, "dark ref", "style")
	check(not r.is_empty() and (r["analysis"] as Dictionary).has("palette"), "reference analysed: " + str((r.get("analysis", {}) as Dictionary).get("summary", "")))
	(Studio.style()["ref_ids"] as Array).append(r["id"])
	Studio.rebuild_style_from_refs()
	check((Studio.style()["palette"] as Array).size() > 0, "style rebuilt from references")
	var mara: Dictionary = Studio.add_character({"name": "Mara", "description": "gaunt woman, black coat, white streak in her hair"})
	Studio.queue_sheet(mara, ["front", "expressions"])
	AiJobs.kick()
	await wait_queue(30)
	check((mara["sheets"] as Dictionary).has("front") and (mara["sheets"] as Dictionary).has("expressions"), "character sheets generated")

	# director plans a shot → queued → drawn
	var sel := {"shot_id": "", "indices": []}
	var res: Dictionary = await AiJobs.director.ask("Create a 1-second shot of Mara walking in the rain", sel)
	check(bool(res.get("ok", false)), "director answered: " + str(res.get("reply", res.get("error", ""))))
	var lines: Array = AiJobs.director.apply(res.get("actions", []), sel)
	print("  ", lines)
	var s: Dictionary = Studio.find_shot(str(sel["shot_id"]))
	check(not s.is_empty(), "shot created")
	var c: Dictionary = Studio.counts(s)
	check(int(c["drawings"]) == 12 and int(c["key"]) == 3 and int(c["breakdown"]) == 1 and int(c["inbetween"]) == 8, "24 frames on twos = 12 drawings (3 keys, 1 breakdown, 8 in-betweens): %s" % str(c))
	check(Studio.drawing_at(s, 23)["frame"] == 22, "frame 24 shows the drawing at frame 23 (held)")
	await wait_queue(60)
	c = Studio.counts(s)
	check(int(c["done"]) == 12, "all 12 drawings drawn (%d)" % int(c["done"]))
	check(((s["background"] as Dictionary)["takes"] as Array).size() == 1, "background plate drawn once")
	# graphs: in-betweens used a blend guide + IP-Adapter from the sheet
	var graphs := FileAccess.get_file_as_string("/tmp/mock_graphs.jsonl").split("\n", false)
	var ib_ok := false
	var ip_ok := false
	var lora_ok := false
	for gl in graphs:
		var g: Dictionary = JSON.parse_string(gl)
		if g.has("41") and str((g["40"] as Dictionary)["class_type"]) == "LoadImage" and float(((g["5"] as Dictionary)["inputs"] as Dictionary)["denoise"]) < 0.9:
			ib_ok = true
		if g.has("29"):
			ip_ok = true
		if g.has("2"):
			lora_ok = true
	check(ib_ok, "in-betweens redrawn over a blend guide (img2img)")
	check(ip_ok, "IP-Adapter node used with character sheet")
	check(lora_ok, "style LoRA in the graph")
	var ib: Dictionary = {}
	for d in s["drawings"]:
		if str((d as Dictionary)["kind"]) == "inbetween":
			ib = d
			break
	var src := str(((ib["takes"] as Array)[0] as Dictionary)["source"])
	check(src == "blend" or src == "motion guide", "in-between take records its guide: " + src)

	# QC: the mock draws every 7th picture in red → flagged
	var qc: Dictionary = FrameQC.run(s)
	check(int(qc["checked"]) == 12, "local QC checked the shot: " + str(qc["notes"]))
	# a synthetic sequence with one off-model drawing (drawing 4)
	var qs: Dictionary = Studio.create_shot({"name": "QC test", "frames": 8, "fps": 12, "exposure": 1, "keys": []})
	for d in qs["drawings"]:
		var i := int(d["index"])
		var img := Image.create_empty(320, 180, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.78, 0.78, 0.78))
		var col := Color(0.12, 0.12, 0.14) if i != 4 else Color(0.95, 0.2, 0.2)
		var w := 30 if i != 4 else 90
		img.fill_rect(Rect2i(60 + i * 20, 40, w, 120), col)
		Studio.add_take(qs, d, img, {"source": "test"})
	var q2: Dictionary = FrameQC.run(qs)
	check(q2["flagged"] == [4], "local QC flags only the off-model drawing: " + str(q2["flagged"]) + " " + str(FrameQC.issues(Studio.drawing(qs, 4))))
	Studio.delete_shot(str(qs["id"]))
	var vr: Dictionary = await AiJobs.director.review_shot(s)
	check(bool(vr.get("ok", false)) and (vr["flagged"] as Array).size() == 1, "vision QC flagged frame 5")
	var n_fix: int = AiJobs.fix_flagged(s)
	await wait_queue(40)
	var reviewing := 0
	for d in s["drawings"]:
		if bool((d as Dictionary).get("review", false)):
			reviewing += 1
	check(n_fix > 0 and reviewing == n_fix, "fixes arrive as takes awaiting approval (%d/%d)" % [reviewing, n_fix])
	var d5: Dictionary = Studio.drawing_at(s, 4)
	var before := int(d5["chosen"])
	Studio.reject_take(d5)
	check(int(d5["chosen"]) == before and not bool(d5.get("review", false)), "reject keeps the current take")

	# revise via the director (frame 9 → drawing at frame 8)
	res = await AiJobs.director.ask("Redraw frame 9, his hand looks anatomically incorrect", sel)
	lines = AiJobs.director.apply(res.get("actions", []), sel)
	print("  ", lines)
	await wait_queue(30)
	var d9: Dictionary = Studio.drawing_at(s, 8)
	check(bool(d9.get("review", false)) and (d9["takes"] as Array).size() >= 2, "frame 9 redrawn as a new take")
	Studio.approve_take(d9)
	check(int(d9["chosen"]) == (d9["takes"] as Array).size() - 1, "approve uses the new take")

	# place on the timeline
	var msg: String = Studio.place_shot(s, 0)
	print("  ", msg)
	var scene: SceneData = App.current_scene()
	var char_layer: LayerData = null
	var bg_layer: LayerData = null
	for l in scene.layers:
		if l.name == "AI · Rain walk":
			char_layer = l
		if l.name == "AI BG · Rain walk":
			bg_layer = l
	check(char_layer != null and char_layer.cels.size() == 13 and char_layer.cel_at(30) != null and not AiImage.has_content(char_layer.cel_at(30).get_image()), "12 drawings placed on a character layer, blank after the shot")
	check(bg_layer != null and bg_layer.cels.has(0) and scene.layers.find(bg_layer) == 0, "background plate on the bottom layer")
	var cel0: CelData = char_layer.cel_at(0) if char_layer != null else null
	var img0: Image = cel0.get_image() if cel0 != null else null
	check(img0 != null and img0.get_pixel(5, 270).a < 0.1 and img0.get_size() == Vector2i(960, 540), "backdrop keyed out (transparent around the figure)")
	check(scene.camera_keys.size() == 2, "camera push-in applied")
	History.undo()
	check(scene.camera_keys.is_empty(), "undo removes the camera move")
	History.undo()
	History.undo()
	var still := false
	for l in scene.layers:
		if l.name.begins_with("AI"):
			still = true
	check(not still, "undo removes the placed layers")
	History.redo()
	History.redo()

	# relight via the director: redraws the whole shot as new takes
	res = await AiJobs.director.ask("Change the lighting to a dim red light", sel)
	lines = AiJobs.director.apply(res.get("actions", []), sel)
	check(str(s["lighting"]) == "dim red light", "lighting changed")
	check(int(AiJobs.summary()["queued"]) >= 12, "whole shot queued for redraw")

	# pause / recover: close mid-queue, reopen → jobs are back in line
	AiJobs.pause_all(true)
	await get_tree().create_timer(1.5).timeout
	var j0: Dictionary = {}
	for j in Studio.jobs():
		if str((j as Dictionary)["status"]) == "queued":
			j0 = j
			break
	j0["status"] = "running"  # as if the app died mid-picture
	Studio.save_now()
	ProjectIO.save_project()
	var path: String = App.project.root_dir
	App.close_project()
	check(not Studio.has_studio(), "studio closed with the project")
	ProjectIO.open_project(path)
	await get_tree().process_frame
	var back: Dictionary = Studio.find_job(str(j0["id"]))
	check(str(back.get("status", "")) == "queued" and bool(back.get("recovered", false)), "interrupted job recovered into the queue")
	check(Studio.is_paused(), "pause survives a restart")
	check(Studio.shots().size() == 1 and Studio.cast().size() == 1 and Studio.refs().size() >= 3, "shots, cast and references reloaded")
	AiJobs.resume_all()
	await wait_queue(60)
	check(int(AiJobs.summary()["queued"]) == 0, "queue finished after resume")

	# Ollama director path (local)
	AiConfig.set_value("director", "ollama")
	AiConfig.set_value("ollama_url", MOCK)
	AiConfig.set_value("ollama_model", "qwen3:14b")
	res = await AiJobs.director.ask("hello", {})
	check(bool(res.get("ok", false)) and str(res.get("reply", "")) == "local hello", "Ollama director works")
	AiConfig.set_value("director", "claude")
	AiConfig.set_value("claude_key", "wrong")
	res = await AiJobs.director.ask("hello", {})
	check(not bool(res.get("ok", true)) and str(res["error"]).contains("invalid x-api-key"), "bad API key reported clearly: " + str(res.get("error", "")))

	# WebM export arguments
	var args := ExportSettings.ffmpeg_args("f_%06d.png", 24, "", {"format": "webm"}, "out.webm")
	check(args.has("libvpx-vp9"), "WebM export uses VP9")
	ws.queue_free()
	print("AITEST done, %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
