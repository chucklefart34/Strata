class_name EpisodeData
extends RefCounted
## An episode: an ordered list of entries that *reference* scenes (never copy
## them), plus title cards, credits and an episode-wide soundtrack.
## Editing a scene automatically changes every episode that uses it.
##
## Entry dictionaries:
##   scene:   {id, type:"scene", scene_id, trim_in, trim_out, transition, transition_frames,
##             overlay_text, overlay_style, overlay_start, overlay_end, notes}
##   title:   {id, type:"title", text, subtitle, preset, animation, duration,
##             bg, color, transition, transition_frames, notes}
##   credits: same as title with type:"credits" (text scrolls, one line per credit)

const STATUSES := ["Planning", "Storyboard", "Layout", "Animation", "Audio", "Compositing", "Final"]
const TRANSITIONS := ["cut", "fade", "dissolve", "wipe"]
const TRANSITION_LABELS := {"cut": "Cut", "fade": "Fade through black", "dissolve": "Dissolve", "wipe": "Wipe"}
const TITLE_PRESETS := ["classic", "bold", "minimal", "chapter"]
const TITLE_ANIMS := ["fade", "rise", "typewriter", "none"]
const OVERLAY_STYLES := ["lower_third", "subtitle", "caption"]

var id: String = ""
var title: String = "Episode"
var number: int = 1
var description: String = ""
var status: String = "Planning"
var entries: Array = []  # Array of Dictionaries (see above)
var audio_tracks: Array[AudioTrackData] = []  # soundtrack in episode time
## Effect clips on the effects track, in episode frames (see VideoFx).
var effects: Array = []


func _init(p_title: String = "Episode", p_number: int = 1) -> void:
	id = Ids.make()
	title = p_title
	number = p_number


static func new_scene_entry(scene_id: String) -> Dictionary:
	return {
		"id": Ids.make(), "type": "scene", "scene_id": scene_id, "trim_in": 0, "trim_out": 0,
		"transition": "cut", "transition_frames": 12,
		"overlay_text": "", "overlay_style": "lower_third", "overlay_start": 0, "overlay_end": 72,
		"notes": "",
	}


static func new_title_entry(text: String, credits: bool = false) -> Dictionary:
	return {
		"id": Ids.make(), "type": "credits" if credits else "title",
		"text": text, "subtitle": "", "preset": "classic", "animation": "none" if credits else "fade",
		"duration": 240 if credits else 72, "bg": "101116ff", "color": "ffffffff",
		"transition": "fade", "transition_frames": 12, "notes": "",
	}


## Timing of every entry. Dissolves and wipes overlap the previous entry by
## their length; fades and cuts don't overlap.
func schedule(project: ProjectData) -> Array:
	var out := []
	var cursor := 0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var scene: SceneData = null
		var length := 1
		if str(e.get("type", "")) == "scene":
			scene = _find_scene(project, str(e.get("scene_id", "")))
			if scene != null:
				length = maxi(1, scene.frame_count - int(e.get("trim_in", 0)) - int(e.get("trim_out", 0)))
		else:
			length = maxi(1, int(e.get("duration", 72)))
		var start := cursor
		var tr := str(e.get("transition", "cut"))
		var overlap := 0
		if i > 0 and (tr == "dissolve" or tr == "wipe"):
			var prev: Dictionary = out[out.size() - 1]
			overlap = mini(int(e.get("transition_frames", 12)), mini(length, int(prev["length"])))
			start = cursor - overlap
		out.append({"entry": e, "index": i, "start": start, "length": length, "scene": scene, "overlap": overlap})
		cursor = start + length
	return out


static func total_frames(sched: Array) -> int:
	if sched.is_empty():
		return 0
	var last: Dictionary = sched[sched.size() - 1]
	return int(last["start"]) + int(last["length"])


static func _find_scene(project: ProjectData, scene_id: String) -> SceneData:
	for s in project.scenes:
		if s.id == scene_id:
			return s
	return null


