class_name AiRefsPage
extends Control
## Reference library and the project's style profile. References are
## analysed on this computer (palette, light key, contrast, line density,
## solid blacks) and the findings become words in the prompts; references
## marked for the style (and character sheets) also guide the image model
## through IP-Adapter. They guide the look; they are not traced or copied.

var ws: AiStudioWorkspace
var _filter: OptionButton
var _add_cat: OptionButton
var _grid: HFlowContainer
var _sel_id: String = ""
var _detail: VBoxContainer
var _hint: Label
var _d_name: LineEdit
var _d_cat: OptionButton
var _d_char: OptionButton
var _d_notes: LineEdit
var _d_info: Label
var _d_ai: Label
var _d_pal: HBoxContainer
var _d_style: CheckBox
var _d_preview: TextureRect
var _st_name: LineEdit
var _st_desc: TextEdit
var _st_neg: TextEdit
var _st_line: LineEdit
var _st_shade: LineEdit
var _st_light: LineEdit
var _st_pal_box: VBoxContainer
var _st_weight: HSlider
var _dialog: FileDialog
var _char_ids: Array = []
var _syncing: bool = false


func _ready() -> void:
	var root := UI.hbox(12)
	UI.full_rect(root)
	add_child(root)
	# ---- style profile
	var left := AiUi.sidebar(root, 400)
	AiUi.head(left, "Project style profile")
	var sv := AiUi.scroll(left)
	sv.add_child(AiUi.wrap_label("Every prompt starts from this. It describes qualities only — keep it original (no artist or studio names).", "Small"))
	var g := AiUi.grid(sv, 2)
	_st_name = AiUi.row(g, "Name", AiUi.line()) as LineEdit
	sv.add_child(UI.label("Look", "FieldLabel"))
	_st_desc = AiUi.text("", 150)
	sv.add_child(_st_desc)
	sv.add_child(UI.label("Avoid (negative prompt)", "FieldLabel"))
	_st_neg = AiUi.text("", 90)
	sv.add_child(_st_neg)
	var g2 := AiUi.grid(sv, 2)
	_st_line = AiUi.row(g2, "Linework", AiUi.line()) as LineEdit
	_st_shade = AiUi.row(g2, "Shading", AiUi.line()) as LineEdit
	_st_light = AiUi.row(g2, "Lighting", AiUi.line()) as LineEdit
	sv.add_child(UI.label("Palette (from style references)", "FieldLabel"))
	_st_pal_box = UI.vbox(2)
	sv.add_child(_st_pal_box)
	_st_weight = UI.slider(sv, "Style references' pull on the image", 0.0, 1.0, 0.05, 0.45, func(_v: float) -> void: pass, "%.2f")
	var h := UI.hbox(6)
	sv.add_child(h)
	var save := UI.button("Save style", "save", "", "AccentButton")
	save.pressed.connect(_save_style)
	h.add_child(save)
	var rebuild := UI.button("From references", "spark", "Fill palette, linework, shading and lighting from the references ticked “Use for the project style”")
	rebuild.pressed.connect(func() -> void:
		Studio.rebuild_style_from_refs()
		App.status("Style profile rebuilt from %d reference(s)." % (Studio.style()["ref_ids"] as Array).size()))
	h.add_child(rebuild)
	var reset := UI.button("House style", "reset", "Back to the original dark graphic-novel look")
	reset.pressed.connect(func() -> void:
		Studio.set_style({"descriptors": Studio.HOUSE_STYLE, "negative": Studio.HOUSE_NEGATIVE, "name": "House style"}))
	h.add_child(reset)

	# ---- library
	var mid := UI.vbox(8)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var top := UI.hbox(6)
	mid.add_child(top)
	top.add_child(UI.label("Show", "FieldLabel"))
	var cats: Array = ["all"]
	cats.append_array(Studio.REF_CATEGORIES)
	_filter = UI.option(cats)
	_filter.item_selected.connect(func(_i: int) -> void: _build_grid())
	top.add_child(_filter)
	top.add_child(UI.spacer())
	top.add_child(UI.label("Add as", "FieldLabel"))
	_add_cat = UI.option(Studio.REF_CATEGORIES, Studio.REF_CATEGORIES.find("style"))
	top.add_child(_add_cat)
	var add := UI.button("Add images…", "import", "Add reference pictures (character designs, faces, clothing, environments, palettes, lighting, linework…)", "AccentButton")
	add.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.6))
	top.add_child(add)
	_dialog = AiUi.image_dialog(self, true, _on_files)
	var gsc := ScrollContainer.new()
	gsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(gsc)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(UI.px(8)))
	_grid.add_theme_constant_override("v_separation", int(UI.px(8)))
	gsc.add_child(_grid)

	# ---- selected reference
	var right := AiUi.sidebar(root, 320)
	AiUi.head(right, "Reference")
	_hint = AiUi.wrap_label("Select a reference to see what was measured, assign it to a character, or use it for the project style.", "Small")
	right.add_child(_hint)
	_detail = AiUi.scroll(right)
	_d_preview = TextureRect.new()
	_d_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_d_preview.custom_minimum_size = UI.size2(290, 200)
	_detail.add_child(_d_preview)
	var dg := AiUi.grid(_detail, 2)
	_d_name = AiUi.row(dg, "Name", AiUi.line()) as LineEdit
	_d_cat = AiUi.row(dg, "Kind", UI.option(Studio.REF_CATEGORIES)) as OptionButton
	_d_char = AiUi.row(dg, "Character", UI.option(["—"])) as OptionButton
	_d_notes = AiUi.row(dg, "Notes", AiUi.line()) as LineEdit
	_d_style = CheckBox.new()
	_d_style.text = "Use for the project style"
	_d_style.tooltip_text = "Guides every background and, when no character sheet exists, every drawing (IP-Adapter), and feeds “From references”."
	_detail.add_child(_d_style)
	var dsave := UI.button("Save", "save")
	dsave.pressed.connect(_save_ref)
	_detail.add_child(dsave)
	_detail.add_child(UI.label("What it shows (measured here)", "FieldLabel"))
	_d_pal = UI.hbox(3)
	_detail.add_child(_d_pal)
	_d_info = AiUi.wrap_label("", "Small")
	_detail.add_child(_d_info)
	_d_ai = AiUi.wrap_label("", "Small")
	_detail.add_child(_d_ai)
	var desc := UI.button("Describe with AI (cloud)", "spark", "Ask Claude to describe this reference's style in words (sent to Anthropic)")
	desc.pressed.connect(_describe)
	_detail.add_child(desc)
	var use_words := UI.button("Add words to style", "plus", "Append the AI description to the style profile's look")
	use_words.pressed.connect(func() -> void:
		var r := Studio.find_ref(_sel_id)
		var t := str(r.get("ai_description", ""))
		if t != "":
			Studio.set_style({"descriptors": str(Studio.style()["descriptors"]) + ", " + t}))
	_detail.add_child(use_words)
	var del := UI.button("Remove reference", "trash")
	del.pressed.connect(func() -> void:
		Studio.delete_ref(_sel_id)
		_sel_id = "")
	_detail.add_child(del)

	Studio.changed.connect(func(kind: String) -> void:
		if kind in ["refs", "style", "cast", "all"]:
			refresh())
	refresh()


