extends Node
## "Ops" autoload: every undoable edit to project structure goes through here.
## Each operation snapshots what it changes (a layer's key dictionary, a
## scene's layer array, ...) so undo/redo is a cheap reference swap.

var ur: UndoRedo:
	get:
		return History.ur


# ================================================================ generic properties

## Sets obj.prop = value with undo. Consecutive edits of the same property
## (e.g. dragging a slider) merge into one undo step.
func set_prop(obj: Object, prop: String, value: Variant, label: String, kind: String) -> void:
	var old: Variant = obj.get(prop)
	if typeof(old) == typeof(value) and old == value:
		return
	ur.create_action(label, UndoRedo.MERGE_ENDS)
	ur.add_do_method(_apply_prop.bind(obj, prop, value, kind))
	ur.add_undo_method(_apply_prop.bind(obj, prop, old, kind))
	ur.commit_action()


func _apply_prop(obj: Object, prop: String, value: Variant, kind: String) -> void:
	obj.set(prop, value)
	App.notify(kind)


func set_layer_prop(layer: LayerData, prop: String, value: Variant) -> void:
	var kind := "layers"
	set_prop(layer, prop, value, "Change %s (%s)" % [prop.replace("_", " "), layer.name], kind)


# ================================================================ layer motion (animated placement)

## Sets placement values for a layer. Without motion keys this edits the
## static placement; once the layer has keys it auto-keys the current frame.
func set_layer_motion(layer: LayerData, values: Dictionary, label: String = "") -> void:
	if values.is_empty():
		return
	var field_names := ", ".join(PackedStringArray(values.keys().map(func(k: Variant) -> String: return str(k))))
	if label == "":
		label = "Change %s (%s)" % [field_names, layer.name]
	if layer.motion_keys.is_empty():
		var old := {}
		var current := layer.static_motion()
		for k in values.keys():
			old[k] = current[k]
		ur.create_action(label, UndoRedo.MERGE_ENDS)
		ur.add_do_method(_apply_static.bind(layer, values.duplicate()))
		ur.add_undo_method(_apply_static.bind(layer, old))
		ur.commit_action()
	else:
		var f: int = App.frame
		var after := layer.motion_keys.duplicate(true)
		var key: Dictionary = layer.motion_at(f)
		if after.has(f):
			var existing: Dictionary = after[f]
			key = existing.duplicate()
		for k in values.keys():
			key[k] = values[k]
		after[f] = key
		_motion_action(label, layer, after, true)


func _apply_static(layer: LayerData, values: Dictionary) -> void:
	layer.apply_static(values)
	App.notify_layers()


func _set_motion(layer: LayerData, keys: Dictionary, static_values: Dictionary) -> void:
	layer.motion_keys = keys.duplicate(true)
	if not static_values.is_empty():
		layer.apply_static(static_values)
	App.notify_layers()
	App.timeline_changed.emit()


func _motion_action(label: String, layer: LayerData, after: Dictionary, merge: bool = false, static_after: Dictionary = {}) -> void:
	ur.create_action(label, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE)
	ur.add_do_method(_set_motion.bind(layer, after, static_after))
	ur.add_undo_method(_set_motion.bind(layer, layer.motion_keys.duplicate(true), layer.static_motion() if not static_after.is_empty() else {}))
	ur.commit_action()


func add_motion_key(layer: LayerData) -> void:
	if layer == null:
		return
	var after := layer.motion_keys.duplicate(true)
	after[App.frame] = layer.motion_at(App.frame)
	_motion_action("Add motion key", layer, after)
	App.status("Motion key on frame %d — now changes to this layer animate" % (App.frame + 1))


func delete_motion_key(layer: LayerData) -> void:
	if layer == null or not layer.motion_keys.has(App.frame):
		App.status("No motion key on this frame")
		return
	var after := layer.motion_keys.duplicate(true)
	after.erase(App.frame)
	# Removing the last key: keep the layer where it currently is.
	var bake := layer.motion_at(App.frame) if after.is_empty() else {}
	_motion_action("Delete motion key", layer, after, false, bake)


func clear_motion(layer: LayerData) -> void:
	if layer == null or layer.motion_keys.is_empty():
		return
	_motion_action("Remove layer animation", layer, {}, false, layer.motion_at(App.frame))


## Ready-made layer moves starting at the current frame.
func apply_motion_preset(layer: LayerData, preset: String, duration: int = 12) -> void:
	if layer == null:
		return
	var s := App.current_scene()
	var a: int = App.frame
	var b := mini(a + duration, s.frame_count - 1)
	if b <= a:
		App.status("Not enough frames after the playhead for this move")
		return
	var base := layer.motion_at(a)
	var k0 := base.duplicate()
	var k1 := base.duplicate()
	var w: float = App.project.width
	var label := "Motion preset"
	match preset:
		"fade_in":
			k0["opacity"] = 0.0
			k1["opacity"] = 1.0
		"fade_out":
			k0["opacity"] = float(base["opacity"])
			k1["opacity"] = 0.0
		"slide_left":
			k0["x"] = float(base["x"]) - w * 0.6
			k0["ease"] = "ease_out"
		"slide_right":
			k0["x"] = float(base["x"]) + w * 0.6
			k0["ease"] = "ease_out"
		"grow":
			k0["scale"] = 0.0
			k0["ease"] = "ease_out"
		"bob":
			# A looping float up and down over the duration.
			var after := layer.motion_keys.duplicate(true)
			var mid := a + (b - a) / 2
			var up := base.duplicate()
			up["y"] = float(base["y"]) - 30.0
			after[a] = base.duplicate()
			after[mid] = up
			after[b] = base.duplicate()
			_motion_action(label, layer, after)
			return
		_:
			return
	var keys := layer.motion_keys.duplicate(true)
	keys[a] = k0
	keys[b] = k1
	_motion_action(label, layer, keys)
	App.status("Applied “%s” over frames %d–%d" % [preset.replace("_", " "), a + 1, b + 1])


# ================================================================ layers

func _set_layers(scene: SceneData, arr: Array, select: int) -> void:
	scene.layers.assign(arr)
	App.layer_index = clampi(select, 0, maxi(0, scene.layers.size() - 1))
	App.notify_layers()
	App.timeline_changed.emit()
	App.layer_selected.emit()


func _layers_action(label: String, scene: SceneData, after: Array, select_after: int) -> void:
	var before := scene.layers.duplicate()
	ur.create_action(label)
	ur.add_do_method(_set_layers.bind(scene, after, select_after))
	ur.add_undo_method(_set_layers.bind(scene, before, App.layer_index))
	ur.commit_action()


func add_layer(layer_name: String, role: String = "drawing") -> LayerData:
	var s := App.current_scene()
	if s == null:
		return null
	var l := LayerData.new(layer_name, role)
	var after := s.layers.duplicate()
	var idx := clampi(App.layer_index + 1, 0, after.size())
	if s.layers.is_empty():
		idx = 0
	after.insert(idx, l)
	_layers_action("Add layer", s, after, idx)
	return l


## Imports a picture as a new layer (held for the whole scene). Reference
## layers are locked guides that never render. Returns "" or an error.
func import_image(path: String, as_reference: bool) -> String:
	var s := App.current_scene()
	if s == null:
		return "Open a project first."
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return "Could not read this image:\n" + path
	img.convert(Image.FORMAT_RGBA8)
	var w: int = App.project.width
	var h: int = App.project.height
	var fit := minf(1.0, minf(float(w) / img.get_width(), float(h) / img.get_height()))
	if fit < 1.0:
		img.resize(maxi(1, int(img.get_width() * fit)), maxi(1, int(img.get_height() * fit)), Image.INTERPOLATE_LANCZOS)
	var cel := CelData.create_blank(w, h)
	var pos := Vector2i((w - img.get_width()) / 2, (h - img.get_height()) / 2)
	cel.image.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), pos)
	var l := LayerData.new(path.get_file().get_basename(), "reference" if as_reference else "drawing")
	l.locked = as_reference
	l.cels[0] = cel
	var after := s.layers.duplicate()
	var idx := clampi(App.layer_index + 1, 0, after.size())
	after.insert(idx, l)
	_layers_action("Import image", s, after, idx)
	App.notify_timeline()
	App.status("Imported “%s”%s" % [l.name, " as a locked reference (not rendered)" if as_reference else ""])
	return ""


