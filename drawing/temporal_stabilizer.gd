class_name TemporalStabilizer
extends Node
## Removes frame-to-frame flicker from a rotoscoped clip. For every pixel
## whose source colour hasn't changed (beyond a threshold) since the last time
## it was refreshed, the previous result is kept. A reference copy of the
## source is held alongside, so slow drifts still refresh once they add up.

const SHADER := preload("res://shaders/temporal_hold.gdshader")
const MOTION_SHADER := preload("res://shaders/video_motion.gdshader")
const MAX_MOTION := 48.0

var _out_vp: SubViewport
var _ref_vp: SubViewport
var _out_mat: ShaderMaterial
var _ref_mat: ShaderMaterial
var _t_cur_src: ImageTexture
var _t_ref_src: ImageTexture
var _t_cur_out: ImageTexture
var _t_prev_out: ImageTexture
var _ref_img: Image = null
var _prev_out: Image = null
var _prev_src: Image = null
var _t_prev_src: ImageTexture
var _motion_vp: SubViewport
var _motion_rect: ColorRect
var _motion_mat: ShaderMaterial


func _ready() -> void:
	_t_cur_src = ImageTexture.new()
	_t_ref_src = ImageTexture.new()
	_t_cur_out = ImageTexture.new()
	_t_prev_out = ImageTexture.new()
	_t_prev_src = ImageTexture.new()
	_out_mat = _make_vp("out")
	_ref_mat = _make_vp("ref")
	# Motion between the previous and this source frame (one vector per block),
	# so held results can follow movement.
	_motion_vp = SubViewport.new()
	_motion_vp.disable_3d = true
	_motion_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_motion_vp)
	_motion_rect = ColorRect.new()
	_motion_mat = ShaderMaterial.new()
	_motion_mat.shader = MOTION_SHADER
	_motion_rect.material = _motion_mat
	_motion_vp.add_child(_motion_rect)


func _make_vp(which: String) -> ShaderMaterial:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.disable_3d = true
	add_child(vp)
	var rect := ColorRect.new()
	rect.name = "Rect"
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	vp.add_child(rect)
	if which == "out":
		_out_vp = vp
	else:
		_ref_vp = vp
	return mat


## Call before a new clip.
func reset() -> void:
	_ref_img = null
	_prev_out = null
	_prev_src = null


## `src` is the frame that went into the rotoscope, `out` what came out.
## `steady` 0..1 sets how much change counts as "the same".
func process(src: Image, out: Image, steady: float, scale_k: float) -> Image:
	var first := _ref_img == null or _prev_out == null or _ref_img.get_size() != src.get_size()
	var sz := src.get_size()
	for vp in [_out_vp, _ref_vp]:
		var v: SubViewport = vp
		v.size = sz
		var r: ColorRect = v.get_node("Rect")
		r.size = Vector2(sz)
	_set_tex(_t_cur_src, src)
	_set_tex(_t_cur_out, out)
	_set_tex(_t_ref_src, src if first else _ref_img)
	_set_tex(_t_prev_out, out if first else _prev_out)
	var thr := lerpf(0.0, 0.16, clampf(steady, 0.0, 1.0))
	var ps := maxf(0.05, sz.y / 1080.0)
	var has_motion := not first and _prev_src != null and _prev_src.get_size() == src.get_size()
	if has_motion:
		_set_tex(_t_prev_src, _prev_src)
		var ms := Vector2i(maxi(8, int(ceil(sz.x / (8.0 * ps)))), maxi(8, int(ceil(sz.y / (8.0 * ps)))))
		_motion_vp.size = ms
		_motion_rect.size = Vector2(ms)
		_motion_mat.set_shader_parameter("cur_tex", _t_cur_src)
		_motion_mat.set_shader_parameter("prev_tex", _t_prev_src)
		_motion_mat.set_shader_parameter("prev_motion", _motion_vp.get_texture())
		_motion_mat.set_shader_parameter("res", Vector2(sz))
		_motion_mat.set_shader_parameter("ps", ps)
		_motion_mat.set_shader_parameter("max_motion", MAX_MOTION)
		_motion_mat.set_shader_parameter("has_prev", true)
		_motion_mat.set_shader_parameter("has_prev_motion", false)
		_motion_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
	for m in [_out_mat, _ref_mat]:
		var mat: ShaderMaterial = m
		mat.set_shader_parameter("cur_src", _t_cur_src)
		mat.set_shader_parameter("ref_src", _t_ref_src)
		mat.set_shader_parameter("threshold", thr)
		mat.set_shader_parameter("radius", maxf(1.0, 2.0 * scale_k))
		mat.set_shader_parameter("first_frame", first)
		mat.set_shader_parameter("texel", Vector2(1.0 / sz.x, 1.0 / sz.y))
		mat.set_shader_parameter("motion_tex", _motion_vp.get_texture())
		mat.set_shader_parameter("has_motion", has_motion)
		mat.set_shader_parameter("max_motion", MAX_MOTION)
		mat.set_shader_parameter("ps", ps)
	_out_mat.set_shader_parameter("fresh", _t_cur_out)
	_out_mat.set_shader_parameter("held", _t_prev_out)
	_ref_mat.set_shader_parameter("fresh", _t_cur_src)
	_ref_mat.set_shader_parameter("held", _t_ref_src)
	_out_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ref_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var result := _out_vp.get_texture().get_image()
	_ref_img = _ref_vp.get_texture().get_image()
	if result.get_format() != Image.FORMAT_RGBA8:
		result.convert(Image.FORMAT_RGBA8)
	_prev_out = result.duplicate() as Image
	_prev_src = src.duplicate() as Image
	return result


func _set_tex(t: ImageTexture, img: Image) -> void:
	if t.get_image() != null and t.get_size() == Vector2(img.get_size()):
		t.update(img)
	else:
		t.set_image(img)