func refresh() -> void:
	if _grid == null:
		return
	_fill_style()
	_build_grid()
	_fill_detail()


func _fill_style() -> void:
	var st := Studio.style()
	_st_name.text = str(st.get("name", ""))
	_st_desc.text = str(st.get("descriptors", ""))
	_st_neg.text = str(st.get("negative", ""))
	_st_line.text = str(st.get("line", ""))
	_st_shade.text = str(st.get("shading", ""))
	_st_light.text = str(st.get("lighting", ""))
	UI.set_slider(_st_weight, float(st.get("style_weight", 0.45)))
	for c in _st_pal_box.get_children():
		c.queue_free()
	var pal: Array = st.get("palette", [])
	if pal.is_empty():
		_st_pal_box.add_child(UI.label("none yet", "Small"))
	else:
		AiUi.swatches(_st_pal_box, pal)
		_st_pal_box.add_child(UI.label(RefAnalyzer.palette_words(pal), "Small"))


func _save_style() -> void:
	Studio.set_style({"name": _st_name.text, "descriptors": _st_desc.text.strip_edges(), "negative": _st_neg.text.strip_edges(),
		"line": _st_line.text.strip_edges(), "shading": _st_shade.text.strip_edges(), "lighting": _st_light.text.strip_edges(),
		"style_weight": _st_weight.value})
	App.status("Style profile saved — new drawings use it.")