func delete_layer(index: int) -> void:
	var s := App.current_scene()
	if s == null or index < 0 or index >= s.layers.size():
		return
	var victim: LayerData = s.layers[index]
	# Keep pixels in memory so undo works even after the PNGs are cleaned up.
	for k in victim.cels.keys():
		var cel: CelData = victim.cels[k]
		cel.get_image()
	var after := s.layers.duplicate()
	after.remove_at(index)
	_layers_action("Delete layer", s, after, index - 1)


func duplicate_layer(index: int) -> void:
	var s := App.current_scene()
	if s == null or index < 0 or index >= s.layers.size():
		return
	var src: LayerData = s.layers[index]
	var copy := src.clone_deep()
	copy.name = src.name + " copy"
	var after := s.layers.duplicate()
	after.insert(index + 1, copy)
	_layers_action("Duplicate layer", s, after, index + 1)


func move_layer(index: int, delta: int) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var to := index + delta
	if index < 0 or index >= s.layers.size() or to < 0 or to >= s.layers.size():
		return
	var after := s.layers.duplicate()
	var l: LayerData = after[index]
	after.remove_at(index)
	after.insert(to, l)
	_layers_action("Reorder layers", s, after, to)


# ================================================================ drawings (cels) on the timeline

func _set_cels(layer: LayerData, cels: Dictionary, scene: SceneData, length: int) -> void:
	layer.cels = cels.duplicate()
	scene.frame_count = length
	App.notify_timeline()
	App.notify_pixels()


func _cels_action(label: String, layer: LayerData, after: Dictionary, new_length: int = -1) -> void:
	var s := App.current_scene()
	var length := s.frame_count if new_length < 0 else new_length
	ur.create_action(label)
	ur.add_do_method(_set_cels.bind(layer, after, s, length))
	ur.add_undo_method(_set_cels.bind(layer, layer.cels.duplicate(), s, s.frame_count))
	ur.commit_action()


## Creates a new key at `frame` (blank, or with the given cel).
func create_key(layer: LayerData, frame: int, cel: CelData = null, label: String = "New drawing") -> CelData:
	if cel == null:
		cel = CelData.create_blank(App.project.width, App.project.height)
	var after := layer.cels.duplicate()
	after[frame] = cel
	var s := App.current_scene()
	_cels_action(label, layer, after, maxi(s.frame_count, frame + 1))
	return cel


## Stop motion: puts photos on `layer` starting at `frame`, each held for
## `hold` frames, as one undo step. Images must already be canvas-sized.
func add_photos(layer: LayerData, frame: int, images: Array, hold: int, label: String = "Capture frame") -> void:
	var after := layer.cels.duplicate()
	var f := frame
	for item in images:
		var img: Image = item
		var cel := CelData.create_blank(App.project.width, App.project.height)
		cel.image = img
		cel.mark_changed()
		after[f] = cel
		f += maxi(1, hold)
	var s := App.current_scene()
	_cels_action(label, layer, after, maxi(s.frame_count, f))


## Stop motion: removes the photo at `frame`; the scene ends after the new
## last photo if this was the end.
func remove_photo(layer: LayerData, frame: int, hold: int) -> void:
	if not layer.cels.has(frame):
		return
	var after := layer.cels.duplicate()
	after.erase(frame)
	var s := App.current_scene()
	var length := s.frame_count
	var last := -1
	for k in after.keys():
		last = maxi(last, int(k))
	if frame > last:
		length = maxi(1, last + maxi(1, hold)) if last >= 0 else 1
	_cels_action("Delete frame", layer, after, length)


## Character instances are posed, not drawn.
func _drawable(layer: LayerData) -> bool:
	if layer != null and layer.is_character():
		App.status("“%s” is a character — pose it in the Pose panel; edit its art in Characters" % layer.name)
		return false
	return layer != null


## Where a new drawing goes: the current frame if it has no key, else the next frame.
func _target_frame(layer: LayerData) -> int:
	var f: int = App.frame
	if layer.cels.has(f):
		f += 1
	return f


func new_drawing(layer: LayerData = null, frame: int = -1) -> void:
	if layer == null:
		layer = App.current_layer()
	if layer == null:
		App.status("Add a layer first")
		return
	if not _drawable(layer):
		return
	var f := frame if frame >= 0 else _target_frame(layer)
	if layer.cels.has(f):
		App.status("Frame %d already has a drawing" % (f + 1))
		return
	create_key(layer, f)
	App.set_frame(f)
	App.status("New drawing at frame %d" % (f + 1))


func duplicate_drawing() -> void:
	var layer := App.current_layer()
	if not _drawable(layer):
		return
	var src := layer.cel_at(App.frame)
	if src == null:
		App.status("Nothing to duplicate on this frame")
		return
	var f := _target_frame(layer)
	if layer.cels.has(f):
		App.status("Frame %d already has a drawing" % (f + 1))
		return
	create_key(layer, f, src.clone(), "Duplicate drawing")
	App.set_frame(f)
	App.status("Duplicated drawing to frame %d" % (f + 1))


func delete_drawing() -> void:
	var layer := App.current_layer()
	if not _drawable(layer):
		return
	var f: int = App.frame
	if not layer.cels.has(f):
		var k := layer.key_at_or_before(f)
		if k >= 0:
			App.status("This frame holds the drawing from frame %d — select that frame to delete it" % (k + 1))
		else:
			App.status("No drawing on this frame")
		return
	var cel: CelData = layer.cels[f]
	cel.get_image()  # keep pixels for undo
	var after := layer.cels.duplicate()
	after.erase(f)
	_cels_action("Delete drawing", layer, after)


## Holds the current drawing one frame longer (shifts later keys right).
func insert_frame() -> void:
	var layer := App.current_layer()
	if not _drawable(layer):
		return
	var f: int = App.frame
	var after := {}
	for k in layer.cels.keys():
		var ki: int = k
		after[ki + 1 if ki > f else ki] = layer.cels[k]
	var s := App.current_scene()
	var last := -1
	for k in after.keys():
		last = maxi(last, int(k))
	# If the current drawing is held to the end of the scene, the scene grows too.
	var reaches_end := layer.exposure_end(layer.key_at_or_before(f), s.frame_count) >= s.frame_count
	var length := s.frame_count + 1 if reaches_end else maxi(s.frame_count, last + 1)
	_cels_action("Insert frame", layer, after, length)


## Shortens the current exposure by one frame (shifts later keys left).
func remove_frame() -> void:
	var layer := App.current_layer()
	if not _drawable(layer):
		return
	var f: int = App.frame
	if layer.cels.has(f + 1) and layer.cels.has(f):
		App.status("This drawing is already one frame long — use Delete drawing instead")
		return
	var after := {}
	for k in layer.cels.keys():
		var ki: int = k
		after[ki - 1 if ki > f else ki] = layer.cels[k]
	_cels_action("Remove frame", layer, after)


func move_key(layer: LayerData, from: int, to: int) -> void:
	if from == to or not layer.cels.has(from):
		return
	if layer.cels.has(to):
		App.status("Frame %d already has a drawing" % (to + 1))
		return
	var after := layer.cels.duplicate()
	var cel: Variant = after[from]
	after.erase(from)
	after[to] = cel
	var s := App.current_scene()
	_cels_action("Move drawing", layer, after, maxi(s.frame_count, to + 1))
	App.set_frame(to)


# ================================================================ 3D stage (floor, light, set pieces)

func _set_stage(scene: SceneData, st: Dictionary) -> void:
	scene.stage = st.duplicate(true)
	App.notify_stage()


## Sets one stage value with undo. Slider drags merge into one step.
func set_stage_value(key: String, value: Variant, label: String = "") -> void:
	var s := App.current_scene()
	if s == null:
		return
	var after := s.stage.duplicate(true)
	after[key] = value
	ur.create_action(label if label != "" else "Stage %s" % key.replace("_", " "), UndoRedo.MERGE_ENDS)
	ur.add_do_method(_set_stage.bind(s, after))
	ur.add_undo_method(_set_stage.bind(s, s.stage.duplicate(true)))
	ur.commit_action()


