class_name DepthView
extends SubViewportContainer
## The 3D stage. Every layer is a textured plane in real 3D space, standing
## on (or floating above) a floor among set pieces, lit by a sun or a lamp
## that casts shadows shaped like the drawings. A free "director" camera
## orbits the set; the animated scene camera produces the final shot.
##
## Units: 100 px of artwork = 1 world unit. Depth is measured away from the
## camera (+depth = into the screen = world -Z). With "keep size" on, a layer
## is scaled so it looks the same size through the default camera at any
## depth — moving it back then only changes parallax.
##
## Mouse: drag a drawing to slide it, drag a coloured gizmo arrow to move
## along exactly one axis, drag empty space (or right-drag) to orbit,
## middle-drag to pan, wheel to zoom.

signal camera_mode_changed
signal selection_changed
signal gizmo_mode_changed
## The 3D-set guide for the Draw tab has a new picture.
signal guide_updated

## The one 3D stage of the app, so the Draw canvas can show the set.
static var instance: DepthView = null

const PX := 100.0
const BASE_FOV := 40.0
const HELPER_LAYER := 2  # visual layer bit for grid/frustum/gizmos (never rendered in output)
const PLANE_LAYER := 4   # visual layer bit for the drawing planes (so the set can be shown without them)
const ART_MASK := 1 | PLANE_LAYER  # what output cameras see: set + drawings
const BLOCKOUT_TINTS := {"plain": "8a8f9c", "building": "a89a86", "tree": "7d9474", "bush": "7d9474", "rock": "8f8c88", "hill": "8a9a76"}
const AXIS_COLORS := [Color("#ff5f56"), Color("#5fd35f"), Color("#4c8dff")]

var viewport: SubViewport
var world: World3D
var root3d: Node3D
var editor_cam: Camera3D
var scene_cam: Camera3D
var through_camera: bool = false

## What the gizmo moves: "layer" (App's current layer), "prop" or "lamp".
var select_kind: String = "layer"
var selected_prop: String = ""

var _env: Environment
var _sun: DirectionalLight3D
var _lamp: OmniLight3D
var _floor: MeshInstance3D
var _floor_mat: StandardMaterial3D
var _props_root: Node3D
var _prop_nodes: Dictionary = {}  # prop id -> MeshInstance3D
var _prop_key: String = ""
var _lp_root: Node3D
var _lp_nodes: Dictionary = {}  # prop id -> MeshInstance3D (low-poly version, ink as child)
var _lp_keys: Dictionary = {}   # prop id -> build key
var _terrain: MeshInstance3D
var _terrain_key: String = ""
var _lp_settings_key: String = ""
var _drag_origin: Vector3 = Vector3.ZERO
var _drag_accum: float = 0.0
var _drag_rot_start: Vector3 = Vector3.ZERO
var _drag_size_start: Vector3 = Vector3.ONE
var _drag_angle_prev: float = 0.0
var _drag_uniform: float = 1.0
var _ghost_nodes: Dictionary = {}  # prop id -> MeshInstance3D shown in the editor only
var _paint_nodes: Dictionary = {}  # prop id -> MeshInstance3D wrapping the prop's drawing

## "move", "rotate" or "scale": what the gizmo handles do (W / E / R).
var gizmo_mode: String = "move"
## Draw-on-shapes mode: left-drag paints onto set pieces.
var paint_mode: bool = false
var paint_erase: bool = false
var paint_size: float = 0.12  # brush radius in world units
var _painting: bool = false
var _paint_prop: String = ""
var _paint_before: Image = null
var _paint_last: Vector2 = Vector2.ZERO
var _brush_key: String = ""
var _brush_img: Image = null
var _brush_clear: Image = null
## Set by the Draw canvas while it shows the 3D set guide.
var guide_wanted: bool = false
var guide_ready: bool = false
var _guide_vp: SubViewport
var _guide_cam: Camera3D
var _guide_env: Environment
var _guide_dirty: bool = false
var _guide_busy: bool = false
# ---- touch: one finger works like the mouse, two fingers pinch / pan
var _touches: Dictionary = {}
var _t_gesture: bool = false
var _t_center: Vector2 = Vector2.ZERO
var _t_dist: float = 1.0

var _planes: Dictionary = {}  # layer.id -> MeshInstance3D
var _boil_mats: Dictionary = {}  # layer.id -> ShaderMaterial (line boil)
const BOIL_SHADER := preload("res://shaders/layer_boil_3d.gdshader")
var _structure: String = ""
var _helpers_mesh: ImmediateMesh
var _grid_mesh: ImmediateMesh
var _line_mat: StandardMaterial3D
var _grid_mat: StandardMaterial3D

var _yaw: float = -0.55
var _pitch: float = -0.2
var _dist: float = 30.0
var _target: Vector3 = Vector3(0, 0, -4)

var _orbiting: bool = false
var _panning: bool = false
var _drag_layer: LayerData = null
var _drag_values: Dictionary = {}
var _drag_start: Dictionary = {}
var _drag_axis: int = -1  # 0 x, 1 y, 2 z while dragging a gizmo arrow
var _drag_stage_before: Dictionary = {}


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.gui_disable_input = true
	viewport.positional_shadow_atlas_size = 2048
	add_child(viewport)

	world = World3D.new()
	_env = make_environment(Palette.VIEWPORT_BG, false)
	world.environment = _env
	viewport.world_3d = world

	root3d = Node3D.new()
	viewport.add_child(root3d)

	# Guide for the Draw tab: the set (no drawings) through the scene camera.
	instance = self
	_guide_vp = SubViewport.new()
	_guide_vp.world_3d = world
	_guide_vp.transparent_bg = true
	_guide_vp.msaa_3d = Viewport.MSAA_2X
	_guide_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_guide_vp.size = Vector2i(960, 540)
	viewport.add_child(_guide_vp)
	_guide_cam = Camera3D.new()
	_guide_cam.cull_mask = 1
	_guide_env = make_environment(Color(0, 0, 0, 0), true)
	_guide_cam.environment = _guide_env
	_guide_vp.add_child(_guide_cam)
	_guide_cam.current = true

	editor_cam = Camera3D.new()
	editor_cam.fov = 45.0
	editor_cam.near = 0.05
	editor_cam.far = 2000.0
	root3d.add_child(editor_cam)
	scene_cam = Camera3D.new()
	scene_cam.cull_mask = ART_MASK
	root3d.add_child(scene_cam)

	_sun = DirectionalLight3D.new()
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 120.0
	root3d.add_child(_sun)
	_lamp = OmniLight3D.new()
	_lamp.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	root3d.add_child(_lamp)

	_floor = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_floor.mesh = pm
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.roughness = 0.95
	_floor.material_override = _floor_mat
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(_floor)
	_props_root = Node3D.new()
	root3d.add_child(_props_root)
	_lp_root = Node3D.new()
	root3d.add_child(_lp_root)
	_terrain = MeshInstance3D.new()
	_terrain.visible = false
	root3d.add_child(_terrain)

	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.no_depth_test = true
	_grid_mat = _line_mat.duplicate() as StandardMaterial3D
	_grid_mat.no_depth_test = false

	_helpers_mesh = ImmediateMesh.new()
	var helpers := MeshInstance3D.new()
	helpers.mesh = _helpers_mesh
	helpers.layers = HELPER_LAYER
	helpers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(helpers)
	_grid_mesh = ImmediateMesh.new()
	var grid := MeshInstance3D.new()
	grid.mesh = _grid_mesh
	grid.layers = HELPER_LAYER
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(grid)

	for sig: Signal in [App.project_opened, App.scene_switched]:
		sig.connect(rebuild)
	App.layers_changed.connect(_on_layers_changed)
	for sig: Signal in [App.frame_changed, App.pixels_changed, App.camera_changed, App.timeline_changed]:
		sig.connect(refresh)
	App.layer_selected.connect(func() -> void:
		select_kind = "layer"
		refresh()
		selection_changed.emit())
	App.stage_changed.connect(refresh)
	resized.connect(_update_aspect)
	_update_editor_cam()
	set_through_camera(false)
	rebuild()


