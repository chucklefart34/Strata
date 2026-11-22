class_name InbetweenProcessor
extends Node
## Auto in-betweens without AI: finds how the lines moved from one keyframe
## drawing to the next (coarse-to-fine matching on blurred ink, on the GPU),
## then draws the frames between as motion in-betweens, smears, wipes or
## fades.

const FLOW_SHADER := preload("res://shaders/drawing_flow.gdshader")
const GEN_SHADER := preload("res://shaders/inbetween.gdshader")
const STYLES := ["motion", "smear", "wipe", "fade"]
const COARSE_MAX := 32.0
const FINE_MAX := 80.0

var _flow_vp: SubViewport
var _flow_rect: TextureRect
var _flow_mat: ShaderMaterial
var _gen_vp: SubViewport
var _gen_rect: TextureRect
var _gen_mat: ShaderMaterial
var _tex_a := ImageTexture.new()
var _tex_b := ImageTexture.new()
var _flow_tex := ImageTexture.new()
var _wipe_dir := Vector2.RIGHT
var _wipe_range := Vector2(-0.7, 0.7)
var _size := Vector2i(1920, 1080)


func _ready() -> void:
	_flow_vp = _make_vp()
	_flow_rect = TextureRect.new()
	_flow_mat = ShaderMaterial.new()
	_flow_mat.shader = FLOW_SHADER
	_flow_rect.material = _flow_mat
	_flow_vp.add_child(_flow_rect)
	_gen_vp = _make_vp()
	_gen_vp.transparent_bg = true
	_gen_rect = TextureRect.new()
	_gen_mat = ShaderMaterial.new()
	_gen_mat.shader = GEN_SHADER
	_gen_rect.material = _gen_mat
	_gen_vp.add_child(_gen_rect)


func _make_vp() -> SubViewport:
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	return vp


## Full-size ink density of a drawing: 1 = ink, 0 = paper (L8).
static func ink_map(img: Image) -> Image:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var flat := Image.create_empty(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color.WHITE)
	flat.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	flat.convert(Image.FORMAT_L8)
	var d := flat.get_data()
	for i in d.size():
		d[i] = 255 - d[i]
	return Image.create_from_data(flat.get_width(), flat.get_height(), false, Image.FORMAT_L8, d)


## The ink map at `sz`, softly blurred and boosted so matching has
## something to grip on near thin lines.
static func density(ink: Image, sz: Vector2i, blur: float) -> Image:
	var den := ink.duplicate() as Image
	den.resize(sz.x, sz.y, Image.INTERPOLATE_LANCZOS)
	if blur > 1.0:
		var small := Vector2i(maxi(2, int(sz.x / blur)), maxi(2, int(sz.y / blur)))
		den.resize(small.x, small.y, Image.INTERPOLATE_LANCZOS)
		den.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
	var dd := den.get_data()
	for i in dd.size():
		dd[i] = mini(255, dd[i] * 3)
	return Image.create_from_data(sz.x, sz.y, false, Image.FORMAT_L8, dd)


## Studies two keyframes. Call before `frame()`.
func prepare(a: Image, b: Image) -> void:
	_size = a.get_size()
	var ink_a := ink_map(a)
	var ink_b := ink_map(b)
	var coarse := Vector2i(maxi(16, _size.x / 8), maxi(16, _size.y / 8))
	var fine := Vector2i(maxi(16, _size.x / 4), maxi(16, _size.y / 4))
	# coarse pass: big moves
	var ca := ImageTexture.create_from_image(density(ink_a, coarse, 3.0))
	var cb := ImageTexture.create_from_image(density(ink_b, coarse, 3.0))
	var coarse_flow := await _flow(ca, cb, coarse, null, COARSE_MAX, 24.0, COARSE_MAX)
	# fine pass: follow each line closely, starting from the coarse result
	var fa := ImageTexture.create_from_image(density(ink_a, fine, 2.0))
	var fb := ImageTexture.create_from_image(density(ink_b, fine, 2.0))
	var fine_flow := await _flow(fa, fb, fine, ImageTexture.create_from_image(coarse_flow), FINE_MAX, 8.0, COARSE_MAX)
	# smooth the motion so neighbouring lines move together
	fine_flow.resize(maxi(2, fine.x / 3), maxi(2, fine.y / 3), Image.INTERPOLATE_BILINEAR)
	fine_flow.resize(fine.x, fine.y, Image.INTERPOLATE_BILINEAR)
	_flow_tex.set_image(fine_flow)
	_measure_direction(fine_flow, density(ink_b, fine, 1.0), density(ink_a, fine, 1.0))
	var ia := a.duplicate() as Image
	ia.convert(Image.FORMAT_RGBA8)
	var ib := b.duplicate() as Image
	ib.convert(Image.FORMAT_RGBA8)
	_tex_a.set_image(ia)
	_tex_b.set_image(ib)