func _build_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var cat := _filter.get_item_text(_filter.selected) if _filter.selected >= 0 else "all"
	var style_ids: Array = Studio.style()["ref_ids"]
	for r in Studio.refs():
		var rd: Dictionary = r
		if cat != "all" and str(rd["category"]) != cat:
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = UI.size2(150, 130)
		b.icon = AiUi.thumb(str(rd["file"]), 130)
		b.expand_icon = true
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.text = "%s%s" % [str(rd["name"]).left(18), " ✦" if style_ids.has(str(rd["id"])) else ""]
		b.tooltip_text = "%s · %s\n%s" % [rd["name"], rd["category"], str((rd.get("analysis", {}) as Dictionary).get("summary", ""))]
		b.add_theme_font_size_override("font_size", int(UI.px(11)))
		b.set_pressed_no_signal(str(rd["id"]) == _sel_id)
		b.pressed.connect(func() -> void:
			_sel_id = str(rd["id"])
			_build_grid()
			_fill_detail())
		_grid.add_child(b)
	if Studio.refs().is_empty():
		_grid.add_child(AiUi.wrap_label("No references yet. Add character designs, faces, clothing, environments, palettes, lighting studies and linework you like. Drop several of a kind for a stronger read.", "Lead"))


func _fill_detail() -> void:
	var r := Studio.find_ref(_sel_id)
	_detail.get_parent().visible = not r.is_empty()
	_hint.visible = r.is_empty()
	if r.is_empty():
		return
	_syncing = true
	_d_preview.texture = AiUi.thumb(str(r["file"]), 300)
	_d_name.text = str(r["name"])
	_d_cat.select(maxi(0, Studio.REF_CATEGORIES.find(str(r["category"]))))
	_d_char.clear()
	_d_char.add_item("—")
	_char_ids = [""]
	for c in Studio.cast():
		_d_char.add_item(str((c as Dictionary)["name"]))
		_char_ids.append(str((c as Dictionary)["id"]))
	_d_char.select(maxi(0, _char_ids.find(str(r.get("character_id", "")))))
	_d_notes.text = str(r.get("notes", ""))
	_d_style.set_pressed_no_signal((Studio.style()["ref_ids"] as Array).has(_sel_id))
	for c in _d_pal.get_children():
		c.queue_free()
	var a: Dictionary = r.get("analysis", {})
	for hx in a.get("palette", []):
		var cr := ColorRect.new()
		cr.color = Color(str(hx))
		cr.custom_minimum_size = UI.size2(22, 22)
		cr.tooltip_text = RefAnalyzer.color_word(Color(str(hx)))
		_d_pal.add_child(cr)
	_d_info.text = "%s\nBrightness %.2f · contrast %.2f · saturation %.2f · warmth %+.2f · line detail %.2f · solid black %.0f%%" % [
		str(a.get("summary", "")), float(a.get("brightness", 0)), float(a.get("contrast", 0)), float(a.get("saturation", 0)),
		float(a.get("warmth", 0)), float(a.get("line_density", 0)), float(a.get("black_share", 0)) * 100.0]
	_d_ai.text = ("AI description: " + str(r["ai_description"])) if str(r.get("ai_description", "")) != "" else ""
	_syncing = false


func _save_ref() -> void:
	var r := Studio.find_ref(_sel_id)
	if r.is_empty():
		return
	r["name"] = _d_name.text.strip_edges()
	r["category"] = Studio.REF_CATEGORIES[_d_cat.selected]
	r["character_id"] = str(_char_ids[_d_char.selected]) if _d_char.selected >= 0 and _d_char.selected < _char_ids.size() else ""
	r["notes"] = _d_notes.text.strip_edges()
	var ids: Array = Studio.style()["ref_ids"]
	if _d_style.button_pressed and not ids.has(_sel_id):
		ids.append(_sel_id)
	elif not _d_style.button_pressed:
		ids.erase(_sel_id)
	Studio.touch("refs")
	App.status("Reference saved.")


func _on_files(paths: Array) -> void:
	var cat: String = Studio.REF_CATEGORIES[_add_cat.selected]
	var errs: Array[String] = []
	for p in paths:
		var e := Studio.add_reference_file(str(p), cat)
		if e != "":
			errs.append(e)
	App.status("Added %d reference(s)%s" % [paths.size() - errs.size(), (" — " + "; ".join(errs)) if not errs.is_empty() else ""])


func _describe() -> void:
	var r := Studio.find_ref(_sel_id)
	var img := Studio.ref_image(_sel_id)
	if r.is_empty() or img == null:
		return
	App.status("Asking the director to describe the reference…")
	var res: Dictionary = await AiJobs.director.describe_reference(img)
	if bool(res.get("ok", false)):
		r["ai_description"] = str(res["text"])
		Studio.touch("refs")
		App.status("Described.")
	else:
		App.status(str(res.get("error", "")))
