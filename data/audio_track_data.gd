class_name AudioTrackData
extends RefCounted
## An audio track in a scene: dialogue, music, sound effects or ambience.

const KINDS := ["dialogue", "music", "sfx", "ambient"]
const KIND_LABELS := {"dialogue": "Dialogue", "music": "Music", "sfx": "Sound FX", "ambient": "Ambience"}
const KIND_COLORS := {
	"dialogue": Color("#4fd1c5"), "music": Color("#9b6cff"),
	"sfx": Color("#ffc94d"), "ambient": Color("#7ccf6a"),
}

var id: String = ""
var name: String = "Track"
var kind: String = "dialogue"
var volume_db: float = 0.0
var muted: bool = false
var solo: bool = false
var clips: Array[AudioClipData] = []


func _init(p_name: String = "Track", p_kind: String = "dialogue") -> void:
	id = Ids.make()
	name = p_name
	kind = p_kind if KINDS.has(p_kind) else "dialogue"


func color() -> Color:
	return KIND_COLORS.get(kind, Palette.DEPTH)


func to_dict() -> Dictionary:
	var list := []
	for c in clips:
		list.append(c.to_dict())
	return {"id": id, "name": name, "kind": kind, "volume_db": volume_db, "muted": muted, "solo": solo, "clips": list}


static func from_dict(d: Dictionary) -> AudioTrackData:
	var t := AudioTrackData.new(str(d.get("name", "Track")), str(d.get("kind", "dialogue")))
	t.id = str(d.get("id", t.id))
	t.volume_db = float(d.get("volume_db", 0.0))
	t.muted = bool(d.get("muted", false))
	t.solo = bool(d.get("solo", false))
	for cd in d.get("clips", []):
		t.clips.append(AudioClipData.from_dict(cd))
	return t


func clone_deep() -> AudioTrackData:
	var t := AudioTrackData.from_dict(to_dict())
	t.id = Ids.make()
	for c in t.clips:
		c.id = Ids.make()
	return t
