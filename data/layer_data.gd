class_name LayerData
extends RefCounted
## A layer: a stack of drawings over time plus its placement in 3D space.
## `cels` maps a key frame (int) -> CelData. A drawing is held (exposed)
## until the next key, like an exposure sheet.

const ROLES := ["background", "midground", "character", "foreground", "effect", "drawing", "reference"]
## Animatable placement fields. Without motion keys the static properties
## (offset, depth, scale, rotation_deg, opacity) are used.
const MOTION_FIELDS := ["x", "y", "depth", "scale", "rotation", "opacity", "turn", "tilt"]

## Suggested depth (world units, + = farther from camera) for each role.
const ROLE_DEPTH := {
	"background": 12.0,
	"midground": 5.0,
	"character": 0.0,
	"foreground": -2.0,
	"effect": -0.5,
	"drawing": 0.0,
	"reference": 0.0,
}

var id: String = ""
var name: String = "Layer"
var role: String = "drawing"
var visible: bool = true
var locked: bool = false
var opacity: float = 1.0
var depth: float = 0.0
var offset: Vector2 = Vector2.ZERO
var scale: float = 1.0
var rotation_deg: float = 0.0
var keep_size: bool = true
## 3D orientation: turn = around the vertical axis, tilt = lean back/forward.
var turn_deg: float = 0.0
var tilt_deg: float = 0.0
## Lighting: lit layers are shaded by the scene light; any layer can cast a
## shadow shaped like its drawing.
var lit: bool = false
var cast_shadow: bool = true
var cels: Dictionary = {}
## int frame -> Dictionary of MOTION_FIELDS + "ease"
var motion_keys: Dictionary = {}

# --- character instance (a linked puppet instead of drawings) ---
var character_id: String = ""
## int frame -> {part name: rotation degrees, "ease": ...} (interpolated)
var pose_keys: Dictionary = {}
## int frame -> view name (held until the next key)
var view_keys: Dictionary = {}
## int frame -> {part name: variant name} (held, cumulative)
var swap_keys: Dictionary = {}


func _init(p_name: String = "Layer", p_role: String = "drawing") -> void:
	id = Ids.make()
	name = p_name
	role = p_role
	depth = float(ROLE_DEPTH.get(p_role, 0.0))


## Reference layers (imported guides, model sheets) show while drawing but
## never appear in the 3D stage or in renders.
func is_reference() -> bool:
	return role == "reference"


func is_character() -> bool:
	return character_id != ""


func pose_at(frame: float, part_names: Array) -> Dictionary:
	var defaults := {"ease": "smooth"}
	for n in part_names:
		defaults[n] = 0.0
	return KeyTrack.sample(pose_keys, frame, part_names, defaults)


func view_at(frame: int) -> String:
	var best := -1
	for k in view_keys.keys():
		var ki: int = k
		if ki <= frame and ki > best:
			best = ki
	return str(view_keys[best]) if best >= 0 else "front"


func swaps_at(frame: int) -> Dictionary:
	var keys := swap_keys.keys()
	keys.sort()
	var out := {}
	for k in keys:
		var ki: int = k
		if ki > frame:
			break
		var d: Dictionary = swap_keys[k]
		for part in d.keys():
			out[part] = d[part]
	return out


func static_motion() -> Dictionary:
	return {
		"x": offset.x, "y": offset.y, "depth": depth, "scale": scale,
		"rotation": rotation_deg, "opacity": opacity, "turn": turn_deg, "tilt": tilt_deg,
		"ease": "smooth",
	}


func motion_at(frame: float) -> Dictionary:
	return KeyTrack.sample(motion_keys, frame, MOTION_FIELDS, static_motion())


## Writes motion values into the static properties.
func apply_static(values: Dictionary) -> void:
	for k in values.keys():
		var v: float = float(values[k]) if typeof(values[k]) != TYPE_STRING else 0.0
		match str(k):
			"x":
				offset.x = v
			"y":
				offset.y = v
			"depth":
				depth = v
			"scale":
				scale = v
			"rotation":
				rotation_deg = v
			"opacity":
				opacity = v
			"turn":
				turn_deg = v
			"tilt":
				tilt_deg = v


func sorted_keys() -> Array:
	var k := cels.keys()
	k.sort()
	return k


func key_at_or_before(frame: int) -> int:
	var best := -1
	for f in cels.keys():
		var fi: int = f
		if fi <= frame and fi > best:
			best = fi
	return best


