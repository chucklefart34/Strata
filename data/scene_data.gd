class_name SceneData
extends RefCounted
## A scene: an ordered stack of layers (index 0 = bottom), a length in frames
## and an animated camera.

const CAMERA_FIELDS := ["x", "y", "dolly", "zoom", "roll", "shake"]
const CAMERA_DEFAULT := {
	"x": 0.0, "y": 0.0, "dolly": 0.0, "zoom": 1.0, "roll": 0.0, "shake": 0.0, "ease": "smooth",
}
const EASES := KeyTrack.EASES

var id: String = ""
var name: String = "Scene"
var frame_count: int = 48
var bg_color: Color = Color(1, 1, 1)
var camera_ortho: bool = false
var layers: Array[LayerData] = []
## int frame -> Dictionary with CAMERA_FIELDS + "ease"
var camera_keys: Dictionary = {}
## int frame -> marker label (dialogue beats, story beats, timing notes)
var markers: Dictionary = {}
## Dialogue, music, effects and ambience for this scene.
var audio_tracks: Array[AudioTrackData] = []
## The 3D set: floor, lighting and set pieces (see default_stage()).
var stage: Dictionary = default_stage()
## Drawings made on set pieces: prop id -> CelData (a texture wrapped on the shape).
var prop_paint: Dictionary = {}


## World units: 1 unit = 100 canvas px. Depth is + away from the camera.
## floor_offset is relative to the bottom of the canvas frame at depth 0.
static func default_stage() -> Dictionary:
	return {
		"floor": true,
		"floor_color": "343844ff",
		"floor_offset": 0.0,
		"light": "sun",          # "sun", "lamp" or "none"
		"azimuth": -35.0,        # sun direction around the set (degrees)
		"elevation": 42.0,       # sun height above the horizon (degrees)
		"light_color": "fff1dcff",
		"energy": 1.3,
		"shadows": true,
		"shadow_strength": 0.75, # the shadow meter: 0 = no shadow, 1 = solid
		"shadow_softness": 1.0,
		"ambient": 0.55,
		"lamp_pos": [3.0, 3.0, -2.0],  # x, y, depth
		"lamp_range": 25.0,
		"props": [],             # blockout shapes: {id, type, role, name, pos, rot, size, color}
		"snap": true,            # snap set pieces to a 0.5 grid while dragging
		"haze": 0.0,             # distance haze in the scene's background colour
		"draw_guide": true,      # show the 3D set under the drawings in the Draw tab
		"draw_guide_opacity": 1.0,
		"draw_guide_front": false,  # true: over the drawings (for tracing)
		"lowpoly": LowPolyBuilder.default_settings(),
	}


func stage_value(key: String) -> Variant:
	return stage.get(key, default_stage().get(key))


func _init(p_name: String = "Scene") -> void:
	id = Ids.make()
	name = p_name


static func create_default(p_name: String) -> SceneData:
	var s := SceneData.new(p_name)
	s.layers.append(LayerData.new("Background", "background"))
	s.layers.append(LayerData.new("Character", "character"))
	return s


## A new scene laid out for the project kind ("2d", "2d3d", "stopmotion").
static func create_for_mode(p_name: String, mode: String) -> SceneData:
	var s := create_default(p_name)
	if mode == "stopmotion":
		# Photos go on the bottom layer; drawn effects, clean-up and lettering
		# go on the layer above.
		s.layers.clear()
		s.layers.append(LayerData.new("Photos", "background"))
		s.layers.append(LayerData.new("Draw on top", "drawing"))
	if mode != "2d3d":
		s.stage["floor"] = false
	return s


func camera_at(frame: float) -> Dictionary:
	return KeyTrack.sample(camera_keys, frame, CAMERA_FIELDS, CAMERA_DEFAULT)


static func ease_t(t: float, mode: String) -> float:
	return KeyTrack.ease_t(t, mode)


func duration_seconds(fps: int) -> float:
	return frame_count / float(maxi(fps, 1))


func to_dict() -> Dictionary:
	var layer_list := []
	for l in layers:
		layer_list.append(l.to_dict())
	var audio_list := []
	for t in audio_tracks:
		audio_list.append(t.to_dict())
	var marker_list := []
	var mk := markers.keys()
	mk.sort()
	for k in mk:
		marker_list.append({"frame": k, "label": str(markers[k])})
	return {
		"id": id,
		"name": name,
		"frame_count": frame_count,
		"bg_color": bg_color.to_html(true),
		"camera_ortho": camera_ortho,
		"layers": layer_list,
		"camera_keys": KeyTrack.to_list(camera_keys, CAMERA_FIELDS, CAMERA_DEFAULT),
		"markers": marker_list,
		"audio_tracks": audio_list,
		"stage": stage.duplicate(true),
		"prop_paint": _paint_ids(),
	}


func _paint_ids() -> Dictionary:
	var out := {}
	var live := {}
	for item in stage_value("props"):
		var p: Dictionary = item
		live[str(p.get("id", ""))] = true
	for k in prop_paint.keys():
		if live.has(str(k)):
			var cel: CelData = prop_paint[k]
			out[str(k)] = cel.id
	return out


static func from_dict(d: Dictionary, root_dir: String) -> SceneData:
	var s := SceneData.new(str(d.get("name", "Scene")))
	s.id = str(d.get("id", s.id))
	s.frame_count = maxi(1, int(d.get("frame_count", 48)))
	s.bg_color = Color.from_string(str(d.get("bg_color", "ffffffff")), Color.WHITE)
	s.camera_ortho = bool(d.get("camera_ortho", false))
	var cel_dir := root_dir.path_join("scenes").path_join(s.id)
	for ld in d.get("layers", []):
		s.layers.append(LayerData.from_dict(ld, cel_dir))
	s.camera_keys = KeyTrack.from_list(d.get("camera_keys", []), CAMERA_FIELDS, CAMERA_DEFAULT)
	var st: Dictionary = d.get("stage", {})
	s.stage = default_stage()
	if not d.has("stage"):
		s.stage["floor"] = false  # scenes made before the 3D set keep their look
	for k in st.keys():
		s.stage[k] = st[k]
	var pp: Dictionary = d.get("prop_paint", {})
	var live := {}
	for item in s.stage_value("props"):
		var p: Dictionary = item
		live[str(p.get("id", ""))] = true
	for k in pp.keys():
		if live.has(str(k)):
			var cel := CelData.new(str(pp[k]))
			cel.file_path = cel_dir.path_join("props").path_join(cel.id + ".png")
			s.prop_paint[str(k)] = cel
	for td in d.get("audio_tracks", []):
		s.audio_tracks.append(AudioTrackData.from_dict(td))
	for m in d.get("markers", []):
		var e: Dictionary = m
		s.markers[int(e.get("frame", 0))] = str(e.get("label", ""))
	return s


func clone_deep() -> SceneData:
	var s := SceneData.new(name + " copy")
	s.frame_count = frame_count
	s.bg_color = bg_color
	s.camera_ortho = camera_ortho
	s.camera_keys = camera_keys.duplicate(true)
	s.markers = markers.duplicate()
	s.stage = stage.duplicate(true)
	for k in prop_paint.keys():
		var cel: CelData = prop_paint[k]
		s.prop_paint[k] = cel.clone()
	for t in audio_tracks:
		s.audio_tracks.append(t.clone_deep())
	for l in layers:
		s.layers.append(l.clone_deep())
	return s
