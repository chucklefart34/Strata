class_name VideoFx
extends RefCounted
## The episode effects library. An effect is a clip on the episode's effects
## track that changes the whole picture while it runs, like an adjustment
## layer in a video editor. Several can overlap; they apply in track order.
##
## Effect clip dictionary:
##   {id, type, start, length, amount (0..1), param (0..1), color, fade_in, fade_out}

## [id, label, category, param label ("" = none), uses colour, default seconds, default amount]
const EFFECTS := [
	["vhs", "VHS tape", "Retro", "Tape wear", false, 3.0, 0.8],
	["film", "Old film", "Retro", "Sepia", false, 3.0, 0.8],
	["crt", "CRT TV", "Retro", "Curve", false, 3.0, 0.7],
	["grain", "Film grain", "Retro", "Grain size", false, 3.0, 0.5],
	["glitch", "Glitch", "Glitch", "Chaos", false, 1.0, 0.7],
	["datamosh", "Datamosh", "Glitch", "Melt (stretch & bloom)", false, 2.5, 0.85],
	["gross", "Gross / crunchy", "Glitch", "Block size", false, 2.0, 0.8],
	["deepfried", "Deep fried", "Glitch", "", false, 1.5, 0.8],
	["rgbsplit", "RGB split", "Glitch", "Direction", false, 1.0, 0.6],
	["echo", "Echo trails", "Motion", "", false, 2.0, 0.7],
	["shake", "Camera shake", "Motion", "Speed", false, 1.0, 0.6],
	["zoom", "Zoom punch", "Motion", "Zoom", false, 0.5, 1.0],
	["wave", "Wavy", "Distort", "Waves", false, 2.0, 0.6],
	["pixelate", "Pixelate", "Distort", "", false, 1.0, 0.6],
	["blur", "Blur", "Distort", "", false, 1.0, 0.6],
	["mirror", "Mirror", "Distort", "Mode", false, 2.0, 1.0],
	["fisheye", "Fisheye", "Distort", "", false, 2.0, 0.7],
	["bw", "Black & white", "Color", "Contrast", false, 3.0, 1.0],
	["sepia", "Sepia", "Color", "", false, 3.0, 1.0],
	["invert", "Invert", "Color", "", false, 0.5, 1.0],
	["posterize", "Posterize", "Color", "", false, 2.0, 0.6],
	["tint", "Color tint", "Color", "Mono tint", true, 3.0, 0.6],
	["punchy", "Punchy colors", "Color", "Contrast", false, 3.0, 0.6],
	["vignette", "Vignette", "Color", "Size", true, 3.0, 0.7],
	["flash", "Flash", "Color", "", true, 0.25, 1.0],
	["bars", "Cinema bars", "Frame", "", false, 3.0, 0.8],
]

const MAX_ACTIVE := 8


static func index_of(type: String) -> int:
	for i in EFFECTS.size():
		if str(EFFECTS[i][0]) == type:
			return i
	return 0


static func info(type: String) -> Array:
	return EFFECTS[index_of(type)]


static func label(type: String) -> String:
	return str(info(type)[1])


static func categories() -> Array:
	var out: Array = []
	for e in EFFECTS:
		if not out.has(e[2]):
			out.append(e[2])
	return out


static func make(type: String, start: int, fps: int) -> Dictionary:
	var inf := info(type)
	var length := maxi(1, int(round(float(inf[5]) * fps)))
	var short := length <= fps
	return {
		"id": Ids.make(), "type": type, "start": maxi(0, start), "length": length,
		"amount": float(inf[6]), "param": 0.5, "color": "ffffffff" if type == "flash" else ("ff8a3dff" if type == "tint" else "000000ff"),
		"fade_in": 0 if short else mini(6, length / 4), "fade_out": mini(6, length / 3) if short else mini(6, length / 4),
	}


## Effects running at frame `f`, in track order, each as
## {fx: Dictionary, index: int (shader effect number), amount: float (with fades)}.
static func active_at(effects: Array, f: int) -> Array:
	var out: Array = []
	for item in effects:
		var e: Dictionary = item
		var st := int(e.get("start", 0))
		var ln := int(e.get("length", 1))
		if f < st or f >= st + ln:
			continue
		var env := 1.0
		var fi := int(e.get("fade_in", 0))
		var fo := int(e.get("fade_out", 0))
		if fi > 0:
			env = minf(env, float(f - st + 1) / fi)
		if fo > 0:
			env = minf(env, float(st + ln - f) / fo)
		var a := clampf(float(e.get("amount", 1.0)), 0.0, 1.0) * clampf(env, 0.0, 1.0)
		if a <= 0.001:
			continue
		out.append({"fx": e, "index": index_of(str(e.get("type", ""))), "amount": a})
		if out.size() >= MAX_ACTIVE:
			break
	return out


## Stacks overlapping clips into rows for the timeline: id -> row.
static func lanes(effects: Array) -> Dictionary:
	var sorted := effects.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("start", 0)) < int(b.get("start", 0)))
	var ends: Array[int] = []
	var out := {}
	for item in sorted:
		var e: Dictionary = item
		var st := int(e.get("start", 0))
		var row := -1
		for r in ends.size():
			if ends[r] <= st:
				row = r
				break
		if row < 0:
			row = ends.size()
			ends.append(0)
		ends[row] = st + int(e.get("length", 1))
		out[str(e.get("id", ""))] = row
	return out


static func category_color(cat: String) -> Color:
	match cat:
		"Retro":
			return Color("#d9a441")
		"Glitch":
			return Color("#e0517a")
		"Motion":
			return Color("#4c8dff")
		"Distort":
			return Color("#8f6cf0")
		"Color":
			return Color("#3fbf8f")
		"Hand-drawn":
			return Color("#f07c4a")
	return Color("#9aa0ae")
