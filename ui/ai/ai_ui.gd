class_name AiUi
extends RefCounted
## Small builders shared by the AI Studio pages.

const KIND_COLORS := {"key": Color("#ff7a59"), "breakdown": Color("#ffc94d"), "inbetween": Color("#4fd1c5")}
const KIND_SHORT := {"key": "KEY", "breakdown": "BRK", "inbetween": "IB"}
const STATUS_TEXT := {
	"pending": "not drawn", "queued": "in queue", "rendering": "drawing…", "done": "drawn",
	"failed": "failed", "stale": "out of date",
}

static var _thumbs: Dictionary = {}  # "path@size" -> ImageTexture
static var _thumb_order: Array = []


static func grid(parent: Control, cols: int = 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", int(UI.px(10)))
	g.add_theme_constant_override("v_separation", int(UI.px(8)))
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g


static func row(g: GridContainer, title: String, c: Control) -> Control:
	var l := UI.label(title, "FieldLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	g.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(c)
	return c


static func line(text: String = "", placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


static func text(text_value: String = "", min_h: float = 70.0, placeholder: String = "") -> TextEdit:
	var t := TextEdit.new()
	t.text = text_value
	t.placeholder_text = placeholder
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.custom_minimum_size.y = UI.px(min_h)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return t


static func wrap_label(t: String, variation: String = "Muted") -> Label:
	var l := UI.label(t, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func scroll(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


static func sidebar(parent: Control, width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Sidebar"
	p.custom_minimum_size.x = UI.px(width)
	parent.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	return v


static func head(parent: Control, title: String) -> HBoxContainer:
	var h := UI.hbox(4)
	parent.add_child(h)
	var t := UI.label(title.to_upper(), "SectionTitle")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	return h


static func swatches(parent: Control, hexes: Array, size: float = 22.0) -> HBoxContainer:
	var h := UI.hbox(3)
	for hx in hexes:
		var r := ColorRect.new()
		r.color = Color(str(hx))
		r.custom_minimum_size = UI.size2(size, size)
		r.tooltip_text = "%s — %s" % [str(hx), RefAnalyzer.color_word(Color(str(hx)))]
		h.add_child(r)
	parent.add_child(h)
	return h


## Cached thumbnail of a picture in the studio folder.
static func thumb(rel: String, max_side: int = 160) -> Texture2D:
	if rel == "":
		return null
	var key := "%s@%d" % [rel, max_side]
	if _thumbs.has(key):
		return _thumbs[key]
	var img: Image = Studio.load_image(rel)
	if img == null:
		return null
	var t := AiImage.thumb(img, int(UI.px(max_side)))
	_thumbs[key] = t
	_thumb_order.append(key)
	if _thumb_order.size() > 600:
		_thumbs.erase(_thumb_order.pop_front())
	return t


static func take_file(d: Dictionary) -> String:
	var takes: Array = d.get("takes", [])
	var ch := int(d.get("chosen", -1))
	if ch < 0 or ch >= takes.size():
		return ""
	return str((takes[ch] as Dictionary).get("file", ""))


static func option_select(o: OptionButton, value: String, values: Array) -> void:
	var i := values.find(value)
	if i >= 0:
		o.select(i)


static func bb(t: String) -> String:
	return t.replace("[", "[lb]")


static func image_dialog(parent: Node, multi: bool, on_files: Callable) -> FileDialog:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES if multi else FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga ; Images"])
	fd.use_native_dialog = true
	fd.title = "Choose images"
	if multi:
		fd.files_selected.connect(func(paths: PackedStringArray) -> void: on_files.call(Array(paths)))
	else:
		fd.file_selected.connect(func(p: String) -> void: on_files.call([p]))
	parent.add_child(fd)
	return fd