## Environment used by the editor view, renders and episode feeds, so the
## ambient light matches everywhere.
func make_environment(bg: Color, transparent: bool) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var amb := 0.55
	if App.has_project() and App.current_scene() != null:
		amb = float(App.current_scene().stage_value("ambient"))
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = amb
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if App.has_project() and App.current_scene() != null:
		apply_haze(env, App.current_scene())
	return env


## Distance haze in the scene's background colour: far set pieces (and far
## drawings) fade toward the sky, which ties 2D and 3D together.
func apply_haze(env: Environment, s: SceneData) -> void:
	if not App.is_3d():
		env.fog_enabled = false
		return
	var haze := clampf(float(s.stage_value("haze")), 0.0, 1.0)
	env.fog_enabled = haze > 0.001
	if not env.fog_enabled:
		return
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = s.bg_color
	env.fog_light_energy = 1.0
	env.fog_density = lerpf(0.35, 1.0, haze)
	env.fog_depth_begin = base_dist() + 2.0
	env.fog_depth_end = base_dist() + lerpf(160.0, 22.0, haze)
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0


# ================================================================ Draw-tab guide

func request_guide() -> void:
	_guide_dirty = true
	if not _guide_busy:
		_render_guide.call_deferred()


func guide_texture() -> Texture2D:
	return _guide_vp.get_texture() if guide_ready else null


## Renders the set (without the drawings) through the scene camera.
func _render_guide() -> void:
	if _guide_busy or not _guide_dirty or not App.has_project() or App.current_scene() == null:
		return
	_guide_busy = true
	_guide_dirty = false
	var p: ProjectData = App.project
	var w := mini(p.width, 1280)
	var h := maxi(16, int(round(float(w) * p.height / float(p.width))))
	if _guide_vp.size != Vector2i(w, h):
		_guide_vp.size = Vector2i(w, h)
	var s := App.current_scene()
	_guide_env.ambient_light_energy = float(s.stage_value("ambient"))
	apply_haze(_guide_env, s)
	apply_scene_camera(_guide_cam, App.frame, false)
	_guide_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	guide_ready = true
	_guide_busy = false
	guide_updated.emit()
	if _guide_dirty:
		_render_guide.call_deferred()


## True when the scene has anything in its 3D set worth showing in Draw.
static func scene_has_set(s: SceneData) -> bool:
	if s == null or not App.is_3d():
		return false
	var props: Array = s.stage_value("props")
	return not props.is_empty() or bool(s.stage_value("floor")) or lowpoly_on(s)


# ================================================================ geometry helpers

func base_dist() -> float:
	if not App.has_project():
		return 14.0
	var h := float(App.project.height) / PX
	return (h * 0.5) / tan(deg_to_rad(BASE_FOV * 0.5))


func plane_size() -> Vector2:
	if not App.has_project():
		return Vector2(19.2, 10.8)
	return Vector2(float(App.project.width) / PX, float(App.project.height) / PX)


## World height of the floor.
func floor_y() -> float:
	var off := 0.0
	if App.has_project() and App.current_scene() != null:
		off = float(App.current_scene().stage_value("floor_offset"))
	return -plane_size().y * 0.5 + off


func depth_factor(layer: LayerData, depth_value: float) -> float:
	if not layer.keep_size:
		return 1.0
	var d := base_dist()
	return maxf(0.05, (d + depth_value) / d)


## Placement of a layer at `frame` (animated motion, or a live drag override).
func layer_motion(layer: LayerData, frame: int) -> Dictionary:
	if _drag_layer == layer and not _drag_values.is_empty():
		return _drag_values
	return layer.motion_at(frame)


func layer_transform(layer: LayerData, index: int, m: Dictionary) -> Transform3D:
	var dep: float = m["depth"]
	if App.has_project() and not App.is_3d():
		# 2D and stop motion: a flat stack in layer order, nothing in depth.
		m = m.duplicate()
		m["tilt"] = 0.0
		m["turn"] = 0.0
		dep = 0.0
	var k := depth_factor(layer, dep)
	var sc: float = float(m["scale"]) * k
	var b := Basis.from_euler(Vector3(deg_to_rad(-float(m.get("tilt", 0.0))), deg_to_rad(float(m.get("turn", 0.0))), deg_to_rad(-float(m["rotation"]))), EULER_ORDER_YXZ)
	b = b * Basis.from_scale(Vector3(sc, sc, 1.0))  # scale in the layer's own frame
	var pos := Vector3(float(m["x"]) / PX * k, -float(m["y"]) / PX * k, -dep + index * 0.002)
	return Transform3D(b, pos)


static func _vec3(a: Variant, fallback: Vector3) -> Vector3:
	if typeof(a) == TYPE_ARRAY:
		var arr: Array = a
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback


## World position of a prop (props store x, y, depth).
static func prop_position(p: Dictionary) -> Vector3:
	var v := _vec3(p.get("pos"), Vector3.ZERO)
	return Vector3(v.x, v.y, -v.z)


## Positions `cam` for the scene camera at `frame`. With fit_width the FOV is
## treated as horizontal so the whole frame fits a narrow viewport.
func apply_scene_camera(cam: Camera3D, frame: int, fit_width: bool = false) -> void:
	if not App.has_project():
		return
	var s := App.current_scene()
	var st := s.camera_at(frame)
	var x: float = st["x"]
	var y: float = st["y"]
	var shake: float = st["shake"]
	if shake > 0.0:
		x += (sin(frame * 12.9898) * 0.6 + sin(frame * 4.1414 + 1.3) * 0.4) * shake
		y += (cos(frame * 9.7310) * 0.6 + cos(frame * 3.3700 + 0.7) * 0.4) * shake
	var dolly: float = st["dolly"]
	var zoom := maxf(0.05, float(st["zoom"]))
	var roll: float = st["roll"]
	cam.position = Vector3(x / PX, -y / PX, base_dist() - dolly)
	cam.rotation = Vector3(0, 0, deg_to_rad(-roll))
	cam.near = 0.05
	cam.far = 2000.0
	var aspect := float(App.project.width) / float(App.project.height)
	var half_v := tan(deg_to_rad(BASE_FOV * 0.5)) / zoom
	if s.camera_ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		var h := float(App.project.height) / PX / zoom
		cam.size = h * aspect if fit_width else h
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		var half := half_v * aspect if fit_width else half_v
		cam.fov = rad_to_deg(2.0 * atan(half))
	cam.keep_aspect = Camera3D.KEEP_WIDTH if fit_width else Camera3D.KEEP_HEIGHT


# ================================================================ scene sync

func _structure_key() -> String:
	var s: SceneData = App.current_scene() if App.has_project() else null
	if s == null:
		return ""
	var ids := PackedStringArray()
	for l in s.layers:
		ids.append(l.id)
	return ",".join(ids)


## Property edits only need a refresh; added/removed/reordered layers need new planes.
func _on_layers_changed() -> void:
	if _structure_key() != _structure:
		rebuild()
	else:
		refresh()


func rebuild() -> void:
	_structure = _structure_key()
	for id in _planes.keys():
		var mi: Node = _planes[id]
		mi.queue_free()
	_planes.clear()
	if not App.has_project() or App.current_scene() == null:
		_helpers_mesh.clear_surfaces()
		_grid_mesh.clear_surfaces()
		return
	var qs := plane_size()
	for layer in App.current_scene().layers:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = qs
		mi.mesh = q
		mi.material_override = _plane_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Shadow-only twin with a hard alpha cutoff, so shadows follow the
		# painted pixels instead of the whole rectangle.
		var sh := MeshInstance3D.new()
		sh.name = "Shadow"
		sh.mesh = q
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		smat.alpha_scissor_threshold = 0.35
		sh.material_override = smat
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.add_child(sh)
		mi.layers = PLANE_LAYER
		root3d.add_child(mi)
		_planes[layer.id] = mi
	_prop_key = ""
	refresh()


