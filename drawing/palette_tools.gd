class_name PaletteTools
extends RefCounted
## Colour helpers for the auto-rotoscope: sRGB <-> CIE Lab conversion and a
## k-means palette extractor. Working in Lab means "nearest colour" matches
## what the eye sees, so footage simplifies into believable flat colours
## instead of false-colour bands.


static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _gam(c: float) -> float:
	c = clampf(c, 0.0, 1.0)
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


static func _f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


static func _finv(t: float) -> float:
	var t3 := t * t * t
	return t3 if t3 > 0.008856 else (t - 16.0 / 116.0) / 7.787


static func to_lab(c: Color) -> Vector3:
	var r := _lin(c.r)
	var g := _lin(c.g)
	var b := _lin(c.b)
	var x := (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
	var y := r * 0.2126 + g * 0.7152 + b * 0.0722
	var z := (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
	var fx := _f(x)
	var fy := _f(y)
	var fz := _f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func from_lab(lab: Vector3) -> Color:
	var fy := (lab.x + 16.0) / 116.0
	var fx := fy + lab.y / 500.0
	var fz := fy - lab.z / 200.0
	var x := _finv(fx) * 0.95047
	var y := _finv(fy)
	var z := _finv(fz) * 1.08883
	var r := x * 3.2406 - y * 1.5372 - z * 0.4986
	var g := -x * 0.9689 + y * 1.8758 + z * 0.0415
	var b := x * 0.0557 - y * 0.2040 + z * 1.0570
	return Color(_gam(r), _gam(g), _gam(b))


## Collects up to `max_samples` Lab colours from images (transparent pixels skipped).
static func sample_images(images: Array, max_samples: int = 6000) -> Array:
	var out := []
	if images.is_empty():
		return out
	var per_image := maxi(1, max_samples / images.size())
	for item in images:
		var src: Image = item
		var img := src.duplicate() as Image
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var side := int(ceilf(sqrt(float(per_image) * img.get_width() / maxf(1.0, img.get_height()))))
		var w := clampi(side, 8, 160)
		var h := clampi(int(w * float(img.get_height()) / img.get_width()), 8, 160)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					out.append(to_lab(c))
	return out


## k-means in Lab (k-means++ start, fixed seed so results are repeatable).
## Returns cluster centres sorted dark → light.
static func kmeans(samples: Array, k: int, iterations: int = 14) -> Array:
	if samples.is_empty():
		return []
	k = clampi(k, 1, mini(32, samples.size()))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var centers := [samples[rng.randi_range(0, samples.size() - 1)]]
	while centers.size() < k:
		# Pick the next centre far from the existing ones.
		var best_d := -1.0
		var best: Vector3 = samples[0]
		for t in 24:
			var cand: Vector3 = samples[rng.randi_range(0, samples.size() - 1)]
			var d := INF
			for c in centers:
				d = minf(d, cand.distance_squared_to(c))
			if d > best_d:
				best_d = d
				best = cand
		centers.append(best)
	for it in iterations:
		var sums := []
		var counts := []
		for i in k:
			sums.append(Vector3.ZERO)
			counts.append(0)
		for s in samples:
			var v: Vector3 = s
			var bi := 0
			var bd := INF
			for i in k:
				var d := v.distance_squared_to(centers[i])
				if d < bd:
					bd = d
					bi = i
			var acc: Vector3 = sums[bi]
			sums[bi] = acc + v
			counts[bi] = int(counts[bi]) + 1
		for i in k:
			if int(counts[i]) > 0:
				var total: Vector3 = sums[i]
				centers[i] = total / float(counts[i])
	centers.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	return centers


## Ready-made looks: colours listed dark → light and mapped onto the
## extracted clusters by brightness. Every swatch can still be edited.
const PRESETS := {
	"Video colours": [],
	"Night & flame": ["0b0909", "0a1c8c", "e2560a", "ff9a1f", "ffc34d", "f2f0ea"],
	"Ink & paper": ["0b0b0b", "f3f0e8"],
	"Red & white": ["e3240b", "f6f3ee"],
	"Sunset": ["1a0f2b", "6e1d47", "d9482b", "f28a3a", "f8c27a"],
	"Ocean": ["06131d", "0b4a66", "1e93b4", "8fd3e0", "eef7f5"],
	"Forest": ["0d140e", "234d2b", "5a8a3c", "c2b866", "f1ecd8"],
}


## Output colours for `centers` (Lab) under a preset; `boost` saturates video colours.
static func preset_outputs(preset: String, centers: Array, boost: float) -> Array:
	var out := []
	var colors: Array = PRESETS.get(preset, [])
	for i in centers.size():
		if colors.is_empty():
			var c := from_lab(centers[i])
			var l := c.get_luminance()
			out.append(Color(lerpf(l, c.r, boost), lerpf(l, c.g, boost), lerpf(l, c.b, boost)).clamp())
		else:
			var t := 0.0 if centers.size() <= 1 else float(i) / float(centers.size() - 1)
			out.append(Color.from_string(str(colors[roundi(t * (colors.size() - 1))]), Color.BLACK))
	return out
