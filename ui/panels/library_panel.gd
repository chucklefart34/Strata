class_name LibraryPanel
extends VBoxContainer
## Drawing library: save any drawing (mouths, blinks, hands, props…) and drop
## a copy onto the current layer at the playhead in any scene.
## In Animate it also has Lip sync: a mouth chart (one click places a mouth
## shape and moves on) and automatic lip sync from a dialogue clip's volume.

const MOUTHS_CATEGORY := "Mouths"
## [name, hint]
const MOUTHS := [
	["Rest", "closed, relaxed — silence"],
	["M B P", "lips pressed together"],
	["A I", "wide open — loud vowels"],
	["E", "wide, teeth showing"],
	["O", "round open"],
	["U W", "small round, pushed out"],
	["F V", "top teeth on the lower lip"],
	["L", "open, tongue up"],
]
## When a mouth isn't drawn yet, use this one instead.
const FALLBACK := {"M B P": "Rest", "E": "A I", "O": "A I", "U W": "O", "F V": "E", "L": "E", "A I": "O"}

var lipsync: bool = false
var _list: VBoxContainer
var _name: LineEdit
var _category: LineEdit
var _chart: GridContainer
var _hold: SpinBox
var _clip_pick: OptionButton
var _clip_refs: Array = []  # [AudioClipData]


func _init(with_lipsync: bool = false) -> void:
	lipsync = with_lipsync


func _ready() -> void:
	var sec := UI.section(self, "Drawing library")
	var hint := UI.label("Save drawings you reuse (mouths, blinks, hands, props) and drop a copy onto the current layer at the playhead — in any scene.", "Small")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(hint)
	var row := UI.hbox(4)
	sec.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = "Name"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	_category = LineEdit.new()
	_category.placeholder_text = "Group"
	_category.text = "Drawings"
	_category.custom_minimum_size.x = UI.px(90)
	row.add_child(_category)
	var save := UI.button("Save current drawing", "save", "Save the drawing on the current layer at this frame into the library", "Button")
	save.pressed.connect(_save_current)
	sec.add_child(save)
	_list = UI.vbox(6)
	sec.add_child(_list)

	if lipsync:
		var ls := UI.section(self, "Lip sync")
		var how := UI.label("1  Draw each mouth shape once on a “Mouth” layer and click its button below to save it (press and hold or right-click a button to replace it).\n2  Click mouths in order while scrubbing the dialogue — each click places the shape and moves ahead — or use Auto lip-sync, then fix by hand.", "Small")
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ls.add_child(how)
		var hrow := UI.hbox(6)
		ls.add_child(hrow)
		hrow.add_child(UI.label("Each mouth lasts", "FieldLabel"))
		_hold = UI.spin(1, 12, 1, 2, " frames")
		hrow.add_child(_hold)
		_chart = GridContainer.new()
		_chart.columns = 2
		_chart.add_theme_constant_override("h_separation", int(UI.px(4)))
		_chart.add_theme_constant_override("v_separation", int(UI.px(4)))
		ls.add_child(_chart)
		ls.add_child(UI.label("AUTO LIP-SYNC", "SectionTitle"))
		_clip_pick = OptionButton.new()
		_clip_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_clip_pick.tooltip_text = "The dialogue clip to follow"
		ls.add_child(_clip_pick)
		var auto := UI.button("Auto lip-sync from dialogue", "audio", "Places mouth shapes on the current layer by how loud the dialogue is (closed when quiet, open when loud). A quick first pass — then refine by hand.", "AccentButton")
		auto.pressed.connect(_auto_lipsync)
		ls.add_child(auto)

	for sig: Signal in [App.project_opened, App.library_changed, App.scene_switched, App.audio_changed]:
		sig.connect(_rebuild)
	_rebuild()


