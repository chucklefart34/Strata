class_name ToonProcessor
extends SubViewport
## Auto-rotoscope: redraws an image as smooth flat colour shapes with traced
## ink lines on top, on the GPU. Two chains (each pass reads the previous one
## through a BackBufferCopy):
##   lines (inner viewport): source → light edge-preserving blur → XDoG trace
##                           → thicken → smooth & clean
##   fills (this viewport):  source → edge-preserving blur ×2 → palette snap + ink
##                           → shape smoothing ×3 → composite traced lines on top
## The lines come from the original frame, so smoothing the fills never
## removes them — it looks traced, with the colours sitting underneath.

const BILATERAL_SHADER := preload("res://shaders/toon_bilateral.gdshader")
const BLOCKS_SHADER := preload("res://shaders/toon_blocks.gdshader")
const MODE_SHADER := preload("res://shaders/toon_mode.gdshader")
const LINES_SHADER := preload("res://shaders/toon_lines.gdshader")
const XDOG_SHADER := preload("res://shaders/toon_xdog.gdshader")
const DILATE_SHADER := preload("res://shaders/toon_line_dilate.gdshader")
const LINE_SMOOTH_SHADER := preload("res://shaders/toon_line_smooth.gdshader")
const MODE_PASSES := 3
const MAX_COLORS := 32

var _tex: ImageTexture
var _source: TextureRect
var _bilateral: Array[ShaderMaterial] = []
var _blocks_mat: ShaderMaterial
var _mode: Array[ShaderMaterial] = []
var _lines_mat: ShaderMaterial
var _rects: Array[ColorRect] = []

var _line_vp: SubViewport
var _line_source: TextureRect
var _line_blur: ShaderMaterial
var _xdog: ShaderMaterial
var _dilate: ShaderMaterial
var _line_smooth: ShaderMaterial
var _line_rects: Array[ColorRect] = []


func _init() -> void:
	transparent_bg = true
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tex = ImageTexture.new()

	# --- line tracing chain (inner viewport, opaque mask) ---
	_line_vp = SubViewport.new()
	_line_vp.transparent_bg = false
	_line_vp.disable_3d = true
	_line_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_line_vp)
	_line_source = _make_source()
	_line_vp.add_child(_line_source)
	_line_blur = _add_pass(_line_vp, BILATERAL_SHADER, _line_rects)
	_xdog = _add_pass(_line_vp, XDOG_SHADER, _line_rects)
	_dilate = _add_pass(_line_vp, DILATE_SHADER, _line_rects)
	_line_smooth = _add_pass(_line_vp, LINE_SMOOTH_SHADER, _line_rects)

	# --- fill chain (this viewport) ---
	_source = _make_source()
	add_child(_source)
	for i in 2:
		_bilateral.append(_add_pass(self, BILATERAL_SHADER, _rects))
	_blocks_mat = _add_pass(self, BLOCKS_SHADER, _rects)
	for i in MODE_PASSES:
		_mode.append(_add_pass(self, MODE_SHADER, _rects))
	_lines_mat = _add_pass(self, LINES_SHADER, _rects)


func _make_source() -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


## Adds "copy what's drawn so far" + a full-frame rect running `shader` on it.
func _add_pass(parent: Node, shader: Shader, rects: Array[ColorRect]) -> ShaderMaterial:
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	parent.add_child(copy)
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	parent.add_child(rect)
	rects.append(rect)
	return mat


