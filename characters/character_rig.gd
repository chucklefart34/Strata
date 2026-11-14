class_name CharacterRig
extends Node2D
## Builds a puppet from a character view: one joint (Node2D) per part placed
## at its pivot and parented like the part hierarchy, with the part's drawing
## as a Sprite2D offset so it rotates around the joint. Draw order follows the
## part list (z_index), independent of the hierarchy.

var character: CharacterData
var view: String = ""
var _joints: Dictionary = {}  # part name -> Node2D
var _sprites: Dictionary = {}  # part name -> Sprite2D
var _parts: Dictionary = {}  # part name -> PartData


func build(c: CharacterData, view_name: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_joints.clear()
	_sprites.clear()
	_parts.clear()
	character = c
	view = view_name
	if c == null:
		return
	var list := c.parts(view_name)
	for i in list.size():
		var part: PartData = list[i]
		var joint := Node2D.new()
		joint.name = "J_" + str(i)
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.position = -part.pivot
		sprite.z_as_relative = false
		sprite.z_index = i
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		joint.add_child(sprite)
		_joints[part.name] = joint
		_sprites[part.name] = sprite
		_parts[part.name] = part
	for i in list.size():
		var part: PartData = list[i]
		var joint: Node2D = _joints[part.name]
		if part.parent != "" and part.parent != part.name and _joints.has(part.parent) and not _is_descendant(part.parent, part.name):
			var parent_part: PartData = _parts[part.parent]
			var parent_joint: Node2D = _joints[part.parent]
			parent_joint.add_child(joint)
			joint.position = part.pivot - parent_part.pivot
		else:
			add_child(joint)
			joint.position = part.pivot


## True if `candidate` hangs (directly or indirectly) below `ancestor` — guards
## against loops in the parent chain.
func _is_descendant(candidate: String, ancestor: String) -> bool:
	var guard := 0
	var cur := candidate
	while cur != "" and guard < 64:
		if cur == ancestor:
			return true
		var p: PartData = _parts.get(cur)
		if p == null:
			return false
		cur = p.parent
		guard += 1
	return false


## Applies rotations (degrees per part name) and drawing swaps.
func apply(pose: Dictionary, swaps: Dictionary) -> void:
	for part_name in _parts.keys():
		var part: PartData = _parts[part_name]
		var joint: Node2D = _joints[part_name]
		var sprite: Sprite2D = _sprites[part_name]
		joint.rotation_degrees = float(pose.get(part_name, 0.0))
		var variant: String = str(swaps.get(part_name, part.variants[0]))
		var cel := part.cel_for(variant)
		sprite.visible = cel != null and part.layer.visible
		sprite.texture = cel.get_texture() if cel != null else null
		sprite.modulate.a = part.layer.opacity
