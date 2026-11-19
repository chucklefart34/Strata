class_name SubjectTracker
extends RefCounted
## "Keep a subject I pick": learns what the subject looks like from a box
## (plus optional + / − marks), follows it through the clip, and makes a
## per-frame mask of just the subject.
##
## 1. Colour model: histograms of subject vs background colours (16 levels
##    per channel), refined a couple of times like GrabCut, turned into a
##    lookup table: colour → chance it belongs to the subject.
## 2. Tracking: mean-shift on that probability map, frame by frame, from
##    every box you drew (keys) forward and backward; between two keys the
##    two tracks are blended. Box size follows the subject's apparent size.
## 3. Mask: probability × "near the box", thresholded, only the blobs that
##    belong to the subject kept, small holes filled. The GPU then refines
##    the edge at full resolution with the same lookup table.
##
## All boxes and marks are in canvas UV (0..1), the same framing as the
## proxy frames and the imported frames.

const WORK_W := 256
const BINS := 4096

var keys: Array = []   # [{t: float, box: Rect2}] sorted by t
var marks: Array = []  # [{t: float, uv: Vector2, r: float, fg: bool}]
var lut := PackedFloat32Array()
var lut_image: Image = null
var track: Dictionary = {}  # proxy frame index -> Rect2
var track_fps: float = 12.0
var tracked: bool = false


func clear() -> void:
	keys.clear()
	marks.clear()
	track.clear()
	tracked = false
	lut = PackedFloat32Array()
	lut_image = null


func has_keys() -> bool:
	return not keys.is_empty()


func set_key(t: float, box: Rect2) -> void:
	for k in keys:
		var d: Dictionary = k
		if absf(float(d["t"]) - t) < 0.05:
			d["box"] = box
			tracked = false
			return
	keys.append({"t": t, "box": box})
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	tracked = false


func add_mark(t: float, uv: Vector2, r: float, fg: bool) -> void:
	marks.append({"t": t, "uv": uv, "r": r, "fg": fg})
	tracked = false


## Box at time `t`: from the track if there is one, otherwise the nearest key.
func box_at(t: float) -> Rect2:
	if tracked and not track.is_empty():
		var f := t * track_fps
		var i0 := int(floor(f))
		var i1 := i0 + 1
		var has0 := track.has(i0)
		var has1 := track.has(i1)
		if has0 and has1:
			var a: Rect2 = track[i0]
			var b: Rect2 = track[i1]
			return _lerp_rect(a, b, f - i0)
		if has0:
			return track[i0]
		if has1:
			return track[i1]
		# Outside the tracked range: hold the nearest end.
		var ks := track.keys()
		ks.sort()
		var first: int = ks[0]
		var last: int = ks[ks.size() - 1]
		return track[first] if f < first else track[last]
	if keys.is_empty():
		return Rect2(0, 0, 1, 1)
	var best: Dictionary = keys[0]
	for k in keys:
		var d: Dictionary = k
		if absf(float(d["t"]) - t) < absf(float(best["t"]) - t):
			best = d
	return best["box"]


static func _lerp_rect(a: Rect2, b: Rect2, w: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, w), a.size.lerp(b.size, w))


static func work_image(img: Image) -> Image:
	var w := WORK_W
	var h := maxi(8, int(round(float(WORK_W) * img.get_height() / float(img.get_width()))))
	var out := img.duplicate() as Image
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	out.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return out


# ================================================================ colour model

