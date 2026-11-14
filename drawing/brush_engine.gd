class_name BrushEngine
extends RefCounted
## Raster drawing primitives operating directly on Images.
## Painting uses cached, pre-colored dab images blended with Image.blend_rect
## (native code, fast). Erasing reduces alpha under a cached falloff mask.
## Flood fill works on the raw pixel buffer.

static var _mask_cache: Dictionary = {}
static var _stamp_cache: Dictionary = {}


static func clear_cache() -> void:
	_mask_cache.clear()
	_stamp_cache.clear()


## Coverage mask (0..1) for a round brush of diameter d.
static func _mask(d: int, hardness: float) -> PackedFloat32Array:
	var key := "%d|%.2f" % [d, hardness]
	if _mask_cache.has(key):
		return _mask_cache[key]
	var m := PackedFloat32Array()
	m.resize(d * d)
	var r := d * 0.5
	var inner := r * clampf(hardness, 0.0, 1.0)
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := 0.0
			if dist < r + 0.5:
				if dist <= inner:
					a = 1.0
				else:
					a = 1.0 - (dist - inner) / maxf(r - inner, 0.001)
					a = clampf(a, 0.0, 1.0)
					a = a * a * (3.0 - 2.0 * a)
				# anti-aliased rim
				a = minf(a, clampf(r - dist + 0.5, 0.0, 1.0))
			m[y * d + x] = a
	if _mask_cache.size() > 128:
		_mask_cache.clear()
	_mask_cache[key] = m
	return m


static func _stamp(d: int, hardness: float, color: Color) -> Image:
	var key := "%d|%.2f|%s" % [d, hardness, color.to_html(true)]
	if _stamp_cache.has(key):
		return _stamp_cache[key]
	var m := _mask(d, hardness)
	var data := PackedByteArray()
	data.resize(d * d * 4)
	var r8 := color.r8
	var g8 := color.g8
	var b8 := color.b8
	var a := color.a * 255.0
	for i in d * d:
		var o := i * 4
		data[o] = r8
		data[o + 1] = g8
		data[o + 2] = b8
		data[o + 3] = clampi(int(roundf(a * m[i])), 0, 255)
	var img := Image.create_from_data(d, d, false, Image.FORMAT_RGBA8, data)
	if _stamp_cache.size() > 96:
		_stamp_cache.clear()
	_stamp_cache[key] = img
	return img


static func _dab_origin(center: Vector2, d: int) -> Vector2i:
	return Vector2i(int(floorf(center.x - d * 0.5 + 0.5)), int(floorf(center.y - d * 0.5 + 0.5)))


## Paints one round dab. `color.a` is the per-dab flow. Returns the touched rect.
static func paint_dab(img: Image, center: Vector2, diameter: float, hardness: float, color: Color) -> Rect2i:
	var d := maxi(1, int(roundf(diameter)))
	var stamp := _stamp(d, hardness, color)
	var pos := _dab_origin(center, d)
	img.blend_rect(stamp, Rect2i(0, 0, d, d), pos)
	return Rect2i(pos, Vector2i(d, d))


## Erases one round dab, reducing alpha by `strength` * coverage.
static func erase_dab(img: Image, center: Vector2, diameter: float, hardness: float, strength: float) -> Rect2i:
	var d := maxi(1, int(roundf(diameter)))
	var m := _mask(d, hardness)
	var pos := _dab_origin(center, d)
	var w := img.get_width()
	var h := img.get_height()
	for j in d:
		var y := pos.y + j
		if y < 0 or y >= h:
			continue
		for i in d:
			var cov := m[j * d + i]
			if cov <= 0.0:
				continue
			var x := pos.x + i
			if x < 0 or x >= w:
				continue
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			c.a = c.a * (1.0 - cov * strength)
			img.set_pixel(x, y, c)
	return Rect2i(pos, Vector2i(d, d))


static func _pack(c: Color) -> int:
	var v := c.r8 | (c.g8 << 8) | (c.b8 << 16) | (c.a8 << 24)
	if v >= 0x80000000:
		v -= 0x100000000
	return v


static func _fillable(v: int, target: int, transparent_mode: bool) -> bool:
	if transparent_mode:
		return ((v >> 24) & 0xFF) < 128
	return v == target


## Fills the connected region under `start`. Clicking empty space fills up to
## the drawn lines (gaps under soft line edges are filled too). Returns the
## changed rect, or an empty rect if nothing changed.
static func flood_fill(img: Image, start: Vector2i, color: Color) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	if start.x < 0 or start.y < 0 or start.x >= w or start.y >= h:
		return Rect2i()
	var px := img.get_data().to_int32_array()
	var fill := _pack(color)
	var si := start.y * w + start.x
	var target := px[si]
	var tm := ((target >> 24) & 0xFF) < 128
	if not tm and target == fill:
		return Rect2i()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack: Array[int] = [si]
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	while not stack.is_empty():
		var idx: int = stack.pop_back()
		if visited[idx] == 1 or not _fillable(px[idx], target, tm):
			continue
		var y := idx / w
		var x := idx - y * w
		var row := y * w
		var lx := x
		while lx > 0 and visited[row + lx - 1] == 0 and _fillable(px[row + lx - 1], target, tm):
			lx -= 1
		var rx := x
		while rx < w - 1 and visited[row + rx + 1] == 0 and _fillable(px[row + rx + 1], target, tm):
			rx += 1
		for i in range(lx, rx + 1):
			px[row + i] = fill
			visited[row + i] = 1
		min_x = mini(min_x, lx)
		max_x = maxi(max_x, rx)
		min_y = mini(min_y, y)
		max_y = maxi(max_y, y)
		for dy in 2:
			var ny := y - 1 + dy * 2
			if ny < 0 or ny >= h:
				continue
			var nrow := ny * w
			var in_span := false
			for i in range(lx, rx + 1):
				var j := nrow + i
				if visited[j] == 0 and _fillable(px[j], target, tm):
					if not in_span:
						stack.append(j)
						in_span = true
				else:
					in_span = false
	if max_x < 0:
		return Rect2i()
	img.set_data(w, h, false, Image.FORMAT_RGBA8, px.to_byte_array())
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Rasterizes a closed polygon (local pixel coordinates) into an RGBA mask of
## `size`: opaque inside, transparent outside. Uses even-odd scanlines with
## native fill_rect per span, so large lassos stay fast.
static func polygon_mask(poly: PackedVector2Array, size: Vector2i) -> Image:
	var m := Image.create_empty(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	m.fill(Color(0, 0, 0, 0))
	var n := poly.size()
	if n < 3:
		return m
	for y in size.y:
		var sy := y + 0.5
		var xs: Array[float] = []
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var x0 := clampi(int(ceilf(xs[k] - 0.5)), 0, size.x)
			var x1 := clampi(int(floorf(xs[k + 1] - 0.5)) + 1, 0, size.x)
			if x1 > x0:
				m.fill_rect(Rect2i(x0, y, x1 - x0, 1), Color.WHITE)
			k += 2
	return m