## Records an edit that was already applied live (e.g. a gizmo drag).
func commit_stage_edit(scene: SceneData, before: Dictionary, label: String) -> void:
	var after := scene.stage.duplicate(true)
	if after == before:
		return
	ur.create_action(label)
	ur.add_do_method(_set_stage.bind(scene, after))
	ur.add_undo_method(_set_stage.bind(scene, before.duplicate(true)))
	ur.commit_action(false)
	App.notify_stage()


## Adds a blockout shape. `role` says what it becomes in the low-poly set.
func add_prop(type: String, role: String = "auto") -> String:
	var s := App.current_scene()
	if s == null:
		return ""
	var current: Array = s.stage_value("props")
	var props: Array = current.duplicate(true)
	var p := LowPolyBuilder.make_prop(type, role, props.size() + 1)
	props.append(p)
	set_stage_value("props", props, "Add set piece")
	return str(p["id"])


## Copies a set piece (and anything drawn on it) next to the original.
func duplicate_prop(id: String) -> String:
	var s := App.current_scene()
	if s == null:
		return ""
	var current: Array = s.stage_value("props")
	var props: Array = current.duplicate(true)
	var copy := {}
	for item in props:
		var p: Dictionary = item
		if str(p.get("id", "")) == id:
			copy = p.duplicate(true)
	if copy.is_empty():
		return ""
	copy["id"] = Ids.make()
	copy["name"] = str(copy.get("name", "Piece")) + " copy"
	var pos: Array = copy.get("pos", [0.0, 0.0, 0.0])
	var size: Array = copy.get("size", [1.0, 1.0, 1.0])
	copy["pos"] = [float(pos[0]) + float(size[0]) + 0.5, float(pos[1]), float(pos[2])]
	props.append(copy)
	if s.prop_paint.has(id):
		var cel: CelData = s.prop_paint[id]
		s.prop_paint[str(copy["id"])] = cel.clone()
	set_stage_value("props", props, "Duplicate set piece")
	return str(copy["id"])


func _set_prop_paint(scene: SceneData, id: String, img: Image) -> void:
	var cel: CelData = scene.prop_paint.get(id)
	if cel == null:
		cel = CelData.create_blank(img.get_width(), img.get_height())
		scene.prop_paint[id] = cel
	cel.image = img.duplicate() as Image
	cel.mark_changed()
	App.notify_stage()


## Records a finished stroke on a set piece (already applied live).
func commit_prop_paint(scene: SceneData, id: String, before: Image, after: Image, label: String) -> void:
	ur.create_action(label)
	ur.add_do_method(_set_prop_paint.bind(scene, id, after))
	ur.add_undo_method(_set_prop_paint.bind(scene, id, before))
	ur.commit_action(false)
	App.mark_modified()


