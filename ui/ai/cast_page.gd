class_name AiCastPage
extends Control
## Characters the AI keeps on-model. Each has a written description and
## turnaround / expression sheets; the sheets are sent with every drawing
## the character appears in (IP-Adapter), so you don't re-explain them.

var ws: AiStudioWorkspace
var _list: ItemList
var _ids: Array = []
var _sel: String = ""
var _form: VBoxContainer
var _f: Dictionary = {}  # field -> control
var _consistency: HSlider
var _sheets: HBoxContainer
var _others: HFlowContainer
var _dialog: FileDialog
var _pick_view: String = ""


func _ready() -> void:
	var root := UI.hbox(12)
	UI.full_rect(root)
	add_child(root)
	var left := AiUi.sidebar(root, 240)
	var h := AiUi.head(left, "Cast")
	var add := UI.icon_button("plus", "New character")
	add.pressed.connect(func() -> void:
		var c := Studio.add_character()
		_sel = str(c["id"])
		refresh())
	h.add_child(add)
	var del := UI.icon_button("trash", "Delete character (its reference pictures stay in the library)")
	del.pressed.connect(func() -> void:
		Studio.delete_character(_sel)
		_sel = "")
	h.add_child(del)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void:
		_sel = str(_ids[i])
		_fill())
	left.add_child(_list)

	var right := UI.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	_form = AiUi.scroll(right)
	var cols := UI.hbox(16)
	_form.add_child(cols)
	var c1 := UI.vbox(6)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c1)
	var c2 := UI.vbox(6)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c2)
	_f["name"] = _field(c1, "Name", AiUi.line())
	_f["description"] = _field(c1, "Look (face, hair, build, signature features)", AiUi.text("", 90))
	_f["proportions"] = _field(c1, "Proportions", AiUi.line("", "e.g. tall and gaunt, 8 heads, long limbs"))
	_f["outfits"] = _field(c1, "Clothing (first line = default; more lines = variations)", AiUi.text("", 70))
	_f["personality"] = _field(c2, "Personality", AiUi.text("", 60))
	_f["voice"] = _field(c2, "Voice", AiUi.line("", "e.g. low, dry, unhurried"))
	_f["movement"] = _field(c2, "How they move", AiUi.text("", 60, "e.g. deliberate, economical; never rushes; head leads turns"))
	_consistency = UI.slider(c2, "Stay on model (reference pull)", 0.2, 1.0, 0.05, 0.75, func(_v: float) -> void: pass, "%.2f")
	var save := UI.button("Save character", "save", "", "AccentButton")
	save.pressed.connect(_save)
	save.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_form.add_child(save)
	AiUi.head(_form, "Model sheets")
	_form.add_child(AiUi.wrap_label("Front, side and back turnarounds and an expression sheet. Generate them, or use your own drawing. They keep the character consistent in every shot.", "Small"))
	_sheets = UI.hbox(10)
	_form.add_child(_sheets)
	var hb := UI.hbox(6)
	_form.add_child(hb)
	var all := UI.button("Generate all sheets", "spark", "Queue front, side, back and expressions", "AccentButton")
	all.pressed.connect(func() -> void:
		var c := Studio.find_char(_sel)
		if not c.is_empty():
			App.status("Queued %d sheet drawing(s)." % Studio.queue_sheet(c, Studio.SHEET_VIEWS))
			AiJobs.kick())
	hb.add_child(all)
	var outfits := UI.button("Clothing variations", "spark", "Queue a front view for each clothing variation line")
	outfits.pressed.connect(_outfit_sheets)
	hb.add_child(outfits)
	var addref := UI.button("Add pictures of this character…", "import")
	addref.pressed.connect(func() -> void:
		_pick_view = ""
		_dialog.popup_centered_ratio(0.6))
	hb.add_child(addref)
	AiUi.head(_form, "Other references of this character")
	_others = HFlowContainer.new()
	_others.add_theme_constant_override("h_separation", int(UI.px(6)))
	_form.add_child(_others)
	_dialog = AiUi.image_dialog(self, true, _on_files)
	Studio.changed.connect(func(kind: String) -> void:
		if kind in ["cast", "refs", "all"]:
			refresh())
	refresh()