## Settings are given for a 1080-pixel-tall frame and scaled to `h`.
## settings: {simplify, smooth, thickness, sensitivity, line_color, ink, ink_color,
##            trace, line_detail, line_smooth, area_lines,
##            palette_lab: Array[Vector3], palette_out: Array[Color]}
func setup(w: int, h: int, settings: Dictionary) -> void:
	size = Vector2i(maxi(16, w), maxi(16, h))
	_line_vp.size = size
	_source.size = Vector2(size)
	_line_source.size = Vector2(size)
	for r in _rects:
		r.size = Vector2(size)
	for r in _line_rects:
		r.size = Vector2(size)
	var k := h / 1080.0

	# fills
	var simplify := float(settings.get("simplify", 7))
	for m in _bilateral:
		m.set_shader_parameter("radius", simplify * 1.4 * k)
		m.set_shader_parameter("step_px", maxf(1.0, simplify * 0.3 * k))
		m.set_shader_parameter("sigma_color", 0.1 + simplify * 0.006)
	_blocks_mat.set_shader_parameter("radius", maxi(1, roundi(simplify * 0.45 * k)))
	var labs: Array = settings.get("palette_lab", [])
	var outs: Array = settings.get("palette_out", [])
	var n := mini(MAX_COLORS, mini(labs.size(), outs.size()))
	var lab_arr := PackedVector3Array()
	var out_arr := PackedVector3Array()
	for i in MAX_COLORS:
		if i < n:
			lab_arr.append(labs[i])
			var c: Color = outs[i]
			out_arr.append(Vector3(c.r, c.g, c.b))
		else:
			lab_arr.append(Vector3(-1000, 0, 0))
			out_arr.append(Vector3(-1, -1, -1))
	var ink: Color = settings.get("ink_color", Color.BLACK)
	var ink_v := Vector3(ink.r, ink.g, ink.b)
	_blocks_mat.set_shader_parameter("palette_size", n)
	_blocks_mat.set_shader_parameter("pal_lab", lab_arr)
	_blocks_mat.set_shader_parameter("pal_out", out_arr)
	_blocks_mat.set_shader_parameter("ink_threshold", float(settings.get("ink", 0.0)))
	_blocks_mat.set_shader_parameter("ink_color", ink_v)
	var smooth := float(settings.get("smooth", 6))
	for m in _mode:
		m.set_shader_parameter("radius", smooth * 1.3 * k if n > 0 else 0.0)
		m.set_shader_parameter("palette_size", n)
		m.set_shader_parameter("pal_out", out_arr)
		m.set_shader_parameter("ink_color", ink_v)

	# traced lines
	var thickness := float(settings.get("thickness", 2.0)) * k
	var detail := float(settings.get("line_detail", 10))
	_line_blur.set_shader_parameter("radius", (3.0 + simplify * 0.4) * k)
	_line_blur.set_shader_parameter("step_px", 1.0)
	_line_blur.set_shader_parameter("sigma_color", 0.08)
	_xdog.set_shader_parameter("sigma", (0.8 + (21.0 - detail) * 0.07) * maxf(k, 0.5))
	_xdog.set_shader_parameter("epsilon", -0.012 + detail * 0.0016)
	_xdog.set_shader_parameter("tau", 0.985)
	_xdog.set_shader_parameter("phi", 60.0)
	_dilate.set_shader_parameter("thickness", maxf(0.0, thickness - 0.5))
	var ls := float(settings.get("line_smooth", 5))
	_line_smooth.set_shader_parameter("smooth_sigma", maxf(0.6, thickness) * (0.3 + ls * 0.07))

	# composite (the traced mask is read from the inner viewport's texture)
	_lines_mat.set_shader_parameter("trace_tex", _line_vp.get_texture())
	var trace := bool(settings.get("trace", true)) and thickness > 0.0
	_lines_mat.set_shader_parameter("use_trace", trace)
	_lines_mat.set_shader_parameter("area_lines", bool(settings.get("area_lines", false)))
	_lines_mat.set_shader_parameter("thickness", thickness)
	_lines_mat.set_shader_parameter("sensitivity", float(settings.get("sensitivity", 0.12)))
	_lines_mat.set_shader_parameter("line_color", settings.get("line_color", Color.BLACK))
	_lines_mat.set_shader_parameter("speck_radius", 0.0)


## Returns the processed image. Renders the line mask first, then the fills
## with the lines composited on top.
func process(img: Image) -> Image:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if _tex.get_width() == img.get_width() and _tex.get_height() == img.get_height():
		_tex.update(img)
	else:
		_tex.set_image(img)
	_source.texture = _tex
	_line_source.texture = _tex
	_lines_mat.set_shader_parameter("alpha_tex", _tex)
	_line_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var out := get_texture().get_image()
	out.convert(Image.FORMAT_RGBA8)
	return out