func refresh() -> void:
	if not App.has_project():
		return
	var s := App.current_scene()
	if s == null:
		return
	for i in s.layers.size():
		var layer: LayerData = s.layers[i]
		if not _planes.has(layer.id):
			rebuild()
			return
		var mi: MeshInstance3D = _planes[layer.id]
		var tex := _layer_texture(layer)
		var m := layer_motion(layer, App.frame)
		mi.visible = layer.visible and tex != null and not layer.is_reference()
		var op := clampf(float(m["opacity"]), 0.0, 1.0)
		# Line boil: unlit drawing layers use a wobbling shader instead.
		if layer.has_fx() and not layer.lit:
			var bm: ShaderMaterial = _boil_mats.get(layer.id)
			if bm == null:
				bm = ShaderMaterial.new()
				bm.shader = BOIL_SHADER
				_boil_mats[layer.id] = bm
			bm.set_shader_parameter("tex", tex)
			bm.set_shader_parameter("opacity", op)
			bm.set_shader_parameter("amount", layer.boil_pixels() if layer.has_boil() else 0.0)
			bm.set_shader_parameter("border", layer.border if layer.has_border() else 0.0)
			bm.set_shader_parameter("border_color", layer.border_color)
			bm.set_shader_parameter("border_inner", layer.border_inner)
			bm.set_shader_parameter("step_k", layer.boil_step(App.frame))
			bm.set_shader_parameter("tex_size", Vector2(App.project.width, App.project.height))
			mi.material_override = bm
		else:
			if not (mi.material_override is StandardMaterial3D):
				mi.material_override = _plane_material()
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var shb: MeshInstance3D = mi.get_node("Shadow")
			shb.visible = layer.cast_shadow and op > 0.05
			if tex != null:
				(shb.material_override as StandardMaterial3D).albedo_texture = tex
			mi.transform = layer_transform(layer, i, m)
			continue
		if tex != null:
			mat.albedo_texture = tex
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if layer.lit else BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.roughness = 1.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if layer.is_character():
			# Viewport renders are premultiplied: blend accordingly.
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
			mat.albedo_color = Color(op, op, op, op)
		else:
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1, 1, 1, op)
		var sh: MeshInstance3D = mi.get_node("Shadow")
		sh.visible = layer.cast_shadow and op > 0.05
		if tex != null:
			(sh.material_override as StandardMaterial3D).albedo_texture = tex
		mi.transform = layer_transform(layer, i, m)
	_refresh_stage(s)
	apply_scene_camera(scene_cam, App.frame, _fit_width())
	_draw_helpers()
	if guide_wanted:
		request_guide()


func _plane_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return mat


func _layer_texture(layer: LayerData) -> Texture2D:
	if layer.is_character():
		return Rigs.texture_for(layer)
	var cel := layer.cel_at(App.frame)
	return cel.get_texture() if cel != null else null


# ---------------------------------------------------------------- stage: floor, lights, set pieces

func _refresh_stage(s: SceneData) -> void:
	# Only 2D+3D projects have a 3D set and stage lights.
	var set_on := App.is_3d()
	_props_root.visible = set_on
	_lp_root.visible = set_on and lowpoly_on(s)
	if not set_on:
		_floor.visible = false
		_terrain.visible = false
		_sun.visible = false
		_lamp.visible = false
		_env.ambient_light_energy = 1.0
		_env.fog_enabled = false
		return
	var fy := floor_y()
	var lps: Dictionary = s.stage_value("lowpoly")
	var use_terrain := lowpoly_on(s) and bool(LowPolyBuilder.setting(lps, "terrain"))
	_floor.visible = bool(s.stage_value("floor")) and not use_terrain
	_floor.position = Vector3(0, fy, -20)
	_floor.scale = Vector3(160, 1, 160)
	_floor_mat.albedo_color = Color.from_string(str(s.stage_value("floor_color")), Color("#343844"))

	var light := str(s.stage_value("light"))
	var col := Color.from_string(str(s.stage_value("light_color")), Color.WHITE)
	var energy := float(s.stage_value("energy"))
	var shadows := bool(s.stage_value("shadows"))
	var strength := clampf(float(s.stage_value("shadow_strength")), 0.0, 1.0)
	var soft := float(s.stage_value("shadow_softness"))
	_sun.visible = light == "sun"
	_lamp.visible = light == "lamp"
	for l: Light3D in [_sun, _lamp]:
		l.light_color = col
		l.light_energy = energy
		l.shadow_enabled = shadows and strength > 0.001
		l.shadow_opacity = strength
		l.shadow_blur = maxf(0.0, soft)
	_sun.rotation = Vector3(deg_to_rad(-float(s.stage_value("elevation"))), deg_to_rad(float(s.stage_value("azimuth"))), 0.0)
	_lamp.position = prop_position({"pos": s.stage_value("lamp_pos")})
	_lamp.omni_range = maxf(1.0, float(s.stage_value("lamp_range")))
	_env.ambient_light_energy = float(s.stage_value("ambient"))
	apply_haze(_env, s)
	_refresh_lowpoly(s)

	var props: Array = s.stage_value("props")
	var key := ""
	for item in props:
		var p: Dictionary = item
		key += str(p.get("id", "")) + str(p.get("type", "")) + ";"
	if key != _prop_key:
		_prop_key = key
		for dict in [_prop_nodes, _ghost_nodes, _paint_nodes]:
			var d: Dictionary = dict
			for id in d.keys():
				var n: Node = d[id]
				n.queue_free()
			d.clear()
		for item in props:
			var p: Dictionary = item
			var id := str(p.get("id", ""))
			var mesh: Mesh = ShapeMesh.unit(str(p.get("type", "box")))["mesh"]
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.roughness = 0.9
			mi.material_override = mat
			_props_root.add_child(mi)
			_prop_nodes[id] = mi
			# Editor-only ghost, so fully clear shapes can still be found and edited.
			var ghost := MeshInstance3D.new()
			ghost.mesh = mesh
			ghost.layers = HELPER_LAYER
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.albedo_color = Color(0.55, 0.85, 1.0, 0.1)
			gm.no_depth_test = false
			gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			ghost.material_override = gm
			_props_root.add_child(ghost)
			_ghost_nodes[id] = ghost
			# Paint shell: the drawing wrapped around the shape.
			var shell := MeshInstance3D.new()
			shell.mesh = mesh
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			shell.material_override = sm
			var sh := MeshInstance3D.new()
			sh.name = "Shadow"
			sh.mesh = mesh
			var shm := StandardMaterial3D.new()
			shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			shm.cull_mode = BaseMaterial3D.CULL_DISABLED
			shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			shm.alpha_scissor_threshold = 0.35
			sh.material_override = shm
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			shell.add_child(sh)
			_props_root.add_child(shell)
			_paint_nodes[id] = shell
	var lp := lowpoly_on(s)
	for item in props:
		var p: Dictionary = item
		var id := str(p.get("id", ""))
		if not _prop_nodes.has(id):
			continue
		var mi: MeshInstance3D = _prop_nodes[id]
		var t := prop_transform(p)
		var clear := prop_clear(p)
		var casts := bool(p.get("cast_shadow", true))
		mi.transform = t
		var bc := Color.from_string(str(p.get("color", "8a8f9cff")), Color.GRAY)
		if str(p.get("color", LowPolyBuilder.DEFAULT_PROP_COLOR)) == LowPolyBuilder.DEFAULT_PROP_COLOR:
			# Tint blockout shapes by what they will become, so the rough set reads at a glance.
			bc = Color.from_string(str(BLOCKOUT_TINTS.get(LowPolyBuilder.resolve_role(p), "8a8f9c")), Color.GRAY)
		var mat := mi.material_override as StandardMaterial3D
		bc.a = 1.0 - clear
		mat.albedo_color = bc
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if clear > 0.001 else BaseMaterial3D.TRANSPARENCY_DISABLED
		if lp or clear >= 0.99:
			# Hidden, but a fully clear shape can still throw its shadow.
			mi.visible = casts and not lp
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			mi.visible = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ghost: MeshInstance3D = _ghost_nodes[id]
		ghost.transform = t
		ghost.visible = clear >= 0.6 and not through_camera
		var shell: MeshInstance3D = _paint_nodes[id]
		var cel: CelData = s.prop_paint.get(id)
		shell.visible = cel != null
		if cel != null:
			var inflate := 1.0 + clampf(0.03 / maxf(0.2, _vec3(p.get("size"), Vector3.ONE)[_min_axis(p)]), 0.004, 0.06)
			if lp:
				inflate += 0.02
			shell.transform = Transform3D(t.basis * Basis.from_scale(Vector3.ONE * inflate), t.origin)
			var tex := cel.get_texture()
			(shell.material_override as StandardMaterial3D).albedo_texture = tex
			var sh: MeshInstance3D = shell.get_node("Shadow")
			sh.visible = casts
			(sh.material_override as StandardMaterial3D).albedo_texture = tex


