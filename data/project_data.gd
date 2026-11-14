class_name ProjectData
extends RefCounted
## A whole production: canvas format plus an ordered list of scenes.
## On disk a project is a folder:
##   project.strata.json        – structure (scenes, layers, keys, camera)
##   scenes/<scene>/<layer>/<cel>.png – one PNG per drawing (relative paths)

const FORMAT_VERSION := 1

var name: String = "Untitled"
var root_dir: String = ""
var width: int = 1920
var height: int = 1080
var fps: int = 24
## What kind of project this is: "2d", "2d3d" (2D with the 3D Depth stage)
## or "stopmotion" (photo frames shot with a camera, drawn over like 2D).
var mode: String = "2d3d"
var master_volume_db: float = 0.0
var created: String = ""
var scenes: Array[SceneData] = []
## Reusable animation clips shared by every scene in the project.
var clips: Array[ClipData] = []
## Character library shared by every scene (scenes hold linked instances).
var characters: Array[CharacterData] = []
## Episodes of the series: ordered references to scenes plus titles and soundtrack.
var episodes: Array[EpisodeData] = []


func to_dict() -> Dictionary:
	var scene_list := []
	for s in scenes:
		scene_list.append(s.to_dict())
	var clip_list := []
	for c in clips:
		clip_list.append(c.to_dict())
	var ep_list := []
	for e in episodes:
		ep_list.append(e.to_dict())
	var char_list := []
	for c in characters:
		char_list.append(c.to_dict())
	return {
		"format": "strata-project",
		"version": FORMAT_VERSION,
		"name": name,
		"width": width,
		"height": height,
		"fps": fps,
		"mode": mode,
		"master_volume_db": master_volume_db,
		"created": created,
		"saved": Time.get_datetime_string_from_system(),
		"scenes": scene_list,
		"clips": clip_list,
		"characters": char_list,
		"episodes": ep_list,
	}


static func from_dict(d: Dictionary, p_root: String) -> ProjectData:
	var p := ProjectData.new()
	p.root_dir = p_root
	p.name = str(d.get("name", "Untitled"))
	p.width = maxi(16, int(d.get("width", 1920)))
	p.height = maxi(16, int(d.get("height", 1080)))
	p.fps = maxi(1, int(d.get("fps", 24)))
	# Projects made before modes existed had the Depth stage.
	p.mode = str(d.get("mode", "2d3d"))
	if not ["2d", "2d3d", "stopmotion"].has(p.mode):
		p.mode = "2d3d"
	p.master_volume_db = float(d.get("master_volume_db", 0.0))
	p.created = str(d.get("created", ""))
	for sd in d.get("scenes", []):
		p.scenes.append(SceneData.from_dict(sd, p_root))
	for cd in d.get("clips", []):
		p.clips.append(ClipData.from_dict(cd, p_root))
	for epd in d.get("episodes", []):
		p.episodes.append(EpisodeData.from_dict(epd))
	for chd in d.get("characters", []):
		p.characters.append(CharacterData.from_dict(chd, p_root))
	if p.scenes.is_empty():
		p.scenes.append(SceneData.create_default("Scene 1"))
	return p


func find_character(char_id: String) -> CharacterData:
	for c in characters:
		if c.id == char_id:
			return c
	return null


func cel_path(scene: SceneData, layer: LayerData, cel: CelData) -> String:
	return root_dir.path_join("scenes").path_join(scene.id).path_join(layer.id).path_join(cel.id + ".png")