## `frames` maps key/mark times to full or proxy images of those moments.
func build_model(frame_for_time: Callable) -> void:
	var fg := PackedFloat32Array()
	var bg := PackedFloat32Array()
	fg.resize(BINS)
	bg.resize(BINS)
	var samples: Array = []  # [work image, box] per key
	for k in keys:
		var d: Dictionary = k
		var src: Image = frame_for_time.call(float(d["t"]))
		if src == null:
			continue
		var img := work_image(src)
		var box: Rect2 = d["box"]
		samples.append([img, box])
		_accumulate_box(img, box, fg, bg)
	for m in marks:
		var d: Dictionary = m
		var src: Image = frame_for_time.call(float(d["t"]))
		if src == null:
			continue
		_accumulate_mark(work_image(src), d["uv"], float(d["r"]), fg if bool(d["fg"]) else bg)
	_make_lut(fg, bg)
	# GrabCut-style refinement: re-learn the subject from what looks like it.
	for it in 2:
		var fg2 := PackedFloat32Array()
		fg2.resize(BINS)
		var bg2 := bg.duplicate()
		for sm in samples:
			var pair: Array = sm
			_refine(pair[0], pair[1], fg2, bg2)
		for m in marks:
			var d: Dictionary = m
			var src: Image = frame_for_time.call(float(d["t"]))
			if src != null:
				_accumulate_mark(work_image(src), d["uv"], float(d["r"]), fg2 if bool(d["fg"]) else bg2)
		_make_lut(fg2, bg2)