## 0 = solid, 1 = completely clear (invisible in the final picture).
static func prop_clear(p: Dictionary) -> float:
	return clampf(float(p.get("clear", 0.0)), 0.0, 1.0)


static func _min_axis(p: Dictionary) -> int:
	var v := _vec3(p.get("size"), Vector3.ONE)
	if v.x <= v.y and v.x <= v.z:
		return 0
	return 1 if v.y <= v.z else 2


## Props are sized in world units; pos.y is the height of the prop's base
## above the floor, so props sit on the floor by default.
func prop_transform(p: Dictionary) -> Transform3D:
	var size := _vec3(p.get("size"), Vector3.ONE)
	var rot := _vec3(p.get("rot"), Vector3.ZERO)
	var pos := prop_position(p)
	pos.y = floor_y() + pos.y + size.y * 0.5
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))) * Basis.from_scale(size)
	return Transform3D(b, pos)


## Placement of a prop without its size (low-poly meshes are built sized).
func prop_pose(p: Dictionary) -> Transform3D:
	var t := prop_transform(p)
	var rot := _vec3(p.get("rot"), Vector3.ZERO)
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))), t.origin)


static func lowpoly_on(s: SceneData) -> bool:
	var lps: Dictionary = s.stage_value("lowpoly")
	return bool(LowPolyBuilder.setting(lps, "on"))


## Builds (only when something changed) and places the low-poly version of
## every blockout shape, plus the rolling terrain.
func _refresh_lowpoly(s: SceneData) -> void:
	var on := lowpoly_on(s)
	_lp_root.visible = on
	var lps: Dictionary = s.stage_value("lowpoly")
	var use_terrain := on and bool(LowPolyBuilder.setting(lps, "terrain"))
	_terrain.visible = use_terrain
	if not on:
		return
	var skey := JSON.stringify(lps)
	if skey != _lp_settings_key:
		_lp_settings_key = skey
		_lp_keys.clear()  # rebuild everything with the new style
	if use_terrain:
		var tkey := skey
		if tkey != _terrain_key or _terrain.mesh == null:
			_terrain_key = tkey
			_terrain.mesh = LowPolyBuilder.build_terrain(lps)
			_terrain.material_override = LowPolyBuilder.body_material(lps)
		_terrain.position = Vector3(0, floor_y(), 0)
	var seen := {}
	for item in s.stage_value("props"):
		var p: Dictionary = item
		var id := str(p.get("id", ""))
		seen[id] = true
		var clear := prop_clear(p)
		var key := "%s|%s|%s|%s|%.2f" % [str(p.get("type", "")), str(p.get("role", "auto")), str(p.get("size", "")), str(p.get("color", "")), clear]
		var mi: MeshInstance3D = _lp_nodes.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var ink := MeshInstance3D.new()
			ink.name = "Ink"
			ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_child(ink)
			_lp_root.add_child(mi)
			_lp_nodes[id] = mi
		if str(_lp_keys.get(id, "")) != key:
			_lp_keys[id] = key
			var built := LowPolyBuilder.build_prop(p, lps)
			mi.mesh = built["body"]
			mi.material_override = LowPolyBuilder.body_material(lps, 1.0 - clear)
			var ink_node: MeshInstance3D = mi.get_node("Ink")
			var ink_mesh: Variant = built["ink"]
			if ink_mesh != null and clear < 0.35:
				var im: ArrayMesh = ink_mesh
				ink_node.mesh = im
				ink_node.material_override = LowPolyBuilder.ink_material(lps)
				ink_node.visible = true
			else:
				ink_node.visible = false
		mi.transform = prop_pose(p)
		var casts := bool(p.get("cast_shadow", true))
		if clear >= 0.99:
			mi.visible = casts
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			mi.visible = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for id in _lp_nodes.keys():
		if not seen.has(id):
			var n: Node = _lp_nodes[id]
			n.queue_free()
			_lp_nodes.erase(id)
			_lp_keys.erase(id)


func find_prop(id: String) -> Dictionary:
	if not App.has_project() or App.current_scene() == null:
		return {}
	for item in App.current_scene().stage_value("props"):
		var p: Dictionary = item
		if str(p.get("id", "")) == id:
			return p
	return {}


func _fit_width() -> bool:
	if not App.has_project() or size.y <= 0.0:
		return false
	var aspect := float(App.project.width) / float(App.project.height)
	return size.x / size.y < aspect


func _update_aspect() -> void:
	if App.has_project():
		apply_scene_camera(scene_cam, App.frame, _fit_width())


# ---------------------------------------------------------------- helpers: grid, frustum, outlines, gizmo

func _build_grid() -> void:
	_grid_mesh.clear_surfaces()
	var fy := floor_y() + 0.01
	_grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _grid_mat)
	for i in range(-20, 21):
		var x := i * 2.0
		var c := Color(1, 1, 1, 0.1 if i == 0 else 0.045)
		_grid_mesh.surface_set_color(c)
		_grid_mesh.surface_add_vertex(Vector3(x, fy, 16.0))
		_grid_mesh.surface_set_color(c)
		_grid_mesh.surface_add_vertex(Vector3(x, fy, -64.0))
	for i in range(-32, 9):
		var z := i * 2.0
		var c := Color(1, 1, 1, 0.1 if i == 0 else 0.045)
		_grid_mesh.surface_set_color(c)
		_grid_mesh.surface_add_vertex(Vector3(-40.0, fy, z))
		_grid_mesh.surface_set_color(c)
		_grid_mesh.surface_add_vertex(Vector3(40.0, fy, z))
	_grid_mesh.surface_end()


## Where the gizmo sits and what it moves.
func gizmo_center() -> Variant:
	if not App.has_project():
		return null
	var s := App.current_scene()
	match select_kind:
		"prop":
			var p := find_prop(selected_prop)
			if p.is_empty():
				return null
			return prop_transform(p).origin
		"lamp":
			if str(s.stage_value("light")) != "lamp":
				return null
			return _lamp.position
		_:
			var layer := App.current_layer()
			if layer == null or not _planes.has(layer.id):
				return null
			var mi: MeshInstance3D = _planes[layer.id]
			return mi.transform.origin


func _gizmo_len() -> float:
	var c: Variant = gizmo_center()
	if c == null:
		return 1.0
	var cv: Vector3 = c
	return clampf(editor_cam.global_position.distance_to(cv) * 0.12, 0.6, 12.0)


