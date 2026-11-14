extends Node
## "Rigs" autoload: renders every character instance of the current scene
## into its own transparent SubViewport, posed for the current frame. The
## canvas and the 3D stage simply draw that texture, so characters are
## linked: editing the character asset updates every instance.
## Viewports render on demand (UPDATE_ONCE) only when something changed.

var _vps: Dictionary = {}  # layer id -> SubViewport
var _rigs: Dictionary = {}  # layer id -> CharacterRig
var _layers: Dictionary = {}  # layer id -> LayerData


func _ready() -> void:
	for sig: Signal in [App.project_opened, App.scene_switched, App.characters_changed]:
		sig.connect(rebuild)
	App.layers_changed.connect(_on_layers_changed)
	for sig: Signal in [App.frame_changed, App.pixels_changed, App.timeline_changed]:
		sig.connect(update_all)
	App.project_closed.connect(_clear)


func count() -> int:
	return _vps.size()


func _clear() -> void:
	for id in _vps.keys():
		var vp: Node = _vps[id]
		vp.queue_free()
	_vps.clear()
	_rigs.clear()
	_layers.clear()


func _on_layers_changed() -> void:
	var s := App.current_scene()
	if s == null:
		return
	var ids := {}
	for l in s.layers:
		if l.is_character():
			ids[l.id] = true
	var same := ids.size() == _vps.size()
	if same:
		for id in ids.keys():
			if not _vps.has(id):
				same = false
				break
	if same:
		update_all()
	else:
		rebuild()


func rebuild() -> void:
	_clear()
	if not App.has_project():
		return
	var s := App.current_scene()
	if s == null:
		return
	for l in s.layers:
		if not l.is_character():
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(App.project.width, App.project.height)
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var rig := CharacterRig.new()
		vp.add_child(rig)
		_vps[l.id] = vp
		_rigs[l.id] = rig
		_layers[l.id] = l
	update_all()


func texture_for(layer: LayerData) -> Texture2D:
	if not _vps.has(layer.id):
		return null
	var vp: SubViewport = _vps[layer.id]
	return vp.get_texture()


func update_all() -> void:
	if not App.has_project():
		return
	for id in _rigs.keys():
		update_layer(_layers[id], App.frame)


func update_layer(layer: LayerData, frame: int) -> void:
	if not _rigs.has(layer.id):
		return
	var rig: CharacterRig = _rigs[layer.id]
	var c := App.project.find_character(layer.character_id)
	var view := layer.view_at(frame)
	if c != null and c.parts(view).is_empty():
		view = "front"
	if rig.character != c or rig.view != view:
		rig.build(c, view)
	if c != null:
		rig.apply(layer.pose_at(frame, c.part_names()), layer.swaps_at(frame))
	var vp: SubViewport = _vps[layer.id]
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Forces a rebuild of rigs (pivots/parents/part list changed).
func refresh_structure() -> void:
	for id in _rigs.keys():
		var rig: CharacterRig = _rigs[id]
		rig.character = null
	update_all()
