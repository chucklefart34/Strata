class_name AudioClipData
extends RefCounted
## A piece of imported audio placed on a track. `file` is relative to the
## project folder (audio/<id>.<ext>) so projects stay portable.
## Timing: the clip starts at `start_frame` on the scene timeline, plays the
## source from `trim_in` seconds, for `length` seconds (looping the source if
## `loop` is on).

var id: String = ""
var name: String = "Clip"
var file: String = ""
var start_frame: int = 0
var trim_in: float = 0.0
var length: float = 1.0
var gain_db: float = 0.0
var fade_in: float = 0.0
var fade_out: float = 0.0
var loop: bool = false


func _init() -> void:
	id = Ids.make()


func start_time(fps: int) -> float:
	return start_frame / float(maxi(fps, 1))


func end_time(fps: int) -> float:
	return start_time(fps) + length


func end_frame(fps: int) -> int:
	return start_frame + ceili(length * fps)


## Position in the source file (seconds) at scene time `t`, or -1 when the
## clip is silent at that time.
func source_pos(t: float, fps: int, stream_length: float) -> float:
	var rel := t - start_time(fps)
	if rel < 0.0 or rel >= length:
		return -1.0
	if loop:
		var span := stream_length - trim_in
		if span <= 0.01:
			return -1.0
		return trim_in + fmod(rel, span)
	var pos := trim_in + rel
	return pos if pos < stream_length else -1.0


## Linear gain from the fades at scene time `t` (1.0 = full).
func fade_gain(t: float, fps: int) -> float:
	var rel := t - start_time(fps)
	var g := 1.0
	if fade_in > 0.0 and rel < fade_in:
		g = minf(g, clampf(rel / fade_in, 0.0, 1.0))
	if fade_out > 0.0 and rel > length - fade_out:
		g = minf(g, clampf((length - rel) / fade_out, 0.0, 1.0))
	return g


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "file": file, "start_frame": start_frame,
		"trim_in": trim_in, "length": length, "gain_db": gain_db,
		"fade_in": fade_in, "fade_out": fade_out, "loop": loop,
	}


func apply_dict(d: Dictionary) -> void:
	name = str(d.get("name", name))
	file = str(d.get("file", file))
	start_frame = int(d.get("start_frame", start_frame))
	trim_in = float(d.get("trim_in", trim_in))
	length = maxf(0.01, float(d.get("length", length)))
	gain_db = float(d.get("gain_db", gain_db))
	fade_in = maxf(0.0, float(d.get("fade_in", fade_in)))
	fade_out = maxf(0.0, float(d.get("fade_out", fade_out)))
	loop = bool(d.get("loop", loop))


static func from_dict(d: Dictionary) -> AudioClipData:
	var c := AudioClipData.new()
	c.id = str(d.get("id", c.id))
	c.apply_dict(d)
	return c


func copy() -> AudioClipData:
	var c := AudioClipData.from_dict(to_dict())
	c.id = Ids.make()
	return c
