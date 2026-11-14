class_name CharacterProvider
extends CanvasProvider
## Shows one view of a character on a CanvasView: every part is a layer, the
## selected part is editable, and each part shows its chosen drawing
## (variant). Draws joints and bones on top and handles pivot placement.

var character: CharacterData = null
var view: String = "front"
var part_index: int = 0
var preview_variants: Dictionary = {}  # part name -> variant index
var pivot_mode: bool = false
var show_bones: bool = true
var dim_others: bool = false


func parts() -> Array:
	return character.parts(view) if character != null else []


func part() -> PartData:
	var list := parts()
	if list.is_empty():
		return null
	part_index = clampi(part_index, 0, list.size() - 1)
	return list[part_index]


func variant_index_of(p: PartData) -> int:
	return clampi(int(preview_variants.get(p.name, 0)), 0, p.variants.size() - 1)


func layers() -> Array:
	var out := []
	for p in parts():
		out.append((p as PartData).layer)
	return out


func active_layer() -> LayerData:
	var p := part()
	return p.layer if p != null else null


func frame_for(layer: LayerData) -> int:
	for item in parts():
		var p: PartData = item
		if p.layer == layer:
			return variant_index_of(p)
	return 0


func create_cel(layer: LayerData, frame: int) -> CelData:
	return Ops.create_part_cel(layer, frame)


func inactive_opacity() -> float:
	return 0.3 if dim_others else 1.0


func draw_overlay(ci: CanvasItem, canvas: CanvasView) -> void:
	if character == null or not (show_bones or pivot_mode):
		return
	var active := part()
	var r := UI.px(4.5) / canvas.zoom
	for item in parts():
		var p: PartData = item
		var parent := character.find_part(view, p.parent)
		if parent != null:
			ci.draw_line(parent.pivot, p.pivot, Color(0.31, 0.82, 0.77, 0.75), maxf(UI.px(2.0) / canvas.zoom, 0.5))
	for item in parts():
		var p: PartData = item
		var is_active := p == active
		ci.draw_circle(p.pivot, r * (1.5 if is_active else 1.0), Color(0, 0, 0, 0.6))
		ci.draw_circle(p.pivot, r * (1.2 if is_active else 0.8), Palette.ACCENT if is_active else Palette.DEPTH)
	if pivot_mode and active != null:
		var cross := UI.px(14) / canvas.zoom
		ci.draw_line(active.pivot - Vector2(cross, 0), active.pivot + Vector2(cross, 0), Palette.ACCENT, -1.0)
		ci.draw_line(active.pivot - Vector2(0, cross), active.pivot + Vector2(0, cross), Palette.ACCENT, -1.0)


func press(pos: Vector2, _canvas: CanvasView) -> bool:
	if pivot_mode:
		var p := part()
		if p != null:
			Ops.set_char_prop(p, "pivot", pos.round(), "Move joint (%s)" % p.name)
		return true
	return false


func select_part(i: int) -> void:
	part_index = i
	context_changed.emit()
	changed.emit()


func set_view(v: String) -> void:
	view = v
	part_index = 0
	context_changed.emit()
	changed.emit()


func set_variant(idx: int) -> void:
	var p := part()
	if p == null:
		return
	preview_variants[p.name] = idx
	context_changed.emit()
	changed.emit()


## Variant names currently previewed for swappable parts (used for expressions).
func preview_swaps() -> Dictionary:
	var out := {}
	for item in parts():
		var p: PartData = item
		if p.has_variants():
			out[p.name] = p.variants[variant_index_of(p)]
	return out
