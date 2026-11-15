class_name FxProcessor
extends Node
## Runs the active episode effects over a picture. Each effect is one pass
## (BackBufferCopy + full-screen ColorRect with shaders/video_fx.gdshader).
##
## Two output viewports take turns every frame (ping-pong), and two more keep
## the picture from before the effects. That way each frame can read last
## frame's result — what datamosh and echo trails are made of.

const MAX_PASSES := VideoFx.MAX_ACTIVE
const SHADER := preload("res://shaders/video_fx.gdshader")

var _out: Array[SubViewport] = []
var _src: Array[SubViewport] = []
var _base: Array[TextureRect] = []
var _src_rect: Array[TextureRect] = []
var _passes: Array = []  # per output viewport: Array of [BackBufferCopy, ColorRect]
var _cur: int = 0
var _hist_valid: bool = false
var _last_frame: int = -999
var _size := Vector2i(16, 16)


func _ready() -> void:
	for i in 2:
		var src_vp := _make_vp()
		var sr := TextureRect.new()
		sr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sr.stretch_mode = TextureRect.STRETCH_SCALE
		src_vp.add_child(sr)
		_src.append(src_vp)
		_src_rect.append(sr)

		var out_vp := _make_vp()
		var base := TextureRect.new()
		base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		base.stretch_mode = TextureRect.STRETCH_SCALE
		out_vp.add_child(base)
		var passes: Array = []
		for k in MAX_PASSES:
			var bbc := BackBufferCopy.new()
			bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			out_vp.add_child(bbc)
			var rect := ColorRect.new()
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			rect.material = mat
			out_vp.add_child(rect)
			passes.append([bbc, rect])
		_out.append(out_vp)
		_base.append(base)
		_passes.append(passes)
	setup(_size.x, _size.y)


func _make_vp() -> SubViewport:
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	return vp


func setup(w: int, h: int) -> void:
	_size = Vector2i(maxi(16, w), maxi(16, h))
	if _out.is_empty():
		return
	var s := Vector2(_size)
	for i in 2:
		_out[i].size = _size
		_src[i].size = _size
		_base[i].size = s
		_src_rect[i].size = s
		for pair in _passes[i]:
			var p: Array = pair
			var rect: ColorRect = p[1]
			rect.size = s
	reset()


## Forget the previous frame (after a jump in time).
func reset() -> void:
	_hist_valid = false
	_last_frame = -999


## Applies `active` (from VideoFx.active_at) to `src` at episode frame
## `frame`. Returns the texture to show; it is drawn this frame. With no
## active effects the source comes straight back.
func process(src: Texture2D, active: Array, frame: int, fps: int) -> Texture2D:
	if active.is_empty() or src == null:
		_hist_valid = false
		_last_frame = frame
		return src
	if frame != _last_frame:
		if frame != _last_frame + 1:
			_hist_valid = false
		_cur = 1 - _cur
	_last_frame = frame
	var i := _cur
	var j := 1 - i
	_src_rect[i].texture = src
	_base[i].texture = src
	var passes: Array = _passes[i]
	for k in MAX_PASSES:
		var pair: Array = passes[k]
		var bbc: BackBufferCopy = pair[0]
		var rect: ColorRect = pair[1]
		var on := k < active.size()
		bbc.visible = on
		rect.visible = on
		if not on:
			continue
		var a: Dictionary = active[k]
		var e: Dictionary = a["fx"]
		var mat := rect.material as ShaderMaterial
		mat.set_shader_parameter("fx", int(a["index"]))
		mat.set_shader_parameter("amount", float(a["amount"]))
		mat.set_shader_parameter("param", clampf(float(e.get("param", 0.5)), 0.0, 1.0))
		mat.set_shader_parameter("tint", Color.from_string(str(e.get("color", "ffffffff")), Color.WHITE))
		mat.set_shader_parameter("t", float(frame) / maxf(1.0, fps))
		mat.set_shader_parameter("frame", float(frame))
		mat.set_shader_parameter("res", Vector2(_size))
		mat.set_shader_parameter("has_prev", _hist_valid)
		mat.set_shader_parameter("seed", float(hash(str(e.get("id", ""))) % 997))
		mat.set_shader_parameter("prev_out", _out[j].get_texture())
		mat.set_shader_parameter("prev_src", _src[j].get_texture())
	_out[i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_src[i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_hist_valid = true
	return _out[i].get_texture()