func _draw_helpers() -> void:
	_build_grid()
	_helpers_mesh.clear_surfaces()
	var verts: Array[Vector3] = []
	var colors: Array[Color] = []
	var s := App.current_scene()
	if not through_camera:
		# Scene camera frustum and the frame it sees at depth 0.
		var cam_t := scene_cam.global_transform
		var cp := cam_t.origin
		var hh := 0.0
		if scene_cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			hh = scene_cam.size * 0.5
		else:
			hh = tan(deg_to_rad(scene_cam.fov * 0.5)) * maxf(0.01, cp.z)
		var aspect := float(App.project.width) / float(App.project.height)
		if scene_cam.keep_aspect == Camera3D.KEEP_WIDTH:
			hh /= aspect
		var hw := hh * aspect
		var corners: Array[Vector3] = []
		for o in [Vector2(-hw, hh), Vector2(hw, hh), Vector2(hw, -hh), Vector2(-hw, -hh)]:
			var local := Vector3(o.x, o.y, -cp.z)
			corners.append(cam_t.basis * local + cp)
		var fc := Palette.DEPTH
		for i in 4:
			_line(verts, colors, cp, corners[i], Color(fc, 0.55))
			_line(verts, colors, corners[i], corners[(i + 1) % 4], fc)
		# Outline every layer (faintly) so empty layers are visible in space.
		var qs := plane_size() * 0.5
		var active := App.current_layer()
		for layer in s.layers:
			if not _planes.has(layer.id) or not layer.visible or layer.is_reference():
				continue
			var mi: MeshInstance3D = _planes[layer.id]
			var t := mi.transform
			var pts := [t * Vector3(-qs.x, qs.y, 0), t * Vector3(qs.x, qs.y, 0), t * Vector3(qs.x, -qs.y, 0), t * Vector3(-qs.x, -qs.y, 0)]
			var col := Palette.ACCENT if layer == active and select_kind == "layer" else Color(1, 1, 1, 0.14)
			for i in 4:
				_line(verts, colors, pts[i], pts[(i + 1) % 4], col)
		# Light helpers
		var light := str(s.stage_value("light"))
		if light == "sun":
			var origin := Vector3(0, plane_size().y * 0.9, -6)
			var dir := -_sun.global_transform.basis.z
			_line(verts, colors, origin, origin + dir * 4.0, Color("#ffd166"))
			for a in 8:
				var ang := TAU * a / 8.0
				_line(verts, colors, origin, origin + Vector3(cos(ang), sin(ang), 0) * 0.7, Color("#ffd166"))
		elif light == "lamp":
			var lp := _lamp.position
			var lc := Color("#ffd166") if select_kind != "lamp" else Palette.ACCENT
			for a in 12:
				var a0 := TAU * a / 12.0
				var a1 := TAU * (a + 1) / 12.0
				_line(verts, colors, lp + Vector3(cos(a0), sin(a0), 0) * 0.5, lp + Vector3(cos(a1), sin(a1), 0) * 0.5, lc)
				_line(verts, colors, lp + Vector3(cos(a0), 0, sin(a0)) * 0.5, lp + Vector3(cos(a1), 0, sin(a1)) * 0.5, lc)
			_line(verts, colors, lp, Vector3(lp.x, floor_y(), lp.z), Color(lc, 0.35))
		# Selected prop outline
		if select_kind == "prop":
			var p := find_prop(selected_prop)
			if not p.is_empty():
				var t := prop_transform(p)
				var cs: Array[Vector3] = [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5),
					Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]
				for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
					var e0: int = e[0]
					var e1: int = e[1]
					_line(verts, colors, t * cs[e0], t * cs[e1], Palette.ACCENT)
		_draw_gizmo(verts, colors)
	if verts.is_empty():
		return
	_helpers_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	for i in verts.size():
		_helpers_mesh.surface_set_color(colors[i])
		_helpers_mesh.surface_add_vertex(verts[i])
	_helpers_mesh.surface_end()


func _line(verts: Array[Vector3], colors: Array[Color], a: Vector3, b: Vector3, c: Color) -> void:
	verts.append(a)
	verts.append(b)
	colors.append(c)
	colors.append(c)


# ================================================================ view control

func set_through_camera(on: bool) -> void:
	through_camera = on
	if on:
		scene_cam.current = true
	else:
		editor_cam.current = true
	refresh()
	camera_mode_changed.emit()


func reset_view() -> void:
	_yaw = -0.55
	_pitch = -0.2
	_dist = base_dist() * 2.0
	_target = Vector3(0, 0, -4)
	_update_editor_cam()


func _update_editor_cam() -> void:
	var b := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	editor_cam.global_transform = Transform3D(b, _target + b.z * _dist)
	if App.has_project():
		_draw_helpers()


func active_camera() -> Camera3D:
	return scene_cam if through_camera else editor_cam


# ================================================================ gizmo (move / rotate / scale)

func set_gizmo_mode(mode: String) -> void:
	gizmo_mode = mode
	if paint_mode:
		paint_mode = false
	_draw_helpers()
	gizmo_mode_changed.emit()


func set_paint_mode(on: bool) -> void:
	paint_mode = on
	_draw_helpers()
	gizmo_mode_changed.emit()


## The lamp only moves; everything else follows the chosen mode.
func _eff_mode() -> String:
	return "move" if select_kind == "lamp" else gizmo_mode


## Directions of the three handles: world axes, except scaling a set piece,
## which follows the piece's own sides.
func _handle_axes() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	if _eff_mode() == "scale" and select_kind == "prop":
		var p := find_prop(selected_prop)
		if not p.is_empty():
			var b := prop_pose(p).basis
			out = [b.x.normalized(), b.y.normalized(), b.z.normalized()]
	return out


func _ring_points(c: Vector3, axis: int, radius: float, n: int = 40) -> Array[Vector3]:
	var u := Vector3.UP if axis == 0 else Vector3.RIGHT
	var w := Vector3.ZERO
	match axis:
		0:
			u = Vector3.UP
			w = Vector3.BACK
		1:
			u = Vector3.RIGHT
			w = Vector3.BACK
		_:
			u = Vector3.RIGHT
			w = Vector3.UP
	var pts: Array[Vector3] = []
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + (u * cos(a) + w * sin(a)) * radius)
	return pts


func _draw_gizmo(verts: Array[Vector3], colors: Array[Color]) -> void:
	if paint_mode:
		return
	var gc: Variant = gizmo_center()
	if gc == null:
		return
	var c: Vector3 = gc
	var glen := _gizmo_len()
	var mode := _eff_mode()
	var axes := _handle_axes()
	for ax in 3:
		var colr: Color = AXIS_COLORS[ax]
		if _drag_axis == ax:
			colr = Color.WHITE
		var dirv: Vector3 = axes[ax]
		match mode:
			"rotate":
				var pts := _ring_points(c, ax, glen * 0.85)
				for i in pts.size() - 1:
					_line(verts, colors, pts[i], pts[i + 1], colr)
			"scale":
				var tip := c + dirv * glen
				_line(verts, colors, c, tip, colr)
				_cube(verts, colors, tip, glen * 0.06, colr)
			_:
				var tip := c + dirv * glen
				_line(verts, colors, c, tip, colr)
				var side := glen * 0.12
				var perp := Vector3.UP if ax != 1 else Vector3.RIGHT
				_line(verts, colors, tip, tip - dirv * side * 1.6 + perp * side * 0.6, colr)
				_line(verts, colors, tip, tip - dirv * side * 1.6 - perp * side * 0.6, colr)
	if mode == "scale":
		_cube(verts, colors, c, glen * 0.08, Color.WHITE if _drag_axis == 3 else Color(1, 1, 1, 0.8))


func _cube(verts: Array[Vector3], colors: Array[Color], c: Vector3, r: float, col: Color) -> void:
	var cs: Array[Vector3] = []
	for i in 8:
		cs.append(c + Vector3(r if (i & 1) != 0 else -r, r if (i & 2) != 0 else -r, r if (i & 4) != 0 else -r))
	for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		var e0: int = e[0]
		var e1: int = e[1]
		_line(verts, colors, cs[e0], cs[e1], col)


