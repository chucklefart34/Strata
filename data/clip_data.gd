class_name ClipData
extends RefCounted
## A reusable animation clip ("cycle"): a run of drawings with their timing
## (and optional layer motion), saved in the project library so it can be
## dropped into any layer of any scene — a walk, a blink, a talk loop.
## Stored on disk under clips/<clip id>/<cel id>.png.

var id: String = ""
var name: String = "Clip"
var length: int = 1
var cels: Dictionary = {}  # relative frame -> CelData
var motion_keys: Dictionary = {}  # relative frame -> motion key


func _init(p_name: String = "Clip") -> void:
	id = Ids.make()
	name = p_name


func drawing_count() -> int:
	return cels.size()


func to_dict() -> Dictionary:
	var cel_list := []
	var keys := cels.keys()
	keys.sort()
	for k in keys:
		var cel: CelData = cels[k]
		cel_list.append({"frame": k, "id": cel.id})
	return {
		"id": id,
		"name": name,
		"length": length,
		"cels": cel_list,
		"motion_keys": KeyTrack.to_list(motion_keys, LayerData.MOTION_FIELDS, {}),
	}


static func from_dict(d: Dictionary, root_dir: String) -> ClipData:
	var c := ClipData.new(str(d.get("name", "Clip")))
	c.id = str(d.get("id", c.id))
	c.length = maxi(1, int(d.get("length", 1)))
	var dir := root_dir.path_join("clips").path_join(c.id)
	for entry in d.get("cels", []):
		var e: Dictionary = entry
		var cel := CelData.new(str(e.get("id", "")))
		cel.file_path = dir.path_join(cel.id + ".png")
		c.cels[int(e.get("frame", 0))] = cel
	c.motion_keys = KeyTrack.from_list(d.get("motion_keys", []), LayerData.MOTION_FIELDS, {})
	return c
