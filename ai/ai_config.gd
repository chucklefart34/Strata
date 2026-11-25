class_name AiConfig
extends RefCounted
## AI Studio settings for this computer (not stored in projects, so API keys
## never travel with a project folder). Kept in their own file: ProjectIO
## clears the old `ai_*` keys from settings.cfg on start.
##
## LOCAL  = runs on this computer (ComfyUI image generation, Ollama director).
## CLOUD  = sent over the internet (Claude director / vision review).

const PATH := "user://ai_studio.cfg"

const DEFAULTS := {
	# ---- image generation: ComfyUI (local)
	"comfy_url": "http://127.0.0.1:8188",
	"checkpoint": "",
	"lora": "",
	"lora_strength": 0.8,
	"controlnet": "",          # lineart / scribble model, used with your roughs
	"controlnet_strength": 0.75,
	"ipadapter": true,          # use IP-Adapter (ComfyUI_IPAdapter_plus) when installed
	"ipadapter_preset": "PLUS (high strength)",
	"ipadapter_weight": 0.7,
	"steps": 28,
	"cfg": 6.0,
	"sampler": "dpmpp_2m",
	"scheduler": "karras",
	"base_size": 1024,          # long side of each generated frame
	"inbetween_denoise": 0.55,
	"motion_guides": true,      # in-between guides from Strata's motion in-betweener (else a cross-fade)  # how much an in-between is redrawn over its blend guide
	"rough_denoise": 0.72,      # img2img strength over your rough when no ControlNet is set
	"custom_workflow": "",      # optional ComfyUI API-format JSON with {{placeholders}}
	# ---- director
	"director": "claude",       # "claude" (cloud) or "ollama" (local) or "off"
	"claude_key": "",
	"claude_model": "claude-sonnet-5-5",
	"anthropic_url": "https://api.anthropic.com",  # change only for a proxy
	"ollama_url": "http://127.0.0.1:11434",
	"ollama_model": "",
	"vision_qc": true,          # let the director look at frames (Claude only)
	"auto_queue": true,         # director requests start rendering right away
}

static var _cfg: ConfigFile = null
## Tests point this at their own file so they never touch your settings.
static var path: String = PATH


static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(path)
	return _cfg


static func use_file(p: String) -> void:
	path = p
	_cfg = null
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


static func get_value(key: String) -> Variant:
	return _load().get_value("ai", key, DEFAULTS.get(key))


static func s(key: String) -> String:
	return str(get_value(key))


static func f(key: String) -> float:
	return float(get_value(key))


static func i(key: String) -> int:
	return int(get_value(key))


static func b(key: String) -> bool:
	return bool(get_value(key))


static func set_value(key: String, value: Variant) -> void:
	_load().set_value("ai", key, value)
	_cfg.save(path)


## Base URL without a trailing slash.
static func comfy_url() -> String:
	return s("comfy_url").strip_edges().trim_suffix("/")


static func director_label() -> String:
	match s("director"):
		"claude":
			return "Claude (cloud)"
		"ollama":
			return "Ollama on this computer (local)"
	return "off"
