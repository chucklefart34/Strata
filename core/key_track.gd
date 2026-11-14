class_name KeyTrack
extends RefCounted
## Shared keyframe interpolation used by the scene camera and layer motion.
## A track is a Dictionary: int frame -> Dictionary of float fields + "ease".
## The ease stored on a key controls the motion from that key to the next.

const EASES := ["smooth", "linear", "ease_in", "ease_out", "hold"]


static func ease_t(t: float, mode: String) -> float:
	match mode:
		"linear":
			return t
		"ease_in":
			return t * t
		"ease_out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"hold":
			return 0.0
		_:
			return t * t * (3.0 - 2.0 * t)


static func filled(src: Dictionary, defaults: Dictionary) -> Dictionary:
	var d := defaults.duplicate()
	for k in src.keys():
		d[k] = src[k]
	return d


## Value of every field at `frame`. Missing fields come from `defaults`.
static func sample(keys: Dictionary, frame: float, fields: Array, defaults: Dictionary) -> Dictionary:
	if keys.is_empty():
		return defaults.duplicate()
	var sorted := keys.keys()
	sorted.sort()
	var first: int = sorted[0]
	var last: int = sorted[sorted.size() - 1]
	if frame <= first:
		return filled(keys[first], defaults)
	if frame >= last:
		return filled(keys[last], defaults)
	var k0 := first
	var k1 := last
	for k in sorted:
		var ki: int = k
		if ki <= frame:
			k0 = ki
		else:
			k1 = ki
			break
	var a := filled(keys[k0], defaults)
	var b := filled(keys[k1], defaults)
	var t := ease_t((frame - k0) / float(k1 - k0), str(a.get("ease", "smooth")))
	var out := {}
	for f in fields:
		out[f] = lerpf(float(a[f]), float(b[f]), t)
	out["ease"] = a.get("ease", "smooth")
	return out


static func to_list(keys: Dictionary, fields: Array, defaults: Dictionary) -> Array:
	var out := []
	var sorted := keys.keys()
	sorted.sort()
	for k in sorted:
		var entry := filled(keys[k], defaults)
		entry["frame"] = k
		out.append(entry)
	return out


static func from_list(list: Array, fields: Array, defaults: Dictionary) -> Dictionary:
	var keys := {}
	for item in list:
		var e: Dictionary = item
		var key := {}
		for f in fields:
			key[f] = float(e.get(f, defaults.get(f, 0.0)))
		key["ease"] = str(e.get("ease", "smooth"))
		keys[int(e.get("frame", 0))] = key
	return keys


## Copy of `keys` restricted to [start, end] and shifted by -start + offset.
static func slice(keys: Dictionary, start: int, end: int, offset: int = 0) -> Dictionary:
	var out := {}
	for k in keys.keys():
		var ki: int = k
		if ki >= start and ki <= end:
			var v: Variant = keys[k]
			out[ki - start + offset] = v.duplicate() if typeof(v) == TYPE_DICTIONARY else v
	return out
