class_name RefAnalyzer
extends RefCounted
## Reads the visual character of a reference picture on this computer (no
## AI needed): main colours, light key, contrast, saturation, warm/cool,
## how much line detail and how much solid black. The results turn into
## plain words that steer the prompts, so references guide the look
## without their pixels being copied.

static func analyze(img: Image) -> Dictionary:
	var small := img.duplicate() as Image
	small.convert(Image.FORMAT_RGBA8)
	var k := 96.0 / maxi(small.get_width(), small.get_height())
	small.resize(maxi(4, int(small.get_width() * k)), maxi(4, int(small.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	var w := small.get_width()
	var h := small.get_height()
	var px := small.get_data()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var cols: Array[Color] = []
	var sum_l := 0.0
	var sum_s := 0.0
	var sum_warm := 0.0
	var dark := 0
	var n := 0
	for i in w * h:
		var o := i * 4
		if px[o + 3] < 40:
			lum[i] = -1.0
			continue
		var c := Color8(px[o], px[o + 1], px[o + 2])
		var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		lum[i] = l
		sum_l += l
		sum_s += c.s
		sum_warm += c.r - c.b
		if l < 0.16:
			dark += 1
		cols.append(c)
		n += 1
	if n == 0:
		return {}
	var mean := sum_l / n
	var var_acc := 0.0
	for i in lum.size():
		if lum[i] >= 0.0:
			var_acc += (lum[i] - mean) * (lum[i] - mean)
	var contrast := sqrt(var_acc / n)
	# edges: share of pixels with a strong brightness step to a neighbour
	var edges := 0
	var counted := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c0 := lum[y * w + x]
			if c0 < 0.0:
				continue
			var gx := absf(lum[y * w + x + 1] - lum[y * w + x - 1])
			var gy := absf(lum[(y + 1) * w + x] - lum[(y - 1) * w + x])
			counted += 1
			if gx + gy > 0.22:
				edges += 1
	var a := {
		"palette": _hexes(kmeans(cols, 6)),
		"brightness": snappedf(mean, 0.01),
		"contrast": snappedf(contrast, 0.01),
		"saturation": snappedf(sum_s / n, 0.01),
		"warmth": snappedf(sum_warm / n, 0.01),
		"line_density": snappedf(float(edges) / maxf(1.0, counted), 0.01),
		"black_share": snappedf(float(dark) / n, 0.01),
	}
	_describe(a)
	return a


## Turns the numbers into words for prompts.
static func _describe(a: Dictionary) -> void:
	var b := float(a.get("brightness", 0.5))
	var c := float(a.get("contrast", 0.2))
	var s := float(a.get("saturation", 0.3))
	var wv := float(a.get("warmth", 0.0))
	var ld := float(a.get("line_density", 0.1))
	var bs := float(a.get("black_share", 0.1))
	var key := "low-key" if b < 0.33 else ("high-key" if b > 0.62 else "mid-key")
	var temp := "warm" if wv > 0.06 else ("cool" if wv < -0.04 else "neutral")
	var sat := "desaturated, muted" if s < 0.22 else ("rich saturated" if s > 0.5 else "restrained")
	a["lighting_text"] = "%s lighting, %s contrast, %s tones" % [key, "stark high" if c > 0.27 else ("soft low" if c < 0.14 else "moderate"), temp]
	if ld > 0.2:
		a["line_text"] = "dense intricate ink linework with fine hatching"
	elif ld > 0.09:
		a["line_text"] = "confident inked outlines with varied line weight"
	else:
		a["line_text"] = "soft painterly edges with sparse outlines"
	if bs > 0.32:
		a["shading_text"] = "heavy solid spot blacks and deep shadow masses"
	elif c > 0.25:
		a["shading_text"] = "hard-edged cel shadows"
	else:
		a["shading_text"] = "soft graded shading"
	a["summary"] = "%s; %s; %s palette; %s" % [a["lighting_text"], a["line_text"], sat, a["shading_text"]]


## Combines several references into one profile.
static func merge(analyses: Array) -> Dictionary:
	var out := {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "warmth": 0.0, "line_density": 0.0, "black_share": 0.0}
	var cols: Array[Color] = []
	var n := 0
	for item in analyses:
		var a: Dictionary = item
		if a.is_empty():
			continue
		for k in out.keys():
			out[k] = float(out[k]) + float(a.get(k, 0.0))
		for hx in a.get("palette", []):
			cols.append(Color(str(hx)))
		n += 1
	if n == 0:
		return {}
	for k in out.keys():
		out[k] = float(out[k]) / n
	out["palette"] = _hexes(kmeans(cols, 6))
	_describe(out)
	return out


static func _hexes(colors: Array[Color]) -> Array:
	var out: Array = []
	for c in colors:
		out.append("#" + c.to_html(false))
	return out


## k-means colour clustering; returns up to k colours, most common first.
static func kmeans(cols: Array[Color], k: int) -> Array[Color]:
	var out: Array[Color] = []
	if cols.is_empty():
		return out
	k = mini(k, cols.size())
	var centers: Array[Color] = []
	var step := maxi(1, cols.size() / k)
	for i in k:
		centers.append(cols[mini(i * step, cols.size() - 1)])
	var counts := PackedInt32Array()
	for _it in 8:
		var sums: Array[Vector3] = []
		counts = PackedInt32Array()
		counts.resize(k)
		for i in k:
			sums.append(Vector3.ZERO)
		for c in cols:
			var best := 0
			var bd := 1e9
			for i in k:
				var cc := centers[i]
				var d := (c.r - cc.r) * (c.r - cc.r) + (c.g - cc.g) * (c.g - cc.g) + (c.b - cc.b) * (c.b - cc.b)
				if d < bd:
					bd = d
					best = i
			sums[best] += Vector3(c.r, c.g, c.b)
			counts[best] += 1
		for i in k:
			if counts[i] > 0:
				var m := sums[i] / counts[i]
				centers[i] = Color(m.x, m.y, m.z)
	var order: Array = range(k)
	order.sort_custom(func(x: int, y: int) -> bool: return counts[x] > counts[y])
	for i in order:
		if counts[int(i)] > 0:
			out.append(centers[int(i)])
	return out


## "#1a2b3c" list → "deep crimson, slate blue, …" for prompts.
static func palette_words(hexes: Array) -> String:
	var words: Array[String] = []
	for hx in hexes:
		var w := color_word(Color(str(hx)))
		if not words.has(w):
			words.append(w)
	return ", ".join(words)


static func color_word(c: Color) -> String:
	var l := c.v
	if c.s < 0.15:
		if l < 0.15:
			return "ink black"
		if l < 0.45:
			return "charcoal grey"
		if l < 0.8:
			return "ash grey"
		return "bone white"
	var hue := c.h * 360.0
	var hue_name := "red"
	if hue < 15 or hue >= 345:
		hue_name = "crimson"
	elif hue < 40:
		hue_name = "rust orange"
	elif hue < 65:
		hue_name = "ochre"
	elif hue < 160:
		hue_name = "moss green"
	elif hue < 200:
		hue_name = "teal"
	elif hue < 255:
		hue_name = "slate blue"
	elif hue < 290:
		hue_name = "violet"
	else:
		hue_name = "plum"
	var shade := "deep " if l < 0.35 else ("pale " if l > 0.8 else "")
	var mute := "muted " if c.s < 0.4 else ""
	return shade + mute + hue_name