## Wipes everything drawn on a set piece.
func clear_prop_paint(id: String) -> void:
	var s := App.current_scene()
	if s == null or not s.prop_paint.has(id):
		return
	var cel: CelData = s.prop_paint[id]
	var before := cel.get_image().duplicate() as Image
	var blank := Image.create_empty(before.get_width(), before.get_height(), false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	ur.create_action("Clear drawing on shape")
	ur.add_do_method(_set_prop_paint.bind(s, id, blank))
	ur.add_undo_method(_set_prop_paint.bind(s, id, before))
	ur.commit_action()


## Replaces the set pieces with a ready-made rough layout.
func apply_set_template(template: String) -> void:
	var s := App.current_scene()
	if s == null:
		return
	set_stage_value("props", LowPolyBuilder.template(template), "Quick set: %s" % template)


func set_prop_field(id: String, field: String, value: Variant) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var current: Array = s.stage_value("props")
	var props: Array = current.duplicate(true)
	for item in props:
		var p: Dictionary = item
		if str(p.get("id", "")) == id:
			p[field] = value
	set_stage_value("props", props, "Edit set piece %s" % field)


func delete_prop(id: String) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var props: Array = []
	for item in s.stage_value("props"):
		var p: Dictionary = item
		if str(p.get("id", "")) != id:
			props.append(p.duplicate(true))
	ur.create_action("Delete set piece")
	var after := s.stage.duplicate(true)
	after["props"] = props
	ur.add_do_method(_set_stage.bind(s, after))
	ur.add_undo_method(_set_stage.bind(s, s.stage.duplicate(true)))
	ur.commit_action()


# ================================================================ camera keys

func _set_camera_keys(scene: SceneData, keys: Dictionary) -> void:
	scene.camera_keys = keys.duplicate(true)
	App.notify_camera()
	App.timeline_changed.emit()


func _camera_action(label: String, scene: SceneData, after: Dictionary, merge: bool = false) -> void:
	ur.create_action(label, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE)
	ur.add_do_method(_set_camera_keys.bind(scene, after))
	ur.add_undo_method(_set_camera_keys.bind(scene, scene.camera_keys.duplicate(true)))
	ur.commit_action()


## Edits one camera field at the current frame, creating a key if needed (auto-key).
func set_camera_field(field: String, value: Variant) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var f: int = App.frame
	var after := s.camera_keys.duplicate(true)
	var key: Dictionary = after[f] if after.has(f) else s.camera_at(f)
	key = key.duplicate()
	key[field] = value
	after[f] = key
	_camera_action("Camera %s" % field, s, after, true)


func add_camera_key() -> void:
	var s := App.current_scene()
	if s == null:
		return
	var after := s.camera_keys.duplicate(true)
	after[App.frame] = s.camera_at(App.frame)
	_camera_action("Add camera key", s, after)
	App.status("Camera key added at frame %d" % (App.frame + 1))


func delete_camera_key() -> void:
	var s := App.current_scene()
	if s == null or not s.camera_keys.has(App.frame):
		App.status("No camera key on this frame")
		return
	var after := s.camera_keys.duplicate(true)
	after.erase(App.frame)
	_camera_action("Delete camera key", s, after)


func clear_camera() -> void:
	var s := App.current_scene()
	if s == null:
		return
	_camera_action("Reset camera", s, {})


## Ready-made camera moves for beginners. They replace existing camera keys.
func apply_camera_preset(preset: String) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var last := maxi(1, s.frame_count - 1)
	var a := SceneData.CAMERA_DEFAULT.duplicate()
	var b := SceneData.CAMERA_DEFAULT.duplicate()
	var w: float = App.project.width
	match preset:
		"push_in":
			b["dolly"] = 6.0
		"pull_out":
			a["dolly"] = 6.0
		"pan_right":
			a["x"] = -w * 0.15
			b["x"] = w * 0.15
		"pan_left":
			a["x"] = w * 0.15
			b["x"] = -w * 0.15
		"truck":
			a["x"] = -w * 0.2
			b["x"] = w * 0.2
			a["dolly"] = 2.0
			b["dolly"] = 2.0
			a["ease"] = "linear"
		"crane_up":
			a["y"] = 250.0
			b["y"] = -250.0
		"zoom_in":
			b["zoom"] = 1.6
		"shake":
			a["shake"] = 14.0
			b["shake"] = 0.0
			a["ease"] = "ease_out"
		_:
			return
	_camera_action("Camera preset", s, {0: a, last: b})
	App.status("Camera preset applied — press Enter to preview")


# ================================================================ scenes

func _set_scenes(arr: Array, select: int) -> void:
	App.project.scenes.assign(arr)
	App.mark_modified()
	App.set_scene(select, true)


func _scenes_action(label: String, after: Array, select_after: int) -> void:
	var before := App.project.scenes.duplicate()
	ur.create_action(label)
	ur.add_do_method(_set_scenes.bind(after, select_after))
	ur.add_undo_method(_set_scenes.bind(before, App.scene_index))
	ur.commit_action()


func add_scene() -> void:
	if not App.has_project():
		return
	var s := SceneData.create_for_mode("Scene %d" % (App.project.scenes.size() + 1), App.project.mode)
	var after := App.project.scenes.duplicate()
	var idx: int = App.scene_index + 1
	after.insert(idx, s)
	_scenes_action("Add scene", after, idx)


func duplicate_scene(index: int) -> void:
	if not App.has_project() or index < 0 or index >= App.project.scenes.size():
		return
	var src: SceneData = App.project.scenes[index]
	var copy := src.clone_deep()
	var after := App.project.scenes.duplicate()
	after.insert(index + 1, copy)
	_scenes_action("Duplicate scene", after, index + 1)


func delete_scene(index: int) -> void:
	if not App.has_project() or App.project.scenes.size() <= 1:
		App.status("A project needs at least one scene")
		return
	var victim: SceneData = App.project.scenes[index]
	for l in victim.layers:
		for k in l.cels.keys():
			var cel: CelData = l.cels[k]
			cel.get_image()
	var after := App.project.scenes.duplicate()
	after.remove_at(index)
	_scenes_action("Delete scene", after, maxi(0, index - 1))


func move_scene(index: int, delta: int) -> void:
	var to := index + delta
	var n: int = App.project.scenes.size()
	if index < 0 or index >= n or to < 0 or to >= n:
		return
	var after := App.project.scenes.duplicate()
	var s: SceneData = after[index]
	after.remove_at(index)
	after.insert(to, s)
	_scenes_action("Reorder scenes", after, to)


# ================================================================ animation clips (reusable cycles)

func _set_clips(arr: Array) -> void:
	App.project.clips.assign(arr)
	App.mark_modified()
	App.clips_changed.emit()


func _clips_action(label: String, after: Array) -> void:
	var before := App.project.clips.duplicate()
	ur.create_action(label)
	ur.add_do_method(_set_clips.bind(after))
	ur.add_undo_method(_set_clips.bind(before))
	ur.commit_action()


## Saves frames [start, end] of `layer` (drawings, timing and motion) as a clip.
func save_clip(layer: LayerData, start: int, end: int, clip_name: String) -> ClipData:
	if layer == null or end < start:
		return null
	var clip := ClipData.new(clip_name if clip_name.strip_edges() != "" else "Clip %d" % (App.project.clips.size() + 1))
	clip.length = end - start + 1
	# A drawing held into the range from before it becomes the clip's first drawing.
	var held := layer.key_at_or_before(start)
	if held >= 0 and held < start:
		var first_cel: CelData = layer.cels[held]
		clip.cels[0] = first_cel.clone()
	for k in layer.cels.keys():
		var ki: int = k
		if ki >= start and ki <= end:
			var cel: CelData = layer.cels[k]
			clip.cels[ki - start] = cel.clone()
	if clip.cels.is_empty():
		App.status("There are no drawings in frames %d–%d of this layer" % [start + 1, end + 1])
		return null
	clip.motion_keys = KeyTrack.slice(layer.motion_keys, start, end)
	var after := App.project.clips.duplicate()
	after.append(clip)
	_clips_action("Save clip", after)
	App.status("Saved clip “%s” (%d drawings, %d frames)" % [clip.name, clip.drawing_count(), clip.length])
	return clip


func delete_clip(clip: ClipData) -> void:
	for k in clip.cels.keys():
		var cel: CelData = clip.cels[k]
		cel.get_image()  # keep pixels for undo
	var after := App.project.clips.duplicate()
	after.erase(clip)
	_clips_action("Delete clip", after)


func rename_clip(clip: ClipData, new_name: String) -> void:
	set_prop(clip, "name", new_name, "Rename clip", "clips")


## Places `repeats` copies of a clip on `layer` starting at frame `at`.
## Drawings already in that range are replaced; the drawing that was showing
## after the range keeps showing afterwards.
func insert_clip(clip: ClipData, layer: LayerData, at: int, repeats: int = 1) -> void:
	if clip == null or not _drawable(layer):
		return
	if layer.locked:
		App.status("“%s” is locked" % layer.name)
		return
	repeats = maxi(1, repeats)
	var total := clip.length * repeats
	var end := at + total  # first frame after the inserted range
	var s := App.current_scene()
	var after := {}
	for k in layer.cels.keys():
		var ki: int = k
		if ki < at or ki >= end:
			after[ki] = layer.cels[k]
	var resume := layer.cel_at(end)
	if resume != null and not layer.cels.has(end) and end < s.frame_count:
		after[end] = resume.clone()
	for r in repeats:
		for rel in clip.cels.keys():
			var src: CelData = clip.cels[rel]
			after[at + r * clip.length + int(rel)] = src.clone()
	var length := maxi(s.frame_count, end)
	var motion_after := layer.motion_keys.duplicate(true)
	if not clip.motion_keys.is_empty():
		for k in motion_after.keys():
			var ki: int = k
			if ki >= at and ki < end:
				motion_after.erase(k)
		for r in repeats:
			var shifted := KeyTrack.slice(clip.motion_keys, 0, clip.length - 1, at + r * clip.length)
			for k in shifted.keys():
				motion_after[k] = shifted[k]
	ur.create_action("Insert clip “%s”" % clip.name)
	ur.add_do_method(_set_cels.bind(layer, after, s, length))
	ur.add_do_method(_set_motion.bind(layer, motion_after, {}))
	ur.add_undo_method(_set_cels.bind(layer, layer.cels.duplicate(), s, s.frame_count))
	ur.add_undo_method(_set_motion.bind(layer, layer.motion_keys.duplicate(true), {}))
	ur.commit_action()
	App.status("Inserted “%s” ×%d at frame %d" % [clip.name, repeats, at + 1])


## Timing builder: creates `count` blank drawings every `spacing` frames
## from the playhead ("on 2s" = spacing 2). A quick start for cycles.
func add_blank_drawings(layer: LayerData, count: int, spacing: int) -> void:
	if layer == null:
		App.status("Add a layer first")
		return
	var at: int = App.frame
	var after := layer.cels.duplicate()
	var added := 0
	for i in count:
		var f := at + i * spacing
		if after.has(f):
			continue
		after[f] = CelData.create_blank(App.project.width, App.project.height)
		added += 1
	var s := App.current_scene()
	var length := maxi(s.frame_count, at + count * spacing)
	_cels_action("Add %d blank drawings" % added, layer, after, length)
	App.status("Added %d blank drawings on %ds — draw each one with onion skin on" % [added, spacing])


# ================================================================ markers

func _set_markers(scene: SceneData, markers: Dictionary) -> void:
	scene.markers = markers.duplicate()
	App.mark_modified()
	App.timeline_changed.emit()
	App.markers_changed.emit()


func _markers_action(label: String, scene: SceneData, after: Dictionary) -> void:
	ur.create_action(label)
	ur.add_do_method(_set_markers.bind(scene, after))
	ur.add_undo_method(_set_markers.bind(scene, scene.markers.duplicate()))
	ur.commit_action()


func toggle_marker(frame: int = -1) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var f := frame if frame >= 0 else App.frame
	var after := s.markers.duplicate()
	if after.has(f):
		after.erase(f)
		_markers_action("Remove marker", s, after)
	else:
		after[f] = "Marker %d" % (after.size() + 1)
		_markers_action("Add marker", s, after)


func rename_marker(frame: int, label: String) -> void:
	var s := App.current_scene()
	if s == null or not s.markers.has(frame) or str(s.markers[frame]) == label:
		return
	var after := s.markers.duplicate()
	after[frame] = label
	_markers_action("Rename marker", s, after)


func delete_marker(frame: int) -> void:
	var s := App.current_scene()
	if s == null or not s.markers.has(frame):
		return
	var after := s.markers.duplicate()
	after.erase(frame)
	_markers_action("Remove marker", s, after)


# ================================================================ character library

func _set_characters(arr: Array) -> void:
	App.project.characters.assign(arr)
	App.notify("characters")


func _characters_action(label: String, after: Array) -> void:
	var before := App.project.characters.duplicate()
	ur.create_action(label)
	ur.add_do_method(_set_characters.bind(after))
	ur.add_undo_method(_set_characters.bind(before))
	ur.commit_action()


func add_character(use_template: bool) -> CharacterData:
	if not App.has_project():
		return null
	var n := "Character %d" % (App.project.characters.size() + 1)
	var c: CharacterData
	if use_template:
		c = CharacterData.create_template(n, App.project.width, App.project.height)
	else:
		c = CharacterData.new(n)
		var body := PartData.new("Body")
		body.pivot = Vector2(App.project.width * 0.5, App.project.height * 0.55)
		var front: Array = c.views["front"]
		front.append(body)
	var after := App.project.characters.duplicate()
	after.append(c)
	_characters_action("New character", after)
	return c


func duplicate_character(c: CharacterData) -> CharacterData:
	var copy := c.clone_deep()
	var after := App.project.characters.duplicate()
	after.insert(after.find(c) + 1, copy)
	_characters_action("Duplicate character", after)
	return copy


func delete_character(c: CharacterData) -> void:
	for v in c.views.keys():
		for p in c.views[v]:
			var part: PartData = p
			for k in part.layer.cels.keys():
				var cel: CelData = part.layer.cels[k]
				cel.get_image()
	var after := App.project.characters.duplicate()
	after.erase(c)
	_characters_action("Delete character", after)


func set_char_prop(obj: Object, prop: String, value: Variant, label: String) -> void:
	set_prop(obj, prop, value, label, "characters")


# ---------------------------------------------------------------- parts

func _set_view_parts(c: CharacterData, view: String, arr: Array) -> void:
	c.views[view] = arr.duplicate()
	App.notify("characters")


func _parts_action(label: String, c: CharacterData, view: String, after: Array) -> void:
	var before: Array = c.parts(view).duplicate()
	ur.create_action(label)
	ur.add_do_method(_set_view_parts.bind(c, view, after))
	ur.add_undo_method(_set_view_parts.bind(c, view, before))
	ur.commit_action()


func add_part(c: CharacterData, view: String, part_name: String, index: int, parent: String = "") -> PartData:
	var part := PartData.new(part_name)
	part.parent = parent
	part.pivot = Vector2(App.project.width * 0.5, App.project.height * 0.5)
	var after: Array = c.parts(view).duplicate()
	after.insert(clampi(index, 0, after.size()), part)
	_parts_action("Add part", c, view, after)
	return part


func delete_part(c: CharacterData, view: String, index: int) -> void:
	var list := c.parts(view)
	if index < 0 or index >= list.size():
		return
	var part: PartData = list[index]
	for k in part.layer.cels.keys():
		var cel: CelData = part.layer.cels[k]
		cel.get_image()
	var after: Array = list.duplicate()
	after.remove_at(index)
	_parts_action("Delete part", c, view, after)


func move_part(c: CharacterData, view: String, index: int, delta: int) -> void:
	var list := c.parts(view)
	var to := index + delta
	if index < 0 or index >= list.size() or to < 0 or to >= list.size():
		return
	var after: Array = list.duplicate()
	var p: Variant = after[index]
	after.remove_at(index)
	after.insert(to, p)
	_parts_action("Reorder parts", c, view, after)


## Copies the parts of one view into another as a starting point (art included).
func copy_view(c: CharacterData, from_view: String, to_view: String) -> void:
	var after := []
	for p in c.parts(from_view):
		after.append((p as PartData).clone_deep())
	_parts_action("Copy %s view to %s" % [from_view, to_view], c, to_view, after)


func _set_part_cels(layer: LayerData, cels: Dictionary) -> void:
	layer.cels = cels.duplicate()
	App.notify_pixels()
	App.characters_changed.emit()


func create_part_cel(layer: LayerData, index: int) -> CelData:
	var cel := CelData.create_blank(App.project.width, App.project.height)
	var after := layer.cels.duplicate()
	after[index] = cel
	ur.create_action("New part drawing")
	ur.add_do_method(_set_part_cels.bind(layer, after))
	ur.add_undo_method(_set_part_cels.bind(layer, layer.cels.duplicate()))
	ur.commit_action()
	return cel


func add_variant(part: PartData, variant_name: String) -> void:
	variant_name = variant_name.strip_edges()
	if variant_name == "" or part.variants.has(variant_name):
		App.status("Choose a new, unique drawing name")
		return
	var v := part.variants.duplicate()
	v.append(variant_name)
	set_char_prop(part, "variants", v, "Add drawing “%s” to %s" % [variant_name, part.name])


func _apply_variants(part: PartData, variants: PackedStringArray, cels: Dictionary) -> void:
	part.variants = variants.duplicate()
	part.layer.cels = cels.duplicate()
	App.notify("characters")
	App.notify_pixels()


func delete_variant(part: PartData, index: int) -> void:
	if part.variants.size() <= 1 or index < 0 or index >= part.variants.size():
		App.status("A part needs at least one drawing")
		return
	var v := part.variants.duplicate()
	v.remove_at(index)
	var cels := {}
	for k in part.layer.cels.keys():
		var ki: int = k
		var cel: CelData = part.layer.cels[k]
		if ki == index:
			cel.get_image()
			continue
		cels[ki - 1 if ki > index else ki] = cel
	ur.create_action("Delete drawing from %s" % part.name)
	ur.add_do_method(_apply_variants.bind(part, v, cels))
	ur.add_undo_method(_apply_variants.bind(part, part.variants.duplicate(), part.layer.cels.duplicate()))
	ur.commit_action()


func save_expression(c: CharacterData, expr_name: String, swaps: Dictionary) -> void:
	expr_name = expr_name.strip_edges()
	if expr_name == "" or swaps.is_empty():
		App.status("Name the expression and choose drawings for the swappable parts first")
		return
	var after := c.expressions.duplicate(true)
	after[expr_name] = swaps.duplicate()
	set_char_prop(c, "expressions", after, "Save expression “%s”" % expr_name)


func delete_expression(c: CharacterData, expr_name: String) -> void:
	var after := c.expressions.duplicate(true)
	after.erase(expr_name)
	set_char_prop(c, "expressions", after, "Delete expression")


# ================================================================ character instances & posing

func add_character_instance(c: CharacterData) -> LayerData:
	var s := App.current_scene()
	if s == null or c == null:
		return null
	var l := LayerData.new(c.name, "character")
	l.character_id = c.id
	var after := s.layers.duplicate()
	var idx := clampi(App.layer_index + 1, 0, after.size())
	after.insert(idx, l)
	_layers_action("Add character to scene", s, after, idx)
	App.status("“%s” added to “%s” — pose it in Animate, place it in Depth" % [c.name, s.name])
	return l


func _set_tracks(layer: LayerData, pose: Dictionary, view: Dictionary, swap: Dictionary) -> void:
	layer.pose_keys = pose.duplicate(true)
	layer.view_keys = view.duplicate(true)
	layer.swap_keys = swap.duplicate(true)
	App.notify_layers()
	App.timeline_changed.emit()


func _tracks_action(label: String, layer: LayerData, pose: Dictionary, view: Dictionary, swap: Dictionary, merge: bool = false) -> void:
	ur.create_action(label, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE)
	ur.add_do_method(_set_tracks.bind(layer, pose, view, swap))
	ur.add_undo_method(_set_tracks.bind(layer, layer.pose_keys.duplicate(true), layer.view_keys.duplicate(true), layer.swap_keys.duplicate(true)))
	ur.commit_action()


func _character_of(layer: LayerData) -> CharacterData:
	if layer == null or not layer.is_character() or not App.has_project():
		return null
	return App.project.find_character(layer.character_id)


func _pose_key_here(layer: LayerData, c: CharacterData) -> Dictionary:
	var f: int = App.frame
	if layer.pose_keys.has(f):
		var existing: Dictionary = layer.pose_keys[f]
		return existing.duplicate()
	return layer.pose_at(f, c.part_names())


func set_pose(layer: LayerData, part_name: String, degrees: float) -> void:
	var c := _character_of(layer)
	if c == null:
		return
	var pose := layer.pose_keys.duplicate(true)
	var key := _pose_key_here(layer, c)
	key[part_name] = degrees
	pose[App.frame] = key
	_tracks_action("Pose %s (%s)" % [part_name, layer.name], layer, pose, layer.view_keys, layer.swap_keys, true)


func set_pose_ease(layer: LayerData, ease_name: String) -> void:
	var c := _character_of(layer)
	if c == null:
		return
	var pose := layer.pose_keys.duplicate(true)
	var key := _pose_key_here(layer, c)
	key["ease"] = ease_name
	pose[App.frame] = key
	_tracks_action("Pose easing", layer, pose, layer.view_keys, layer.swap_keys)


func add_pose_key(layer: LayerData) -> void:
	var c := _character_of(layer)
	if c == null:
		return
	var pose := layer.pose_keys.duplicate(true)
	pose[App.frame] = _pose_key_here(layer, c)
	_tracks_action("Add pose key", layer, pose, layer.view_keys, layer.swap_keys)


## Removes every pose/view/drawing key of this character on the current frame.
func delete_character_keys(layer: LayerData) -> void:
	var f: int = App.frame
	if layer == null or not (layer.pose_keys.has(f) or layer.view_keys.has(f) or layer.swap_keys.has(f)):
		App.status("No character keys on this frame")
		return
	var pose := layer.pose_keys.duplicate(true)
	var view := layer.view_keys.duplicate(true)
	var swap := layer.swap_keys.duplicate(true)
	pose.erase(f)
	view.erase(f)
	swap.erase(f)
	_tracks_action("Delete character keys", layer, pose, view, swap)


func reset_pose(layer: LayerData) -> void:
	var c := _character_of(layer)
	if c == null:
		return
	var pose := layer.pose_keys.duplicate(true)
	var key := {"ease": "smooth"}
	for n in c.part_names():
		key[n] = 0.0
	pose[App.frame] = key
	_tracks_action("Reset pose", layer, pose, layer.view_keys, layer.swap_keys)


func set_view_key(layer: LayerData, view_name: String) -> void:
	if _character_of(layer) == null:
		return
	var view := layer.view_keys.duplicate(true)
	view[App.frame] = view_name
	_tracks_action("Switch to %s view" % view_name, layer, layer.pose_keys, view, layer.swap_keys)


func set_swap(layer: LayerData, part_name: String, variant: String) -> void:
	if _character_of(layer) == null:
		return
	var swap := layer.swap_keys.duplicate(true)
	var d := {}
	if swap.has(App.frame):
		var existing: Dictionary = swap[App.frame]
		d = existing.duplicate()
	d[part_name] = variant
	swap[App.frame] = d
	_tracks_action("%s → %s" % [part_name, variant], layer, layer.pose_keys, layer.view_keys, swap)


func apply_expression(layer: LayerData, expr_name: String) -> void:
	var c := _character_of(layer)
	if c == null or not c.expressions.has(expr_name):
		return
	var e: Dictionary = c.expressions[expr_name]
	var swap := layer.swap_keys.duplicate(true)
	var d := {}
	if swap.has(App.frame):
		var existing: Dictionary = swap[App.frame]
		d = existing.duplicate()
	for part in e.keys():
		d[part] = e[part]
	swap[App.frame] = d
	_tracks_action("Expression “%s”" % expr_name, layer, layer.pose_keys, layer.view_keys, swap)


## Saves frames [start, end] of an instance's posing as a reusable action on its character.
func save_action(layer: LayerData, start: int, end: int, action_name: String) -> void:
	var c := _character_of(layer)
	if c == null or end < start:
		return
	var pose := KeyTrack.slice(layer.pose_keys, start, end)
	var view := KeyTrack.slice(layer.view_keys, start, end)
	var swap := KeyTrack.slice(layer.swap_keys, start, end)
	# Make sure the action starts from the state at `start`.
	if not pose.has(0) and not layer.pose_keys.is_empty():
		pose[0] = layer.pose_at(start, c.part_names())
	if not view.has(0) and not layer.view_keys.is_empty():
		view[0] = layer.view_at(start)
	if not swap.has(0) and not layer.swap_keys.is_empty():
		swap[0] = layer.swaps_at(start)
	if pose.is_empty() and view.is_empty() and swap.is_empty():
		App.status("No posing in frames %d–%d to save" % [start + 1, end + 1])
		return
	var action := {
		"name": action_name.strip_edges() if action_name.strip_edges() != "" else "Action %d" % (c.actions.size() + 1),
		"length": end - start + 1,
		"pose": LayerData._dict_track_to_list(pose),
		"view": LayerData._dict_track_to_list(view),
		"swap": LayerData._dict_track_to_list(swap),
	}
	var after := c.actions.duplicate(true)
	after.append(action)
	set_char_prop(c, "actions", after, "Save action “%s”" % action["name"])
	App.status("Saved action “%s” to %s — reuse it on any instance" % [action["name"], c.name])


func delete_action(c: CharacterData, index: int) -> void:
	if index < 0 or index >= c.actions.size():
		return
	var after := c.actions.duplicate(true)
	after.remove_at(index)
	set_char_prop(c, "actions", after, "Delete action")


func apply_action(layer: LayerData, index: int, at: int, repeats: int = 1) -> void:
	var c := _character_of(layer)
	if c == null or index < 0 or index >= c.actions.size():
		return
	var action: Dictionary = c.actions[index]
	var length := maxi(1, int(action.get("length", 1)))
	repeats = maxi(1, repeats)
	var end := at + length * repeats
	var tracks := [layer.pose_keys.duplicate(true), layer.view_keys.duplicate(true), layer.swap_keys.duplicate(true)]
	var sources := [
		LayerData._list_to_dict_track(action.get("pose", [])),
		LayerData._list_to_dict_track(action.get("view", [])),
		LayerData._list_to_dict_track(action.get("swap", [])),
	]
	for t in 3:
		var src: Dictionary = sources[t]
		if src.is_empty():
			continue
		var dst: Dictionary = tracks[t]
		for k in dst.keys():
			var ki: int = k
			if ki >= at and ki < end:
				dst.erase(k)
		for r in repeats:
			var shifted := KeyTrack.slice(src, 0, length - 1, at + r * length)
			for k in shifted.keys():
				dst[k] = shifted[k]
	var s := App.current_scene()
	if end > s.frame_count:
		set_prop(s, "frame_count", end, "Extend scene", "timeline")
	_tracks_action("Apply action “%s”" % str(action.get("name", "")), layer, tracks[0], tracks[1], tracks[2])
	App.status("Applied “%s” ×%d at frame %d" % [str(action.get("name", "")), repeats, at + 1])


# ================================================================ audio

func _set_audio_tracks(scene: SceneData, arr: Array) -> void:
	scene.audio_tracks.assign(arr)
	App.notify("audio")


func _audio_tracks_action(label: String, scene: SceneData, after: Array) -> void:
	ur.create_action(label)
	ur.add_do_method(_set_audio_tracks.bind(scene, after))
	ur.add_undo_method(_set_audio_tracks.bind(scene, scene.audio_tracks.duplicate()))
	ur.commit_action()


func _set_track_clips(track: AudioTrackData, arr: Array) -> void:
	track.clips.assign(arr)
	App.notify("audio")


func _track_clips_action(label: String, track: AudioTrackData, after: Array) -> void:
	ur.create_action(label)
	ur.add_do_method(_set_track_clips.bind(track, after))
	ur.add_undo_method(_set_track_clips.bind(track, track.clips.duplicate()))
	ur.commit_action()


func add_audio_track(kind: String = "dialogue") -> AudioTrackData:
	var s := App.current_scene()
	if s == null:
		return null
	var t := AudioTrackData.new("%s %d" % [AudioTrackData.KIND_LABELS.get(kind, "Track"), s.audio_tracks.size() + 1], kind)
	var after := s.audio_tracks.duplicate()
	after.append(t)
	_audio_tracks_action("Add audio track", s, after)
	return t


func delete_audio_track(t: AudioTrackData) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var after := s.audio_tracks.duplicate()
	after.erase(t)
	_audio_tracks_action("Delete audio track", s, after)


func move_audio_track(t: AudioTrackData, delta: int) -> void:
	var s := App.current_scene()
	var i := s.audio_tracks.find(t)
	var to := i + delta
	if i < 0 or to < 0 or to >= s.audio_tracks.size():
		return
	var after := s.audio_tracks.duplicate()
	after.remove_at(i)
	after.insert(to, t)
	_audio_tracks_action("Reorder audio tracks", s, after)


func set_audio_prop(obj: Object, prop: String, value: Variant, label: String) -> void:
	set_prop(obj, prop, value, label, "audio")


## Copies an audio file into the project's audio/ folder and places it at the
## playhead — on `track`, or on a new track named after the file.
func import_audio(path: String, track: AudioTrackData = null) -> String:
	var s := App.current_scene()
	if s == null:
		return "Open a project first."
	if not Audio.is_audio_file(path):
		return "Unsupported audio format. Use WAV, OGG or MP3 (FLAC: convert to WAV or OGG first)."
	var ext := path.get_extension().to_lower()
	var rel := "audio".path_join(Ids.make() + "." + ext)
	var dest: String = App.project.root_dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var err := DirAccess.copy_absolute(path, dest)
	if err != OK:
		return "Could not copy the audio into the project (%s)" % error_string(err)
	var length := Audio.length_of(rel)
	if length <= 0.0:
		DirAccess.remove_absolute(dest)
		return "Could not read this audio file:\n" + path
	var clip := AudioClipData.new()
	clip.name = path.get_file().get_basename()
	clip.file = rel
	clip.start_frame = App.frame
	clip.length = length
	var lower := clip.name.to_lower()
	var kind := "dialogue"
	if lower.contains("music") or lower.contains("song") or lower.contains("theme") or length > 90.0:
		kind = "music"
	elif lower.contains("sfx") or lower.contains("fx") or length < 2.5:
		kind = "sfx"
	elif lower.contains("amb") or lower.contains("room") or lower.contains("wind"):
		kind = "ambient"
	var needed_frames := clip.end_frame(App.project.fps)
	ur.create_action("Import audio “%s”" % clip.name)
	if track == null:
		var t := AudioTrackData.new(clip.name, kind)
		t.clips.append(clip)
		var after := s.audio_tracks.duplicate()
		after.append(t)
		ur.add_do_method(_set_audio_tracks.bind(s, after))
		ur.add_undo_method(_set_audio_tracks.bind(s, s.audio_tracks.duplicate()))
	else:
		var after_clips := track.clips.duplicate()
		after_clips.append(clip)
		ur.add_do_method(_set_track_clips.bind(track, after_clips))
		ur.add_undo_method(_set_track_clips.bind(track, track.clips.duplicate()))
	if needed_frames > s.frame_count:
		ur.add_do_method(_apply_prop.bind(s, "frame_count", needed_frames, "timeline"))
		ur.add_undo_method(_apply_prop.bind(s, "frame_count", s.frame_count, "timeline"))
	ur.commit_action()
	App.status("Imported “%s” (%.1f s) as %s%s" % [clip.name, length, AudioTrackData.KIND_LABELS.get(kind, kind),
		" — scene extended to fit" if needed_frames > s.frame_count else ""])
	return ""


## Applies a finished drag/trim of a clip (values already set live) as one undo step.
func commit_clip_edit(clip: AudioClipData, before: Dictionary) -> void:
	var after := clip.to_dict()
	if after == before:
		return
	ur.create_action("Edit audio clip “%s”" % clip.name)
	ur.add_do_method(_apply_clip.bind(clip, after))
	ur.add_undo_method(_apply_clip.bind(clip, before))
	ur.commit_action(false)
	App.notify("audio")


func _apply_clip(clip: AudioClipData, d: Dictionary) -> void:
	clip.apply_dict(d)
	App.notify("audio")


func delete_audio_clip(track: AudioTrackData, clip: AudioClipData) -> void:
	var after := track.clips.duplicate()
	after.erase(clip)
	_track_clips_action("Delete audio clip", track, after)


func duplicate_audio_clip(track: AudioTrackData, clip: AudioClipData) -> AudioClipData:
	var c := clip.copy()
	c.start_frame = clip.end_frame(App.project.fps)
	var after := track.clips.duplicate()
	after.append(c)
	_track_clips_action("Duplicate audio clip", track, after)
	return c


## Splits a clip in two at the playhead.
func split_audio_clip(track: AudioTrackData, clip: AudioClipData) -> void:
	var fps: int = App.project.fps
	var t := App.frame / float(fps)
	var rel := t - clip.start_time(fps)
	if rel <= 0.02 or rel >= clip.length - 0.02:
		App.status("Move the playhead inside the clip to split it")
		return
	var first := clip.copy()
	first.id = clip.id
	first.length = rel
	first.fade_out = 0.0
	var second := clip.copy()
	second.start_frame = App.frame
	second.trim_in = clip.trim_in + rel
	second.length = clip.length - rel
	second.fade_in = 0.0
	var after := track.clips.duplicate()
	var i := after.find(clip)
	after[i] = first
	after.insert(i + 1, second)
	_track_clips_action("Split audio clip", track, after)


## Assisted lip-sync: reads the loudness of `clip` frame by frame and keys
## mouth drawings on `layer`'s `part_name`. Fully editable afterwards.
func auto_lipsync(layer: LayerData, part_name: String, clip: AudioClipData) -> void:
	var c := _character_of(layer)
	if c == null or clip == null:
		App.status("Choose a character layer and a dialogue clip")
		return
	var part: PartData = null
	for v in CharacterData.VIEWS:
		part = c.find_part(str(v), part_name)
		if part != null:
			break
	if part == null or part.variants.size() < 2:
		App.status("“%s” needs a part called %s with several drawings" % [c.name, part_name])
		return
	if Audio.peaks_for(clip.file).is_empty():
		App.status("The waveform is still being analysed — try again in a moment")
		return
	var fps: int = App.project.fps
	var first_frame := clip.start_frame
	var last_frame := clip.end_frame(fps)
	# Loudness per frame, normalised to the clip's loudest frame.
	var levels := PackedFloat32Array()
	var loudest := 0.0001
	for f in range(first_frame, last_frame):
		var t0 := f / float(fps)
		var src := clip.source_pos(t0, fps, Audio.length_of(clip.file))
		var lv := 0.0
		if src >= 0.0:
			lv = Audio.peak_between(clip.file, src, src + 1.0 / fps)
		levels.append(lv)
		loudest = maxf(loudest, lv)
	var pick := func(candidates: Array, fallback: int) -> String:
		for cand in candidates:
			if part.variants.has(str(cand)):
				return str(cand)
		return part.variants[clampi(fallback, 0, part.variants.size() - 1)]
	var n := part.variants.size()
	var rest: String = pick.call(["rest", "closed", "default"], 0)
	var closed: String = pick.call(["MBP", "M", "closed"], 0)
	var small_a: String = pick.call(["E", "FV", "L"], 1)
	var small_b: String = pick.call(["L", "FV", "E"], 1)
	var mid_a: String = pick.call(["O", "U", "E"], n / 2)
	var mid_b: String = pick.call(["U", "O", "E"], n / 2)
	var wide: String = pick.call(["AI", "A", "open"], n - 1)
	var shapes := []
	var alt := false
	for i in levels.size():
		var lv := levels[i] / loudest
		var prev := levels[i - 1] / loudest if i > 0 else 0.0
		var next := levels[i + 1] / loudest if i + 1 < levels.size() else 0.0
		var shape := rest
		if lv < 0.08:
			shape = rest
		elif lv < prev * 0.55 and lv < next * 0.55:
			shape = closed  # a short dip between syllables reads as lips closing
		elif lv < 0.3:
			shape = small_a if alt else small_b
		elif lv < 0.65:
			shape = mid_a if alt else mid_b
		else:
			shape = wide
		if i > 0 and shape != shapes[i - 1]:
			alt = not alt
		shapes.append(shape)
	# Hold each mouth at least 2 frames so it doesn't flicker.
	for i in range(1, shapes.size() - 1):
		if shapes[i] != shapes[i - 1] and shapes[i] != shapes[i + 1]:
			shapes[i] = shapes[i - 1]
	var swap := layer.swap_keys.duplicate(true)
	for k in swap.keys():
		var ki: int = k
		if ki >= first_frame and ki < last_frame:
			var d: Dictionary = swap[k]
			d = d.duplicate()
			d.erase(part.name)
			if d.is_empty():
				swap.erase(k)
			else:
				swap[k] = d
	var last_shape := ""
	var keys := 0
	for i in shapes.size():
		var sh: String = shapes[i]
		if sh == last_shape:
			continue
		last_shape = sh
		var f := first_frame + i
		var d := {}
		if swap.has(f):
			var existing: Dictionary = swap[f]
			d = existing.duplicate()
		d[part.name] = sh
		swap[f] = d
		keys += 1
	# Close the mouth after the line.
	if not swap.has(last_frame):
		swap[last_frame] = {part.name: rest}
	_tracks_action("Auto lip-sync “%s”" % clip.name, layer, layer.pose_keys, layer.view_keys, swap)
	App.status("Lip-sync: %d mouth changes over %d frames — refine any frame by hand" % [keys, shapes.size()])


# ================================================================ episodes

func _set_episodes(arr: Array) -> void:
	App.project.episodes.assign(arr)
	App.notify("episodes")


func _episodes_action(label: String, after: Array) -> void:
	ur.create_action(label)
	ur.add_do_method(_set_episodes.bind(after))
	ur.add_undo_method(_set_episodes.bind(App.project.episodes.duplicate()))
	ur.commit_action()


func add_episode() -> EpisodeData:
	if not App.has_project():
		return null
	var n: int = App.project.episodes.size() + 1
	var ep := EpisodeData.new("Episode %d" % n, n)
	ep.entries.append(EpisodeData.new_title_entry("%s\nEpisode %d" % [App.project.name, n]))
	var title_entry: Dictionary = ep.entries[0]
	title_entry["text"] = App.project.name
	title_entry["subtitle"] = "Episode %d" % n
	for s in App.project.scenes:
		ep.entries.append(EpisodeData.new_scene_entry(s.id))
	var credits := EpisodeData.new_title_entry("#%s\n\nDirected by - You\nAnimation - You\n\n#Made with Strata" % App.project.name, true)
	ep.entries.append(credits)
	var after := App.project.episodes.duplicate()
	after.append(ep)
	_episodes_action("New episode", after)
	return ep


func duplicate_episode(ep: EpisodeData) -> EpisodeData:
	var copy := ep.clone_deep()
	var after := App.project.episodes.duplicate()
	after.insert(after.find(ep) + 1, copy)
	_episodes_action("Duplicate episode", after)
	return copy


func delete_episode(ep: EpisodeData) -> void:
	var after := App.project.episodes.duplicate()
	after.erase(ep)
	_episodes_action("Delete episode", after)


func set_episode_prop(ep: EpisodeData, prop: String, value: Variant, label: String) -> void:
	set_prop(ep, prop, value, label, "episodes")


func _set_entries(ep: EpisodeData, arr: Array) -> void:
	ep.entries = arr.duplicate(true)
	App.notify("episodes")


func _entries_action(label: String, ep: EpisodeData, after: Array, merge: bool = false) -> void:
	ur.create_action(label, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE)
	ur.add_do_method(_set_entries.bind(ep, after))
	ur.add_undo_method(_set_entries.bind(ep, ep.entries.duplicate(true)))
	ur.commit_action()


func add_entry(ep: EpisodeData, entry: Dictionary, index: int = -1) -> void:
	var after := ep.entries.duplicate(true)
	if index < 0 or index > after.size():
		after.append(entry)
	else:
		after.insert(index, entry)
	_entries_action("Add to episode", ep, after)


func remove_entry(ep: EpisodeData, index: int) -> void:
	if index < 0 or index >= ep.entries.size():
		return
	var after := ep.entries.duplicate(true)
	after.remove_at(index)
	_entries_action("Remove from episode", ep, after)


func move_entry(ep: EpisodeData, index: int, to: int) -> void:
	if index < 0 or index >= ep.entries.size():
		return
	to = clampi(to, 0, ep.entries.size() - 1)
	if to == index:
		return
	var after := ep.entries.duplicate(true)
	var e: Variant = after[index]
	after.remove_at(index)
	after.insert(to, e)
	_entries_action("Reorder episode", ep, after)


func duplicate_entry(ep: EpisodeData, index: int) -> void:
	if index < 0 or index >= ep.entries.size():
		return
	var after := ep.entries.duplicate(true)
	var src: Dictionary = after[index]
	var copy := src.duplicate(true)
	copy["id"] = Ids.make()
	after.insert(index + 1, copy)
	_entries_action("Duplicate shot", ep, after)


func set_entry_field(ep: EpisodeData, index: int, field: String, value: Variant) -> void:
	if index < 0 or index >= ep.entries.size():
		return
	var cur: Dictionary = ep.entries[index]
	var old: Variant = cur.get(field)
	if typeof(old) == typeof(value) and old == value:
		return
	var after := ep.entries.duplicate(true)
	var e: Dictionary = after[index]
	e[field] = value
	_entries_action("Edit %s (%s)" % [field.replace("_", " "), str(cur.get("id", ""))], ep, after, true)


## Copies an audio file into the project's audio folder. Returns {rel, length, name} or {error}.
func _bring_audio(path: String) -> Dictionary:
	if not Audio.is_audio_file(path):
		return {"error": "Unsupported audio format. Use WAV, OGG or MP3."}
	var rel := "audio".path_join(Ids.make() + "." + path.get_extension().to_lower())
	var dest: String = App.project.root_dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if DirAccess.copy_absolute(path, dest) != OK:
		return {"error": "Could not copy the audio into the project."}
	var length := Audio.length_of(rel)
	if length <= 0.0:
		DirAccess.remove_absolute(dest)
		return {"error": "Could not read this audio file."}
	return {"rel": rel, "length": length, "name": path.get_file().get_basename()}


## Adds music/sound that spans the episode (placed at episode frame `at`).
func import_episode_audio(ep: EpisodeData, path: String, at: int = 0) -> String:
	var info := _bring_audio(path)
	if info.has("error"):
		return str(info["error"])
	var clip := AudioClipData.new()
	clip.name = str(info["name"])
	clip.file = str(info["rel"])
	clip.start_frame = at
	clip.length = float(info["length"])
	var t := AudioTrackData.new(clip.name, "music")
	t.clips.append(clip)
	var after := ep.audio_tracks.duplicate()
	after.append(t)
	ur.create_action("Add episode music “%s”" % clip.name)
	ur.add_do_method(_set_episode_tracks.bind(ep, after))
	ur.add_undo_method(_set_episode_tracks.bind(ep, ep.audio_tracks.duplicate()))
	ur.commit_action()
	return ""


func _set_episode_tracks(ep: EpisodeData, arr: Array) -> void:
	ep.audio_tracks.assign(arr)
	App.notify("episodes")


func delete_episode_track(ep: EpisodeData, t: AudioTrackData) -> void:
	var after := ep.audio_tracks.duplicate()
	after.erase(t)
	ur.create_action("Remove episode music")
	ur.add_do_method(_set_episode_tracks.bind(ep, after))
	ur.add_undo_method(_set_episode_tracks.bind(ep, ep.audio_tracks.duplicate()))
	ur.commit_action()



# ================================================================ video import

## Adds a layer created from a video (frames already on disk), optionally with
## its sound on a new audio track, extending the scene to fit — one undo step.
func add_video_layer(layer: LayerData, clip: AudioClipData, end_frame: int) -> void:
	var s := App.current_scene()
	if s == null:
		return
	var after := s.layers.duplicate()
	var idx := clampi(App.layer_index + 1, 0, after.size())
	after.insert(idx, layer)
	ur.create_action("Import video “%s”" % layer.name)
	ur.add_do_method(_set_layers.bind(s, after, idx))
	ur.add_undo_method(_set_layers.bind(s, s.layers.duplicate(), App.layer_index))
	if clip != null:
		var t := AudioTrackData.new(layer.name, "dialogue")
		t.clips.append(clip)
		var tracks_after := s.audio_tracks.duplicate()
		tracks_after.append(t)
		ur.add_do_method(_set_audio_tracks.bind(s, tracks_after))
		ur.add_undo_method(_set_audio_tracks.bind(s, s.audio_tracks.duplicate()))
	var needed := maxi(end_frame, clip.end_frame(App.project.fps) if clip != null else 0)
	if needed > s.frame_count:
		ur.add_do_method(_apply_prop.bind(s, "frame_count", needed, "timeline"))
		ur.add_undo_method(_apply_prop.bind(s, "frame_count", s.frame_count, "timeline"))
	ur.commit_action()
