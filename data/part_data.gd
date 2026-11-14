class_name PartData
extends RefCounted
## One body part of a character view (head, arm, mouth...). Its artwork is a
## LayerData whose drawings are keyed by variant index (0 = default variant),
## so the normal drawing engine edits parts unchanged. `pivot` is the joint
## the part rotates around, in canvas pixels; `parent` names the part it
## hangs from, which makes the parts a puppet rig.

var id: String = ""
var name: String = "Part"
var parent: String = ""
var pivot: Vector2 = Vector2.ZERO
var variants: PackedStringArray = PackedStringArray(["default"])
var layer: LayerData


func _init(p_name: String = "Part") -> void:
	id = Ids.make()
	name = p_name
	layer = LayerData.new(p_name, "drawing")


func variant_index(variant_name: String) -> int:
	var i := variants.find(variant_name)
	return i if i >= 0 else 0


func cel_for(variant_name: String) -> CelData:
	var idx := variant_index(variant_name)
	if layer.cels.has(idx):
		return layer.cels[idx]
	return layer.cels.get(0)


func has_variants() -> bool:
	return variants.size() > 1


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"parent": parent,
		"pivot": [pivot.x, pivot.y],
		"variants": Array(variants),
		"layer": layer.to_dict(),
	}


static func from_dict(d: Dictionary, view_dir: String) -> PartData:
	var p := PartData.new(str(d.get("name", "Part")))
	p.id = str(d.get("id", p.id))
	p.parent = str(d.get("parent", ""))
	var pv: Array = d.get("pivot", [0, 0])
	if pv.size() >= 2:
		p.pivot = Vector2(float(pv[0]), float(pv[1]))
	var vlist := PackedStringArray()
	for v in d.get("variants", ["default"]):
		vlist.append(str(v))
	if vlist.is_empty():
		vlist.append("default")
	p.variants = vlist
	if d.has("layer"):
		p.layer = LayerData.from_dict(d["layer"], view_dir)
	return p


func clone_deep() -> PartData:
	var p := PartData.new(name)
	p.parent = parent
	p.pivot = pivot
	p.variants = variants.duplicate()
	p.layer = layer.clone_deep()
	p.layer.name = name
	return p
