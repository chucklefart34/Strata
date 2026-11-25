class_name FrameQC
extends RefCounted
## Automatic checks of a shot's drawings, run on this computer. They compare
## each drawing with its neighbours and with the character references:
##   flicker      brightness jumps between drawings
##   pop          a drawing very different from both neighbours (broken continuity)
##   colour       colour mix changes (costume / palette inconsistency)
##   background   the backdrop changes between drawings (when not separated)
##   silhouette   the figure's size/shape jumps (often anatomy or framing trouble)
##   off-model    colours drift away from the character's reference sheet
## These are measurements, not understanding: anatomy and faces are checked
## by the director's vision review (Claude), when it's switched on.

const SIG_W := 48
const SIG_H := 27


static func signature(img: Image, separate: bool) -> Dictionary:
	var small := img.duplicate() as Image
	small.convert(Image.FORMAT_RGBA8)
	small.resize(SIG_W * 4, SIG_H * 4, Image.INTERPOLATE_BILINEAR)
	var cov := 1.0
	if separate:
		var keyed := AiImage.key_backdrop(small)
		var kd := keyed.get_data()
		var on := 0
		for i in range(3, kd.size(), 4):
			if kd[i] > 128:
				on += 1
		cov = float(on) / (kd.size() / 4.0)
	var tiny := small.duplicate() as Image
	tiny.resize(SIG_W, SIG_H, Image.INTERPOLATE_BILINEAR)
	var d := tiny.get_data()
	var g := PackedFloat32Array()
	g.resize(SIG_W * SIG_H)
	var hist := PackedFloat32Array()
	hist.resize(64)
	var mean := 0.0
	for i in SIG_W * SIG_H:
		var o := i * 4
		var l := (0.2126 * d[o] + 0.7152 * d[o + 1] + 0.0722 * d[o + 2]) / 255.0
		g[i] = l
		mean += l
		var bin := (d[o] >> 6) * 16 + (d[o + 1] >> 6) * 4 + (d[o + 2] >> 6)
		hist[bin] += 1.0
	var total := float(SIG_W * SIG_H)
	for i in 64:
		hist[i] /= total
	return {"g": g, "hist": hist, "mean": mean / total, "cov": cov}


static func _gdiff(a: PackedFloat32Array, b: PackedFloat32Array, border_only: bool) -> float:
	var acc := 0.0
	var n := 0
	for y in SIG_H:
		for x in SIG_W:
			if border_only and x > 4 and x < SIG_W - 5 and y > 3 and y < SIG_H - 4:
				continue
			var i := y * SIG_W + x
			acc += absf(a[i] - b[i])
			n += 1
	return acc / maxf(1.0, n)


static func _hdiff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var acc := 0.0
	for i in 64:
		acc += absf(a[i] - b[i])
	return acc * 0.5


static func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return float(s[s.size() / 2])


## Checks a shot. Writes `qc` into each drawing and returns a summary
## {checked, flagged: [indices], notes: String}.
static func run(s: Dictionary) -> Dictionary:
	var separate := bool(s.get("separate_background", true))
	var sigs: Array = []
	var idx: Array = []
	for d in s["drawings"]:
		var dd: Dictionary = d
		var img: Image = Studio.chosen_image(dd)
		if img == null:
			continue
		sigs.append(signature(img, separate))
		idx.append(int(dd["index"]))
	var result := {"checked": sigs.size(), "flagged": [], "notes": ""}
	if sigs.size() < 2:
		result["notes"] = "Need at least two finished drawings to compare."
		return result
	# reference colours for the shot's first character
	var ref_hist := PackedFloat32Array()
	for cid in s.get("characters", []):
		var c: Dictionary = Studio.find_char(str(cid))
		var ids: Array = Studio.character_ref_ids(c) if not c.is_empty() else []
		if not ids.is_empty():
			var rimg: Image = Studio.ref_image(str(ids[0]))
			if rimg != null:
				ref_hist = signature(rimg, false)["hist"]
				break
	var m := {"flicker": [], "pop": [], "colour": [], "background": [], "silhouette": [], "ref": []}
	var per: Array = []
	# Differences between neighbours, then each drawing is judged by the
	# smaller of its two differences: an isolated bad drawing differs from
	# both sides, while the drawing after it only differs on one side.
	var pair: Array = []  # pair[i] = diffs between drawing i and i+1
	for i in sigs.size() - 1:
		var a: Dictionary = sigs[i]
		var b: Dictionary = sigs[i + 1]
		pair.append({
			"flicker": absf(float(a["mean"]) - float(b["mean"])),
			"colour": _hdiff(a["hist"], b["hist"]),
			"silhouette": absf(float(a["cov"]) - float(b["cov"])) if separate else 0.0,
			"background": 0.0 if separate else _gdiff(a["g"], b["g"], true),
			"pop": _gdiff(a["g"], b["g"], false),
		})
	for i in sigs.size():
		var cur: Dictionary = sigs[i]
		var v := {}
		var before: Dictionary = pair[i - 1] if i > 0 else {}
		var after: Dictionary = pair[i] if i < pair.size() else {}
		for k in ["flicker", "colour", "silhouette", "background", "pop"]:
			if before.is_empty():
				v[k] = float(after[k])
			elif after.is_empty():
				v[k] = float(before[k])
			else:
				v[k] = minf(float(before[k]), float(after[k]))
		if not ref_hist.is_empty():
			v["ref"] = _hdiff(cur["hist"], ref_hist)
		for k in v.keys():
			(m[k] as Array).append(v[k])
		per.append(v)
	var floors := {"flicker": 0.05, "pop": 0.09, "colour": 0.18, "background": 0.05, "silhouette": 0.06, "ref": 0.45}
	var words := {
		"flicker": "brightness jumps from the previous drawing (flicker)",
		"pop": "very different from the drawings on both sides (continuity pop)",
		"colour": "colours shift from the previous drawing (costume/palette)",
		"background": "the background changes between drawings",
		"silhouette": "the figure's size or shape jumps (check anatomy/framing)",
		"ref": "colours drift from the character's reference sheet (off-model)",
	}
	var limits := {}
	for k in m.keys():
		limits[k] = maxf(float(floors[k]), 2.6 * _median(m[k]))
	var flagged: Array = []
	for i in per.size():
		var v: Dictionary = per[i]
		var issues: Array = []
		for k in v.keys():
			if float(v[k]) > float(limits[k]):
				issues.append(str(words[k]))
		var d: Dictionary = Studio.drawing(s, int(idx[i]))
		var qc: Dictionary = d.get("qc", {})
		qc["auto"] = issues
		qc["scores"] = v
		qc["checked"] = Time.get_datetime_string_from_system()
		d["qc"] = qc
		if not issues.is_empty():
			flagged.append(int(idx[i]))
	result["flagged"] = flagged
	result["notes"] = "Checked %d drawings: %d flagged." % [sigs.size(), flagged.size()]
	s["qc"] = {"last": result["notes"], "flagged": flagged, "time": Time.get_datetime_string_from_system()}
	Studio.touch("shots")
	return result


## Issues for a drawing from both checks.
static func issues(d: Dictionary) -> Array:
	var qc: Dictionary = d.get("qc", {})
	var out: Array = []
	out.append_array(qc.get("auto", []))
	out.append_array(qc.get("vision", []))
	return out
