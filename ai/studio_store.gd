extends Node
## "Studio" autoload: the AI Studio's memory for the open project.
##
## Everything is kept in <project>/ai_studio/:
##   studio.json          style profile, references, cast, shots, jobs, chat
##   refs/<id>.png        reference images (yours, and generated sheets)
##   renders/<shot>/…     every generated drawing ("take"), never overwritten
##   guides/…             snapshots of your roughs used to guide drawings
##
## It is saved by itself a moment after every change (atomic write with a
## .bak copy), separately from the project's Save, so queued work, results
## and decisions survive a crash or a closed window.

signal changed(kind: String)  # "style", "refs", "cast", "shots", "jobs", "chat", "all"

const FILE := "studio.json"
const VERSION := 1
const KINDS := ["key", "breakdown", "inbetween"]
const CAMERA_PRESETS := ["none", "push_in", "pull_out", "pan_left", "pan_right", "truck", "crane_up", "zoom_in", "shake"]
const REF_CATEGORIES := ["character", "face", "clothing", "environment", "palette", "lighting", "background", "style", "linework", "animation"]
const SHEET_VIEWS := ["front", "side", "back", "expressions"]

## The house look: an original mature graphic-novel style described by its
## qualities only (no artist, studio or title names, on purpose).
const HOUSE_STYLE := "mature hand-drawn 2D animation frame, gothic graphic-novel atmosphere, expressive inked linework with varied line weight, heavy spot blacks and crosshatched shadows, noir chiaroscuro lighting, muted desaturated palette with one selective accent colour, cinematic composition, painterly textured backgrounds, anime-influenced expressive faces and fluid acting, detailed eyes, dark fantasy and psychological horror mood, adult tone"
const HOUSE_NEGATIVE := "photorealistic, photo, 3d render, cgi, plastic skin, chibi, children's cartoon, cute, flat vector art, clip art, glossy, generic anime screenshot, oversaturated, text, speech bubble, caption, watermark, signature, logo, frame border, extra fingers, fused fingers, malformed hands, extra limbs, distorted face, asymmetrical eyes, blurry, lowres, jpeg artifacts"

var data: Dictionary = _blank()
var _root: String = ""
var _save_timer: Timer
var _img_cache: Dictionary = {}  # path -> Image
var _img_order: Array = []
const CACHE_MAX := 48


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.8
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	App.project_opened.connect(_on_project_opened)
	App.project_closed.connect(_on_project_closed)


func has_studio() -> bool:
	return _root != ""


func dir() -> String:
	return _root


func _on_project_opened() -> void:
	if _root != "":
		save_now()
	_img_cache.clear()
	_img_order.clear()
	_root = App.project.root_dir.path_join("ai_studio") if App.project.root_dir != "" else ""
	data = _blank()
	if _root != "":
		DirAccess.make_dir_recursive_absolute(_root)
		_load()
	changed.emit("all")


func _on_project_closed() -> void:
	if _root != "":
		save_now()
	_root = ""
	data = _blank()
	_img_cache.clear()
	_img_order.clear()
	changed.emit("all")


static func _blank() -> Dictionary:
	return {
		"format": "strata-ai-studio", "version": VERSION,
		"style": {"name": "House style", "descriptors": HOUSE_STYLE, "negative": HOUSE_NEGATIVE,
			"line": "", "shading": "", "lighting": "", "palette": [], "ref_ids": [], "style_weight": 0.45},
		"refs": [], "cast": [], "shots": [], "jobs": [], "chat": [], "paused": false,
	}


func _load() -> void:
	var path := _root.path_join(FILE)
	var parsed: Variant = null
	for p in [path, path + ".bak"]:
		if FileAccess.file_exists(p):
			parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(parsed) == TYPE_DICTIONARY:
				break
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var blank := _blank()
	for k in blank.keys():
		if d.has(k):
			data[k] = d[k]
	var style: Dictionary = data["style"]
	for k in (blank["style"] as Dictionary).keys():
		if not style.has(k):
			style[k] = blank["style"][k]
	# Recovery: work that was on the GPU when the app closed goes back in line.
	for j in data["jobs"]:
		var jd: Dictionary = j
		if str(jd.get("status", "")) == "running":
			jd["status"] = "queued"
			jd["recovered"] = true
	for s in data["shots"]:
		for dr in (s as Dictionary).get("drawings", []):
			var dd: Dictionary = dr
			if str(dd.get("status", "")) == "rendering":
				dd["status"] = "queued"


