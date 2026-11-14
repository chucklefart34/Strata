class_name CaptureWorkspace
extends Control
## Stop motion: shoot frames with a camera connected to the computer (or add
## photos you shot on a phone/DSLR), with onion skin over the live picture,
## then retouch and draw over them in Draw / Animate like any 2D scene.
##
## Photos go on the chosen layer (the scene's "Photos" layer by default),
## one after another, each held for "Each photo lasts" frames.

const SHADER_CODE := """
shader_type canvas_item;
// Camera feed → RGB, mirrored if asked, cropped to fill the canvas.
uniform sampler2D tex_a : filter_linear;   // RGB image, or Y plane, or packed YCbCr
uniform sampler2D tex_b : filter_linear;   // CbCr plane (separate mode)
uniform int mode = 0;                      // 0 RGB, 1 packed YCbCr, 2 Y + CbCr planes
uniform bool mirror = false;
uniform int rotate = 0;                    // quarter turns (tablet cameras can arrive sideways)
uniform vec2 crop_scale = vec2(1.0);
void fragment() {
	vec2 uv = UV;
	if (mirror) { uv.x = 1.0 - uv.x; }
	uv = (uv - 0.5) * crop_scale + 0.5;
	if (rotate == 1) { uv = vec2(uv.y, 1.0 - uv.x); }
	else if (rotate == 2) { uv = vec2(1.0 - uv.x, 1.0 - uv.y); }
	else if (rotate == 3) { uv = vec2(1.0 - uv.y, uv.x); }
	vec3 c;
	if (mode == 0) {
		c = texture(tex_a, uv).rgb;
	} else {
		float y;
		vec2 cbcr;
		if (mode == 1) {
			vec3 t = texture(tex_a, uv).rgb;
			y = t.r;
			cbcr = t.gb;
		} else {
			y = texture(tex_a, uv).r;
			cbcr = texture(tex_b, uv).rg;
		}
		cbcr -= vec2(0.5);
		c = vec3(y + 1.402 * cbcr.y, y - 0.344 * cbcr.x - 0.714 * cbcr.y, y + 1.772 * cbcr.x);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""


## The big picture: live camera (or the frame at the playhead) with onion
## skin, a framing grid and a "flip" to compare with the last photo.
class CaptureView extends Control:
	var ws: CaptureWorkspace

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.DESK)
		if not App.has_project():
			return
		var r := ws.image_rect(size)
		draw_rect(r, Color.BLACK)
		var layer := ws.target_layer()
		var live := ws.live_texture()
		var show_live := live != null and not App.playing and not ws.flip_held and ws.at_end()
		if show_live:
			draw_texture_rect(live, r, false)
			if ws.onion_count > 0 and layer != null:
				var keys := ws.photo_keys()
				var n := mini(ws.onion_count, keys.size())
				for i in range(n, 0, -1):
					var k: int = keys[keys.size() - i]
					var cel: CelData = layer.cels[k]
					var a := ws.onion_opacity / float(i)
					draw_texture_rect(cel.get_texture(), r, false, Color(1, 1, 1, a))
		elif layer != null:
			var cel := layer.cel_at(App.frame) if not ws.flip_held else ws.last_photo()
			if cel != null:
				draw_texture_rect(cel.get_texture(), r, false)
			elif live == null:
				_center_text(r, "No photos yet")
		else:
			_center_text(r, "Add a layer for the photos")
		if live == null and ws.at_end() and not App.playing:
			_center_text(Rect2(r.position + Vector2(0, r.size.y * 0.75), Vector2(r.size.x, r.size.y * 0.25)), ws.camera_message)
		if ws.show_grid:
			var c := Color(1, 1, 1, 0.35)
			for i in range(1, 3):
				var x := r.position.x + r.size.x * i / 3.0
				var y := r.position.y + r.size.y * i / 3.0
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), c, 1.0)
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), c, 1.0)
		draw_rect(r, Color(0, 0, 0, 0.4), false, 1.0)
		var label := "LIVE" if show_live else ("LAST PHOTO" if ws.flip_held else "FRAME %d" % (App.frame + 1))
		var font := get_theme_default_font()
		var fs := int(UI.px(12))
		draw_string(font, r.position + Vector2(UI.px(10), UI.px(20)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ff5f56") if show_live else Palette.TEXT)

	func _center_text(r: Rect2, text: String) -> void:
		var font := get_theme_default_font()
		var fs := int(UI.px(13))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, r.get_center() - Vector2(w * 0.5, -fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.DIM)

	func _gui_input(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed:
			grab_focus()
		var k := e as InputEventKey
		if k != null and ws.handle_key(k):
			accept_event()


var view: CaptureView
var onion_count: int = 1
var onion_opacity: float = 0.45
var show_grid: bool = false
var flip_held: bool = false
var camera_message: String = "Looking for cameras…"

var _feed: CameraFeed = null
var _cam_vp: SubViewport
var _cam_rect: TextureRect
var _cam_mat: ShaderMaterial
var _tex_a: CameraTexture
var _tex_b: CameraTexture
var _colour_override: int = -1  # -1 automatic, else shader mode
var _rotate: int = 0
var _camera_pick: OptionButton
var _colour_pick: OptionButton
var _start_btn: Button
var _layer_pick: OptionButton
var _hold: SpinBox
var _mirror: CheckBox
var _info: Label
var _strip: HBoxContainer
var _strip_key: String = ""
var _feed_ids: Array = []
var _poll: Timer
var _files_dialog: FileDialog


func _ready() -> void:
	var root := UI.hbox(10)
	UI.full_rect(root)
	add_child(root)

	var center := UI.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	center.add_child(HintBar.new("capture", "Set up your shot, then press Capture (Space or Enter) for each frame. The last photo shows faintly over the live picture (onion skin) so you can see how far to move things. Hold F to flip to the last photo. Retouch or draw over frames in Draw and Animate."))
	var frame := PanelContainer.new()
	frame.theme_type_variation = "CanvasFrame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(frame)
	view = CaptureView.new()
	view.ws = self
	view.focus_mode = Control.FOCUS_ALL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_child(view)

	var controls := UI.hbox(8)
	center.add_child(controls)
	var capture := UI.button("Capture", "camera", "Take a photo and add it as the next frame (Space / Enter)", "AccentButton")
	capture.custom_minimum_size = UI.size2(140, 40)
	capture.pressed.connect(capture_frame)
	controls.add_child(capture)
	var undo_btn := UI.button("Delete last", "trash", "Remove the last photo (Backspace)", "FlatButton")
	undo_btn.pressed.connect(delete_last)
	controls.add_child(undo_btn)
	var replace := UI.button("Retake this frame", "reset", "Replace the photo at the playhead with a new one", "FlatButton")
	replace.pressed.connect(retake)
	controls.add_child(replace)
	controls.add_child(UI.vsep())
	var play := UI.button("Play", "play", "Play the animation so far (P)", "FlatButton")
	play.pressed.connect(App.toggle_play)
	controls.add_child(play)
	var live := UI.button("Back to live", "camera", "Jump to the end, ready for the next photo", "FlatButton")
	live.pressed.connect(go_live)
	controls.add_child(live)
	controls.add_child(UI.spacer())
	_info = UI.label("", "Muted")
	controls.add_child(_info)

	var strip_scroll := ScrollContainer.new()
	strip_scroll.custom_minimum_size.y = UI.px(84)
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(strip_scroll)
	_strip = UI.hbox(4)
	strip_scroll.add_child(_strip)

	# ---------------------------------------------------------- side panel
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = UI.px(300)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(side_scroll)
	var side := UI.vbox(10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)

	var cam := UI.section(side, "Camera")
	_camera_pick = OptionButton.new()
	_camera_pick.item_selected.connect(_on_camera_picked)
	cam.add_child(_camera_pick)
	_start_btn = UI.button("Start camera", "camera", "Turn the selected camera on or off", "Button")
	_start_btn.pressed.connect(_toggle_camera)
	cam.add_child(_start_btn)
	_mirror = CheckBox.new()
	_mirror.text = "Mirror (for a front-facing webcam)"
	_mirror.focus_mode = Control.FOCUS_NONE
	_mirror.toggled.connect(func(on: bool) -> void: _cam_mat.set_shader_parameter("mirror", on))
	cam.add_child(_mirror)
	var crow := UI.hbox(6)
	cam.add_child(crow)
	crow.add_child(UI.label("Colours", "FieldLabel"))
	_colour_pick = UI.option(["Automatic", "RGB", "YCbCr (packed)", "YCbCr (two planes)"])
	_colour_pick.tooltip_text = "If the picture looks green or purple, try another setting"
	_colour_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_colour_pick.item_selected.connect(func(i: int) -> void:
		_colour_override = i - 1
		_apply_feed_textures())
	crow.add_child(_colour_pick)
	var rrow := UI.hbox(6)
	cam.add_child(rrow)
	rrow.add_child(UI.label("Rotate", "FieldLabel"))
	var rot := UI.option(["None", "90°", "180°", "270°"])
	rot.tooltip_text = "If the picture arrives sideways or upside down"
	rot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot.item_selected.connect(func(i: int) -> void:
		_rotate = i
		_cam_mat.set_shader_parameter("rotate", i))
	rrow.add_child(rot)
	var note := UI.label("Uses cameras your computer can see (webcams, capture cards, many DSLRs over USB). No camera? Shoot on your phone and use Add photos.", "Small")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cam.add_child(note)

	var shoot := UI.section(side, "Frames")
	var lrow := UI.hbox(6)
	shoot.add_child(lrow)
	lrow.add_child(UI.label("Photos go on", "FieldLabel"))
	_layer_pick = OptionButton.new()
	_layer_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_pick.item_selected.connect(func(_i: int) -> void:
		_strip_key = ""
		_refresh())
	lrow.add_child(_layer_pick)
	var hrow := UI.hbox(6)
	shoot.add_child(hrow)
	hrow.add_child(UI.label("Each photo lasts", "FieldLabel"))
	_hold = UI.spin(1, 12, 1, 1, " frame(s)")
	_hold.tooltip_text = "1 = a new photo every frame (\"on ones\"), 2 = every other frame (\"on twos\", common at 24 fps)"
	_hold.value_changed.connect(func(_v: float) -> void: _refresh())
	hrow.add_child(_hold)
	var add_files := UI.button("Add photos from files…", "image", "Add a set of photos as frames, in file-name order", "Button")
	add_files.pressed.connect(func() -> void: _files_dialog.popup_centered_ratio(0.6))
	shoot.add_child(add_files)

	var onion := UI.section(side, "Onion skin")
	UI.slider(onion, "Photos shown", 0, 3, 1, 1, _on_onion_count, "%d")
	UI.slider(onion, "Strength", 5, 90, 1, 45, _on_onion_opacity, "%d%%")
	var grid := CheckBox.new()
	grid.text = "Framing grid (thirds)"
	grid.focus_mode = Control.FOCUS_NONE
	grid.toggled.connect(func(on: bool) -> void:
		show_grid = on
		view.queue_redraw())
	onion.add_child(grid)
	var keys := UI.label("Keys: Space / Enter capture · Backspace delete last · P play · F (hold) flip to last photo · O onion on/off", "Small")
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	onion.add_child(keys)

	_files_dialog = FileDialog.new()
	_files_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_files_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_files_dialog.use_native_dialog = true
	_files_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga ; Photos"])
	_files_dialog.files_selected.connect(_on_files)
	add_child(_files_dialog)

	# Camera picture is rendered at canvas size so captures match the project.
	_cam_vp = SubViewport.new()
	_cam_vp.disable_3d = true
	_cam_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_cam_vp)
	_cam_rect = TextureRect.new()
	_cam_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cam_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_cam_mat = ShaderMaterial.new()
	_cam_mat.shader = shader
	_cam_rect.material = _cam_mat
	_cam_vp.add_child(_cam_rect)

	_poll = Timer.new()
	_poll.wait_time = 1.0
	_poll.timeout.connect(_refresh_feeds)
	add_child(_poll)

	for sig: Signal in [App.project_opened, App.scene_switched, App.layers_changed, App.timeline_changed, App.pixels_changed, App.frame_changed, App.playback_changed]:
		sig.connect(_refresh)
	visibility_changed.connect(_on_visibility)
	_refresh()


# ================================================================ camera

func _on_visibility() -> void:
	if is_visible_in_tree():
		_enable_monitoring()
		_refresh_feeds()
		_poll.start()
		_refresh()
		go_live()
		view.grab_focus.call_deferred()
	else:
		_poll.stop()
		_stop_camera()


func _enable_monitoring() -> void:
	# Newer Godot versions only list cameras while monitoring is on.
	if "monitoring_feeds" in CameraServer:
		CameraServer.set("monitoring_feeds", true)


func _refresh_feeds() -> void:
	var feeds := CameraServer.feeds()
	var ids: Array = []
	for f in feeds:
		var feed: CameraFeed = f
		ids.append(feed.get_id())
	if ids == _feed_ids:
		return
	_feed_ids = ids
	var keep := _feed.get_id() if _feed != null else -1
	_camera_pick.clear()
	for f in feeds:
		var feed: CameraFeed = f
		_camera_pick.add_item(feed.get_name() if feed.get_name() != "" else "Camera %d" % feed.get_id(), feed.get_id())
	if feeds.is_empty():
		camera_message = "No camera found — connect one, or use “Add photos from files…”"
		_camera_pick.add_item("No camera found", -1)
		_camera_pick.disabled = true
		_start_btn.disabled = true
		_stop_camera()
	else:
		_camera_pick.disabled = false
		_start_btn.disabled = false
		var idx := maxi(0, ids.find(keep))
		_camera_pick.select(idx)
		if _feed == null:
			camera_message = "Press “Start camera” to see the live picture"
	view.queue_redraw()


func _on_camera_picked(_i: int) -> void:
	var was_on := _feed != null
	_stop_camera()
	if was_on:
		_start_camera()


func _toggle_camera() -> void:
	if _feed != null:
		_stop_camera()
	else:
		_start_camera()


func _selected_feed() -> CameraFeed:
	var id := _camera_pick.get_selected_id()
	for f in CameraServer.feeds():
		var feed: CameraFeed = f
		if feed.get_id() == id:
			return feed
	return null


func _start_camera() -> void:
	var feed := _selected_feed()
	if feed == null:
		return
	# Newer Godot: pick the largest picture up to the canvas size first.
	if feed.has_method("get_formats") and feed.has_method("set_format"):
		var formats: Array = feed.call("get_formats")
		var best := -1
		var best_px := 0
		for i in formats.size():
			var fmt: Dictionary = formats[i]
			var w := int(fmt.get("width", 0))
			var h := int(fmt.get("height", 0))
			if w * h > best_px and w <= maxi(1920, App.project.width if App.has_project() else 1920):
				best_px = w * h
				best = i
		if best >= 0:
			feed.call("set_format", best, {})
	feed.feed_is_active = true
	_feed = feed
	_tex_a = CameraTexture.new()
	_tex_a.camera_feed_id = feed.get_id()
	_tex_a.which_feed = CameraServer.FEED_RGBA_IMAGE
	_tex_b = CameraTexture.new()
	_tex_b.camera_feed_id = feed.get_id()
	_tex_b.which_feed = CameraServer.FEED_CBCR_IMAGE
	_apply_feed_textures()
	_start_btn.text = "Stop camera"
	camera_message = "Starting the camera…"
	_cam_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)


func _stop_camera() -> void:
	if _feed != null:
		_feed.feed_is_active = false
	_feed = null
	_tex_a = null
	_tex_b = null
	if _start_btn != null:
		_start_btn.text = "Start camera"
	if _cam_vp != null:
		_cam_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	if view != null:
		view.queue_redraw()


func _apply_feed_textures() -> void:
	if _feed == null:
		return
	var mode := 0
	match _feed.get_datatype():
		CameraFeed.FEED_YCBCR:
			mode = 1
		CameraFeed.FEED_YCBCR_SEP:
			mode = 2
	if _colour_override >= 0:
		mode = _colour_override
	_cam_mat.set_shader_parameter("mode", mode)
	_cam_mat.set_shader_parameter("tex_a", _tex_a)
	_cam_mat.set_shader_parameter("tex_b", _tex_b)


func _process(_delta: float) -> void:
	if _feed == null or not App.has_project():
		return
	var vs := Vector2i(App.project.width, App.project.height)
	if _cam_vp.size != vs:
		_cam_vp.size = vs
		_cam_rect.size = Vector2(vs)
	var tw := _tex_a.get_width() if _tex_a != null else 0
	var th := _tex_a.get_height() if _tex_a != null else 0
	if _rotate % 2 == 1:
		var t := tw
		tw = th
		th = t
	if tw > 0 and th > 0:
		var fa := float(tw) / th
		var pa := float(vs.x) / vs.y
		_cam_mat.set_shader_parameter("crop_scale", Vector2(pa / fa, 1.0) if fa > pa else Vector2(1.0, fa / pa))
		camera_message = ""
	else:
		camera_message = "Waiting for the camera picture…"
	view.queue_redraw()


## The live picture (canvas-sized), or null when no camera is running.
func live_texture() -> Texture2D:
	if _feed == null or camera_message != "":
		return null
	return _cam_vp.get_texture()


# ================================================================ frames

func target_layer() -> LayerData:
	var s := App.current_scene() if App.has_project() else null
	if s == null or s.layers.is_empty():
		return null
	var idx := _layer_pick.get_selected_id()
	if idx >= 0 and idx < s.layers.size():
		return s.layers[idx]
	return null


func photo_keys() -> Array:
	var l := target_layer()
	return l.sorted_keys() if l != null else []


func last_photo() -> CelData:
	var keys := photo_keys()
	if keys.is_empty():
		return null
	var l := target_layer()
	return l.cels[keys[keys.size() - 1]]


func hold() -> int:
	return int(_hold.value) if _hold != null else 1


## Frame where the next photo goes.
func next_frame() -> int:
	var keys := photo_keys()
	if keys.is_empty():
		return 0
	return int(keys[keys.size() - 1]) + hold()


## True when the playhead is on or after the last photo (so live shows).
func at_end() -> bool:
	var keys := photo_keys()
	if keys.is_empty():
		return true
	return App.frame >= int(keys[keys.size() - 1])


func image_rect(area: Vector2) -> Rect2:
	if not App.has_project():
		return Rect2(Vector2.ZERO, area)
	var aspect := float(App.project.width) / App.project.height
	var pad := UI.px(8)
	var avail := area - Vector2(pad, pad) * 2.0
	var w := avail.x
	var h := w / aspect
	if h > avail.y:
		h = avail.y
		w = h * aspect
	return Rect2((area - Vector2(w, h)) * 0.5, Vector2(w, h))


func _grab_photo() -> Image:
	if live_texture() == null:
		App.status("Start a camera first (or use “Add photos from files…”)")
		return null
	var img := _cam_vp.get_texture().get_image()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func capture_frame() -> void:
	var l := target_layer()
	if l == null:
		App.status("Add a layer for the photos first")
		return
	if l.locked:
		App.status("“%s” is locked" % l.name)
		return
	var img := _grab_photo()
	if img == null:
		return
	var f := next_frame()
	Ops.add_photos(l, f, [img], hold(), "Capture frame")
	App.set_frame(f)
	App.status("Captured frame %d" % (photo_keys().size()))


func retake() -> void:
	var l := target_layer()
	if l == null:
		return
	var keys := photo_keys()
	if keys.is_empty():
		capture_frame()
		return
	var img := _grab_photo()
	if img == null:
		return
	var k := l.key_at_or_before(App.frame)
	if k < 0:
		k = int(keys[0])
	Ops.add_photos(l, k, [img], hold(), "Retake frame")
	App.status("Retook the photo at frame %d" % (k + 1))


func delete_last() -> void:
	var l := target_layer()
	var keys := photo_keys()
	if l == null or keys.is_empty():
		return
	var k: int = keys[keys.size() - 1]
	Ops.remove_photo(l, k, hold())
	go_live()


func go_live() -> void:
	if App.playing:
		App.stop()
	var keys := photo_keys()
	if not keys.is_empty():
		App.set_frame(int(keys[keys.size() - 1]))
	view.queue_redraw()


func _on_files(paths: PackedStringArray) -> void:
	var l := target_layer()
	if l == null:
		App.status("Add a layer for the photos first")
		return
	var list := Array(paths)
	list.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var w: int = App.project.width
	var h: int = App.project.height
	var images: Array = []
	for item in list:
		var path: String = item
		var src := Image.load_from_file(path)
		if src == null or src.is_empty():
			continue
		images.append(_fill_canvas(src, w, h))
	if images.is_empty():
		App.status("Couldn't read those photos")
		return
	var f := next_frame()
	Ops.add_photos(l, f, images, hold(), "Add %d photos" % images.size())
	App.status("Added %d photos as frames" % images.size())
	go_live()


## Scales a photo to cover the canvas and crops the overflow (centred).
static func _fill_canvas(src: Image, w: int, h: int) -> Image:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var k := maxf(float(w) / img.get_width(), float(h) / img.get_height())
	var nw := maxi(w, int(ceil(img.get_width() * k)))
	var nh := maxi(h, int(ceil(img.get_height() * k)))
	img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i((nw - w) / 2, (nh - h) / 2, w, h), Vector2i.ZERO)
	return out


func handle_key(k: InputEventKey) -> bool:
	if k.keycode == KEY_F:
		var was := flip_held
		flip_held = k.pressed
		if was != flip_held:
			view.queue_redraw()
		return true
	if not k.pressed or k.echo or k.ctrl_pressed or k.meta_pressed:
		return false
	match k.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			capture_frame()
		KEY_BACKSPACE, KEY_DELETE:
			delete_last()
		KEY_P:
			App.toggle_play()
		KEY_O:
			onion_count = 0 if onion_count > 0 else 1
			view.queue_redraw()
		_:
			return false
	return true


func _on_onion_count(v: float) -> void:
	onion_count = int(v)
	if view != null:
		view.queue_redraw()


func _on_onion_opacity(v: float) -> void:
	onion_opacity = v / 100.0
	if view != null:
		view.queue_redraw()


# ================================================================ panel sync

func _refresh() -> void:
	if not App.has_project() or App.current_scene() == null:
		return
	var s := App.current_scene()
	# Layer picker: keep the choice, default to "Photos".
	var names := PackedStringArray()
	for l in s.layers:
		names.append(l.name)
	var key := ",".join(names)
	if _layer_pick.item_count != s.layers.size() or str(_layer_pick.get_meta("key", "")) != key:
		var prev := _layer_pick.get_item_text(_layer_pick.selected) if _layer_pick.selected >= 0 else ""
		_layer_pick.clear()
		var pick := -1
		for i in s.layers.size():
			var l: LayerData = s.layers[i]
			_layer_pick.add_item(l.name, i)
			if l.name == prev:
				pick = i
		if pick < 0:
			for i in s.layers.size():
				var l: LayerData = s.layers[i]
				if l.name == "Photos":
					pick = i
		_layer_pick.select(maxi(0, pick))
		_layer_pick.set_meta("key", key)
	var count := photo_keys().size()
	var secs := float(next_frame()) / maxf(1.0, App.project.fps)
	_info.text = "%d photo%s · %.1f s at %d fps" % [count, "" if count == 1 else "s", secs, App.project.fps]
	_rebuild_strip()
	view.queue_redraw()


func _rebuild_strip() -> void:
	var l := target_layer()
	var keys := photo_keys()
	var shown: Array = keys.slice(maxi(0, keys.size() - 40))
	var cur := l.key_at_or_before(App.frame) if l != null else -1
	var key := "%s|%s|%d" % [str(l.get_instance_id()) if l != null else "", str(shown), cur]
	if key == _strip_key:
		return
	_strip_key = key
	for c in _strip.get_children():
		c.queue_free()
	if l == null:
		return
	for item in shown:
		var k: int = item
		var cel: CelData = l.cels[k]
		var b := Button.new()
		b.icon = cel.get_texture()
		b.expand_icon = true
		b.custom_minimum_size = UI.size2(112, 66)
		b.tooltip_text = "Frame %d" % (k + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = k == cur
		b.pressed.connect(App.set_frame.bind(k))
		_strip.add_child(b)