## Which handle is under the mouse: 0..2 for an axis, 3 for uniform scale, -1 for none.
func _handle_at(pos: Vector2) -> int:
	if through_camera or paint_mode:
		return -1
	var gc: Variant = gizmo_center()
	if gc == null:
		return -1
	var c: Vector3 = gc
	var cam := editor_cam
	if cam.is_position_behind(c):
		return -1
	var sc := cam.unproject_position(c)
	var glen := _gizmo_len()
	var mode := _eff_mode()
	if mode == "scale" and sc.distance_to(pos) < UI.px(10):
		return 3
	var axes := _handle_axes()
	var best := -1
	var best_d := UI.px(9)
	for ax in 3:
		var d := INF
		if mode == "rotate":
			var pts := _ring_points(c, ax, glen * 0.85, 32)
			for i in pts.size() - 1:
				if cam.is_position_behind(pts[i]) or cam.is_position_behind(pts[i + 1]):
					continue
				var a := cam.unproject_position(pts[i])
				var b := cam.unproject_position(pts[i + 1])
				d = minf(d, Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos))
		else:
			var st := cam.unproject_position(c + axes[ax] * glen)
			d = Geometry2D.get_closest_point_to_segment(pos, sc, st).distance_to(pos)
		if d < best_d:
			best_d = d
			best = ax
	return best


func _gui_input(event: InputEvent) -> void:
	if not App.has_project():
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		return
	if _t_gesture and (event is InputEventMouseButton or event is InputEventMouseMotion):
		accept_event()
		return
	if event is InputEventKey:
		if _on_key(event as InputEventKey):
			accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			grab_focus()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and not through_camera:
					_dist = maxf(1.0, _dist * 0.9)
					_update_editor_cam()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and not through_camera:
					_dist = minf(600.0, _dist * 1.1)
					_update_editor_cam()
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press(mb.position)
				else:
					_release()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _painting:
			_paint_to(mm.position)
		elif _drag_axis >= 0:
			_drag_handle(mm.position, mm.relative)
		elif _drag_layer != null:
			_drag_move(mm.relative, mm.shift_pressed)
		elif _orbiting and not through_camera:
			_yaw -= mm.relative.x * 0.008
			_pitch = clampf(_pitch - mm.relative.y * 0.008, -1.45, 1.45)
			_update_editor_cam()
		elif _panning and not through_camera:
			var b := editor_cam.global_transform.basis
			_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0016
			_update_editor_cam()
		elif paint_mode:
			mouse_default_cursor_shape = Control.CURSOR_CROSS
		else:
			mouse_default_cursor_shape = Control.CURSOR_MOVE if _handle_at(mm.position) >= 0 else Control.CURSOR_ARROW
	elif event is InputEventPanGesture and not through_camera:
		var pg := event as InputEventPanGesture
		_yaw -= pg.delta.x * 0.05
		_pitch = clampf(_pitch - pg.delta.y * 0.05, -1.45, 1.45)
		_update_editor_cam()
	elif event is InputEventMagnifyGesture and not through_camera:
		var mg := event as InputEventMagnifyGesture
		_dist = clampf(_dist / mg.factor, 1.0, 600.0)
		_update_editor_cam()


## Two fingers: pinch to zoom, drag to pan (one finger orbits / moves
## things through the emulated mouse, like a left-drag).
func _touch_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st != null:
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() >= 2 and not _t_gesture:
			# Cancel whatever the first finger started.
			_t_gesture = true
			_orbiting = false
			if _painting:
				_end_paint()
			if _drag_layer != null or _drag_axis >= 0:
				_release()
		if _touches.size() >= 2:
			_t_reset()
		elif _touches.is_empty():
			_t_gesture = false
		accept_event()
		return
	var sd := event as InputEventScreenDrag
	if sd == null:
		return
	_touches[sd.index] = sd.position
	if not _t_gesture or _touches.size() < 2 or through_camera:
		return
	var ks := _touches.keys()
	ks.sort()
	var a: Vector2 = _touches[ks[0]]
	var b: Vector2 = _touches[ks[1]]
	var center := (a + b) * 0.5
	var dist := maxf(1.0, a.distance_to(b))
	_dist = clampf(_dist * _t_dist / dist, 1.0, 600.0)
	var rel := center - _t_center
	var basis := editor_cam.global_transform.basis
	_target += (-basis.x * rel.x + basis.y * rel.y) * _dist * 0.0016
	_t_center = center
	_t_dist = dist
	_update_editor_cam()
	accept_event()


func _t_reset() -> void:
	var ks := _touches.keys()
	ks.sort()
	var a: Vector2 = _touches[ks[0]]
	var b: Vector2 = _touches[ks[1]]
	_t_center = (a + b) * 0.5
	_t_dist = maxf(1.0, a.distance_to(b))


## W / E / R gizmo modes, B draw on shapes, Delete and Ctrl+D for set pieces.
func _on_key(k: InputEventKey) -> bool:
	if not k.pressed or k.echo:
		return false
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if ctrl and k.keycode == KEY_D and select_kind == "prop":
		var id := Ops.duplicate_prop(selected_prop)
		if id != "":
			selected_prop = id
			selection_changed.emit()
		return true
	if ctrl or k.alt_pressed:
		return false
	match k.keycode:
		KEY_W:
			set_gizmo_mode("move")
		KEY_E:
			set_gizmo_mode("rotate")
		KEY_R:
			set_gizmo_mode("scale")
		KEY_B:
			set_paint_mode(not paint_mode)
		KEY_DELETE, KEY_BACKSPACE:
			if select_kind != "prop":
				return false
			Ops.delete_prop(selected_prop)
			select_kind = "layer"
			selection_changed.emit()
		KEY_ESCAPE:
			if paint_mode:
				set_paint_mode(false)
			elif select_kind != "layer":
				select_kind = "layer"
				selection_changed.emit()
				refresh()
			else:
				return false
		_:
			return false
	return true


func select_prop(id: String) -> void:
	select_kind = "prop"
	selected_prop = id
	selection_changed.emit()
	refresh()


func _press(pos: Vector2) -> void:
	var s := App.current_scene()
	if paint_mode:
		if _begin_paint(pos):
			return
		if not through_camera:
			_orbiting = true
		return
	var handle := _handle_at(pos)
	if handle >= 0:
		_drag_axis = handle
		_begin_drag(pos)
		return
	# Lamp, props, then drawings.
	if not through_camera and str(s.stage_value("light")) == "lamp":
		var lp := editor_cam.unproject_position(_lamp.position)
		if not editor_cam.is_position_behind(_lamp.position) and lp.distance_to(pos) < UI.px(14):
			select_kind = "lamp"
			selection_changed.emit()
			refresh()
			return
	var prop_hit := _prop_hit(pos)
	var hit := pick_layer(pos)
	var prop_dist := INF
	var layer_dist := INF
	if not prop_hit.is_empty():
		prop_dist = float(prop_hit["dist"])
	if hit >= 0:
		var mi: MeshInstance3D = _planes[s.layers[hit].id]
		layer_dist = active_camera().global_position.distance_to(mi.global_position)
	if not prop_hit.is_empty() and prop_dist < layer_dist:
		select_prop(str(prop_hit["id"]))
		return
	if hit >= 0:
		select_kind = "layer"
		App.set_layer(hit)
		var l := App.current_layer()
		if l.locked:
			App.status("“%s” is locked" % l.name)
		else:
			_drag_layer = l
			_drag_values = l.motion_at(App.frame)
			_drag_start = _drag_values.duplicate()
		selection_changed.emit()
		refresh()
	elif not through_camera:
		_orbiting = true


func _begin_drag(pos: Vector2) -> void:
	var s := App.current_scene()
	_drag_stage_before = s.stage.duplicate(true)
	_drag_accum = 0.0
	_drag_uniform = 1.0
	var gc: Variant = gizmo_center()
	if gc != null:
		var c: Vector3 = gc
		_drag_angle_prev = (pos - editor_cam.unproject_position(c)).angle()
	if select_kind == "prop":
		var p := find_prop(selected_prop)
		_drag_origin = _vec3(p.get("pos"), Vector3.ZERO)
		_drag_rot_start = _vec3(p.get("rot"), Vector3.ZERO)
		_drag_size_start = _vec3(p.get("size"), Vector3.ONE)
	elif select_kind == "lamp":
		_drag_origin = _vec3(s.stage_value("lamp_pos"), Vector3.ZERO)
	if select_kind == "layer":
		var l := App.current_layer()
		if l != null and not l.locked:
			_drag_layer = l
			_drag_values = l.motion_at(App.frame)
			_drag_start = _drag_values.duplicate()