func _flow(ta: Texture2D, tb: Texture2D, sz: Vector2i, init: Texture2D, out_max: float, search: float, init_max: float) -> Image:
	_flow_vp.size = sz
	_flow_rect.size = Vector2(sz)
	_flow_rect.texture = tb
	_flow_mat.set_shader_parameter("cur_tex", tb)
	_flow_mat.set_shader_parameter("prev_tex", ta)
	_flow_mat.set_shader_parameter("has_init", init != null)
	if init != null:
		_flow_mat.set_shader_parameter("init_tex", init)
	_flow_mat.set_shader_parameter("init_max", init_max)
	_flow_mat.set_shader_parameter("init_scale", 2.0)
	_flow_mat.set_shader_parameter("max_motion", out_max)
	_flow_mat.set_shader_parameter("search", search)
	_flow_mat.set_shader_parameter("res", Vector2(sz))
	_flow_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _flow_vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Main direction of movement (weighted by ink), for wipes.
func _measure_direction(flow: Image, den_b: Image, den_a: Image) -> void:
	var f := flow.get_data()
	var db := den_b.get_data()
	var da := den_a.get_data()
	var w := flow.get_width()
	var h := flow.get_height()
	var sum := Vector2.ZERO
	var lo := INF
	var hi := -INF
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var i := y * w + x
			var ink := maxi(db[i], da[i])
			if ink < 40:
				continue
			var d := Vector2((f[i * 4] / 255.0 - 0.5), (f[i * 4 + 1] / 255.0 - 0.5)) * 2.0 * FINE_MAX
			sum += d * ink
	_wipe_dir = sum.normalized() if sum.length() > 0.001 else Vector2.RIGHT
	# how far the drawing spreads along that direction (in UV, centred)
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var i := y * w + x
			if maxi(db[i], da[i]) < 40:
				continue
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(w, h) - Vector2(0.5, 0.5)
			var proj := p.dot(_wipe_dir)
			lo = minf(lo, proj)
			hi = maxf(hi, proj)
	_wipe_range = Vector2(lo, hi) if hi > lo else Vector2(-0.7, 0.7)


## One in-between at `t` (0 = first keyframe, 1 = next).
func frame(t: float, style: String, smear: float) -> Image:
	_gen_vp.size = _size
	_gen_rect.size = Vector2(_size)
	_gen_rect.texture = _tex_a
	_gen_mat.set_shader_parameter("tex_a", _tex_a)
	_gen_mat.set_shader_parameter("tex_b", _tex_b)
	_gen_mat.set_shader_parameter("flow_tex", _flow_tex)
	_gen_mat.set_shader_parameter("flow_max", FINE_MAX)
	_gen_mat.set_shader_parameter("flow_scale", float(_size.x) / float(maxi(1, _flow_tex.get_width())))
	_gen_mat.set_shader_parameter("res", Vector2(_size))
	_gen_mat.set_shader_parameter("t", t)
	_gen_mat.set_shader_parameter("mode", maxi(0, STYLES.find(style)))
	_gen_mat.set_shader_parameter("smear", smear)
	_gen_mat.set_shader_parameter("wipe_dir", _wipe_dir)
	_gen_mat.set_shader_parameter("wipe_range", _wipe_range)
	_gen_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var out := _gen_vp.get_texture().get_image()
	out.convert(Image.FORMAT_RGBA8)
	return out
