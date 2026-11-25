class_name AiQueuePage
extends Control
## The background render queue. Jobs run one at a time on ComfyUI while you
## work anywhere in Strata; they're saved with the project, so unfinished
## work continues after closing and reopening (unless paused).

var ws: AiStudioWorkspace
var _rows: VBoxContainer
var _info: Label
var _pending: bool = false


func _ready() -> void:
	var root := UI.vbox(10)
	UI.full_rect(root)
	add_child(root)
	var top := UI.hbox(6)
	root.add_child(top)
	var pause := UI.button("Pause after this picture", "pause", "Stop taking new jobs; the picture being drawn finishes")
	pause.pressed.connect(func() -> void: AiJobs.pause_all(false))
	top.add_child(pause)
	var stop := UI.button("Pause now", "close", "Stop right away (the current picture goes back in line)")
	stop.pressed.connect(func() -> void: AiJobs.pause_all(true))
	top.add_child(stop)
	var resume := UI.button("Resume", "play", "", "AccentButton")
	resume.pressed.connect(AiJobs.resume_all)
	top.add_child(resume)
	var retry := UI.button("Retry failed", "reset")
	retry.pressed.connect(func() -> void:
		for j in Studio.jobs():
			if str((j as Dictionary)["status"]) == "failed":
				AiJobs.set_job_status(str((j as Dictionary)["id"]), "queued"))
	top.add_child(retry)
	var clear := UI.button("Clear finished", "trash")
	clear.pressed.connect(AiJobs.clear_finished)
	top.add_child(clear)
	top.add_child(UI.spacer())
	_info = UI.label("", "Muted")
	top.add_child(_info)
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(card)
	_rows = AiUi.scroll(card)
	AiJobs.jobs_changed.connect(_queue_refresh)
	AiJobs.job_progress.connect(func(_id: String, _v: int, _m: int) -> void: _update_info())
	refresh()


func _queue_refresh() -> void:
	if _pending:
		return
	_pending = true
	await get_tree().create_timer(0.25).timeout
	_pending = false
	refresh()


func _update_info() -> void:
	var s := AiJobs.summary()
	var p := AiJobs.current_progress
	_info.text = "%d waiting · %d done · %d failed%s%s" % [int(s["queued"]), int(s["done"]), int(s["failed"]),
		" · PAUSED" if bool(s["queue_paused"]) else "",
		(" · step %d/%d" % [p.x, p.y]) if p.y > 0 and AiJobs.current_id != "" else ""]


func refresh() -> void:
	if _rows == null or not is_visible_in_tree():
		if _rows != null:
			_update_info()
		return
	_update_info()
	for c in _rows.get_children():
		c.queue_free()
	var list: Array = Studio.jobs()
	if list.is_empty():
		_rows.add_child(AiUi.wrap_label("Nothing in the queue. Render a shot, generate a character sheet, or ask the Director.", "Lead"))
		return
	# newest first, but running and waiting jobs on top
	var order: Array = []
	for st in ["running", "queued", "paused", "failed", "done", "canceled"]:
		for i in range(list.size() - 1, -1, -1):
			if str((list[i] as Dictionary)["status"]) == st:
				order.append(list[i])
	for j in order.slice(0, 300):
		var jd: Dictionary = j
		var row := UI.hbox(8)
		_rows.add_child(row)
		var st := str(jd["status"])
		var badge := UI.label(st.to_upper(), "Small")
		badge.custom_minimum_size.x = UI.px(80)
		var col := {"running": Palette.ACCENT, "queued": Palette.TEXT, "failed": Palette.DANGER, "done": Palette.DEPTH, "paused": Palette.MUTED}
		badge.add_theme_color_override("font_color", col.get(st, Palette.DIM))
		row.add_child(badge)
		var txt := str(jd.get("label", jd.get("kind", "")))
		if str(jd.get("note", "")) != "":
			txt += "  — " + str(jd["note"]).left(80)
		if bool(jd.get("recovered", false)) and st in ["queued", "running"]:
			txt += "  (recovered after restart)"
		if st == "failed":
			txt += "\n" + str(jd.get("error", ""))
		var l := AiUi.wrap_label(txt, "Label")
		row.add_child(l)
		var id := str(jd["id"])
		if st in ["queued", "running"]:
			var pb := UI.icon_button("pause", "Pause this job")
			pb.pressed.connect(func() -> void: AiJobs.set_job_status(id, "paused"))
			row.add_child(pb)
		if st == "paused" or st == "failed":
			var rb := UI.icon_button("play", "Put back in the queue")
			rb.pressed.connect(func() -> void: AiJobs.set_job_status(id, "queued"))
			row.add_child(rb)
		if st in ["queued", "running", "paused", "failed"]:
			var cb := UI.icon_button("close", "Cancel this job")
			cb.pressed.connect(func() -> void: AiJobs.set_job_status(id, "canceled"))
			row.add_child(cb)
		if str(jd.get("shot_id", "")) != "":
			var go := UI.icon_button("film", "Show the shot")
			go.pressed.connect(func() -> void:
				var s := Studio.find_shot(str(jd["shot_id"]))
				if s.is_empty():
					return
				ws.select_shot(str(s["id"]), [int(jd.get("index", -1))] if int(jd.get("index", -1)) >= 0 else [])
				ws.show_page("shots"))
			row.add_child(go)