func _release() -> void:
	var s := App.current_scene()
	if _painting:
		_end_paint()
	elif _drag_layer != null:
		var l := _drag_layer
		var v := {}
		for k in ["x", "y", "depth", "rotation", "turn", "tilt", "scale"]:
			var nv := float(_drag_values.get(k, 0.0))
			if absf(nv - float(_drag_start.get(k, nv))) > 0.0001:
				v[k] = nv
		_drag_layer = null
		_drag_values = {}
		if not v.is_empty():
			var what := {"move": "Move", "rotate": "Rotate", "scale": "Scale"}
			Ops.set_layer_motion(l, v, "%s layer in 3D (%s)" % [str(what.get(_eff_mode(), "Move")), l.name])
	elif _drag_axis >= 0 and (select_kind == "prop" or select_kind == "lamp"):
		var what2 := {"move": "Move", "rotate": "Rotate", "scale": "Resize"}
		Ops.commit_stage_edit(s, _drag_stage_before, "%s %s" % [str(what2.get(_eff_mode(), "Move")), "set piece" if select_kind == "prop" else "lamp"])
	_drag_axis = -1
	_orbiting = false
	refresh()


## Drags the grabbed gizmo handle.
func _drag_handle(pos: Vector2, rel: Vector2) -> void:
	var gc: Variant = gizmo_center()
	if gc == null:
		return
	var c: Vector3 = gc
	var s := App.current_scene()
	var snap := bool(s.stage_value("snap")) and not Input.is_key_pressed(KEY_ALT)
	var mode := _eff_mode()
	if mode == "rotate":
		_drag_rotate(pos, c, snap)
	elif mode == "scale":
		_drag_scale(rel, c, snap)
	else:
		_drag_along_axis(rel, c, snap)
	refresh()
	selection_changed.emit()


## Mouse movement along an axis's on-screen direction, in world units.
func _axis_amount(rel: Vector2, c: Vector3, dirv: Vector3) -> float:
	var a := editor_cam.unproject_position(c)
	var b := editor_cam.unproject_position(c + dirv)
	var screen_dir := b - a
	var l2 := screen_dir.length_squared()
	if l2 < 0.0001:
		return 0.0
	return rel.dot(screen_dir) / l2


func _drag_along_axis(rel: Vector2, c: Vector3, snap: bool) -> void:
	var dirv := Vector3.ZERO
	dirv[_drag_axis] = 1.0
	var amount := _axis_amount(rel, c, dirv)
	var s := App.current_scene()
	match select_kind:
		"layer":
			if _drag_layer == null:
				return
			var k := depth_factor(_drag_layer, float(_drag_values["depth"]))
			match _drag_axis:
				0:
					_drag_values["x"] = float(_drag_values["x"]) + amount * PX / k
				1:
					_drag_values["y"] = float(_drag_values["y"]) - amount * PX / k
				2:
					_drag_values["depth"] = maxf(-base_dist() + 1.0, float(_drag_values["depth"]) - amount)
		"prop", "lamp":
			_drag_accum += amount
			var v := _drag_origin
			match _drag_axis:
				0:
					v.x = _snap(v.x + _drag_accum, snap)
				1:
					v.y = _snap(v.y + _drag_accum, snap)
				2:
					v.z = _snap(v.z - _drag_accum, snap)
			if select_kind == "lamp":
				s.stage["lamp_pos"] = [v.x, v.y, v.z]
			else:
				_set_live_prop("pos", [v.x, v.y, v.z])


func _drag_rotate(pos: Vector2, c: Vector3, snap: bool) -> void:
	var ang := (pos - editor_cam.unproject_position(c)).angle()
	var delta := wrapf(ang - _drag_angle_prev, -PI, PI)
	_drag_angle_prev = ang
	var axis := Vector3.ZERO
	axis[_drag_axis] = 1.0
	# Screen angles grow clockwise (y points down); flip when the axis faces us.
	var toward := axis.dot(editor_cam.global_position - c) > 0.0
	_drag_accum += -delta if toward else delta
	var total := snappedf(_drag_accum, deg_to_rad(15.0)) if snap else _drag_accum
	match select_kind:
		"prop":
			var r0 := _drag_rot_start
			var b := Basis(axis, total) * Basis.from_euler(Vector3(deg_to_rad(r0.x), deg_to_rad(r0.y), deg_to_rad(r0.z)))
			var e := b.get_euler()
			_set_live_prop("rot", [snappedf(rad_to_deg(e.x), 0.01), snappedf(rad_to_deg(e.y), 0.01), snappedf(rad_to_deg(e.z), 0.01)])
		"layer":
			if _drag_layer == null:
				return
			var deg := rad_to_deg(total)
			match _drag_axis:
				0:
					_drag_values["tilt"] = clampf(float(_drag_start.get("tilt", 0.0)) - deg, -89.0, 89.0)
				1:
					_drag_values["turn"] = clampf(float(_drag_start.get("turn", 0.0)) + deg, -89.0, 89.0)
				_:
					_drag_values["rotation"] = wrapf(float(_drag_start.get("rotation", 0.0)) - deg, -180.0, 180.0)


func _drag_scale(rel: Vector2, c: Vector3, snap: bool) -> void:
	if _drag_axis == 3:
		_drag_uniform = maxf(0.02, _drag_uniform * (1.0 + (rel.x - rel.y) * 0.006))
	else:
		_drag_accum += _axis_amount(rel, c, _handle_axes()[_drag_axis])
	match select_kind:
		"prop":
			var sz := _drag_size_start
			if _drag_axis == 3:
				sz *= _drag_uniform
				if snap:
					sz = Vector3(maxf(0.25, snappedf(sz.x, 0.25)), maxf(0.25, snappedf(sz.y, 0.25)), maxf(0.25, snappedf(sz.z, 0.25)))
			else:
				# Height grows upward from the floor; width and depth grow both ways.
				var grow := _drag_accum * (1.0 if _drag_axis == 1 else 2.0)
				var v := maxf(0.1, sz[_drag_axis] + grow)
				sz[_drag_axis] = maxf(0.25, snappedf(v, 0.25)) if snap else v
			_set_live_prop("size", [sz.x, sz.y, sz.z])
		"layer":
			if _drag_layer == null:
				return
			var f := _drag_uniform
			if _drag_axis != 3:
				f = maxf(0.05, 1.0 + _drag_accum / maxf(0.5, _gizmo_len()))
			var sc := maxf(0.05, float(_drag_start.get("scale", 1.0)) * f)
			_drag_values["scale"] = snappedf(sc, 0.05) if snap else sc


## Changes a field of the selected piece without an undo step (the drag
## records one step when it ends).
func _set_live_prop(field: String, value: Variant) -> void:
	var s := App.current_scene()
	var props: Array = s.stage_value("props")
	for item in props:
		var p: Dictionary = item
		if str(p.get("id", "")) == selected_prop:
			p[field] = value
	s.stage["props"] = props


# ================================================================ draw on shapes

## Nearest set piece under `pos`: {id, prop, dist, uv, tri, transform} or {}.
func _prop_hit(pos: Vector2) -> Dictionary:
	var s := App.current_scene()
	if s == null:
		return {}
	var cam := active_camera()
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	var best := {}
	var best_d := INF
	for item in s.stage_value("props"):
		var p: Dictionary = item
		var t := prop_transform(p)
		var inv := t.affine_inverse()
		var r := ShapeMesh.raycast(str(p.get("type", "box")), inv * o, inv.basis * d)
		if r.is_empty():
			continue
		var lp: Vector3 = r["point"]
		var dist := o.distance_to(t * lp)
		if dist < best_d:
			best_d = dist
			best = {"id": str(p.get("id", "")), "prop": p, "dist": dist, "uv": r["uv"], "tri": r["tri"], "transform": t}
	return best