# ---------------------------------------------------------------- library list

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	if not App.has_project():
		return
	var p := App.project
	var groups := {}
	var order: Array = []
	for item in p.library:
		var it: Dictionary = item
		var cat := str(it["category"])
		if not groups.has(cat):
			groups[cat] = []
			order.append(cat)
		var arr: Array = groups[cat]
		arr.append(it)
	if order.is_empty():
		_list.add_child(UI.label("Nothing saved yet.", "Small"))
	for cat in order:
		_list.add_child(UI.label(str(cat).to_upper(), "SectionTitle"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", int(UI.px(4)))
		flow.add_theme_constant_override("v_separation", int(UI.px(4)))
		_list.add_child(flow)
		for item in groups[cat]:
			var it: Dictionary = item
			flow.add_child(_item_tile(it))
	if lipsync:
		_rebuild_chart()
		_rebuild_clips()


func _item_tile(it: Dictionary) -> Control:
	var v := UI.vbox(2)
	var id := str(it["id"])
	var cel: CelData = App.project.library_cels.get(id)
	var b := Button.new()
	b.icon = cel.get_texture() if cel != null else null
	b.expand_icon = true
	b.custom_minimum_size = UI.size2(76, 46)
	b.tooltip_text = "Place “%s” on the current layer at the playhead" % str(it["name"])
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_place.bind(id, 0))
	v.add_child(b)
	var h := UI.hbox(2)
	v.add_child(h)
	var l := UI.label(str(it["name"]), "Small")
	l.clip_text = true
	l.custom_minimum_size.x = UI.px(52)
	h.add_child(l)
	var del := UI.icon_button("trash", "Remove from the library")
	del.custom_minimum_size = UI.size2(22, 22)
	del.pressed.connect(func() -> void: Ops.remove_from_library(id))
	h.add_child(del)
	return v


func _target_layer() -> LayerData:
	var l := App.current_layer()
	if l == null:
		App.status("Pick a layer first")
		return null
	if l.is_character() or l.is_reference():
		App.status("Pick a drawing layer (not a character or reference layer)")
		return null
	if l.locked:
		App.status("“%s” is locked" % l.name)
		return null
	return l


func _place(id: String, advance: int) -> void:
	var l := _target_layer()
	if l == null:
		return
	var it := App.project.library_item(id)
	Ops.place_library(l, [[App.frame, id]], "Place “%s”" % str(it.get("name", "drawing")))
	if advance > 0:
		App.set_frame(App.frame + advance)


func _current_cel() -> CelData:
	var l := App.current_layer()
	if l == null or l.is_character():
		return null
	return l.cel_at(App.frame)


func _save_current() -> void:
	var cel := _current_cel()
	if cel == null:
		App.status("Nothing drawn on the current layer at this frame")
		return
	var n := _name.text.strip_edges()
	if n == "":
		n = "Drawing %d" % (App.project.library.size() + 1)
	var cat := _category.text.strip_edges()
	if cat == "":
		cat = "Drawings"
	Ops.save_to_library(cel, n, cat)
	_name.text = ""
	App.status("Saved “%s” to the library" % n)


# ---------------------------------------------------------------- lip sync

func _rebuild_chart() -> void:
	for c in _chart.get_children():
		c.queue_free()
	for m in MOUTHS:
		var mname := str(m[0])
		var it := App.project.library_find(MOUTHS_CATEGORY, mname)
		var b := Button.new()
		b.text = mname
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = UI.px(44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if it.is_empty():
			b.tooltip_text = "%s (%s)\nNot drawn yet: draw it on the current layer, then click to save it." % [mname, str(m[1])]
			b.modulate = Color(1, 1, 1, 0.6)
		else:
			var cel: CelData = App.project.library_cels.get(str(it["id"]))
			b.icon = cel.get_texture() if cel != null else null
			b.expand_icon = true
			b.tooltip_text = "%s (%s)\nClick: place it here and move ahead. Right-click / hold: replace it with the current drawing." % [mname, str(m[1])]
		b.pressed.connect(_on_mouth.bind(mname))
		b.gui_input.connect(_on_mouth_input.bind(mname))
		_chart.add_child(b)


func _on_mouth(mname: String) -> void:
	var it := App.project.library_find(MOUTHS_CATEGORY, mname)
	if it.is_empty():
		_save_mouth(mname)
		return
	_place(str(it["id"]), int(_hold.value))


func _on_mouth_input(event: InputEvent, mname: String) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_save_mouth(mname)


func _save_mouth(mname: String) -> void:
	var cel := _current_cel()
	if cel == null:
		App.status("Draw the “%s” mouth on the current layer first, then click its button to save it" % mname)
		return
	Ops.save_to_library(cel, mname, MOUTHS_CATEGORY)
	App.status("Saved the “%s” mouth" % mname)


func _rebuild_clips() -> void:
	var keep := _clip_pick.get_item_text(_clip_pick.selected) if _clip_pick.selected >= 0 else ""
	_clip_pick.clear()
	_clip_refs.clear()
	var s := App.current_scene()
	if s == null:
		return
	for t in s.audio_tracks:
		for c in t.clips:
			_clip_refs.append(c)
			_clip_pick.add_item("%s — %s" % [t.name, c.name])
	if _clip_refs.is_empty():
		_clip_pick.add_item("No sound in this scene (add dialogue in Audio)")
		_clip_pick.disabled = true
	else:
		_clip_pick.disabled = false
		for i in _clip_pick.item_count:
			if _clip_pick.get_item_text(i) == keep:
				_clip_pick.select(i)


func _mouth_id(mname: String) -> String:
	var n := mname
	for _i in 4:
		var it := App.project.library_find(MOUTHS_CATEGORY, n)
		if not it.is_empty():
			return str(it["id"])
		n = str(FALLBACK.get(n, "Rest"))
	for item in App.project.library:
		var it2: Dictionary = item
		if str(it2["category"]) == MOUTHS_CATEGORY:
			return str(it2["id"])
	return ""


func _auto_lipsync() -> void:
	var l := _target_layer()
	if l == null or _clip_refs.is_empty():
		return
	if _mouth_id("A I") == "" or _mouth_id("Rest") == "":
		App.status("Save at least a closed (Rest) and an open (A I) mouth first")
		return
	var c: AudioClipData = _clip_refs[clampi(_clip_pick.selected, 0, _clip_refs.size() - 1)]
	if Audio.peaks_for(c.file).is_empty():
		App.status("Still reading the sound — try again in a moment")
		return
	var fps: int = App.project.fps
	var hold := int(_hold.value)
	var f0 := c.start_frame
	var f1 := c.end_frame(fps)
	var stream_len := Audio.length_of(c.file)
	var gain := db_to_linear(c.gain_db)
	var louds: Array[float] = []
	var mx := 0.0001
	for f in range(f0, f1, hold):
		var t := float(f) / fps
		var src := c.source_pos(t, fps, stream_len)
		var v := 0.0 if src < 0.0 else Audio.peak_between(c.file, src, src + float(hold) / fps) * gain * c.fade_gain(t, fps)
		louds.append(v)
		mx = maxf(mx, v)
	var placements: Array = []
	var prev := ""
	var syllable := 0
	var was_low := true
	var cycle := ["E", "O", "A I", "U W", "E", "L"]
	for i in louds.size():
		var r := louds[i] / mx
		var mname := "Rest"
		if r < 0.12:
			mname = "Rest" if r < 0.05 or prev == "Rest" or prev == "M B P" else "M B P"
		else:
			if was_low:
				syllable += 1
			if r > 0.62:
				mname = "A I"
			elif r > 0.3:
				mname = str(cycle[syllable % cycle.size()])
			else:
				mname = "E" if syllable % 2 == 0 else "U W"
		was_low = r < 0.12
		var id := _mouth_id(mname)
		if id != "" and mname != prev:
			placements.append([f0 + i * hold, id])
			prev = mname
	placements.append([f1, _mouth_id("Rest")])
	Ops.place_library(l, placements, "Auto lip-sync")
	App.status("Placed %d mouth shapes on “%s”. Scrub and swap any that look wrong with the mouth chart." % [placements.size(), l.name])
