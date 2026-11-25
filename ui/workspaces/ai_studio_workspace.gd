class_name AiStudioWorkspace
extends Control
## AI Studio: your animation team. Pages:
##   Director    chat with the AI director (plans shots, revises, suggests)
##   Shots       every drawing of every shot: preview, takes, approve/reject, QC, place on timeline
##   Style       reference library and the project's style profile
##   Cast        characters with turnaround and expression sheets
##   Queue       the background render queue (pause, resume, cancel, retry)
##   Setup       this computer, ComfyUI (local) and the director (cloud/local)

signal selection_changed

const PAGES := [
	["director", "Director", "chat"],
	["shots", "Shots", "film"],
	["refs", "Style & references", "image"],
	["cast", "Cast", "character"],
	["queue", "Queue", "queue"],
	["setup", "Setup", "settings"],
]

## What's selected across pages: {shot_id, indices: [drawing indices]}.
var selection: Dictionary = {"shot_id": "", "indices": []}
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _status: Label
var _bar: ProgressBar
var _pause: Button


func _ready() -> void:
	var root := UI.vbox(10)
	UI.full_rect(root)
	add_child(root)
	var top := PanelContainer.new()
	top.theme_type_variation = "Toolbar"
	root.add_child(top)
	var h := UI.hbox(6)
	top.add_child(h)
	var group := ButtonGroup.new()
	for p in PAGES:
		var b := UI.button(p[1], p[2], "", "TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(show_page.bind(p[0]))
		h.add_child(b)
		_tabs[p[0]] = b
	h.add_child(UI.spacer())
	_status = UI.label("", "Small")
	_status.clip_text = true
	_status.custom_minimum_size.x = UI.px(320)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = UI.size2(140, 10)
	_bar.show_percentage = false
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_bar)
	_pause = UI.button("Pause queue", "pause", "Pause or resume the background render queue")
	_pause.pressed.connect(func() -> void:
		if Studio.is_paused():
			AiJobs.resume_all()
		else:
			AiJobs.pause_all())
	h.add_child(_pause)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var made := {
		"director": AiDirectorPage.new(),
		"shots": AiShotsPage.new(),
		"refs": AiRefsPage.new(),
		"cast": AiCastPage.new(),
		"queue": AiQueuePage.new(),
		"setup": AiSetupPage.new(),
	}
	for id in made.keys():
		var c: Control = made[id]
		c.set("ws", self)
		UI.full_rect(c)
		c.visible = false
		body.add_child(c)
		_pages[id] = c
	AiJobs.jobs_changed.connect(_update_status)
	AiJobs.job_progress.connect(func(_id: String, v: int, m: int) -> void:
		_bar.max_value = maxi(1, m)
		_bar.value = v)
	AiJobs.job_finished.connect(func(_id: String, _ok: bool) -> void: _bar.value = 0)
	show_page("director")
	_update_status()


func show_page(id: String) -> void:
	for k in _pages.keys():
		(_pages[k] as Control).visible = k == id
	for k in _tabs.keys():
		(_tabs[k] as Button).set_pressed_no_signal(k == id)
	var p: Control = _pages[id]
	if p.has_method("refresh"):
		p.call("refresh")


func select_shot(shot_id: String, indices: Array = []) -> void:
	selection["shot_id"] = shot_id
	selection["indices"] = indices.duplicate()
	selection_changed.emit()


func _update_status() -> void:
	if not is_inside_tree():
		return
	var s := AiJobs.summary()
	_pause.text = "Resume queue" if bool(s["queue_paused"]) else "Pause queue"
	_pause.icon = Icons.tex("play" if bool(s["queue_paused"]) else "pause")
	var parts: Array[String] = []
	if str(s["current"]) != "":
		parts.append("Drawing: " + str(s["current"]))
	if int(s["queued"]) > 0:
		parts.append("%d waiting" % int(s["queued"]))
	if int(s["failed"]) > 0:
		parts.append("%d failed" % int(s["failed"]))
	if bool(s["queue_paused"]):
		parts.append("paused")
	if str(s["waiting"]) != "":
		parts.append(str(s["waiting"]).split("\n")[0])
	_status.text = "  ·  ".join(parts) if not parts.is_empty() else "Queue empty"
	_bar.visible = str(s["current"]) != ""
