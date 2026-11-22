class_name InbetweenProcessor
extends Node
## Auto in-betweens without AI: finds how the lines moved from one keyframe
## drawing to the next (coarse-to-fine matching on blurred ink, on the GPU,
## in both directions), then pushes every inked pixel of both drawings along
## its own motion to draw the frames between — as motion in-betweens, smears,
## wipes or fades. (Pushing ink forward, rather than looking motion up at the
## empty spot where the line will be, is what works for sparse line art.)

const FLOW_SHADER := preload("res://shaders/drawing_flow.gdshader")
const STYLES := ["motion", "smear", "wipe", "fade"]
const COARSE_MAX := 32.0
const FINE_MAX := 80.0

var _flow_vp: SubViewport
var _flow_rect: TextureRect
var _flow_mat: ShaderMaterial
# inked pixels of each keyframe: index, colour (RGBA8) and where it moves
var _a_idx := PackedInt32Array()
var _a_col := PackedByteArray()
var _a_move := PackedVector2Array()  # full move from A to B, in pixels
var _b_idx := PackedInt32Array()
var _b_col := PackedByteArray()
var _b_move := PackedVector2Array()  # full move from A to B (seen from B)
var _wipe_dir := Vector2.RIGHT
var _wipe_range := Vector2(-0.7, 0.7)
var _size := Vector2i(1920, 1080)
var _shift := Vector2.ZERO


func _ready() -> void:
	_flow_vp = _make_vp()
	_flow_rect = TextureRect.new()
	_flow_mat = ShaderMaterial.new()
	_flow_mat.shader = FLOW_SHADER
	_flow_rect.material = _flow_mat
	_flow_vp.add_child(_flow_rect)


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
	var ia := a.duplicate() as Image
	ia.convert(Image.FORMAT_RGBA8)
	var ib := b.duplicate() as Image
	ib.convert(Image.FORMAT_RGBA8)
	if ib.get_size() != _size:
		ib.resize(_size.x, _size.y)
	var ink_a := ink_map(ia)
	var ink_b := ink_map(ib)
	var coarse := Vector2i(maxi(16, _size.x / 8), maxi(16, _size.y / 8))
	var fine := Vector2i(maxi(16, _size.x / 4), maxi(16, _size.y / 4))
	var ca := ImageTexture.create_from_image(density(ink_a, coarse, 3.0))
	var cb := ImageTexture.create_from_image(density(ink_b, coarse, 3.0))
	var fa := ImageTexture.create_from_image(density(ink_a, fine, 2.0))
	var fb := ImageTexture.create_from_image(density(ink_b, fine, 2.0))
	# starting guess: how far the drawing moved as a whole (coarse pixels)
	_shift = _centre(density(ink_b, coarse, 1.0)) - _centre(density(ink_a, coarse, 1.0))
	# B seen from A (where each bit of A went) and A seen from B
	var c_ab := await _flow(ca, cb, coarse, null, COARSE_MAX, 24.0, COARSE_MAX, true)
	var f_ab := await _flow(fa, fb, fine, ImageTexture.create_from_image(c_ab), FINE_MAX, 8.0, COARSE_MAX, true)
	var c_ba := await _flow(ca, cb, coarse, null, COARSE_MAX, 24.0, COARSE_MAX, false)
	var f_ba := await _flow(fa, fb, fine, ImageTexture.create_from_image(c_ba), FINE_MAX, 8.0, COARSE_MAX, false)
	for f in [f_ab, f_ba]:
		var fi: Image = f
		fi.resize(maxi(2, fine.x / 3), maxi(2, fine.y / 3), Image.INTERPOLATE_BILINEAR)
		fi.resize(fine.x, fine.y, Image.INTERPOLATE_BILINEAR)
	var scale := float(_size.x) / float(fine.x) * 2.0 * FINE_MAX / 255.0
	# A's ink moves by -d_ab (A(p) ≈ B(p - d)); B's ink came from p - d_ba
	_collect(ia, f_ab, fine, -scale, _a_idx, _a_col, _a_move)
	_collect(ib, f_ba, fine, scale, _b_idx, _b_col, _b_move)
	_measure_direction()


