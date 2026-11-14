class_name CharacterData
extends RefCounted
## A reusable character asset: parts per view (front/side/back), named
## expressions (which drawing each swappable part shows) and reusable
## actions (pose animation). Scenes contain linked instances, so editing the
## character updates it everywhere.
## Stored on disk under characters/<id>/<view>/<part layer id>/<cel>.png

const VIEWS := ["front", "side", "back"]
const MOUTH_SHAPES := ["rest", "AI", "E", "O", "U", "MBP", "FV", "L"]
const EYE_STATES := ["open", "half", "closed"]

var id: String = ""
var name: String = "Character"
var views: Dictionary = {}  # view name -> Array of PartData, bottom → top
var expressions: Dictionary = {}  # expression name -> {part name: variant name}
var actions: Array = []  # [{name, length, pose_keys, swap_keys, view_keys}]


func _init(p_name: String = "Character") -> void:
	id = Ids.make()
	name = p_name
	for v in VIEWS:
		views[v] = []


func parts(view: String) -> Array:
	return views.get(view, [])


func find_part(view: String, part_name: String) -> PartData:
	for p in parts(view):
		var part: PartData = p
		if part.name == part_name:
			return part
	return null


## Names of all parts across views (front order first), used for posing.
func part_names() -> Array:
	var out := []
	for v in VIEWS:
		for p in parts(v):
			var part: PartData = p
			if not out.has(part.name):
				out.append(part.name)
	return out


## Parts that have more than one drawing (mouths, eyes, hands...).
func swappable_parts() -> Array:
	var out := []
	var seen := {}
	for v in VIEWS:
		for p in parts(v):
			var part: PartData = p
			if part.has_variants() and not seen.has(part.name):
				seen[part.name] = true
				out.append(part)
	return out


## A ready-to-draw body: parts, joints and hierarchy laid out on the canvas.
static func create_template(p_name: String, w: int, h: int) -> CharacterData:
	var c := CharacterData.new(p_name)
	var spec := [
		# name, parent, pivot (fraction of canvas), variants
		["Leg L", "Body", Vector2(0.47, 0.62), []],
		["Leg R", "Body", Vector2(0.53, 0.62), []],
		["Arm R", "Body", Vector2(0.565, 0.42), []],
		["Body", "", Vector2(0.5, 0.55), []],
		["Head", "Body", Vector2(0.5, 0.39), []],
		["Eyes", "Head", Vector2(0.5, 0.29), EYE_STATES],
		["Mouth", "Head", Vector2(0.5, 0.335), MOUTH_SHAPES],
		["Arm L", "Body", Vector2(0.435, 0.42), []],
	]
	for s in spec:
		var part := PartData.new(str(s[0]))
		part.parent = str(s[1])
		var f: Vector2 = s[2]
		part.pivot = Vector2(f.x * w, f.y * h)
		var vars: Array = s[3]
		if not vars.is_empty():
			part.variants = PackedStringArray(vars)
		var front: Array = c.views["front"]
		front.append(part)
	c.expressions = {
		"Neutral": {"Eyes": "open", "Mouth": "rest"},
		"Blink": {"Eyes": "closed"},
		"Talk": {"Eyes": "open", "Mouth": "AI"},
	}
	return c


func to_dict() -> Dictionary:
	var vd := {}
	for v in views.keys():
		var list := []
		for p in views[v]:
			list.append((p as PartData).to_dict())
		vd[v] = list
	return {
		"id": id,
		"name": name,
		"views": vd,
		"expressions": expressions.duplicate(true),
		"actions": actions.duplicate(true),
	}


static func from_dict(d: Dictionary, root_dir: String) -> CharacterData:
	var c := CharacterData.new(str(d.get("name", "Character")))
	c.id = str(d.get("id", c.id))
	var vd: Dictionary = d.get("views", {})
	for v in vd.keys():
		var list := []
		var view_dir := root_dir.path_join("characters").path_join(c.id).path_join(str(v))
		for pd in vd[v]:
			list.append(PartData.from_dict(pd, view_dir))
		c.views[str(v)] = list
	for v in VIEWS:
		if not c.views.has(v):
			c.views[v] = []
	var ex: Dictionary = d.get("expressions", {})
	c.expressions = ex.duplicate(true)
	var ac: Array = d.get("actions", [])
	c.actions = ac.duplicate(true)
	return c


func clone_deep() -> CharacterData:
	var c := CharacterData.new(name + " copy")
	for v in views.keys():
		var list := []
		for p in views[v]:
			list.append((p as PartData).clone_deep())
		c.views[v] = list
	c.expressions = expressions.duplicate(true)
	c.actions = actions.duplicate(true)
	return c
