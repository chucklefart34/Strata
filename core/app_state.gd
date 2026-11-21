extends Node
## "App" autoload: the open project plus the user's current selections.
## Systems talk through these signals so the canvas, the timeline, the 3D
## view and the panels stay in sync without referencing each other.

signal project_opened
signal project_closed
signal scene_switched
signal layers_changed
signal layer_selected
signal frame_changed
signal pixels_changed
signal timeline_changed
signal camera_changed
signal camera_view_changed
signal library_changed
signal stage_changed
signal tool_changed
signal brush_changed
signal playback_changed
signal playback_looped
signal onion_changed
signal modified_changed
signal clips_changed
signal characters_changed
signal audio_changed
signal episodes_changed
signal markers_changed
signal workspace_requested(workspace_name: String)
signal video_import_requested(path: String)
signal status_message(text: String)

const TOOLS := ["brush", "pencil", "eraser", "fill", "picker", "line", "rect", "ellipse", "select", "lasso", "lassoline", "move", "hand"]

var project: ProjectData = null
var scene_index: int = 0
var layer_index: int = 0
var frame: int = 0

var playing: bool = false
var loop_playback: bool = true
var onion_enabled: bool = true
## Draw/Animate canvas shows the picture framed by the scene camera.
var camera_view: bool = false
var onion_before: int = 2
var onion_after: int = 1

var tool: String = "brush"
var color: Color = Color(0.11, 0.11, 0.13)
var brush_size: float = 10.0
var brush_opacity: float = 1.0
var brush_hardness: float = 0.8
var stabilizer: float = 0.25
var pressure_size: bool = true
## Lasso lineart tool: "shape" (fill a solid colour block; the layer's border
## effect draws the lineart around it), "trace" (trace lines from the picture inside the loop),
## "outline" (the loop becomes a clean ink line) or "fill" (fill the loop).
var lasso_mode: String = "shape"
var lasso_new_layer: bool = false  # shape: each shape on its own new layer
var lasso_behind: bool = true   # fill goes under the lines already drawn
var lasso_detail: float = 10.0  # trace: 1 = only strong edges … 20 = every detail
var palette: Array[Color] = [
	Color("#1c1c21"), Color("#ffffff"), Color("#8a8d99"), Color("#d9d4cc"),
	Color("#ff7a59"), Color("#e8483f"), Color("#ffc94d"), Color("#f3a6b8"),
	Color("#7ccf6a"), Color("#2f9e6e"), Color("#4fd1c5"), Color("#4c8dff"),
	Color("#2b4c9b"), Color("#9b6cff"), Color("#8b5a3c"), Color("#f2d0a9"),
]

var modified: bool = false
var _play_start_usec: int = 0
var _play_start_frame: int = 0


# ---------------------------------------------------------------- queries

## True when the project uses the 3D Depth stage (2D+3D projects).
func is_3d() -> bool:
	return project != null and project.mode == "2d3d"


func is_stop_motion() -> bool:
	return project != null and project.mode == "stopmotion"


func set_camera_view(on: bool) -> void:
	camera_view = on
	camera_view_changed.emit()


func has_project() -> bool:
	return project != null


func current_scene() -> SceneData:
	if project == null or project.scenes.is_empty():
		return null
	scene_index = clampi(scene_index, 0, project.scenes.size() - 1)
	return project.scenes[scene_index]


func current_layer() -> LayerData:
	var s := current_scene()
	if s == null or s.layers.is_empty():
		return null
	layer_index = clampi(layer_index, 0, s.layers.size() - 1)
	return s.layers[layer_index]


func current_cel() -> CelData:
	var l := current_layer()
	if l == null:
		return null
	return l.cel_at(frame)


func frame_count() -> int:
	var s := current_scene()
	return s.frame_count if s != null else 1


# ---------------------------------------------------------------- project

func open_project(p: ProjectData) -> void:
	stop()
	project = p
	scene_index = 0
	var s := current_scene()
	layer_index = maxi(0, s.layers.size() - 1) if s != null else 0
	frame = 0
	modified = false
	History.clear()
	project_opened.emit()
	scene_switched.emit()
	layers_changed.emit()
	frame_changed.emit()
	modified_changed.emit()


func close_project() -> void:
	stop()
	project = null
	History.clear()
	modified = false
	project_closed.emit()
	modified_changed.emit()


# ---------------------------------------------------------------- selection

func set_scene(i: int, force: bool = false) -> void:
	if project == null:
		return
	i = clampi(i, 0, project.scenes.size() - 1)
	if i == scene_index and not force:
		return
	stop()
	scene_index = i
	var s := current_scene()
	layer_index = maxi(0, s.layers.size() - 1)
	frame = clampi(frame, 0, s.frame_count - 1)
	scene_switched.emit()
	layers_changed.emit()
	frame_changed.emit()