## Ink-weighted centre of a density map, in its pixels.
static func _centre(den: Image) -> Vector2:
	var d := den.get_data()
	var w := den.get_width()
	var sum := Vector2.ZERO
	var tot := 0.0
	for i in d.size():
		if d[i] > 20:
			sum += Vector2(i % w, i / w) * d[i]
			tot += d[i]
	return sum / tot if tot > 0.0 else Vector2(w, den.get_height()) * 0.5


## Runs one flow pass. `a_to_b`: matches A's content in B (result lives on
## A's pixels); otherwise B's content in A (on B's pixels).
func _flow(ta: Texture2D, tb: Texture2D, sz: Vector2i, init: Texture2D, out_max: float, search: float, init_max: float, a_to_b: bool) -> Image:
	var cur := ta if a_to_b else tb
	var prev := tb if a_to_b else ta
	_flow_vp.size = sz
	_flow_rect.size = Vector2(sz)
	_flow_rect.texture = cur
	_flow_mat.set_shader_parameter("cur_tex", cur)
	_flow_mat.set_shader_parameter("prev_tex", prev)
	_flow_mat.set_shader_parameter("has_init", init != null)
	# A(p) ≈ B(p - d): A's content moved by -d; B(p) ≈ A(p - d): by +d
	_flow_mat.set_shader_parameter("base_shift", -_shift if a_to_b else _shift)
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


## Lists the inked pixels of `img` with their colour and full A→B move.
func _collect(img: Image, flow: Image, fine: Vector2i, k: float, idx: PackedInt32Array, col: PackedByteArray, move: PackedVector2Array) -> void:
	idx.clear()
	col.clear()
	move.clear()
	var d := img.get_data()
	var f := flow.get_data()
	var w := _size.x
	var fx := float(fine.x) / float(_size.x)
	var fy := float(fine.y) / float(_size.y)
	var n := w * _size.y
	for i in n:
		var a := d[i * 4 + 3]
		if a < 12:
			continue
		var x := i % w
		var y := i / w
		var fi := (mini(fine.y - 1, int(y * fy)) * fine.x + mini(fine.x - 1, int(x * fx))) * 4
		idx.append(i)
		col.append(d[i * 4])
		col.append(d[i * 4 + 1])
		col.append(d[i * 4 + 2])
		col.append(a)
		move.append(Vector2(f[fi] - 127.5, f[fi + 1] - 127.5) * k)


## Main direction of movement (weighted by ink), for wipes.
func _measure_direction() -> void:
	var sum := Vector2.ZERO
	for i in range(0, _a_move.size(), 7):
		sum += _a_move[i]
	_wipe_dir = sum.normalized() if sum.length() > 0.001 else Vector2.RIGHT
	var lo := INF
	var hi := -INF
	var w := _size.x
	for i in range(0, _a_idx.size(), 5):
		var p := Vector2(_a_idx[i] % w, _a_idx[i] / w)
		var pr := p.dot(_wipe_dir)
		lo = minf(lo, pr)
		hi = maxf(hi, (p + _a_move[i]).dot(_wipe_dir))
	for i in range(0, _b_idx.size(), 5):
		var p := Vector2(_b_idx[i] % w, _b_idx[i] / w)
		hi = maxf(hi, p.dot(_wipe_dir))
		lo = minf(lo, (p - _b_move[i]).dot(_wipe_dir))
	_wipe_range = Vector2(lo, hi) if hi > lo else Vector2(0, 1)


## Splats one keyframe's ink at time `t` into the buffers. `weight` scales
## its strength; `use_max` keeps the strongest instead of adding (smears).
## `wipe_side`: 0 = all, 1 = only the part the wipe hasn't reached (A),
## 2 = only the part it has (B); `edge` is the wipe position (0..1).
func _splat(acc: PackedFloat32Array, rgb: PackedFloat32Array, from_b: bool, t: float, weight: float, use_max: bool, wipe_side: int, edge: float, soft: float) -> void:
	var idx := _b_idx if from_b else _a_idx
	var col := _b_col if from_b else _a_col
	var move := _b_move if from_b else _a_move
	var w := _size.x
	var h := _size.y
	var k := (t - 1.0) if from_b else t
	var span := maxf(0.001, _wipe_range.y - _wipe_range.x)
	for j in idx.size():
		var p := Vector2(idx[j] % w, idx[j] / w) + move[j] * k
		var a := col[j * 4 + 3] / 255.0 * weight
		if wipe_side != 0:
			var n := (p.dot(_wipe_dir) - _wipe_range.x) / span
			var mb := smoothstep(edge - soft, edge + soft, n)
			a *= mb if wipe_side == 2 else 1.0 - mb
			if a < 0.004:
				continue
		var x0 := int(p.x)
		var y0 := int(p.y)
		for oy in 2:
			var y := y0 + oy
			if y < 0 or y >= h:
				continue
			for ox in 2:
				var x := x0 + ox
				if x < 0 or x >= w:
					continue
				var o := y * w + x
				if use_max:
					if a > acc[o]:
						acc[o] = a
						rgb[o * 3] = col[j * 4]
						rgb[o * 3 + 1] = col[j * 4 + 1]
						rgb[o * 3 + 2] = col[j * 4 + 2]
				else:
					acc[o] += a
					rgb[o * 3] += col[j * 4] * a
					rgb[o * 3 + 1] += col[j * 4 + 1] * a
					rgb[o * 3 + 2] += col[j * 4 + 2] * a