func _paint_cel(id: String, create: bool) -> CelData:
	var s := App.current_scene()
	var cel: CelData = s.prop_paint.get(id)
	if cel == null and create:
		cel = CelData.create_blank(App.project.width, App.project.height)
		s.prop_paint[id] = cel
		_prop_key = ""  # make sure the paint shell is shown
		refresh()
	return cel


func _begin_paint(pos: Vector2) -> bool:
	var hit := _prop_hit(pos)
	if hit.is_empty():
		return false
	var id := str(hit["id"])
	if select_kind != "prop" or selected_prop != id:
		select_kind = "prop"
		selected_prop = id
		selection_changed.emit()
	if paint_erase and _paint_cel(id, false) == null:
		return true
	var cel := _paint_cel(id, true)
	_paint_prop = id
	_paint_before = cel.get_image().duplicate() as Image
	_painting = true
	_paint_last = pos
	_stamp_hit(hit, cel)
	_paint_updated(cel)
	return true


func _paint_to(pos: Vector2) -> void:
	var cel := _paint_cel(_paint_prop, false)
	if cel == null:
		return
	var dist := _paint_last.distance_to(pos)
	var steps := clampi(int(dist / 3.0), 1, 32)
	for i in steps:
		var sp := _paint_last.lerp(pos, float(i + 1) / steps)
		var hit := _prop_hit(sp)
		if hit.is_empty() or str(hit["id"]) != _paint_prop:
			continue
		_stamp_hit(hit, cel)
	_paint_last = pos
	_paint_updated(cel)


func _end_paint() -> void:
	_painting = false
	var cel := _paint_cel(_paint_prop, false)
	if cel != null and _paint_before != null:
		Ops.commit_prop_paint(App.current_scene(), _paint_prop, _paint_before, cel.get_image().duplicate() as Image, "Erase on shape" if paint_erase else "Draw on shape")
	_paint_before = null


func _paint_updated(cel: CelData) -> void:
	cel.mark_changed()
	var tex := cel.get_texture()
	if _paint_nodes.has(_paint_prop):
		var shell: MeshInstance3D = _paint_nodes[_paint_prop]
		(shell.material_override as StandardMaterial3D).albedo_texture = tex
	App.mark_modified()


## Stamps one dab where the ray hit, sized in world units (so it looks the
## same on big and small shapes).
func _stamp_hit(hit: Dictionary, cel: CelData) -> void:
	var p: Dictionary = hit["prop"]
	var t: Transform3D = hit["transform"]
	var mesh := ShapeMesh.unit(str(p.get("type", "box")))
	var verts: PackedVector3Array = mesh["verts"]
	var uvs: PackedVector2Array = mesh["uvs"]
	var i: int = hit["tri"]
	var img := cel.get_image()
	var isz := Vector2(img.get_size())
	var wa := (t * verts[i + 1] - t * verts[i]).cross(t * verts[i + 2] - t * verts[i]).length() * 0.5
	var ua := uvs[i + 1] * isz - uvs[i] * isz
	var ub := uvs[i + 2] * isz - uvs[i] * isz
	var uv_area := absf(ua.x * ub.y - ua.y * ub.x) * 0.5
	var density := sqrt(uv_area / maxf(wa, 1e-6))  # texture pixels per world unit
	var r := clampi(int(round(paint_size * density)), 1, 160)
	_ensure_brush(r)
	var uv: Vector2 = hit["uv"]
	var dst := Vector2i(uv * isz) - Vector2i(r, r)
	var rect := Rect2i(Vector2i.ZERO, _brush_img.get_size())
	if paint_erase:
		img.blit_rect_mask(_brush_clear, _brush_img, rect, dst)
	else:
		img.blend_rect(_brush_img, rect, dst)


func _ensure_brush(r: int) -> void:
	var col := App.color
	var key := "%d|%s|%s" % [r, col.to_html(true), str(paint_erase)]
	if key == _brush_key:
		return
	_brush_key = key
	var n := r * 2 + 1
	_brush_img = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	_brush_clear = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	_brush_clear.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var d := Vector2(x - r, y - r).length()
			var a := clampf(float(r) + 0.5 - d, 0.0, 1.0)
			var c := col
			c.a = col.a * a
			_brush_img.set_pixel(x, y, c)


static func _snap(v: float, on: bool) -> float:
	return snappedf(v, 0.5) if on else v


func _drag_move(rel: Vector2, depth_mode: bool) -> void:
	var layer := _drag_layer
	if not _planes.has(layer.id):
		return
	var mi: MeshInstance3D = _planes[layer.id]
	var cam := active_camera()
	var dist_to := maxf(0.5, cam.global_position.distance_to(mi.global_position))
	var world_per_px := 2.0 * dist_to * tan(deg_to_rad(cam.fov * 0.5)) / maxf(1.0, size.y)
	if depth_mode:
		var limit := -base_dist() + 1.0
		_drag_values["depth"] = maxf(limit, float(_drag_values["depth"]) - rel.y * world_per_px * 2.0)
	else:
		var k := depth_factor(layer, float(_drag_values["depth"]))
		_drag_values["x"] = float(_drag_values["x"]) + rel.x * world_per_px * PX / k
		_drag_values["y"] = float(_drag_values["y"]) + rel.y * world_per_px * PX / k
	refresh()


## Vertical offset (canvas px, for LayerData.offset.y / motion "y") that puts
## the bottom of the layer's drawing on the floor. Returns NAN if it has no art.
func floor_offset_for(layer: LayerData) -> float:
	var cel := layer.cel_at(App.frame)
	if cel == null:
		return NAN
	var used := cel.get_image().get_used_rect()
	if used.size.y <= 0:
		return NAN
	var m := layer.motion_at(App.frame)
	var k := depth_factor(layer, float(m["depth"]))
	var sc := float(m["scale"]) * k
	var h := float(App.project.height)
	var local_bottom := (h * 0.5 - used.end.y) / PX  # local y of the art's lowest pixel
	var world_y := floor_y() - local_bottom * sc
	return -world_y * PX / k


## Returns the index of the topmost visible layer whose painted pixels are
## under `pos` (viewport coordinates), or -1.
func pick_layer(pos: Vector2) -> int:
	var s := App.current_scene()
	if s == null:
		return -1
	var cam := active_camera()
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	var best := -1
	var best_dist := INF
	for i in s.layers.size():
		var layer: LayerData = s.layers[i]
		if not _planes.has(layer.id):
			continue
		var mi: MeshInstance3D = _planes[layer.id]
		if not mi.visible:
			continue
		var inv := mi.global_transform.affine_inverse()
		var lo := inv * o
		var ld := inv.basis * d
		if absf(ld.z) < 0.000001:
			continue
		var t := -lo.z / ld.z
		if t <= 0.0:
			continue
		var p := lo + ld * t
		var qs := plane_size()
		var u := p.x / qs.x + 0.5
		var v := 0.5 - p.y / qs.y
		if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
			continue
		var img: Image = null
		if layer.is_character():
			var tex := Rigs.texture_for(layer)
			img = tex.get_image() if tex != null else null
		else:
			var cel := layer.cel_at(App.frame)
			img = cel.get_image() if cel != null else null
		if img == null or img.is_empty():
			continue
		var px := Vector2i(int(u * (img.get_width() - 1)), int(v * (img.get_height() - 1)))
		if img.get_pixelv(px).a < 0.08:
			continue
		var hit_dist := o.distance_to(mi.global_transform * p)
		if hit_dist < best_dist:
			best_dist = hit_dist
			best = i
	return best


## Returns the id of the nearest set piece under `pos`, or "".
func pick_prop(pos: Vector2) -> String:
	var hit := _prop_hit(pos)
	return "" if hit.is_empty() else str(hit["id"])