func cel_at(frame: int) -> CelData:
	var k := key_at_or_before(frame)
	if k < 0:
		return null
	return cels[k]


## First frame after `key` that holds a different drawing (exclusive end).
func exposure_end(key: int, frame_count: int) -> int:
	var end := frame_count
	for f in cels.keys():
		var fi: int = f
		if fi > key and fi < end:
			end = fi
	return maxi(end, key + 1)


func to_dict() -> Dictionary:
	var cel_list := []
	for k in sorted_keys():
		var cel: CelData = cels[k]
		cel_list.append({"frame": k, "id": cel.id})
	return {
		"id": id,
		"name": name,
		"role": role,
		"visible": visible,
		"locked": locked,
		"opacity": opacity,
		"depth": depth,
		"offset": [offset.x, offset.y],
		"scale": scale,
		"rotation": rotation_deg,
		"keep_size": keep_size,
		"turn": turn_deg,
		"tilt": tilt_deg,
		"lit": lit,
		"cast_shadow": cast_shadow,
		"cels": cel_list,
		"motion_keys": KeyTrack.to_list(motion_keys, MOTION_FIELDS, static_motion()),
		"character_id": character_id,
		"pose_keys": _dict_track_to_list(pose_keys),
		"view_keys": _dict_track_to_list(view_keys),
		"swap_keys": _dict_track_to_list(swap_keys),
	}


static func _dict_track_to_list(track: Dictionary) -> Array:
	var keys := track.keys()
	keys.sort()
	var out := []
	for k in keys:
		var v: Variant = track[k]
		out.append({"frame": k, "value": v.duplicate() if typeof(v) == TYPE_DICTIONARY else v})
	return out


static func _list_to_dict_track(list: Array) -> Dictionary:
	var out := {}
	for item in list:
		var e: Dictionary = item
		out[int(e.get("frame", 0))] = e.get("value")
	return out


static func from_dict(d: Dictionary, cel_dir: String) -> LayerData:
	var l := LayerData.new(str(d.get("name", "Layer")), str(d.get("role", "drawing")))
	l.id = str(d.get("id", l.id))
	l.visible = bool(d.get("visible", true))
	l.locked = bool(d.get("locked", false))
	l.opacity = float(d.get("opacity", 1.0))
	l.depth = float(d.get("depth", 0.0))
	var off: Array = d.get("offset", [0, 0])
	if off.size() >= 2:
		l.offset = Vector2(float(off[0]), float(off[1]))
	l.scale = float(d.get("scale", 1.0))
	l.rotation_deg = float(d.get("rotation", 0.0))
	l.keep_size = bool(d.get("keep_size", true))
	l.turn_deg = float(d.get("turn", 0.0))
	l.tilt_deg = float(d.get("tilt", 0.0))
	l.lit = bool(d.get("lit", false))
	l.cast_shadow = bool(d.get("cast_shadow", true))
	l.motion_keys = KeyTrack.from_list(d.get("motion_keys", []), MOTION_FIELDS, l.static_motion())
	l.character_id = str(d.get("character_id", ""))
	l.pose_keys = _list_to_dict_track(d.get("pose_keys", []))
	l.view_keys = _list_to_dict_track(d.get("view_keys", []))
	l.swap_keys = _list_to_dict_track(d.get("swap_keys", []))
	var dir := cel_dir.path_join(l.id)
	for entry in d.get("cels", []):
		var e: Dictionary = entry
		var cel := CelData.new(str(e.get("id", "")))
		cel.file_path = dir.path_join(cel.id + ".png")
		l.cels[int(e.get("frame", 0))] = cel
	return l


## Full copy with new ids and copied pixels (used when duplicating).
func clone_deep() -> LayerData:
	var l := LayerData.new(name, role)
	l.visible = visible
	l.locked = false
	l.opacity = opacity
	l.depth = depth
	l.offset = offset
	l.scale = scale
	l.rotation_deg = rotation_deg
	l.keep_size = keep_size
	l.turn_deg = turn_deg
	l.tilt_deg = tilt_deg
	l.lit = lit
	l.cast_shadow = cast_shadow
	l.motion_keys = motion_keys.duplicate(true)
	l.character_id = character_id
	l.pose_keys = pose_keys.duplicate(true)
	l.view_keys = view_keys.duplicate(true)
	l.swap_keys = swap_keys.duplicate(true)
	for k in cels.keys():
		var cel: CelData = cels[k]
		l.cels[k] = cel.clone()
	return l