func _accumulate_box(img: Image, box: Rect2, fg: PackedFloat32Array, bg: PackedFloat32Array) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var inner := box.grow_individual(-box.size.x * 0.12, -box.size.y * 0.06, -box.size.x * 0.12, -box.size.y * 0.06)
	var outer := box.grow_individual(box.size.x * 0.08, box.size.y * 0.06, box.size.x * 0.08, box.size.y * 0.06)
	for y in h:
		var v := (y + 0.5) / h
		for x in w:
			var u := (x + 0.5) / w
			var i := (y * w + x) * 4
			if data[i + 3] < 8:
				continue
			var bin := ((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4)
			var p := Vector2(u, v)
			if inner.has_point(p):
				# Centre of the box counts more: the subject is usually there.
				var c := (p - box.get_center()) / (box.size * 0.5)
				fg[bin] += 0.4 + 0.6 * clampf(1.0 - c.length_squared(), 0.0, 1.0)
			elif not outer.has_point(p):
				bg[bin] += 1.0


func _accumulate_mark(img: Image, uv: Vector2, r: float, hist: PackedFloat32Array) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var rx := maxi(1, int(r * w))
	var cx := int(uv.x * w)
	var cy := int(uv.y * h)
	for y in range(maxi(0, cy - rx), mini(h, cy + rx + 1)):
		for x in range(maxi(0, cx - rx), mini(w, cx + rx + 1)):
			if Vector2(x - cx, y - cy).length() > rx:
				continue
			var i := (y * w + x) * 4
			var bin := ((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4)
			hist[bin] += 8.0


func _refine(img: Image, box: Rect2, fg: PackedFloat32Array, bg: PackedFloat32Array) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	for y in h:
		var v := (y + 0.5) / h
		for x in w:
			var u := (x + 0.5) / w
			if not box.has_point(Vector2(u, v)):
				continue
			var i := (y * w + x) * 4
			if data[i + 3] < 8:
				continue
			var bin := ((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4)
			var p := lut[bin]
			if p > 0.5:
				fg[bin] += p
			else:
				bg[bin] += (1.0 - p) * 0.5


func _make_lut(fg_in: PackedFloat32Array, bg_in: PackedFloat32Array) -> void:
	var fg := _blur_hist(fg_in)
	var bg := _blur_hist(bg_in)
	var fs := 0.0
	var bs := 0.0
	for i in BINS:
		fs += fg[i]
		bs += bg[i]
	fs = maxf(fs, 1e-6)
	bs = maxf(bs, 1e-6)
	lut.resize(BINS)
	var bytes := PackedByteArray()
	bytes.resize(BINS)
	for i in BINS:
		var f := fg[i] / fs + 1e-6
		var b := bg[i] / bs + 1e-6
		var p := f / (f + b)
		lut[i] = p
		bytes[i] = clampi(int(p * 255.0), 0, 255)
	# 64 × 64: bin i at (i % 64, i / 64)
	lut_image = Image.create_from_data(64, 64, false, Image.FORMAT_L8, bytes)


## Spreads each bin a little into its neighbours so unseen-but-similar
## colours still get a sensible answer.
static func _blur_hist(h: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BINS)
	for r in 16:
		for g in 16:
			for b in 16:
				var i := (r << 8) | (g << 4) | b
				var s := h[i] * 2.0
				var n := 2.0
				if r > 0:
					s += h[i - 256]
					n += 1.0
				if r < 15:
					s += h[i + 256]
					n += 1.0
				if g > 0:
					s += h[i - 16]
					n += 1.0
				if g < 15:
					s += h[i + 16]
					n += 1.0
				if b > 0:
					s += h[i - 1]
					n += 1.0
				if b < 15:
					s += h[i + 1]
					n += 1.0
				out[i] = s / n
	return out


## Subject probability for every work pixel inside `area` (UV); 0 elsewhere.
func probability(img: Image, area: Rect2 = Rect2(0, 0, 1, 1)) -> PackedFloat32Array:
	var w := img.get_width()
	var h := img.get_height()
	var out := PackedFloat32Array()
	out.resize(w * h)
	if lut.size() != BINS:
		return out
	var data := img.get_data()
	var a := area.intersection(Rect2(0, 0, 1, 1))
	var x0 := clampi(int(a.position.x * w), 0, w)
	var x1 := clampi(int(ceil(a.end.x * w)), 0, w)
	var y0 := clampi(int(a.position.y * h), 0, h)
	var y1 := clampi(int(ceil(a.end.y * h)), 0, h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := (y * w + x) * 4
			if data[i + 3] < 8:
				continue
			out[y * w + x] = lut[((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4)]
	return out


## Automatic background removal (no picking): colours seen along the left,
## right and top edges of the frame are background, colours in the middle
## are probably the subject; refined twice like GrabCut.
func build_auto_model(img: Image) -> void:
	var work := work_image(img)
	var w := work.get_width()
	var h := work.get_height()
	var data := work.get_data()
	var fg := PackedFloat32Array()
	var bg := PackedFloat32Array()
	fg.resize(BINS)
	bg.resize(BINS)
	var inner := Rect2(0.2, 0.12, 0.6, 0.8)
	for y in h:
		var v := (y + 0.5) / h
		for x in w:
			var u := (x + 0.5) / w
			var i := (y * w + x) * 4
			if data[i + 3] < 8:
				continue
			var bin := ((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4)
			var edge := minf(minf(u, 1.0 - u), v)
			if edge < 0.06:
				bg[bin] += 1.0
			elif 1.0 - v < 0.04:
				bg[bin] += 0.3  # subjects are often cut off at the bottom
			elif inner.has_point(Vector2(u, v)):
				var c := (Vector2(u, v) - Vector2(0.5, 0.55)) / Vector2(0.3, 0.4)
				fg[bin] += maxf(0.0, 1.0 - c.length_squared())
	_make_lut(fg, bg)
	for it in 2:
		var fg2 := PackedFloat32Array()
		fg2.resize(BINS)
		var bg2 := bg.duplicate()
		_refine(work, Rect2(0.06, 0.05, 0.88, 0.95), fg2, bg2)
		_make_lut(fg2, bg2)


# ================================================================ tracking

## Tracks across proxy frames [i_from, i_to]. `frame_at(index)` returns the
## proxy image for that index (or null). `progress(done, total)` is called as
## it goes. Returns false if cancelled (`should_stop` returns true).
func run_tracking(i_from: int, i_to: int, fps: float, frame_at: Callable, progress: Callable, should_stop: Callable, tree: SceneTree) -> bool:
	track.clear()
	tracked = false
	track_fps = fps
	if keys.is_empty() or i_to < i_from:
		return false
	var key_idx: Array = []
	for k in keys:
		var d: Dictionary = k
		key_idx.append(clampi(int(round(float(d["t"]) * fps)), i_from, i_to))
	var total := (i_to - i_from + 1) * 2
	var done := 0
	var fwd := {}  # index -> [Rect2, key index it came from]
	var bwd := {}
	# Forward from each key until the next key.
	for ki in keys.size():
		var start: int = key_idx[ki]
		var stop := i_to if ki == keys.size() - 1 else int(key_idx[ki + 1])
		var kd: Dictionary = keys[ki]
		var r: int = await _track_run(kd["box"], start, stop, 1, frame_at, fwd, should_stop, tree, progress, done, total)
		if r < 0:
			return false
		done = r
	# Backward from each key to the previous key.
	for ki in range(keys.size() - 1, -1, -1):
		var start: int = key_idx[ki]
		var stop := i_from if ki == 0 else int(key_idx[ki - 1])
		var kd: Dictionary = keys[ki]
		var r: int = await _track_run(kd["box"], start, stop, -1, frame_at, bwd, should_stop, tree, progress, done, total)
		if r < 0:
			return false
		done = r
	# Blend: between two keys, fade from the earlier key's forward track to
	# the later key's backward track.
	var raw := {}
	for i in range(i_from, i_to + 1):
		var prev_k := -1
		var next_k := -1
		for ki in keys.size():
			if int(key_idx[ki]) <= i:
				prev_k = ki
			if int(key_idx[ki]) >= i and next_k < 0:
				next_k = ki
		var has_f := fwd.has(i)
		var has_b := bwd.has(i)
		if has_f and has_b and prev_k >= 0 and next_k >= 0 and prev_k != next_k:
			var a := float(key_idx[prev_k])
			var b := float(key_idx[next_k])
			var w := smoothstep(0.0, 1.0, (i - a) / maxf(1.0, b - a))
			var rf: Rect2 = fwd[i]
			var rb: Rect2 = bwd[i]
			raw[i] = _lerp_rect(rf, rb, w)
		elif has_f:
			raw[i] = fwd[i]
		elif has_b:
			raw[i] = bwd[i]
	# Light smoothing over time to remove jitter.
	for i in range(i_from, i_to + 1):
		if not raw.has(i):
			continue
		var acc := Rect2()
		var wsum := 0.0
		for o in range(-2, 3):
			if raw.has(i + o):
				var wt := 3.0 - absf(o)
				var rr: Rect2 = raw[i + o]
				acc.position += rr.position * wt
				acc.size += rr.size * wt
				wsum += wt
		track[i] = Rect2(acc.position / wsum, acc.size / wsum)
	# Keys are exact.
	for ki in keys.size():
		var kd: Dictionary = keys[ki]
		track[int(key_idx[ki])] = kd["box"]
	tracked = true
	return true


func _track_run(start_box: Rect2, i_start: int, i_stop: int, dir: int, frame_at: Callable, out: Dictionary, should_stop: Callable, tree: SceneTree, progress: Callable, done: int, total: int) -> int:
	var box := start_box
	var ref_mass := -1.0
	var i := i_start
	while true:
		if should_stop.call():
			return -1
		var src: Image = frame_at.call(i)
		if src != null:
			var img := work_image(src)
			var res := _mean_shift(img, box)
			var mass: float = res["mass"]
			if ref_mass < 0.0:
				ref_mass = maxf(mass, 1e-3)
				out[i] = box
			elif mass > ref_mass * 0.08:
				var nb: Rect2 = res["box"]
				# Size follows the subject's mass, a little at a time.
				var sc := clampf(sqrt(mass / ref_mass), 0.6, 1.8)
				var target := start_box.size * sc
				var size := box.size.lerp(target, 0.25)
				size = size.clamp(box.size * 0.92, box.size * 1.08)
				box = Rect2(nb.get_center() - size * 0.5, size)
				out[i] = box
			else:
				out[i] = box  # lost: hold position until it reappears
		done += 1
		if progress.is_valid():
			progress.call(done, total)
		if done % 2 == 0:
			await tree.process_frame
		if i == i_stop:
			break
		i += dir
	return done


## Mean-shift: move the box to the probability-weighted centre, repeatedly.
func _mean_shift(img: Image, box: Rect2) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var search := box.grow_individual(box.size.x * 0.6, box.size.y * 0.4, box.size.x * 0.6, box.size.y * 0.4)
	var p := probability(img, search)
	var b := box
	var mass := 0.0
	for it in 10:
		var x0 := clampi(int(b.position.x * w), 0, w - 1)
		var x1 := clampi(int(ceil(b.end.x * w)), 1, w)
		var y0 := clampi(int(b.position.y * h), 0, h - 1)
		var y1 := clampi(int(ceil(b.end.y * h)), 1, h)
		var sx := 0.0
		var sy := 0.0
		mass = 0.0
		for y in range(y0, y1):
			for x in range(x0, x1):
				var v := p[y * w + x]
				if v < 0.3:
					continue
				v = v * v
				sx += v * x
				sy += v * y
				mass += v
		if mass < 1e-3:
			break
		var c := Vector2((sx / mass + 0.5) / w, (sy / mass + 0.5) / h)
		var shift := c - b.get_center()
		b.position += shift
		b.position = b.position.clamp(-b.size * 0.5, Vector2.ONE - b.size * 0.5)
		if shift.length() < 0.5 / w:
			break
	return {"box": b, "mass": mass}


# ================================================================ mask

## Low-res mask (FORMAT_L8, work size) of the subject in `img` at `box`.
func support_mask(img: Image, box: Rect2, cut: float = 0.5, fallback: bool = true, main_only: bool = false) -> Image:
	var work := work_image(img)
	var w := work.get_width()
	var h := work.get_height()
	var near := box.grow_individual(box.size.x * 0.25, box.size.y * 0.15, box.size.x * 0.25, box.size.y * 0.15)
	var p := probability(work, near)
	var m := PackedByteArray()
	m.resize(w * h)
	var c := box.get_center()
	var half := box.size * 0.5
	for y in h:
		var v := (y + 0.5) / h
		for x in w:
			var u := (x + 0.5) / w
			# "Near the box" prior: full inside, fading out over a margin.
			var dx := maxf(0.0, absf(u - c.x) - half.x) / maxf(0.001, box.size.x * 0.2)
			var dy := maxf(0.0, absf(v - c.y) - half.y) / maxf(0.001, box.size.y * 0.12)
			var prior := clampf(1.0 - maxf(dx, dy), 0.0, 1.0)
			m[y * w + x] = 1 if p[y * w + x] * prior > cut else 0
	_keep_subject_blobs(m, w, h, box)
	if main_only:
		_keep_main_blobs(m, w, h)
	# Safety net: if the colour model found (almost) nothing inside the box,
	# loosen the cut, and failing that keep an oval inside the box, so a
	# subject is never wiped out completely.
	var box_px := maxf(1.0, box.size.x * w * box.size.y * h)
	if fallback and _count(m) < box_px * 0.03:
		for y in h:
			var v := (y + 0.5) / h
			for x in w:
				var u := (x + 0.5) / w
				m[y * w + x] = 1 if box.has_point(Vector2(u, v)) and p[y * w + x] > cut * 0.6 else 0
		_keep_subject_blobs(m, w, h, box)
		if _count(m) < box_px * 0.03:
			for y in h:
				var v := (y + 0.5) / h
				for x in w:
					var d := (Vector2((x + 0.5) / w, v) - c) / Vector2(maxf(half.x, 0.0001), maxf(half.y, 0.0001))
					m[y * w + x] = 1 if d.length() <= 1.0 else 0
	_fill_holes(m, w, h, box)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in w * h:
		bytes[i] = 255 if m[i] != 0 else 0
	var out := Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes)
	return out


static func _count(m: PackedByteArray) -> int:
	var n := 0
	for v in m:
		n += v
	return n


## Keeps connected blobs that mostly sit inside the box (and the biggest one).
func _keep_subject_blobs(m: PackedByteArray, w: int, h: int, box: Rect2) -> void:
	var labels := PackedInt32Array()
	labels.resize(w * h)
	var sizes: Array[int] = [0]
	var inside: Array[int] = [0]
	var next := 1
	var stack := PackedInt32Array()
	for start in w * h:
		if m[start] == 0 or labels[start] != 0:
			continue
		var count := 0
		var in_count := 0
		stack.clear()
		stack.append(start)
		labels[start] = next
		while not stack.is_empty():
			var idx := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var x := idx % w
			var y := idx / w
			if box.has_point(Vector2((x + 0.5) / w, (y + 0.5) / h)):
				in_count += 1
			if x > 0 and m[idx - 1] != 0 and labels[idx - 1] == 0:
				labels[idx - 1] = next
				stack.append(idx - 1)
			if x < w - 1 and m[idx + 1] != 0 and labels[idx + 1] == 0:
				labels[idx + 1] = next
				stack.append(idx + 1)
			if y > 0 and m[idx - w] != 0 and labels[idx - w] == 0:
				labels[idx - w] = next
				stack.append(idx - w)
			if y < h - 1 and m[idx + w] != 0 and labels[idx + w] == 0:
				labels[idx + w] = next
				stack.append(idx + w)
		sizes.append(count)
		inside.append(in_count)
		next += 1
	var best := 0
	for l in range(1, next):
		if inside[l] > inside[best]:
			best = l
	var box_px := box.size.x * w * box.size.y * h
	var keep := {}
	for l in range(1, next):
		if l == best or (inside[l] >= sizes[l] * 0.5 and sizes[l] >= box_px * 0.01):
			keep[l] = true
	for i in w * h:
		if m[i] != 0 and not keep.has(labels[i]):
			m[i] = 0


## Automatic mode: keeps the main subject — the blob scoring highest on
## size × how central it is — plus any blob scoring at least half as well
## (a second person beside them), and drops the rest (bright windows, lamps,
## posters that just don't look like the edges of the frame).
func _keep_main_blobs(m: PackedByteArray, w: int, h: int) -> void:
	var labels := PackedInt32Array()
	labels.resize(w * h)
	var scores: Array[float] = [0.0]
	var stack := PackedInt32Array()
	var next := 1
	for start in w * h:
		if m[start] == 0 or labels[start] != 0:
			continue
		var count := 0
		var sum := Vector2.ZERO
		stack.clear()
		stack.append(start)
		labels[start] = next
		while not stack.is_empty():
			var idx := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var x := idx % w
			var y := idx / w
			sum += Vector2(x, y)
			for nb in [idx - 1 if x > 0 else -1, idx + 1 if x < w - 1 else -1, idx - w if y > 0 else -1, idx + w if y < h - 1 else -1]:
				var n: int = nb
				if n >= 0 and m[n] != 0 and labels[n] == 0:
					labels[n] = next
					stack.append(n)
		var centre := sum / count
		var off := Vector2((centre.x + 0.5) / w - 0.5, (centre.y + 0.5) / h - 0.5) * 2.0
		var central := clampf(1.0 - off.length() * 0.75, 0.05, 1.0)
		scores.append(float(count) * central * central)
		next += 1
	if next <= 2:
		return
	var best := 0.0
	for l in range(1, next):
		best = maxf(best, scores[l])
	for i in w * h:
		if m[i] != 0 and scores[labels[i]] < best * 0.5:
			m[i] = 0


## Fills small enclosed gaps (bits of the subject coloured like the background).
func _fill_holes(m: PackedByteArray, w: int, h: int, box: Rect2) -> void:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	var limit := box.size.x * w * box.size.y * h * 0.04
	for start in w * h:
		if m[start] != 0 or seen[start] != 0:
			continue
		var region := PackedInt32Array()
		var touches_edge := false
		stack.clear()
		stack.append(start)
		seen[start] = 1
		while not stack.is_empty():
			var idx := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			region.append(idx)
			var x := idx % w
			var y := idx / w
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				touches_edge = true
			for n in [idx - 1, idx + 1, idx - w, idx + w]:
				var ni: int = n
				if ni < 0 or ni >= w * h:
					continue
				if (ni == idx - 1 and x == 0) or (ni == idx + 1 and x == w - 1):
					continue
				if m[ni] == 0 and seen[ni] == 0:
					seen[ni] = 1
					stack.append(ni)
		if not touches_edge and region.size() < limit:
			for idx in region:
				m[idx] = 1
