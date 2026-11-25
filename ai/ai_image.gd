class_name AiImage
extends RefCounted
## Picture helpers for the AI Studio: sizing, guides, background keying,
## contact sheets.

## Generation size: the project's shape with the long side `base`,
## rounded to multiples of 64 (what diffusion models expect).
static func gen_size(w: int, h: int, base: int) -> Vector2i:
	var k := float(base) / float(maxi(w, h))
	var gw := maxi(256, int(round(w * k / 64.0)) * 64)
	var gh := maxi(256, int(round(h * k / 64.0)) * 64)
	return Vector2i(gw, gh)


## Scales to cover w×h and crops the middle (RGBA8 copy).
static func cover(img: Image, w: int, h: int) -> Image:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var k := maxf(float(w) / src.get_width(), float(h) / src.get_height())
	var nw := maxi(w, int(ceil(src.get_width() * k)))
	var nh := maxi(h, int(ceil(src.get_height() * k)))
	if nw != src.get_width() or nh != src.get_height():
		src.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	return src.get_region(Rect2i((src.get_size() - Vector2i(w, h)) / 2, Vector2i(w, h)))


## Fits inside w×h on `bg` (letterboxed), for reference sheets.
static func contain(img: Image, w: int, h: int, bg: Color = Color(0.8, 0.8, 0.8)) -> Image:
	var src := flatten(img, bg)
	var k := minf(float(w) / src.get_width(), float(h) / src.get_height())
	var sz := Vector2i(maxi(1, int(src.get_width() * k)), maxi(1, int(src.get_height() * k)))
	src.resize(sz.x, sz.y, Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.fill(bg)
	out.blit_rect(src, Rect2i(Vector2i.ZERO, sz), (Vector2i(w, h) - sz) / 2)
	return out


## Transparent areas filled with `bg`.
static func flatten(img: Image, bg: Color = Color.WHITE) -> Image:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create_empty(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(bg)
	out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	return out


## Cross-fade of two pictures at `t` (0 = a, 1 = b). Same size required.
static func mix(a: Image, b: Image, t: float) -> Image:
	var fa := a.duplicate() as Image
	var fb := b.duplicate() as Image
	fa.convert(Image.FORMAT_RGBA8)
	fb.convert(Image.FORMAT_RGBA8)
	if fb.get_size() != fa.get_size():
		fb.resize(fa.get_width(), fa.get_height(), Image.INTERPOLATE_BILINEAR)
	var da := fa.get_data()
	var db := fb.get_data()
	var wa := int(round((1.0 - t) * 256.0))
	var wb := 256 - wa
	for i in da.size():
		da[i] = (da[i] * wa + db[i] * wb) >> 8
	return Image.create_from_data(fa.get_width(), fa.get_height(), false, Image.FORMAT_RGBA8, da)


## Is there anything drawn on this (transparent-background) picture?
static func has_content(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var small := img.duplicate() as Image
	small.convert(Image.FORMAT_RGBA8)
	small.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var d := small.get_data()
	for i in range(3, d.size(), 4):
		if d[i] > 24:
			return true
	return false


## Makes the flat backdrop around a character see-through: colours close to
## the picture's border colour and connected to the border are removed.
## Works on a reduced mask, so it's quick; edges get a soft 1-2 px ramp.
static func key_backdrop(img: Image, tolerance: float = 0.14) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var k := minf(1.0, 512.0 / w)
	var sw := maxi(2, int(w * k))
	var sh := maxi(2, int(h * k))
	var small := img.duplicate() as Image
	small.convert(Image.FORMAT_RGBA8)
	small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var px := small.get_data()
	# border colour = median-ish: average of the border pixels
	var acc := Vector3.ZERO
	var n := 0
	for x in sw:
		for y in [0, sh - 1]:
			var o: int = (int(y) * sw + x) * 4
			acc += Vector3(px[o], px[o + 1], px[o + 2])
			n += 1
	for y in sh:
		for x in [0, sw - 1]:
			var o: int = (y * sw + int(x)) * 4
			acc += Vector3(px[o], px[o + 1], px[o + 2])
			n += 1
	var bgc := acc / maxf(1.0, n)
	var tol := tolerance * 255.0 * 1.732
	var bg := PackedByteArray()
	bg.resize(sw * sh)
	var queue := PackedInt32Array()
	for x in sw:
		queue.append(x)
		queue.append((sh - 1) * sw + x)
	for y in sh:
		queue.append(y * sw)
		queue.append(y * sw + sw - 1)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		if bg[p] != 0:
			continue
		var o := p * 4
		var d := Vector3(px[o], px[o + 1], px[o + 2]).distance_to(bgc)
		if d > tol:
			continue
		bg[p] = 255
		var x := p % sw
		var y := p / sw
		if x > 0:
			queue.append(p - 1)
		if x < sw - 1:
			queue.append(p + 1)
		if y > 0:
			queue.append(p - sw)
		if y < sh - 1:
			queue.append(p + sw)
	var mask := Image.create_from_data(sw, sh, false, Image.FORMAT_L8, bg)
	mask.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var m := mask.get_data()
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var data := src.get_data()
	for i in m.size():
		data[i * 4 + 3] = mini(data[i * 4 + 3], 255 - m[i])
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


## A grid of numbered thumbnails (for the director's vision review).
static func contact_sheet(images: Array, labels: Array, cell_w: int = 320) -> Image:
	var cols := mini(4, maxi(1, images.size()))
	var rows := int(ceil(images.size() / float(cols)))
	var first: Image = images[0]
	var cell_h := int(cell_w * float(first.get_height()) / first.get_width())
	var pad := 6
	var out := Image.create_empty(cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.05, 0.05, 0.06))
	for idx in images.size():
		var img := flatten(images[idx], Color(0.5, 0.5, 0.5))
		img.resize(cell_w, cell_h, Image.INTERPOLATE_BILINEAR)
		var cx := pad + (idx % cols) * (cell_w + pad)
		var cy := pad + (idx / cols) * (cell_h + pad)
		out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(cx, cy))
		# a small white tab in the corner; the number itself is given in the prompt order
		var tab := Image.create_empty(14 + 6 * str(labels[idx]).length(), 4, false, Image.FORMAT_RGBA8)
		tab.fill(Color(1, 1, 1))
		out.blit_rect(tab, Rect2i(Vector2i.ZERO, tab.get_size()), Vector2i(cx, cy))
	return out


static func thumb(img: Image, max_side: int = 220) -> ImageTexture:
	var t := img.duplicate() as Image
	var k := float(max_side) / maxi(t.get_width(), t.get_height())
	if k < 1.0:
		t.resize(maxi(1, int(t.get_width() * k)), maxi(1, int(t.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(t)