func _field(parent: Control, title: String, c: Control) -> Control:
	parent.add_child(UI.label(title, "FieldLabel"))
	parent.add_child(c)
	return c


func refresh() -> void:
	if _list == null:
		return
	_list.clear()
	_ids.clear()
	for c in Studio.cast():
		var cd: Dictionary = c
		_list.add_item(str(cd["name"]))
		_ids.append(str(cd["id"]))
		if str(cd["id"]) == _sel:
			_list.select(_list.item_count - 1)
	if _sel == "" and not _ids.is_empty():
		_sel = str(_ids[0])
		_list.select(0)
	_fill()


func _fill() -> void:
	var c := Studio.find_char(_sel)
	_form.get_parent().visible = not c.is_empty()
	if c.is_empty():
		return
	for k in _f.keys():
		var ctl: Control = _f[k]
		if ctl is LineEdit:
			(ctl as LineEdit).text = str(c.get(k, ""))
		elif ctl is TextEdit:
			(ctl as TextEdit).text = str(c.get(k, ""))
	UI.set_slider(_consistency, float(c.get("consistency", 0.75)))
	for ch in _sheets.get_children():
		ch.queue_free()
	var sheets: Dictionary = c.get("sheets", {})
	for v in Studio.SHEET_VIEWS:
		var box := UI.vbox(4)
		_sheets.add_child(box)
		box.add_child(UI.label(str(v).capitalize(), "FieldLabel"))
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = UI.size2(150, 190)
		var r := Studio.find_ref(str(sheets.get(v, "")))
		tr.texture = AiUi.thumb(str(r.get("file", "")), 190) if not r.is_empty() else null
		box.add_child(tr)
		var queued := false
		for j in Studio.jobs():
			var jd: Dictionary = j
			if str(jd.get("char_id", "")) == _sel and str(jd.get("view", "")) == v and str(jd["status"]) in ["queued", "running"]:
				queued = true
		var gen := UI.button("In queue…" if queued else "Generate", "spark")
		gen.disabled = queued
		gen.pressed.connect(func() -> void:
			Studio.queue_sheet(c, [v])
			AiJobs.kick())
		box.add_child(gen)
		var own := UI.button("Use my image…", "import")
		own.pressed.connect(func() -> void:
			_pick_view = str(v)
			_dialog.popup_centered_ratio(0.6))
		box.add_child(own)
	for ch in _others.get_children():
		ch.queue_free()
	for id in Studio.character_ref_ids(c):
		var r := Studio.find_ref(str(id))
		var t := TextureRect.new()
		t.texture = AiUi.thumb(str(r["file"]), 96)
		t.tooltip_text = str(r["name"])
		_others.add_child(t)


func _save() -> void:
	var c := Studio.find_char(_sel)
	if c.is_empty():
		return
	var changes := {"consistency": _consistency.value}
	for k in _f.keys():
		var ctl: Control = _f[k]
		changes[k] = (ctl as LineEdit).text.strip_edges() if ctl is LineEdit else (ctl as TextEdit).text.strip_edges()
	Studio.update_character(_sel, changes)
	App.status("Saved %s." % changes["name"])


func _outfit_sheets() -> void:
	var c := Studio.find_char(_sel)
	if c.is_empty():
		return
	var lines := str(c.get("outfits", "")).split("\n", false)
	if lines.size() < 2:
		App.status("Write clothing variations on separate lines (the first line is the default outfit).")
		return
	var views: Array = []
	for i in range(1, lines.size()):
		views.append(lines[i].strip_edges())
	App.status("Queued %d clothing variation(s)." % Studio.queue_sheet(c, views))
	AiJobs.kick()


func _on_files(paths: Array) -> void:
	var c := Studio.find_char(_sel)
	if c.is_empty():
		return
	for p in paths:
		var img := Image.load_from_file(str(p))
		if img == null or img.is_empty():
			continue
		var r := Studio.add_reference_image(img, "%s — %s" % [c["name"], _pick_view if _pick_view != "" else str(p).get_file().get_basename()], "character", _sel)
		if _pick_view != "" and not r.is_empty():
			var sheets: Dictionary = c.get("sheets", {})
			sheets[_pick_view] = r["id"]
			c["sheets"] = sheets
	Studio.touch("cast")