## What is visible at episode frame `f`:
## {a: slot, b: slot or null, mix: 0..1, mode: "dissolve"/"wipe", fade: 0..1}
## A slot is {sched, local} where `local` is the frame inside the scene/title.
static func frame_state(sched: Array, f: int) -> Dictionary:
	var active := []
	for item in sched:
		var s: Dictionary = item
		var st: int = s["start"]
		if f >= st and f < st + int(s["length"]):
			active.append(s)
	var state := {"a": null, "b": null, "mix": 0.0, "mode": "", "fade": 0.0}
	if active.is_empty():
		return state
	var inc: Dictionary = active[active.size() - 1]
	state["a"] = _slot(inc, f)
	if active.size() >= 2:
		var out_s: Dictionary = active[active.size() - 2]
		state["b"] = _slot(out_s, f)
		var ov := maxi(1, int(inc["overlap"]))
		state["mix"] = clampf(float(f - int(inc["start"]) + 1) / ov, 0.0, 1.0)
		var inc_entry: Dictionary = inc["entry"]
		state["mode"] = str(inc_entry.get("transition", "dissolve"))
	# Fades through black: second half of the outgoing, first half of the incoming.
	var e: Dictionary = inc["entry"]
	var rel := f - int(inc["start"])
	if str(e.get("transition", "cut")) == "fade" and int(inc["index"]) > 0:
		var half := maxi(1, int(e.get("transition_frames", 12)) / 2)
		if rel < half:
			state["fade"] = 1.0 - float(rel) / half
	var idx: int = inc["index"]
	if idx + 1 < sched.size():
		var nxt: Dictionary = sched[idx + 1]
		var ne: Dictionary = nxt["entry"]
		if str(ne.get("transition", "cut")) == "fade":
			var half_n := maxi(1, int(ne.get("transition_frames", 12)) / 2)
			var end := int(inc["start"]) + int(inc["length"])
			if f >= end - half_n:
				state["fade"] = maxf(float(state["fade"]), float(f - (end - half_n) + 1) / half_n)
	return state


static func _slot(s: Dictionary, f: int) -> Dictionary:
	var e: Dictionary = s["entry"]
	var local := f - int(s["start"])
	if str(e.get("type", "")) == "scene":
		local += int(e.get("trim_in", 0))
	return {"sched": s, "local": local}


func to_dict() -> Dictionary:
	var tl := []
	for t in audio_tracks:
		tl.append(t.to_dict())
	return {
		"id": id, "title": title, "number": number, "description": description,
		"status": status, "entries": entries.duplicate(true), "audio_tracks": tl,
		"effects": effects.duplicate(true),
	}


static func from_dict(d: Dictionary) -> EpisodeData:
	var ep := EpisodeData.new(str(d.get("title", "Episode")), int(d.get("number", 1)))
	ep.id = str(d.get("id", ep.id))
	ep.description = str(d.get("description", ""))
	ep.status = str(d.get("status", "Planning"))
	var ents: Array = d.get("entries", [])
	for item in ents:
		var e: Dictionary = item
		var copy := e.duplicate(true)
		for k in ["trim_in", "trim_out", "transition_frames", "overlay_start", "overlay_end", "duration"]:
			if copy.has(k):
				copy[k] = int(copy[k])
		ep.entries.append(copy)
	for td in d.get("audio_tracks", []):
		ep.audio_tracks.append(AudioTrackData.from_dict(td))
	var fxs: Array = d.get("effects", [])
	for item in fxs:
		var fx: Dictionary = item
		var copy := fx.duplicate(true)
		for k in ["start", "length", "fade_in", "fade_out"]:
			copy[k] = int(copy.get(k, 0))
		copy["length"] = maxi(1, int(copy["length"]))
		ep.effects.append(copy)
	return ep


func clone_deep() -> EpisodeData:
	var ep := EpisodeData.from_dict(to_dict())
	ep.id = Ids.make()
	ep.title = title + " copy"
	for e in ep.entries:
		var ed: Dictionary = e
		ed["id"] = Ids.make()
	for e in ep.effects:
		var fd: Dictionary = e
		fd["id"] = Ids.make()
	return ep
