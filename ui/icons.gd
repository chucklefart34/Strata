class_name Icons
extends RefCounted
## Strata's icon set: hand-written SVG line icons rasterized at runtime at the
## current UI scale (crisp on HiDPI). Icons are white and get tinted by theme
## icon colors.

const _TEMPLATE := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">%s</svg>'

const _PATHS := {
	"home": '<path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
	"brush": '<path d="M18.5 2.5l3 3-9.5 9.5-3-3z"/><path d="M9 12.2c-2.4-.2-4 1.2-4.2 3.6-.2 2-1 3-2.8 3.4 2.6 1.9 7.3 1.6 8.6-1.2.7-1.6.3-3.4-1.6-5.8z"/>',
	"pencil": '<path d="M4 20l1.2-4.8L16 4.4a2 2 0 0 1 2.8 0l.8.8a2 2 0 0 1 0 2.8L8.8 18.8z"/><path d="M14 6.5l3.5 3.5"/>',
	"eraser": '<path d="M7.5 19.5L3.6 15.6a2 2 0 0 1 0-2.8L12.8 3.6a2 2 0 0 1 2.8 0l4.8 4.8a2 2 0 0 1 0 2.8L11.5 19.5z"/><path d="M8.5 8l7.5 7.5"/><path d="M11.5 19.5H21"/>',
	"fill": '<path d="M4.5 11.5L11 5l7 7-6.5 6.5a2 2 0 0 1-2.8 0L4.5 14.3a2 2 0 0 1 0-2.8z"/><path d="M4 12h14"/><path d="M8.5 3l2.5 2"/><path d="M20 15s1.8 2.2 1.8 3.4a1.8 1.8 0 0 1-3.6 0C18.2 17.2 20 15 20 15z"/>',
	"picker": '<path d="M13 7l4 4"/><path d="M15 5l1.6-1.6a2.1 2.1 0 0 1 3 3L18 8"/><path d="M14 8l-8.5 8.5L4 20l3.5-1.5L16 10"/>',
	"line": '<path d="M5 19L19 5"/><circle cx="5" cy="19" r="1.5"/><circle cx="19" cy="5" r="1.5"/>',
	"rect": '<rect x="4" y="6" width="16" height="12" rx="1.5"/>',
	"ellipse": '<ellipse cx="12" cy="12" rx="8.5" ry="6.5"/>',
	"move": '<path d="M12 3v18M3 12h18"/><path d="M9 6l3-3 3 3M9 18l3 3 3-3M6 9l-3 3 3 3M18 9l3 3-3 3"/>',
	"hand": '<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12"/><path d="M11 11.5V4a1.5 1.5 0 0 1 3 0v7.5"/><path d="M14 11.5V6a1.5 1.5 0 0 1 3 0v8c0 3.9-2.7 7-6.2 7-2.3 0-3.9-1.1-5.3-3.2L3.8 15a1.5 1.5 0 0 1 2.4-1.8L8 15"/>',
	"play": '<path d="M7 4.5v15l12.5-7.5z" fill="#ffffff"/>',
	"pause": '<rect x="6" y="5" width="4" height="14" rx="1" fill="#ffffff"/><rect x="14" y="5" width="4" height="14" rx="1" fill="#ffffff"/>',
	"prev": '<path d="M15 6l-6 6 6 6"/>',
	"next": '<path d="M9 6l6 6-6 6"/>',
	"first": '<path d="M6 6v12"/><path d="M17 6l-6 6 6 6"/>',
	"last": '<path d="M18 6v12"/><path d="M7 6l6 6-6 6"/>',
	"loop": '<path d="M17 2.5l3 3-3 3"/><path d="M4 11.5v-1a5 5 0 0 1 5-5h11"/><path d="M7 21.5l-3-3 3-3"/><path d="M20 12.5v1a5 5 0 0 1-5 5H4"/>',
	"onion": '<circle cx="9" cy="12" r="5.5" stroke-opacity="0.5"/><circle cx="15" cy="12" r="5.5"/>',
	"plus": '<path d="M12 5v14M5 12h14"/>',
	"copy": '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
	"trash": '<path d="M4 7h16"/><path d="M10 11v6M14 11v6"/><path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12"/><path d="M9 7V4h6v3"/>',
	"eye": '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
	"eye_off": '<path d="M3 3l18 18"/><path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.2 4.1"/><path d="M6.6 6.6C3.7 8.4 2 12 2 12s3.6 7 10 7c1.9 0 3.6-.6 5-1.5"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
	"lock": '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
	"unlock": '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/>',
	"up": '<path d="M6 15l6-6 6 6"/>',
	"down": '<path d="M6 9l6 6 6-6"/>',
	"undo": '<path d="M9 14L4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
	"redo": '<path d="M15 14l5-5-5-5"/><path d="M20 9H9.5a5.5 5.5 0 0 0 0 11H13"/>',
	"save": '<path d="M5 3h11l5 5v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M7 3v5h8V3"/><rect x="7" y="13" width="10" height="8"/>',
	"folder": '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
	"camera": '<path d="M3 8a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M16 10l5-3v10l-5-3"/>',
	"layers": '<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>',
	"film": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
	"cube": '<path d="M12 2.5l8.5 4.8v9.4L12 21.5l-8.5-4.8V7.3z"/><path d="M3.5 7.3L12 12l8.5-4.7"/><path d="M12 12v9.5"/>',
	"key": '<path d="M12 4l8 8-8 8-8-8z"/>',
	"new_frame": '<rect x="5" y="4" width="14" height="16" rx="2"/><path d="M12 9v6M9 12h6"/>',
	"insert": '<path d="M4 12h10"/><path d="M11 9l3 3-3 3"/><path d="M19 5v14"/>',
	"remove_frame": '<path d="M20 12H10"/><path d="M13 9l-3 3 3 3"/><path d="M5 5v14"/>',
	"fit": '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
	"render": '<circle cx="12" cy="12" r="9"/><path d="M10 8.5v7l6-3.5z" fill="#ffffff"/>',
	"menu": '<path d="M4 7h16M4 12h16M4 17h16"/>',
	"close": '<path d="M6 6l12 12M18 6L6 18"/>',
	"help": '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6"/><path d="M12 17.5v.01"/>',
	"orbit": '<ellipse cx="12" cy="12" rx="9.5" ry="4"/><circle cx="12" cy="12" r="2.5"/><path d="M19 9l2.5 3"/>',
	"select": '<rect x="4" y="5" width="16" height="14" rx="1" stroke-dasharray="3 2.6"/>',
	"lasso_ink": '<path d="M11 4c4.6 0 8 2.2 8 5s-3.4 5-8 5-8-2.2-8-5 3.4-5 8-5z" stroke-dasharray="3 2.6"/><path d="M14.5 21l1-3.5 4.5-4.5 2 2-4.5 4.5z"/><path d="M5.5 12.5c-.8 1.5-.4 3 1 3.8"/>',
	"lasso": '<path d="M12 4c5 0 8.5 2.4 8.5 5.5S17 15 12 15s-8.5-2.4-8.5-5.5S7 4 12 4z" stroke-dasharray="3 2.6"/><path d="M6.5 13.5c-1 1.6-.7 3.6 1 4.5 1.2.6 2 1.7 1.5 3"/>',
	"import": '<path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
	"image": '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 9"/>',
	"character": '<circle cx="12" cy="6.5" r="3"/><path d="M12 9.5v6"/><path d="M7.5 12.5l4.5-2 4.5 2"/><path d="M9 21l3-5.5 3 5.5"/>',
	"bone": '<circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M7.5 16.5l9-9"/>',
	"audio": '<path d="M4 9v6h4l5 4V5L8 9z"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/><path d="M19 6a8.5 8.5 0 0 1 0 12"/>',
	"clapper": '<path d="M4 10h16v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/><path d="M4 10l-.6-3.2 15.4-2.9.6 3.2z"/><path d="M8.5 6.3l2 3.4M13.5 5.4l2 3.4"/>',
	"reset": '<path d="M4 12a8 8 0 1 0 2.4-5.7"/><path d="M4 4v4h4"/>',
}