## Marks the store changed and schedules a save.
func touch(kind: String) -> void:
	if _root == "":
		return
	_save_timer.start()
	changed.emit(kind)


func save_now() -> void:
	if _root == "":
		return
	_save_timer.stop()
	DirAccess.make_dir_recursive_absolute(_root)
	var path := _root.path_join(FILE)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("AI Studio: could not save " + tmp)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


# ================================================================ images

func abs_path(rel: String) -> String:
	return _root.path_join(rel)


func load_image(rel: String) -> Image:
	if rel == "":
		return null
	var p := abs_path(rel)
	if _img_cache.has(p):
		return _img_cache[p]
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	_img_cache[p] = img
	_img_order.append(p)
	if _img_order.size() > CACHE_MAX:
		_img_cache.erase(_img_order.pop_front())
	return img


func save_image(img: Image, rel: String) -> bool:
	var p := abs_path(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	if img.save_png(p) != OK:
		return false
	_img_cache.erase(p)
	return true


# ================================================================ style

func style() -> Dictionary:
	return data["style"]


func set_style(changes: Dictionary) -> void:
	var st := style()
	for k in changes.keys():
		if st.has(k) or k in ["descriptors", "negative", "line", "shading", "lighting", "name"]:
			st[k] = changes[k]
	touch("style")


# ================================================================ references

func refs() -> Array:
	return data["refs"]


func find_ref(id: String) -> Dictionary:
	for r in refs():
		if str((r as Dictionary).get("id", "")) == id:
			return r
	return {}


## Copies a picture into the project and analyses it. Returns the ref or {}.
func add_reference_image(img: Image, ref_name: String, category: String, char_id: String = "", notes: String = "") -> Dictionary:
	if _root == "":
		return {}
	var id := Ids.make()
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	# Keep references a sensible size (they guide, they aren't the artwork).
	var k := minf(1.0, 1536.0 / maxi(src.get_width(), src.get_height()))
	if k < 1.0:
		src.resize(int(src.get_width() * k), int(src.get_height() * k), Image.INTERPOLATE_LANCZOS)
	var rel := "refs/%s.png" % id
	if not save_image(src, rel):
		return {}
	var ref := {
		"id": id, "file": rel, "name": ref_name, "category": category if REF_CATEGORIES.has(category) else "style",
		"character_id": char_id, "notes": notes, "analysis": RefAnalyzer.analyze(src),
		"ai_description": "", "added": Time.get_datetime_string_from_system(),
	}
	refs().append(ref)
	touch("refs")
	return ref


func add_reference_file(path: String, category: String, char_id: String = "") -> String:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return "Couldn't read " + path.get_file()
	var r := add_reference_image(img, path.get_file().get_basename(), category, char_id)
	return "" if not r.is_empty() else "Couldn't store " + path.get_file()


func delete_ref(id: String) -> void:
	var r := find_ref(id)
	if r.is_empty():
		return
	refs().erase(r)
	var st := style()
	(st["ref_ids"] as Array).erase(id)
	for c in cast():
		var cd: Dictionary = c
		(cd.get("ref_ids", []) as Array).erase(id)
		var sheets: Dictionary = cd.get("sheets", {})
		for v in sheets.keys():
			if str(sheets[v]) == id:
				sheets.erase(v)
	touch("refs")


func ref_image(id: String) -> Image:
	var r := find_ref(id)
	return load_image(str(r.get("file", ""))) if not r.is_empty() else null


## Rebuilds the style profile's palette and wording from its references.
func rebuild_style_from_refs() -> void:
	var st := style()
	var ids: Array = st["ref_ids"]
	var analyses: Array = []
	for id in ids:
		var r := find_ref(str(id))
		if not r.is_empty():
			analyses.append(r.get("analysis", {}))
	if analyses.is_empty():
		return
	var merged := RefAnalyzer.merge(analyses)
	st["palette"] = merged.get("palette", [])
	st["line"] = str(merged.get("line_text", ""))
	st["shading"] = str(merged.get("shading_text", ""))
	st["lighting"] = str(merged.get("lighting_text", ""))
	touch("style")


# ================================================================ cast

func cast() -> Array:
	return data["cast"]


func find_char(id_or_name: String) -> Dictionary:
	var key := id_or_name.strip_edges().to_lower()
	for c in cast():
		var cd: Dictionary = c
		if str(cd.get("id", "")) == id_or_name or str(cd.get("name", "")).to_lower() == key:
			return cd
	return {}


func add_character(spec: Dictionary = {}) -> Dictionary:
	var c := {
		"id": Ids.make(), "name": "New character", "description": "", "personality": "",
		"voice": "", "proportions": "", "movement": "", "palette": [], "outfits": "",
		"sheets": {}, "ref_ids": [], "consistency": 0.75, "seed": randi() % 1000000000,
	}
	for k in spec.keys():
		if c.has(k) and k != "id":
			c[k] = spec[k]
	cast().append(c)
	touch("cast")
	return c


func update_character(id: String, changes: Dictionary) -> void:
	var c := find_char(id)
	if c.is_empty():
		return
	for k in changes.keys():
		if c.has(k) and k != "id":
			c[k] = changes[k]
	touch("cast")


func delete_character(id: String) -> void:
	var c := find_char(id)
	if not c.is_empty():
		cast().erase(c)
		touch("cast")


## The pictures that show what a character looks like, best first.
func character_ref_ids(c: Dictionary) -> Array:
	var out: Array = []
	var sheets: Dictionary = c.get("sheets", {})
	for v in ["front", "side", "expressions", "back"]:
		if sheets.has(v) and not find_ref(str(sheets[v])).is_empty():
			out.append(str(sheets[v]))
	for id in c.get("ref_ids", []):
		if not out.has(str(id)) and not find_ref(str(id)).is_empty():
			out.append(str(id))
	for r in refs():
		var rd: Dictionary = r
		if str(rd.get("character_id", "")) == str(c.get("id", "")) and not out.has(str(rd["id"])):
			out.append(str(rd["id"]))
	return out


# ================================================================ shots

func shots() -> Array:
	return data["shots"]


func find_shot(id: String) -> Dictionary:
	for s in shots():
		if str((s as Dictionary).get("id", "")) == id:
			return s
	return {}


## Creates a shot from a plan (from the director or the New shot button).
## spec: {name, frames | duration_seconds, fps, exposure, action, environment,
##        lighting, camera, camera_preset, mood, dialogue, characters,
##        background, separate_background, guide_layer, keys: [{frame, kind, pose, expression, notes}]}
func create_shot(spec: Dictionary) -> Dictionary:
	var pfps: int = App.project.fps if App.has_project() else 24
	var fps := int(spec.get("fps", pfps))
	if not [12, 18, 24, 30].has(fps):
		fps = 24 if fps <= 0 else _nearest_fps(fps)
	var frames := int(spec.get("frames", 0))
	if frames <= 0:
		frames = int(round(float(spec.get("duration_seconds", 2.0)) * fps))
	frames = clampi(frames, 1, fps * 60)
	var chars: Array = []
	for c in spec.get("characters", []):
		var cd := find_char(str(c))
		if not cd.is_empty():
			chars.append(str(cd["id"]))
	var s := {
		"id": Ids.make(),
		"name": str(spec.get("name", "Shot %d" % (shots().size() + 1))),
		"frames": frames, "fps": fps,
		"exposure": clampi(int(spec.get("exposure", 2)), 1, 4),
		"action": str(spec.get("action", "")),
		"environment": str(spec.get("environment", "")),
		"lighting": str(spec.get("lighting", "")),
		"camera": str(spec.get("camera", "")),
		"camera_preset": str(spec.get("camera_preset", "none")) if CAMERA_PRESETS.has(str(spec.get("camera_preset", "none"))) else "none",
		"mood": str(spec.get("mood", "")),
		"dialogue": str(spec.get("dialogue", "")),
		"characters": chars,
		"separate_background": bool(spec.get("separate_background", true)),
		"background": {"prompt": str(spec.get("background", "")), "status": "pending", "takes": [], "chosen": -1},
		"guide_layer": str(spec.get("guide_layer", "")),
		"seed": randi() % 1000000000,
		"drawings": [],
		"placed": {},
		"qc": {},
		"created": Time.get_datetime_string_from_system(),
	}
	_expand(s, spec.get("keys", []))
	shots().append(s)
	touch("shots")
	return s


static func _nearest_fps(fps: int) -> int:
	var best := 24
	for c in [12, 18, 24, 30]:
		if absi(c - fps) < absi(best - fps):
			best = c
	return best


## Works out every drawing of the shot from its keys and its timing.
## On ones every frame is a drawing; on twos every 2nd frame, and so on.
## Frames given by the plan are keys/breakdowns; the rest are in-betweens
## whose description sits between the two drawings around them.
## Existing drawings (and their takes) on the same frames are kept.
func _expand(s: Dictionary, plan_keys: Array) -> void:
	var e := int(s["exposure"])
	var frames := int(s["frames"])
	var old := {}
	for d in s.get("drawings", []):
		old[int((d as Dictionary)["frame"])] = d
	var keys := {}
	for k in plan_keys:
		var kd: Dictionary = k
		var f := clampi(int(round(float(kd.get("frame", 0)) / e)) * e, 0, maxi(0, ((frames - 1) / e) * e))
		var kind := str(kd.get("kind", "key"))
		keys[f] = {"kind": kind if KINDS.has(kind) and kind != "inbetween" else "key",
			"pose": str(kd.get("pose", "")), "expression": str(kd.get("expression", "")), "notes": str(kd.get("notes", ""))}
	# keep the user's/director's existing keys if no new plan was given
	if keys.is_empty():
		for f in old.keys():
			var od: Dictionary = old[f]
			if str(od.get("kind", "")) != "inbetween" and int(f) % e == 0 and int(f) < frames:
				keys[int(f)] = {"kind": od["kind"], "pose": od.get("pose", ""), "expression": od.get("expression", ""), "notes": od.get("notes", "")}
	if not keys.has(0):
		var first := {"kind": "key", "pose": str(s.get("action", "")), "expression": "", "notes": ""}
		if not keys.is_empty():
			var ks := keys.keys()
			ks.sort()
			first = (keys[ks[0]] as Dictionary).duplicate()
			first["kind"] = "key"
		keys[0] = first
	var key_frames := keys.keys()
	key_frames.sort()
	var out: Array = []
	var idx := 0
	var f := 0
	while f < frames:
		var d: Dictionary
		if keys.has(f):
			var kd: Dictionary = keys[f]
			d = {"kind": kd["kind"], "pose": kd["pose"], "expression": kd["expression"], "notes": kd["notes"]}
		else:
			var a := 0
			var b := -1
			for kf in key_frames:
				if int(kf) < f:
					a = int(kf)
				elif int(kf) > f and b < 0:
					b = int(kf)
			var ka: Dictionary = keys[a]
			if b < 0:
				d = {"kind": "inbetween", "pose": "follow-through continuing from: " + str(ka["pose"]), "expression": ka["expression"], "notes": ""}
			else:
				var kb: Dictionary = keys[b]
				var t := float(f - a) / float(b - a)
				d = {"kind": "inbetween", "pose": "in-between, %d%% of the way from [%s] to [%s]" % [int(round(t * 100)), ka["pose"], kb["pose"]],
					"expression": ka["expression"] if t < 0.5 else kb["expression"], "notes": "", "between": [a, b], "t": t}
		d["frame"] = f
		d["index"] = idx
		if old.has(f):
			var od: Dictionary = old[f]
			d["takes"] = od.get("takes", [])
			d["chosen"] = int(od.get("chosen", -1))
			d["status"] = str(od.get("status", "pending"))
			d["qc"] = od.get("qc", {})
			# a changed description means the old picture is out of date
			if str(od.get("pose", "")) != str(d["pose"]) or str(od.get("expression", "")) != str(d["expression"]):
				if str(d["status"]) == "done":
					d["status"] = "stale"
		else:
			d["takes"] = []
			d["chosen"] = -1
			d["status"] = "pending"
			d["qc"] = {}
		out.append(d)
		idx += 1
		f += e
	s["drawings"] = out


func update_shot(id: String, changes: Dictionary) -> Dictionary:
	var s := find_shot(id)
	if s.is_empty():
		return {}
	var retime := false
	for k in changes.keys():
		match str(k):
			"frames", "exposure", "fps":
				var v := int(changes[k])
				if str(k) == "fps":
					v = _nearest_fps(v)
				if int(s.get(k, 0)) != v:
					s[k] = v
					retime = true
			"duration_seconds":
				var nf := int(round(float(changes[k]) * int(s["fps"])))
				if nf != int(s["frames"]):
					s["frames"] = maxi(1, nf)
					retime = true
			"characters":
				var chars: Array = []
				for c in changes[k]:
					var cd := find_char(str(c))
					if not cd.is_empty():
						chars.append(str(cd["id"]))
				s["characters"] = chars
			"background":
				(s["background"] as Dictionary)["prompt"] = str(changes[k])
			"camera_preset":
				s[k] = str(changes[k]) if CAMERA_PRESETS.has(str(changes[k])) else "none"
			"keys":
				_expand(s, changes[k])
			"name", "action", "environment", "lighting", "camera", "mood", "dialogue", "guide_layer":
				s[k] = str(changes[k])
			"separate_background":
				s[k] = bool(changes[k])
	if retime and not changes.has("keys"):
		_expand(s, [])
	touch("shots")
	return s


func delete_shot(id: String) -> void:
	var s := find_shot(id)
	if s.is_empty():
		return
	shots().erase(s)
	var keep: Array = []
	for j in jobs():
		if str((j as Dictionary).get("shot_id", "")) != id:
			keep.append(j)
	data["jobs"] = keep
	touch("shots")
	touch("jobs")


## The drawing shown at shot frame `f` (0-based): the last drawing at or before it.
static func drawing_at(s: Dictionary, f: int) -> Dictionary:
	var best: Dictionary = {}
	for d in s.get("drawings", []):
		var dd: Dictionary = d
		if int(dd["frame"]) <= f:
			best = dd
	return best


static func drawing(s: Dictionary, index: int) -> Dictionary:
	var ds: Array = s.get("drawings", [])
	return ds[index] if index >= 0 and index < ds.size() else {}


static func counts(s: Dictionary) -> Dictionary:
	var c := {"key": 0, "breakdown": 0, "inbetween": 0, "done": 0, "drawings": 0}
	for d in s.get("drawings", []):
		var dd: Dictionary = d
		c[str(dd["kind"])] = int(c.get(str(dd["kind"]), 0)) + 1
		c["drawings"] = int(c["drawings"]) + 1
		if int(dd.get("chosen", -1)) >= 0:
			c["done"] = int(c["done"]) + 1
	return c


## The take (picture) a drawing currently uses, or null.
func chosen_image(d: Dictionary) -> Image:
	var takes: Array = d.get("takes", [])
	var ch := int(d.get("chosen", -1))
	if ch < 0 or ch >= takes.size():
		return null
	return load_image(str((takes[ch] as Dictionary).get("file", "")))


## Stores a new picture for a drawing. The first take is used right away;
## later takes (revisions, QC fixes) wait for approval unless `auto_use`.
func add_take(s: Dictionary, d: Dictionary, img: Image, meta: Dictionary, auto_use: bool = false) -> void:
	var takes: Array = d["takes"]
	var rel := "renders/%s/d%03d_t%02d_%s.png" % [str(s["id"]), int(d["index"]), takes.size() + 1, Ids.make()]
	if not save_image(img, rel):
		d["status"] = "failed"
		d["error"] = "Couldn't write " + rel
		return
	var take := meta.duplicate()
	take["file"] = rel
	take["created"] = Time.get_datetime_string_from_system()
	takes.append(take)
	if int(d.get("chosen", -1)) < 0 or auto_use:
		d["chosen"] = takes.size() - 1
		d["review"] = false
	else:
		d["review"] = true  # a new take is waiting for approve / reject
	d["status"] = "done"
	d.erase("error")
	touch("shots")


func approve_take(d: Dictionary, take_index: int = -1) -> void:
	var takes: Array = d.get("takes", [])
	if takes.is_empty():
		return
	d["chosen"] = takes.size() - 1 if take_index < 0 else clampi(take_index, 0, takes.size() - 1)
	d["review"] = false
	touch("shots")


## Throws away the newest take (keeps the one in use).
func reject_take(d: Dictionary) -> void:
	var takes: Array = d.get("takes", [])
	if takes.size() <= 1 or not bool(d.get("review", false)):
		d["review"] = false
		touch("shots")
		return
	var last := takes.size() - 1
	if int(d["chosen"]) != last:
		var rel := str((takes[last] as Dictionary).get("file", ""))
		takes.remove_at(last)
		DirAccess.remove_absolute(abs_path(rel))
	d["review"] = false
	touch("shots")


# ================================================================ prompts

func character_text(c: Dictionary) -> String:
	var parts: Array[String] = [str(c.get("name", ""))]
	for k in ["description", "proportions", "outfits"]:
		var v := str(c.get(k, "")).strip_edges()
		if v != "":
			parts.append(v.split("\n")[0] if k == "outfits" else v)
	return ", ".join(parts)


## {positive, negative} for one drawing of a shot.
func prompt_for(s: Dictionary, d: Dictionary, extra_note: String = "") -> Dictionary:
	var st := style()
	var pos: Array[String] = [str(st["descriptors"])]
	for k in ["line", "shading", "lighting"]:
		if str(st.get(k, "")) != "":
			pos.append(str(st[k]))
	var pal: Array = st.get("palette", [])
	if not pal.is_empty():
		pos.append("colour palette " + RefAnalyzer.palette_words(pal))
	var separate := bool(s.get("separate_background", true))
	for cid in s.get("characters", []):
		var c := find_char(str(cid))
		if not c.is_empty():
			pos.append(character_text(c))
	if str(s.get("action", "")) != "":
		pos.append("action: " + str(s["action"]))
	if str(d.get("pose", "")) != "":
		pos.append("pose: " + str(d["pose"]))
	if str(d.get("expression", "")) != "":
		pos.append("expression: " + str(d["expression"]))
	if str(d.get("notes", "")) != "":
		pos.append(str(d["notes"]))
	if extra_note != "":
		pos.append(extra_note)
	if str(s.get("camera", "")) != "":
		pos.append("shot: " + str(s["camera"]))
	if str(s.get("lighting", "")) != "":
		pos.append("lighting: " + str(s["lighting"]))
	if str(s.get("mood", "")) != "":
		pos.append("mood: " + str(s["mood"]))
	var neg := str(st["negative"])
	if separate:
		pos.append("the figure alone, isolated on a plain flat light grey backdrop, no scenery, no background details")
		neg += ", scenery, background details, environment, landscape, buildings"
	elif str(s.get("environment", "")) != "":
		pos.append("setting: " + str(s["environment"]))
	return {"positive": ", ".join(pos), "negative": neg}


func background_prompt(s: Dictionary) -> Dictionary:
	var st := style()
	var pos: Array[String] = [str(st["descriptors"])]
	if str(st.get("lighting", "")) != "":
		pos.append(str(st["lighting"]))
	var bg := str((s["background"] as Dictionary).get("prompt", ""))
	pos.append("empty background plate for an animated scene, no characters, no people")
	pos.append(bg if bg != "" else str(s.get("environment", "")))
	for k in ["lighting", "mood", "camera"]:
		if str(s.get(k, "")) != "":
			pos.append("%s: %s" % [k, str(s[k])])
	return {"positive": ", ".join(pos), "negative": str(st["negative"]) + ", people, person, character, figure, face"}


func sheet_prompt(c: Dictionary, view: String) -> Dictionary:
	var st := style()
	var what := ""
	match view:
		"front":
			what = "character model sheet, full body, front view, standing in a neutral relaxed pose, arms slightly away from the body"
		"side":
			what = "character model sheet, full body, side profile view facing left, neutral standing pose"
		"back":
			what = "character model sheet, full body, back view, neutral standing pose"
		"expressions":
			what = "facial expression sheet, six head-and-shoulders studies of the same face in a grid: neutral, quiet anger, fear, grief, menace, bitter laughter"
		_:
			what = "character model sheet, full body, front view, wearing: " + view
	var pos := "%s, %s, %s, personality: %s, plain flat light grey backdrop, even studio lighting" % [str(st["descriptors"]), what, character_text(c), str(c.get("personality", ""))]
	return {"positive": pos, "negative": str(st["negative"]) + ", scenery, multiple different characters"}


# ================================================================ jobs (data only; AiJobs runs them)

func jobs() -> Array:
	return data["jobs"]


func is_paused() -> bool:
	return bool(data.get("paused", false))


func set_paused(p: bool) -> void:
	data["paused"] = p
	touch("jobs")


func add_job(job: Dictionary) -> Dictionary:
	var j := job.duplicate()
	j["id"] = Ids.make()
	j["status"] = "queued"
	j["attempts"] = 0
	j["created"] = Time.get_datetime_string_from_system()
	jobs().append(j)
	touch("jobs")
	return j


func find_job(id: String) -> Dictionary:
	for j in jobs():
		if str((j as Dictionary).get("id", "")) == id:
			return j
	return {}


## Is a drawing (or the shot's background) already waiting or rendering?
func has_open_job(shot_id: String, index: int, kind: String = "drawing") -> bool:
	for j in jobs():
		var jd: Dictionary = j
		if str(jd.get("shot_id", "")) == shot_id and int(jd.get("index", -1)) == index and str(jd.get("kind", "")) == kind and str(jd["status"]) in ["queued", "running", "paused"]:
			return true
	return false


## Queues drawings of a shot. `indices` empty = every drawing without a
## picture (plus the background plate). `note` steers a revision.
func queue_shot(s: Dictionary, indices: Array = [], note: String = "", redo: bool = false) -> int:
	var n := 0
	if bool(s.get("separate_background", true)):
		var bgd: Dictionary = s["background"]
		if (indices.is_empty() and ((bgd["takes"] as Array).is_empty() or redo)) and not has_open_job(str(s["id"]), -1, "background"):
			add_job({"kind": "background", "shot_id": s["id"], "index": -1, "note": note, "label": "%s · background" % s["name"]})
			bgd["status"] = "queued"
			n += 1
	for d in s["drawings"]:
		var dd: Dictionary = d
		var i := int(dd["index"])
		if not indices.is_empty() and not indices.has(i):
			continue
		var needs: bool = redo or not indices.is_empty() or int(dd.get("chosen", -1)) < 0 or str(dd.get("status", "")) == "stale"
		if not needs or has_open_job(str(s["id"]), i):
			continue
		add_job({"kind": "drawing", "shot_id": s["id"], "index": i, "note": note,
			"label": "%s · F%d %s" % [s["name"], int(dd["frame"]) + 1, str(dd["kind"])]})
		dd["status"] = "queued"
		n += 1
	touch("shots")
	return n


func queue_sheet(c: Dictionary, views: Array) -> int:
	var n := 0
	for v in views:
		add_job({"kind": "sheet", "char_id": c["id"], "view": str(v), "index": -2, "label": "%s · %s sheet" % [c["name"], str(v)]})
		n += 1
	return n


# ================================================================ chat

func chat() -> Array:
	return data["chat"]


func add_chat(role: String, text: String) -> void:
	chat().append({"role": role, "text": text, "time": Time.get_datetime_string_from_system()})
	while chat().size() > 400:
		chat().pop_front()
	touch("chat")


# ================================================================ timeline placement

## Puts a shot's chosen drawings onto layers of the current scene, starting
## at timeline frame `start`. Character drawings go on "AI · <shot>"; the
## background plate (if any) on "AI BG · <shot>". Each drawing is held for
## its exposure. Placing again updates the same layers. Undoable.
func place_shot(s: Dictionary, start: int) -> String:
	var scene := App.current_scene()
	if scene == null:
		return "Open a project first."
	var pw: int = App.project.width
	var ph: int = App.project.height
	var k := float(App.project.fps) / float(int(s["fps"]))
	var images := {}
	var missing := 0
	var separate := bool(s.get("separate_background", true))
	for d in s["drawings"]:
		var dd: Dictionary = d
		var img := chosen_image(dd)
		if img == null:
			missing += 1
			continue
		var fitted := AiImage.cover(img, pw, ph)
		if separate:
			fitted = AiImage.key_backdrop(fitted)
		images[start + int(round(int(dd["frame"]) * k))] = fitted
	if images.is_empty():
		return "No drawings of “%s” are finished yet." % s["name"]
	var end := start + int(ceil(int(s["frames"]) * k))
	var placed: Dictionary = s.get("placed", {})
	var char_layer := _find_layer(scene, str(placed.get("layer", "")))
	Ops.place_drawings("AI · " + str(s["name"]), "character", images, char_layer, start, end, scene)
	var new_char := _find_layer_by_name(scene, "AI · " + str(s["name"])) if char_layer == null else char_layer
	placed = {"scene": scene.id, "layer": new_char.id if new_char != null else "", "start": start, "end": end}
	if separate:
		var bgd: Dictionary = s["background"]
		var takes: Array = bgd.get("takes", [])
		var ch := int(bgd.get("chosen", -1))
		if ch >= 0 and ch < takes.size():
			var bimg := load_image(str((takes[ch] as Dictionary)["file"]))
			if bimg != null:
				var bg_layer := _find_layer(scene, str(s.get("placed", {}).get("bg_layer", "")))
				Ops.place_drawings("AI BG · " + str(s["name"]), "background", {start: AiImage.cover(bimg, pw, ph)}, bg_layer, start, end, scene, true)
				var nb := _find_layer_by_name(scene, "AI BG · " + str(s["name"])) if bg_layer == null else bg_layer
				placed["bg_layer"] = nb.id if nb != null else ""
	s["placed"] = placed
	if str(s.get("camera_preset", "none")) != "none":
		Ops.apply_camera_preset(str(s["camera_preset"]))
	touch("shots")
	App.set_frame(start)
	var msg := "Placed “%s” on frames %d–%d" % [s["name"], start + 1, end]
	if missing > 0:
		msg += " (%d drawing(s) not finished yet: the previous drawing is held)" % missing
	return msg


static func _find_layer(scene: SceneData, id: String) -> LayerData:
	if id == "":
		return null
	for l in scene.layers:
		if l.id == id:
			return l
	return null


static func _find_layer_by_name(scene: SceneData, layer_name: String) -> LayerData:
	for i in range(scene.layers.size() - 1, -1, -1):
		if scene.layers[i].name == layer_name:
			return scene.layers[i]
	return null


## A snapshot of a drawn layer at a timeline frame (your rough), or null.
func guide_from_layer(layer_name: String, frame: int) -> Image:
	if layer_name == "" or not App.has_project():
		return null
	var scene := App.current_scene()
	for l in scene.layers:
		if l.name == layer_name and not l.is_character():
			var cel := l.cel_at(frame)
			if cel == null:
				return null
			var img := cel.get_image()
			return img if AiImage.has_content(img) else null
	return null