## How far the ink moves between the keyframes, in pixels (median-ish).
func _typical_move() -> float:
	if _a_move.is_empty():
		return 0.0
	var lens := PackedFloat32Array()
	for i in range(0, _a_move.size(), maxi(1, _a_move.size() / 200)):
		lens.append(_a_move[i].length())
	lens.sort()
	return lens[lens.size() / 2]


## One in-between at `t` (0 = first keyframe, 1 = next).
func frame(t: float, style: String, smear: float) -> Image:
	var n := _size.x * _size.y
	var acc := PackedFloat32Array()
	acc.resize(n)
	var rgb := PackedFloat32Array()
	rgb.resize(n * 3)
	var summed := true
	match style:
		"fade":
			_splat(acc, rgb, false, 0.0, 1.0 - t, false, 0, 0.0, 0.0)
			_splat(acc, rgb, true, 1.0, t, false, 0, 0.0, 0.0)
		"smear":
			summed = false
			# enough copies that the streak is continuous over the distance
			var steps := clampi(int(_typical_move() * smear / 3.0), 9, 48)
			for s in steps:
				var f := float(s) / float(steps - 1) - 0.5
				var tt := clampf(t + f * smear, 0.0, 1.0)
				var wgt := 1.0 - absf(f) * 1.1
				_splat(acc, rgb, false, tt, wgt * (1.0 - tt) * 2.0, true, 0, 0.0, 0.0)
				_splat(acc, rgb, true, tt, wgt * tt * 2.0, true, 0, 0.0, 0.0)
		"wipe":
			summed = false
			var soft := 0.12
			var edge := lerpf(1.0 + soft, -soft, t)
			_splat(acc, rgb, false, t, 1.0, true, 1, edge, soft)
			_splat(acc, rgb, true, t, 1.0, true, 2, edge, soft)
			var wsteps := clampi(int(_typical_move() * smear / 4.0), 7, 32)
			for s in wsteps:
				var f := float(s) / float(wsteps - 1) - 0.5
				var tt := clampf(t + f * smear, 0.0, 1.0)
				var wgt := (1.0 - absf(f) * 1.2) * 0.8
				_splat(acc, rgb, false, tt, wgt, true, 2, edge, soft * 1.6)
				_splat(acc, rgb, true, tt, wgt, true, 1, edge, soft * 1.6)
		_:
			_splat(acc, rgb, false, t, 1.0 - t, false, 0, 0.0, 0.0)
			_splat(acc, rgb, true, t, t, false, 0, 0.0, 0.0)
	var out := PackedByteArray()
	out.resize(n * 4)
	for i in n:
		var a := acc[i]
		if a <= 0.003:
			continue
		if summed:
			out[i * 4] = int(rgb[i * 3] / a)
			out[i * 4 + 1] = int(rgb[i * 3 + 1] / a)
			out[i * 4 + 2] = int(rgb[i * 3 + 2] / a)
			# where both drawings agree the line is solid; lone ghosts stay faint
			out[i * 4 + 3] = int(clampf(smoothstep(0.15, 0.85, a), 0.0, 1.0) * 255.0)
		else:
			out[i * 4] = int(rgb[i * 3])
			out[i * 4 + 1] = int(rgb[i * 3 + 1])
			out[i * 4 + 2] = int(rgb[i * 3 + 2])
			out[i * 4 + 3] = int(clampf(a, 0.0, 1.0) * 255.0)
	return Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, out)
