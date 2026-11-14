class_name SceneFeed
extends SubViewport
## Renders "scene X at frame N through its camera" into a texture, using the
## shared 3D stage of the Depth workspace. Used by episode preview/render.

var depth: DepthView
var cam: Camera3D
var _env: Environment


func setup(p_depth: DepthView, w: int, h: int, always_render: bool = false) -> void:
	depth = p_depth
	size = Vector2i(maxi(16, w), maxi(16, h))
	world_3d = depth.world
	msaa_3d = Viewport.MSAA_4X
	if always_render:
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if cam == null:
		cam = Camera3D.new()
		cam.cull_mask = DepthView.ART_MASK
		_env = depth.make_environment(Palette.VIEWPORT_BG, false)
		cam.environment = _env
		add_child(cam)
	cam.current = true


## Switches the app to `scene_index` at `frame` and aims the camera.
func show_scene_frame(scene_index: int, frame: int) -> void:
	if not App.has_project():
		return
	App.set_scene(scene_index)
	var s := App.current_scene()
	App.set_frame(clampi(frame, 0, s.frame_count - 1))
	_env.background_color = s.bg_color
	_env.ambient_light_energy = float(s.stage_value("ambient"))
	depth.apply_haze(_env, s)
	depth.refresh()
	depth.apply_scene_camera(cam, App.frame, false)