func set_layer(i: int) -> void:
	var s := current_scene()
	if s == null:
		return
	i = clampi(i, 0, maxi(0, s.layers.size() - 1))
	if i == layer_index:
		return
	layer_index = i
	layer_selected.emit()


func set_frame(f: int) -> void:
	var fc := frame_count()
	f = clampi(f, 0, fc - 1)
	if f == frame:
		return
	frame = f
	frame_changed.emit()


func step_frame(delta: int) -> void:
	var fc := frame_count()
	var f := frame + delta
	if loop_playback:
		f = posmod(f, fc)
	set_frame(f)


## Jumps to the previous (-1) or next (+1) drawing on the selected layer.
## Wraps around when looping is on; otherwise stays put at the ends.
func step_key(delta: int) -> void:
	var layer := current_layer()
	var keys: Array = [] if layer == null or layer.is_character() else layer.sorted_keys()
	if keys.is_empty():
		step_frame(delta)
		return
	var target := -1
	if delta > 0:
		for k in keys:
			if int(k) > frame:
				target = int(k)
				break
		if target < 0 and loop_playback:
			target = int(keys[0])
	else:
		for i in range(keys.size() - 1, -1, -1):
			if int(keys[i]) < frame:
				target = int(keys[i])
				break
		if target < 0 and loop_playback:
			target = int(keys[keys.size() - 1])
	if target >= 0:
		set_frame(target)


func set_tool(t: String) -> void:
	if t == tool or not TOOLS.has(t):
		return
	tool = t
	tool_changed.emit()


func set_color(c: Color) -> void:
	color = c
	brush_changed.emit()


# ---------------------------------------------------------------- playback

func toggle_play() -> void:
	if playing:
		stop()
	else:
		play()


func play() -> void:
	if project == null or playing:
		return
	if frame >= frame_count() - 1:
		set_frame(0)
	playing = true
	_play_start_frame = frame
	_play_start_usec = Time.get_ticks_usec()
	playback_changed.emit()
	onion_changed.emit()


func stop() -> void:
	if not playing:
		return
	playing = false
	playback_changed.emit()
	onion_changed.emit()


## Playback runs on the wall clock (not accumulated frame deltas), so the
## picture stays locked to audio, which also plays in real time.
func _process(_delta: float) -> void:
	if not playing or project == null:
		return
	var fc := frame_count()
	var elapsed := (Time.get_ticks_usec() - _play_start_usec) / 1000000.0
	var f := _play_start_frame + int(elapsed * project.fps)
	if f >= fc:
		if loop_playback:
			_play_start_frame = 0
			_play_start_usec = Time.get_ticks_usec()
			f = 0
			playback_looped.emit()
		else:
			set_frame(fc - 1)
			stop()
			return
	set_frame(f)


## Exact playhead time in seconds (sub-frame accurate while playing).
func playhead_seconds() -> float:
	if project == null:
		return 0.0
	var fps := float(maxi(project.fps, 1))
	if playing:
		var elapsed := (Time.get_ticks_usec() - _play_start_usec) / 1000000.0
		return minf(_play_start_frame / fps + elapsed, frame_count() / fps)
	return frame / fps


# ---------------------------------------------------------------- change notification

func mark_modified() -> void:
	if not modified:
		modified = true
		modified_changed.emit()


func mark_saved() -> void:
	modified = false
	modified_changed.emit()


func notify_pixels() -> void:
	mark_modified()
	pixels_changed.emit()


func notify_layers() -> void:
	mark_modified()
	layers_changed.emit()


func notify_timeline() -> void:
	mark_modified()
	frame = clampi(frame, 0, frame_count() - 1)
	timeline_changed.emit()
	frame_changed.emit()


func notify_stage() -> void:
	mark_modified()
	stage_changed.emit()


func notify_camera() -> void:
	mark_modified()
	camera_changed.emit()


func notify(kind: String) -> void:
	match kind:
		"layers":
			notify_layers()
		"timeline":
			notify_timeline()
		"camera":
			notify_camera()
		"stage":
			notify_stage()
		"pixels":
			notify_pixels()
		"clips":
			mark_modified()
			clips_changed.emit()
		"library":
			mark_modified()
			library_changed.emit()
		"characters":
			mark_modified()
			characters_changed.emit()
		"audio":
			mark_modified()
			audio_changed.emit()
		"episodes":
			mark_modified()
			episodes_changed.emit()
		"scene":
			mark_modified()
			scene_switched.emit()
			layers_changed.emit()
			timeline_changed.emit()
		_:
			mark_modified()
			timeline_changed.emit()


func status(text: String) -> void:
	status_message.emit(text)
