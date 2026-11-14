class_name MatteProcessor
extends SubViewport
## Video import "Elements": decides which parts of each frame become the
## layer. GPU passes in one render: key (background difference / colour /
## brightness + keep-box) → BackBufferCopy → cleanup (fill holes, remove
## specks, smooth or grow the edge). Also builds clean background plates
## (per-pixel median of 9 frames) for "Remove still background".

const KEY_SHADER := preload("res://shaders/matte_key.gdshader")
const CLEAN_SHADER := preload("res://shaders/matte_clean.gdshader")
const MEDIAN_SHADER := preload("res://shaders/matte_median.gdshader")

const MODES := ["everything", "background", "colour", "light", "dark", "subject"]

var _tex: ImageTexture
var _source: TextureRect
var _key_mat: ShaderMaterial
var _clean_mat: ShaderMaterial
var _clean_rect: ColorRect
var _plate_tex: ImageTexture
var _lut_tex: ImageTexture
var _mask_tex: ImageTexture

var _plate_vp: SubViewport
var _plate_rect: ColorRect
var _plate_mat: ShaderMaterial
var _plate_inputs: Array[ImageTexture] = []


func _init() -> void:
	transparent_bg = true
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tex = ImageTexture.new()
	_plate_tex = ImageTexture.new()
	_lut_tex = ImageTexture.new()
	_mask_tex = ImageTexture.new()
	_source = TextureRect.new()
	_source.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_source.stretch_mode = TextureRect.STRETCH_SCALE
	_key_mat = ShaderMaterial.new()
	_key_mat.shader = KEY_SHADER
	_source.material = _key_mat
	add_child(_source)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	_clean_rect = ColorRect.new()
	_clean_mat = ShaderMaterial.new()
	_clean_mat.shader = CLEAN_SHADER
	_clean_rect.material = _clean_mat
	add_child(_clean_rect)

	_plate_vp = SubViewport.new()
	_plate_vp.disable_3d = true
	_plate_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_plate_vp)
	_plate_rect = ColorRect.new()
	_plate_mat = ShaderMaterial.new()
	_plate_mat.shader = MEDIAN_SHADER
	_plate_rect.material = _plate_mat
	_plate_vp.add_child(_plate_rect)
	for i in 9:
		_plate_inputs.append(ImageTexture.new())


static func is_active(settings: Dictionary) -> bool:
	if str(settings.get("mode", "everything")) != "everything":
		return true
	return bool(settings.get("crop", false))


## settings (all at 1080p scale): {mode, threshold, softness, key_color,
## spill, invert, cleanup, grow, crop, box: Rect2 (0..1), feather}
func setup(w: int, h: int, settings: Dictionary) -> void:
	size = Vector2i(maxi(16, w), maxi(16, h))
	_source.size = Vector2(size)
	_clean_rect.size = Vector2(size)
	var k := h / 1080.0
	var mode_name := str(settings.get("mode", "everything"))
	_key_mat.set_shader_parameter("mode", maxi(0, MODES.find(mode_name)))
	_key_mat.set_shader_parameter("plate", _plate_tex)
	_key_mat.set_shader_parameter("threshold", float(settings.get("threshold", 0.12)))
	_key_mat.set_shader_parameter("softness", float(settings.get("softness", 0.06)))
	var kc: Color = settings.get("key_color", Color(0, 1, 0))
	_key_mat.set_shader_parameter("key_color", Vector3(kc.r, kc.g, kc.b))
	_key_mat.set_shader_parameter("spill", float(settings.get("spill", 0.6)))
	_key_mat.set_shader_parameter("invert", bool(settings.get("invert", false)))
	if bool(settings.get("crop", false)):
		var b: Rect2 = settings.get("box", Rect2(0, 0, 1, 1))
		_key_mat.set_shader_parameter("box", Vector4(b.position.x, b.position.y, b.end.x, b.end.y))
		_key_mat.set_shader_parameter("box_feather", float(settings.get("feather", 0.0)))
	else:
		_key_mat.set_shader_parameter("box", Vector4(-1, -1, 2, 2))
		_key_mat.set_shader_parameter("box_feather", 0.0)
	_key_mat.set_shader_parameter("subject_lut", _lut_tex)
	_key_mat.set_shader_parameter("subject_mask", _mask_tex)
	_key_mat.set_shader_parameter("edge_detail", float(settings.get("edge_detail", 0.7)))
	_clean_mat.set_shader_parameter("radius", float(settings.get("cleanup", 2.0)) * k)
	_clean_mat.set_shader_parameter("grow", float(settings.get("grow", 0.0)))


## Subject mode: the colour lookup (64×64) and this frame's low-res mask.
func set_subject(lut: Image, mask: Image) -> void:
	if lut != null:
		_set_tex(_lut_tex, lut)
	if mask != null:
		_set_tex(_mask_tex, mask)
		_key_mat.set_shader_parameter("mask_texel", Vector2(1.0 / mask.get_width(), 1.0 / mask.get_height()))


static func _set_tex(t: ImageTexture, img: Image) -> void:
	if t.get_image() != null and t.get_size() == Vector2(img.get_size()) and t.get_format() == img.get_format():
		t.update(img)
	else:
		t.set_image(img)


func has_plate() -> bool:
	return _plate_tex.get_width() > 0


## Builds the clean background from sample frames (canvas-sized images).
func build_plate(images: Array) -> void:
	if images.is_empty():
		return
	var first: Image = images[0]
	_plate_vp.size = Vector2i(first.get_width(), first.get_height())
	_plate_rect.size = Vector2(_plate_vp.size)
	for i in 9:
		var img: Image = images[int(float(i) / 9.0 * images.size()) % images.size()]
		_plate_inputs[i].set_image(img)
		_plate_mat.set_shader_parameter("f%d" % i, _plate_inputs[i])
	_plate_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var plate := _plate_vp.get_texture().get_image()
	plate.convert(Image.FORMAT_RGBA8)
	_plate_tex.set_image(plate)


## Returns the frame with everything not kept made transparent.
func process(img: Image) -> Image:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if _tex.get_width() == img.get_width() and _tex.get_height() == img.get_height():
		_tex.update(img)
	else:
		_tex.set_image(img)
	_source.texture = _tex
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	return get_texture().get_image()