const _RAW := {
	"logo": '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 28 28"><rect x="9" y="3" width="16" height="16" rx="4" fill="#4fd1c5" fill-opacity="0.55"/><rect x="6" y="6" width="16" height="16" rx="4" fill="#ff9b7d" fill-opacity="0.8"/><rect x="3" y="9" width="16" height="16" rx="4" fill="#ff7a59"/></svg>',
	"grabber": '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6" fill="#ffffff"/></svg>',
	"grabber_hl": '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.5" fill="#ffffff" stroke="#ff7a59" stroke-width="1.5"/></svg>',
}

static var _cache: Dictionary = {}


## Returns the named icon as a texture. `size` is the logical size in px.
static func tex(icon_name: String, size: float = 20.0) -> Texture2D:
	var key := "%s@%.2f" % [icon_name, size * UI.scale]
	if _cache.has(key):
		return _cache[key]
	var svg := ""
	var base := 24.0
	if _RAW.has(icon_name):
		svg = _RAW[icon_name]
		base = 28.0 if icon_name == "logo" else 16.0
	elif _PATHS.has(icon_name):
		svg = _TEMPLATE % _PATHS[icon_name]
	else:
		push_warning("Unknown icon: " + icon_name)
		svg = _TEMPLATE % '<circle cx="12" cy="12" r="6"/>'
	var img := Image.new()
	var err := img.load_svg_from_string(svg, maxf(0.1, size * UI.scale / base))
	var t: Texture2D
	if err != OK or img.is_empty():
		var fallback := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
		t = ImageTexture.create_from_image(fallback)
	else:
		t = ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
