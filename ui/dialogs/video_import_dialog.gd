class_name VideoImportDialog
extends ConfirmationDialog
## Imports a video file as a new layer: FFmpeg decodes it straight into
## canvas-sized RGBA PNG frames inside the project (one drawing per frame,
## or on 2s/3s), so the video is an ordinary layer you can draw over
## (rotoscope), place in 3D and render. The video's sound can come along as
## an audio clip lined up with the first frame.
## Frames are written to disk and loaded lazily, so long clips don't fill memory.

const VIDEO_EXTENSIONS := ["mp4", "mov", "m4v", "webm", "mkv", "avi", "ogv", "gif", "mpg", "mpeg", "wmv", "flv"]

var _path: String = ""
var _duration: float = 0.0
var _src_fps: float = 0.0
var _src_size: Vector2i = Vector2i.ZERO
var _ffmpeg: String = ""

var _file_label: Label
var _info: Label
var _start: SpinBox
var _length: SpinBox
var _step: OptionButton
var _reference: CheckBox
var _audio: CheckBox
var _progress: ProgressBar
var _file_dialog: FileDialog
var _locate_dialog: FileDialog
var _locate_btn: Button
var _roto: CheckBox
var _roto_box: VBoxContainer
var _r_simplify: HSlider
var _r_preset: OptionButton
var _r_colors: HSlider
var _r_ink: HSlider
var _r_smooth: HSlider
var _r_steady: HSlider
var _steady: TemporalStabilizer
var _r_trace: CheckBox
var _r_line_detail: HSlider
var _r_line_smooth: HSlider
var _r_area: CheckBox
var _swatches: HFlowContainer
var _centers: Array = []  # palette cluster centres (Lab), dark → light
var _custom_outputs: Dictionary = {}  # swatch index -> Color chosen by the user
var _r_thickness: HSlider
var _r_sensitivity: HSlider
var _r_saturation: HSlider
var _r_line_color: ColorPickerButton
var _preview: TextureRect
var _preview_tex: ImageTexture
var _processor: ToonProcessor
var _matte: MatteProcessor
var _e_mode: OptionButton
var _e_box: VBoxContainer
var _e_threshold: HSlider
var _e_softness: HSlider
var _e_cleanup: HSlider
var _e_grow: HSlider
var _e_key_row: HBoxContainer
var _e_key: ColorPickerButton
var _e_spill: HSlider
var _e_invert: CheckBox
var _e_crop: CheckBox
var _e_crop_box: VBoxContainer
var _e_left: HSlider
var _e_right: HSlider
var _e_top: HSlider
var _e_bottom: HSlider
var _e_feather: HSlider
var _e_hint: Label
var _plate_sources: Array = []  # sample frames for the preview's background plate
var _pid: int = -1
var _running: bool = false
var _cancel: bool = false

# ---- video preview (low-res proxy frames decoded in the background)
const PROXY_WIDTH := 480
const PROXY_MAX_FRAMES := 900
var _pv_frame: TextureRect
var _pv_tex: ImageTexture
var _result_tex: ImageTexture
var _pv_overlay: PreviewOverlay
var _pv_bar: RangeBar
var _pv_play: Button
var _pv_time: Label
var _pv_original: Button
var _pv_result: Button
var _pv_status: Label
var _proxy_dir: String = ""
var _proxy_fps: float = 12.0
var _proxy_count: int = 0
var _proxy_done: bool = false
var _proxy_pid: int = -1
var _proxy_gen: int = 0
var _time: float = 0.0  # playhead, seconds into the video
var _playing: bool = false
var _show_result: bool = false
var _result_time: float = -1.0  # where the shown result was made
var _shown_index: int = -1
var _press_pos: Vector2 = Vector2.ZERO
var _press_down: bool = false
var _box_drag: bool = false
var _want_result: bool = false
## Elements "Keep" choices in menu order: [label, matte mode].
const KEEP := [
	["Everything", "everything"],
	["Remove the background automatically (keeps the main subject)", "auto"],
	["Keep a subject I pick (tracked through the clip)", "subject"],
	["Remove an object I pick (tracked through the clip)", "object"],
	["Moving subjects (remove a still background)", "background"],
	["Everything except a colour (green screen / colour key)", "colour"],
	["Remove light areas (white paper, sky)", "light"],
	["Remove dark areas (black backgrounds)", "dark"],
]
const AUTO_RELEARN := 1.5  # seconds between re-learning the background (auto mode)
var _auto_tracker := SubjectTracker.new()
var _auto_key: int = -999
var _frames_btn: Button
var _frames_dialog: FileDialog
var _result_mode: bool = false  # the person wants to see the result (live)
var _result_timer: Timer
var _preview_busy: bool = false
var _preview_pending: bool = false
var _ui_ready: bool = false
# ---- subject tracking
var _tracker := SubjectTracker.new()
var _subject_box_ui: VBoxContainer
var _subject_tool: String = "box"  # "box", "fg", "bg"
var _subject_tool_btns: Dictionary = {}
var _subject_status: Label
var _e_edge: HSlider
var _tracking: bool = false
var _last_mark_pos: Vector2 = Vector2(-999, -999)


## Timeline under the preview: the import range (in → out) and the playhead.
class RangeBar extends Control:
	signal scrubbed(t: float)
	signal range_moved(t_in: float, t_out: float)
	signal range_released
	var duration: float = 0.0
	var loaded: float = 0.0  # seconds of preview decoded so far
	var t_in: float = 0.0
	var t_out: float = 0.0
	var playhead: float = 0.0
	var key_times: Array = []
	var tracked_range: Vector2 = Vector2(-1, -1)
	var _drag: String = ""

	func _x(t: float) -> float:
		var pad := UI.px(8)
		return pad + (size.x - pad * 2.0) * (t / maxf(0.001, duration))

	func _t(x: float) -> float:
		var pad := UI.px(8)
		return clampf((x - pad) / maxf(1.0, size.x - pad * 2.0), 0.0, 1.0) * duration

	func _draw() -> void:
		var mid := size.y * 0.55
		var th := UI.px(8)
		var pad := UI.px(8)
		draw_rect(Rect2(pad, mid - th * 0.5, size.x - pad * 2.0, th), Palette.FIELD)
		if duration <= 0.0:
			return
		draw_rect(Rect2(pad, mid - th * 0.5, _x(loaded) - pad, th), Palette.HOVER)
		var a := _x(t_in)
		var b := _x(t_out)
		draw_rect(Rect2(a, mid - th * 0.5, b - a, th), Palette.ACCENT_SOFT)
		draw_rect(Rect2(a, mid - th * 0.5, b - a, th), Palette.ACCENT, false, 1.0)
		for hx in [a, b]:
			var x: float = hx
			draw_rect(Rect2(x - UI.px(3), mid - th, UI.px(6), th * 2.0), Palette.ACCENT)
		if tracked_range.x >= 0.0:
			draw_rect(Rect2(_x(tracked_range.x), mid + th * 0.5 + 1.0, _x(tracked_range.y) - _x(tracked_range.x), UI.px(3)), Color("#5fd35f"))
		for kt in key_times:
			var kx := _x(float(kt))
			var d := UI.px(5)
			draw_colored_polygon(PackedVector2Array([Vector2(kx, mid - d), Vector2(kx + d, mid), Vector2(kx, mid + d), Vector2(kx - d, mid)]), Color("#5fd35f"))
		var px := _x(playhead)
		draw_line(Vector2(px, UI.px(2)), Vector2(px, size.y - UI.px(2)), Palette.TEXT, 2.0)
		draw_circle(Vector2(px, UI.px(4)), UI.px(4), Palette.TEXT)
		var font := get_theme_default_font()
		var fs := int(UI.px(10))
		draw_string(font, Vector2(a + UI.px(2), size.y), "IN", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.ACCENT)
		draw_string(font, Vector2(b - UI.px(22), size.y), "OUT", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.ACCENT)

	func _gui_input(e: InputEvent) -> void:
		if duration <= 0.0:
			return
		var mb := e as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var grab := UI.px(7)
				if absf(mb.position.x - _x(t_in)) < grab and mb.position.y > size.y * 0.3:
					_drag = "in"
				elif absf(mb.position.x - _x(t_out)) < grab and mb.position.y > size.y * 0.3:
					_drag = "out"
				else:
					_drag = "head"
					scrubbed.emit(_t(mb.position.x))
			else:
				if _drag == "in" or _drag == "out":
					range_released.emit()
				_drag = ""
			accept_event()
		var mm := e as InputEventMouseMotion
		if mm != null and _drag != "":
			var t := _t(mm.position.x)
			match _drag:
				"in":
					t_in = minf(t, t_out - 0.05)
					range_moved.emit(t_in, t_out)
					scrubbed.emit(t_in)
				"out":
					t_out = maxf(t, t_in + 0.05)
					range_moved.emit(t_in, t_out)
					scrubbed.emit(t_out)
				_:
					scrubbed.emit(t)
			accept_event()


## Draws the "keep only this area" box over the preview.
class PreviewOverlay extends Control:
	var box: Rect2 = Rect2(0, 0, 1, 1)
	var show_box: bool = false
	var aspect: float = 16.0 / 9.0
	var subject_box: Rect2 = Rect2()
	var show_subject: bool = false
	var subject_is_key: bool = false
	var marks: Array = []  # [{uv, r, fg}]

	func image_rect() -> Rect2:
		var r := Rect2(Vector2.ZERO, size)
		if size.x / maxf(size.y, 1.0) > aspect:
			var w := size.y * aspect
			return Rect2((size.x - w) * 0.5, 0, w, size.y)
		var h := size.x / aspect
		return Rect2(0, (size.y - h) * 0.5, size.x, h)

	func _draw() -> void:
		_draw_subject()
		if not show_box:
			return
		var ir := image_rect()
		var r := Rect2(ir.position + box.position * ir.size, box.size * ir.size)
		var shade := Color(0, 0, 0, 0.5)
		draw_rect(Rect2(ir.position.x, ir.position.y, ir.size.x, r.position.y - ir.position.y), shade)
		draw_rect(Rect2(ir.position.x, r.end.y, ir.size.x, ir.end.y - r.end.y), shade)
		draw_rect(Rect2(ir.position.x, r.position.y, r.position.x - ir.position.x, r.size.y), shade)
		draw_rect(Rect2(r.end.x, r.position.y, ir.end.x - r.end.x, r.size.y), shade)
		draw_rect(r, Palette.ACCENT, false, 2.0)

	func _draw_subject() -> void:
		var ir := image_rect()
		for m in marks:
			var d: Dictionary = m
			var uv: Vector2 = d["uv"]
			var col := Color(0.37, 0.83, 0.37, 0.8) if bool(d["fg"]) else Color(1.0, 0.37, 0.34, 0.8)
			draw_circle(ir.position + uv * ir.size, maxf(2.0, float(d["r"]) * ir.size.x), col)
		if show_subject:
			var r := Rect2(ir.position + subject_box.position * ir.size, subject_box.size * ir.size)
			var col := Color("#5fd35f")
			draw_rect(r, col, false, 3.0 if subject_is_key else 2.0)
			var font := get_theme_default_font()
			draw_string(font, r.position + Vector2(4, -5), "SUBJECT" + (" (key)" if subject_is_key else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, int(UI.px(11)), col)


static func is_video_file(path: String) -> bool:
	return VIDEO_EXTENSIONS.has(path.get_extension().to_lower())


func _ready() -> void:
	title = "Import video as layer"
	ok_button_text = "Import"
	dialog_hide_on_ok = false
	min_size = Vector2i(int(UI.px(520)), 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(UI.px(780), UI.px(680))
	add_child(scroll)
	var v := UI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var fr := UI.hbox(8)
	v.add_child(fr)
	_file_label = UI.label("No file chosen", "ValueLabel")
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_label.clip_text = true
	fr.add_child(_file_label)
	var browse := UI.button("Choose video…", "folder")
	browse.pressed.connect(func() -> void: _file_dialog.popup_centered_ratio(0.6))
	fr.add_child(browse)
	_build_video_preview(v)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(UI.px(12)))
	grid.add_theme_constant_override("v_separation", int(UI.px(8)))
	v.add_child(grid)
	grid.add_child(UI.label("Start at", "FieldLabel"))
	_start = UI.spin(0, 36000, 0.1, 0, " s")
	_start.value_changed.connect(func(_x: float) -> void:
		_update_info()
		_sync_bar())
	grid.add_child(_start)
	grid.add_child(UI.label("Length", "FieldLabel"))
	_length = UI.spin(0, 36000, 0.1, 0, " s")
	_length.tooltip_text = "0 = until the end of the video"
	_length.value_changed.connect(func(_x: float) -> void:
		_update_info()
		_sync_bar())
	grid.add_child(_length)
	grid.add_child(UI.label("Frames", "FieldLabel"))
	_step = UI.option(["Every frame (on 1s)", "Every 2nd frame (on 2s)", "Every 3rd frame (on 3s)"])
	_step.tooltip_text = "On 2s halves the drawings to edit — the classic choice for rotoscoping"
	_step.item_selected.connect(func(_i: int) -> void: _update_info())
	grid.add_child(_step)
	_reference = CheckBox.new()
	_reference.text = "Reference only (for rotoscoping — shown faded, never rendered)"
	_reference.focus_mode = Control.FOCUS_NONE
	v.add_child(_reference)
	_audio = CheckBox.new()
	_audio.text = "Also import the video's sound as an audio clip"
	_audio.button_pressed = true
	_audio.focus_mode = Control.FOCUS_NONE
	v.add_child(_audio)
	_build_elements(v)
	_roto = CheckBox.new()
	_roto.text = "Auto-rotoscope: redraw as flat colour blocks with clean outlines"
	_roto.focus_mode = Control.FOCUS_NONE
	_roto.toggled.connect(func(on: bool) -> void:
		_roto_box.visible = on
		reset_size())
	v.add_child(_roto)
	_build_roto_settings(v)
	_info = UI.label("", "Small")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = UI.px(480)
	v.add_child(_info)
	_frames_btn = UI.button("Import frames from images…", "image", "Pick a series of PNG/JPG frames (in file-name order) and put them on a new layer, one per frame")
	_frames_btn.pressed.connect(func() -> void: _frames_dialog.popup_centered_ratio(0.6))
	_frames_dialog = FileDialog.new()
	_frames_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_frames_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_frames_dialog.use_native_dialog = true
	_frames_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Frames"])
	_frames_dialog.files_selected.connect(_import_frame_files)
	add_child(_frames_dialog)
	_locate_btn = UI.button("Locate FFmpeg…", "folder", "Choose the ffmpeg executable (or the folder you unzipped it to)")
	_locate_btn.pressed.connect(func() -> void: _locate_dialog.popup_centered_ratio(0.6))
	v.add_child(_locate_btn)
	v.add_child(_frames_btn)
	_progress = ProgressBar.new()
	_progress.visible = false
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = UI.px(6)
	v.add_child(_progress)

	_processor = ToonProcessor.new()
	add_child(_processor)
	_matte = MatteProcessor.new()
	add_child(_matte)
	_steady = TemporalStabilizer.new()
	add_child(_steady)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.title = "Choose a video"
	_file_dialog.filters = PackedStringArray(["*.%s ; Video" % ", *.".join(PackedStringArray(VIDEO_EXTENSIONS))])
	_file_dialog.file_selected.connect(set_file)
	add_child(_file_dialog)

	_locate_dialog = FileDialog.new()
	_locate_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_locate_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_locate_dialog.use_native_dialog = true
	_locate_dialog.title = "Locate ffmpeg"
	_locate_dialog.file_selected.connect(_on_locate)
	_locate_dialog.dir_selected.connect(_on_locate)
	add_child(_locate_dialog)

	_result_timer = Timer.new()
	_result_timer.one_shot = true
	_result_timer.wait_time = 0.3
	_result_timer.timeout.connect(_refresh_result)
	add_child(_result_timer)
	_ui_ready = true
	confirmed.connect(_on_import)
	canceled.connect(func() -> void:
		if _running:
			_cancel = true)
	visibility_changed.connect(func() -> void:
		if not visible:
			_playing = false
			_stop_proxy())


func _build_roto_settings(parent: Control) -> void:
	_roto_box = UI.vbox(6)
	_roto_box.visible = false
	parent.add_child(_roto_box)
	var cols := UI.hbox(14)
	_roto_box.add_child(cols)
	var sliders := UI.vbox(4)
	sliders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sliders.custom_minimum_size.x = UI.px(270)
	cols.add_child(sliders)
	var lr := UI.hbox(8)
	sliders.add_child(lr)
	lr.add_child(UI.label("Look", "FieldLabel"))
	_r_preset = UI.option(PaletteTools.PRESETS.keys())
	_r_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_r_preset.tooltip_text = "Video colours keeps the footage's own colours, simplified. The others recolour it into a limited graphic palette."
	_r_preset.item_selected.connect(func(_i: int) -> void:
		_custom_outputs.clear()
		_recolor())
	lr.add_child(_r_preset)
	_r_colors = UI.slider(sliders, "Number of colours", 2, 32, 1, 8, _on_colors_changed, "%d")
	_r_ink = UI.slider(sliders, "Shadows to solid ink", 0, 60, 1, 18, _on_roto_changed, "%d%%")
	_r_simplify = UI.slider(sliders, "Remove texture & detail", 1, 14, 1, 7, _on_roto_changed, "%d")
	sliders.add_child(UI.label("LINES (traced from the video, drawn over the colours)", "SectionTitle"))
	_r_trace = CheckBox.new()
	_r_trace.text = "Trace ink lines"
	_r_trace.button_pressed = true
	_r_trace.focus_mode = Control.FOCUS_NONE
	_r_trace.toggled.connect(func(_on: bool) -> void: _on_roto_changed(0.0))
	sliders.add_child(_r_trace)
	_r_thickness = UI.slider(sliders, "Line thickness", 0, 8, 0.5, 2, _on_roto_changed, "%.1f px")
	_r_line_detail = UI.slider(sliders, "Line detail (higher = more lines)", 1, 20, 1, 10, _on_roto_changed, "%d")
	_r_line_smooth = UI.slider(sliders, "Line smoothness (cleaner curves, fewer specks)", 0, 10, 1, 5, _on_roto_changed, "%d")
	_r_area = CheckBox.new()
	_r_area.text = "Also outline every colour area"
	_r_area.focus_mode = Control.FOCUS_NONE
	_r_area.toggled.connect(func(_on: bool) -> void: _on_roto_changed(0.0))
	sliders.add_child(_r_area)
	_r_sensitivity = UI.slider(sliders, "Area outline detail (lower = more)", 4, 50, 1, 12, _on_roto_changed, "%d")
	_r_saturation = UI.slider(sliders, "Colour boost (video colours)", 50, 200, 5, 125, _on_boost_changed, "%d%%")
	_r_smooth = UI.slider(sliders, "Smooth shapes (rounder edges, no specks)", 0, 12, 1, 6, _on_roto_changed, "%d")
	_r_steady = UI.slider(sliders, "Steady over time (less flicker between frames)", 0, 100, 1, 45, _on_roto_changed, "%d%%")
	_r_steady.tooltip_text = "Areas that don't really change between frames keep exactly the same colours and lines. Higher = calmer, but very subtle motion may stick."
	var lc := UI.hbox(8)
	sliders.add_child(lc)
	lc.add_child(UI.label("Ink & outline colour", "FieldLabel"))
	_r_line_color = ColorPickerButton.new()
	_r_line_color.color = Color("#0b0909")
	_r_line_color.custom_minimum_size = UI.size2(56, 28)
	_r_line_color.popup_closed.connect(_on_roto_changed.bind(0.0))
	lc.add_child(_r_line_color)

	var pv := UI.vbox(6)
	pv.custom_minimum_size.x = UI.px(240)
	cols.add_child(pv)
	var pb := UI.button("Preview look", "eye", "Rotoscope the frame under the playhead (also picks the palette)")
	pb.pressed.connect(func() -> void:
		_result_mode = true
		_make_preview(true))
	pv.add_child(pb)
	pv.add_child(UI.label("PALETTE — click a colour to change it", "SectionTitle"))
	_swatches = HFlowContainer.new()
	_swatches.add_theme_constant_override("h_separation", int(UI.px(4)))
	_swatches.add_theme_constant_override("v_separation", int(UI.px(4)))
	pv.add_child(_swatches)


func _roto_settings() -> Dictionary:
	return {
		"simplify": _r_simplify.value,
		"thickness": _r_thickness.value,
		"sensitivity": _r_sensitivity.value / 100.0,
		"line_color": _r_line_color.color,
		"ink": _r_ink.value / 100.0,
		"ink_color": _r_line_color.color,
		"smooth": _r_smooth.value,
		"trace": _r_trace.button_pressed,
		"line_detail": _r_line_detail.value,
		"line_smooth": _r_line_smooth.value,
		"area_lines": _r_area.button_pressed,
		"palette_lab": _centers,
		"palette_out": _outputs(),
	}


## Picks the clip's palette from sample images (k-means in Lab).
func _extract_palette(images: Array) -> void:
	var samples := PaletteTools.sample_images(images)
	_centers = PaletteTools.kmeans(samples, int(_r_colors.value))
	_custom_outputs.clear()
	_recolor()


func _outputs() -> Array:
	var preset := _r_preset.get_item_text(_r_preset.selected)
	var outs := PaletteTools.preset_outputs(preset, _centers, _r_saturation.value / 100.0)
	for i in outs.size():
		if _custom_outputs.has(i):
			outs[i] = _custom_outputs[i]
	return outs


## Rebuilds the swatch row and refreshes the preview.
func _recolor() -> void:
	for c in _swatches.get_children():
		c.queue_free()
	var outs := _outputs()
	for i in outs.size():
		var b := ColorPickerButton.new()
		b.color = outs[i]
		b.edit_alpha = false
		b.custom_minimum_size = UI.size2(34, 26)
		b.tooltip_text = "Areas that look like this in the video get this colour"
		b.popup_closed.connect(func() -> void:
			_custom_outputs[i] = b.color
			_on_roto_changed(0.0))
		_swatches.add_child(b)
	if _centers.is_empty():
		_swatches.add_child(UI.label("Click “Preview look” to pick colours from the video.", "Small"))
	_on_roto_changed(0.0)


func _on_boost_changed(_v: float) -> void:
	_recolor()


func _on_colors_changed(_v: float) -> void:
	if _preview_source != null:
		_extract_palette([_preview_source])


var _preview_source: Image = null


func _on_roto_changed(_v: float) -> void:
	_sync_overlay()
	if not _ui_ready or _running:
		return
	# Any change to what gets kept or how it looks: show the result right away.
	if _matte_active() or _roto.button_pressed:
		_result_mode = true
		_request_result()
	elif _show_result:
		_request_result()


## Asks for the result preview at the playhead (debounced, one at a time).
func _request_result() -> void:
	if _result_timer != null and _path != "" and _ffmpeg != "":
		_result_timer.start()


func _refresh_result() -> void:
	if _running or _tracking or _playing or _path == "":
		return
	if _preview_busy:
		_preview_pending = true
		return
	if _preview_source == null or absf(_result_time - _time) > 0.01:
		await _make_preview()
	else:
		_want_result = true
		await _apply_preview()


## Decodes one frame at the start point (canvas-sized) and shows it with the
## chosen elements and look. For "Remove still background" it also decodes
## 9 frames across the range to build the background plate.
func _make_preview(repick_palette: bool = false) -> void:
	if _ffmpeg == "" or _path == "" or _running:
		return
	if _preview_busy:
		_preview_pending = true
		return
	_preview_busy = true
	var p: ProjectData = App.project
	var tmp := OS.get_user_data_dir().path_join("roto_preview.png")
	_playing = false
	_update_play_button()
	var at := _time
	var args := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error"])
	if at > 0.0:
		args.append_array(PackedStringArray(["-ss", "%.3f" % at]))
	args.append_array(PackedStringArray(["-i", _path, "-frames:v", "1", "-vf", _scale_filter(p), tmp]))
	_pv_status.text = "Making the preview…"
	var ok := await _run(args, Callable())
	_pv_status.text = ""
	if not ok or not FileAccess.file_exists(tmp):
		_info.text = "Couldn't decode a preview frame from this video."
		_preview_busy = false
		return
	_preview_source = Image.load_from_file(tmp)
	_result_time = at
	_want_result = true
	_plate_sources.clear()
	if _matte_settings()["mode"] == "background":
		await _decode_plate_frames()
	if _roto.button_pressed and (repick_palette or _centers.is_empty()):
		var pal_src := _preview_source
		if _matte_active():
			pal_src = await _matted(_preview_source)
		_centers = PaletteTools.kmeans(PaletteTools.sample_images([pal_src]), int(_r_colors.value))
		_custom_outputs.clear()
		_recolor()
	_preview_busy = false
	_want_result = true
	await _apply_preview()
	_update_info()


## Decodes 9 frames spread over the import range for the background plate.
func _decode_plate_frames() -> void:
	var p: ProjectData = App.project
	var span := _length.value if _length.value > 0.0 else maxf(0.5, _duration - _start.value)
	var dir := OS.get_user_data_dir().path_join("plate_preview")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var args := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error"])
	args.append_array(_range_args())
	args.append_array(PackedStringArray(["-i", _path, "-vf", "fps=%f,%s" % [9.0 / span, _scale_filter(p)], "-frames:v", "9", dir.path_join("p_%02d.png")]))
	_info.text = "Building the clean background…"
	await _run(args, Callable())
	for f in DirAccess.get_files_at(dir):
		var img := Image.load_from_file(dir.path_join(f))
		if img != null and not img.is_empty():
			_plate_sources.append(img)
	if not _plate_sources.is_empty():
		await _matte.build_plate(_plate_sources)


func _matte_active() -> bool:
	return MatteProcessor.is_active(_matte_settings())


func _matted(img: Image) -> Image:
	var p: ProjectData = App.project
	var settings := _matte_settings()
	_matte.setup(p.width, p.height, settings)
	var was_low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var out := await _matte_frame(img.duplicate() as Image, _result_time if _result_time >= 0.0 else _time, settings)
	OS.low_processor_usage_mode = was_low
	return out


## Runs the matte on one canvas-sized frame shot at time `t` (seconds). For
## a tracked subject it first works out that frame's subject mask.
func _matte_frame(img: Image, t: float, settings: Dictionary) -> Image:
	if str(settings["mode"]) == "auto":
		# Re-learn what the background looks like every so often, so it keeps
		# working when the shot changes.
		var key := int(floor(t / AUTO_RELEARN))
		if key != _auto_key or _auto_tracker.lut_image == null:
			_auto_tracker.build_auto_model(img)
			_auto_key = key
		var amask := _auto_tracker.support_mask(img, Rect2(0, 0, 1, 1), float(settings["threshold"]), false, true)
		_matte.set_subject(_auto_tracker.lut_image, amask)
		return await _matte.process(img)
	if str(settings["mode"]) == "subject" or str(settings["mode"]) == "object":
		if _tracker.lut_image == null and _tracker.has_keys():
			_tracker.build_model(_proxy_image_at_time)
		if _tracker.lut_image != null:
			var mask := _tracker.support_mask(img, _tracker.box_at(t), float(settings["threshold"]))
			_matte.set_subject(_tracker.lut_image, mask)
	return await _matte.process(img)


func _apply_preview() -> void:
	if _preview_source == null:
		return
	if _preview_busy:
		_preview_pending = true
		return
	_preview_busy = true
	var p: ProjectData = App.project
	var img := _preview_source.duplicate() as Image
	var kept := -1.0
	if _matte_active():
		img = await _matted(img)
		kept = _kept_fraction(img)
	if _roto.button_pressed:
		_processor.setup(p.width, p.height, _roto_settings())
		var was_low := OS.low_processor_usage_mode
		OS.low_processor_usage_mode = false  # make sure the next frame is drawn
		img = await _processor.process(img)
		OS.low_processor_usage_mode = was_low
	# Show transparency on a checkerboard.
	var shown := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	shown.fill(Color("#e6e6ea"))
	var cell := maxi(8, img.get_height() / 24)
	for y in range(0, img.get_height(), cell):
		for x in range(0, img.get_width(), cell):
			if ((x / cell) + (y / cell)) % 2 == 0:
				shown.fill_rect(Rect2i(x, y, cell, cell), Color("#c9c9d0"))
	shown.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	_result_tex.set_image(shown)
	if _want_result:
		_want_result = false
		_set_show_result(true)
	elif _show_result:
		_pv_frame.texture = _result_tex
	_pv_status.text = _kept_message(kept)
	_preview_busy = false
	if _preview_pending:
		_preview_pending = false
		_request_result()


## Share of the frame (by area) that survives the matte.
static func _kept_fraction(img: Image) -> float:
	var small := img.duplicate() as Image
	if small.get_format() != Image.FORMAT_RGBA8:
		small.convert(Image.FORMAT_RGBA8)
	small.resize(96, maxi(8, int(96.0 * img.get_height() / float(img.get_width()))), Image.INTERPOLATE_BILINEAR)
	var data := small.get_data()
	var n := data.size() / 4
	var kept := 0
	for i in n:
		if data[i * 4 + 3] > 127:
			kept += 1
	return float(kept) / maxf(1.0, n)


func _kept_message(kept: float) -> String:
	if kept < 0.0:
		return ""
	if kept < 0.005:
		return "Nothing is kept on this frame — lower Sensitivity, or check the subject box / mode."
	if kept > 0.985:
		return "Everything is kept on this frame — raise Sensitivity, or try another Keep option."
	return "Keeping %d%% of this frame" % int(round(kept * 100.0))


# ================================================================ elements

func _build_elements(parent: Control) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(UI.label("ELEMENTS — choose what to keep from the video", "SectionTitle"))
	var row := UI.hbox(8)
	parent.add_child(row)
	row.add_child(UI.label("Keep", "FieldLabel"))
	var keep_labels: Array = []
	for k in KEEP:
		keep_labels.append(str(k[0]))
	_e_mode = UI.option(keep_labels)
	_e_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_e_mode.item_selected.connect(func(_i: int) -> void:
		_auto_key = -999
		_update_elements_ui()
		if _matte_settings()["mode"] == "background" and _preview_source != null:
			_plate_sources.clear()
			await _decode_plate_frames()
		_on_roto_changed(0.0))
	row.add_child(_e_mode)
	_build_subject_ui(parent)
	_e_box = UI.vbox(4)
	parent.add_child(_e_box)
	_e_hint = UI.label("", "Small")
	_e_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_e_box.add_child(_e_hint)
	_e_key_row = UI.hbox(8)
	_e_box.add_child(_e_key_row)
	_e_key_row.add_child(UI.label("Colour to remove", "FieldLabel"))
	_e_key = ColorPickerButton.new()
	_e_key.color = Color(0.1, 0.75, 0.2)
	_e_key.edit_alpha = false
	_e_key.custom_minimum_size = UI.size2(56, 28)
	_e_key.popup_closed.connect(_on_roto_changed.bind(0.0))
	_e_key_row.add_child(_e_key)
	_e_key_row.add_child(UI.label("…or click the preview to pick it", "Small"))
	_e_threshold = UI.slider(_e_box, "Sensitivity", 1, 60, 1, 12, _on_roto_changed, "%d")
	_e_softness = UI.slider(_e_box, "Edge softness", 0, 30, 1, 6, _on_roto_changed, "%d")
	_e_spill = UI.slider(_e_box, "Remove colour spill on edges", 0, 100, 5, 60, _on_roto_changed, "%d%%")
	_e_cleanup = UI.slider(_e_box, "Clean up (fill holes, remove specks)", 0, 10, 0.5, 2.5, _on_roto_changed, "%.1f")
	_e_grow = UI.slider(_e_box, "Shrink / grow edge", -10, 10, 1, 0, _on_roto_changed, "%d")
	_e_edge = UI.slider(_e_box, "Edge detail (follow hair and outlines)", 0, 100, 1, 70, _on_roto_changed, "%d%%")
	_e_invert = CheckBox.new()
	_e_invert.text = "Keep the removed part instead (e.g. only the background)"
	_e_invert.focus_mode = Control.FOCUS_NONE
	_e_invert.toggled.connect(func(_on: bool) -> void: _on_roto_changed(0.0))
	_e_box.add_child(_e_invert)
	_e_crop = CheckBox.new()
	_e_crop.text = "Keep only an area of the frame"
	_e_crop.focus_mode = Control.FOCUS_NONE
	_e_crop.toggled.connect(func(_on: bool) -> void:
		_update_elements_ui()
		_on_roto_changed(0.0))
	parent.add_child(_e_crop)
	_e_crop_box = UI.vbox(4)
	parent.add_child(_e_crop_box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(UI.px(14)))
	_e_crop_box.add_child(grid)
	var c1 := UI.vbox(2)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(c1)
	var c2 := UI.vbox(2)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(c2)
	_e_left = UI.slider(c1, "Left edge", 0, 100, 1, 0, _on_roto_changed, "%d%%")
	_e_right = UI.slider(c2, "Right edge", 0, 100, 1, 100, _on_roto_changed, "%d%%")
	_e_top = UI.slider(c1, "Top edge", 0, 100, 1, 0, _on_roto_changed, "%d%%")
	_e_bottom = UI.slider(c2, "Bottom edge", 0, 100, 1, 100, _on_roto_changed, "%d%%")
	_e_feather = UI.slider(_e_crop_box, "Soft edge", 0, 20, 1, 2, _on_roto_changed, "%d%%")
	_preview_pick_ready.call_deferred()
	_update_elements_ui()


func _build_subject_ui(parent: Control) -> void:
	_subject_box_ui = UI.vbox(6)
	_subject_box_ui.visible = false
	parent.add_child(_subject_box_ui)
	var steps := UI.label("1  Pause on a frame where the subject (or the object to remove) is clear and drag a box around it on the preview.\n2  Optional: paint + on parts of the subject and − on background it should never keep.\n3  Press Track subject, then scrub to check. If the box slips, drag a new box on that frame and track again.", "Small")
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subject_box_ui.add_child(steps)
	var row := UI.hbox(6)
	_subject_box_ui.add_child(row)
	var group := ButtonGroup.new()
	for t in [["box", "Box", "Drag a box around the subject on this frame"], ["fg", "+ Subject", "Paint over parts that belong to the subject"], ["bg", "− Background", "Paint over background that should be removed"]]:
		var b := UI.button(str(t[1]), "", str(t[2]), "FlatButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[0] == "box"
		b.pressed.connect(_set_subject_tool.bind(str(t[0])))
		row.add_child(b)
		_subject_tool_btns[str(t[0])] = b
	var row2 := UI.hbox(6)
	_subject_box_ui.add_child(row2)
	var track_btn := UI.button("Track subject", "play", "Follow the subject through the chosen range", "AccentButton")
	track_btn.pressed.connect(_on_track_pressed)
	row2.add_child(track_btn)
	var clear_marks := UI.button("Clear marks", "", "Remove the + / − paint", "FlatButton")
	clear_marks.pressed.connect(func() -> void:
		_tracker.marks.clear()
		_tracker.tracked = false
		_tracker.lut_image = null
		_sync_subject())
	row2.add_child(clear_marks)
	var reset := UI.button("Start over", "reset", "Remove all boxes, marks and tracking", "FlatButton")
	reset.pressed.connect(func() -> void:
		_tracker.clear()
		_sync_subject())
	row2.add_child(reset)
	_subject_status = UI.label("", "Small")
	_subject_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subject_box_ui.add_child(_subject_status)


func _set_subject_tool(tool: String) -> void:
	_subject_tool = tool


func _subject_mode() -> bool:
	return _e_mode != null and _e_feather != null and (_matte_settings()["mode"] == "subject" or _matte_settings()["mode"] == "object")


## Updates the subject overlay, the key markers and the status line.
func _sync_subject() -> void:
	if _pv_overlay == null or _subject_status == null:
		return
	var on := _subject_mode()
	_pv_overlay.show_subject = on and _tracker.has_keys()
	var key_here := false
	for k in _tracker.keys:
		var d: Dictionary = k
		if absf(float(d["t"]) - _time) < 0.05:
			key_here = true
	_pv_overlay.subject_is_key = key_here
	if _pv_overlay.show_subject:
		_pv_overlay.subject_box = _tracker.box_at(_time)
	var shown: Array = []
	if on:
		for m in _tracker.marks:
			var d: Dictionary = m
			if absf(float(d["t"]) - _time) < 0.25:
				shown.append(d)
	_pv_overlay.marks = shown
	_pv_overlay.queue_redraw()
	if _pv_bar != null:
		var kts: Array = []
		if on:
			for k in _tracker.keys:
				var d: Dictionary = k
				kts.append(float(d["t"]))
		_pv_bar.key_times = kts
		_pv_bar.tracked_range = Vector2(-1, -1)
		if on and _tracker.tracked and not _tracker.track.is_empty():
			var ks := _tracker.track.keys()
			ks.sort()
			_pv_bar.tracked_range = Vector2(float(ks[0]) / _tracker.track_fps, float(ks[ks.size() - 1]) / _tracker.track_fps)
		_pv_bar.queue_redraw()
	if not on or _tracking:
		return
	if not _tracker.has_keys():
		_subject_status.text = "No subject yet: drag a box around it on the preview."
	elif not _tracker.tracked:
		_subject_status.text = "%d box(es), %d mark(s). Press Track subject." % [_tracker.keys.size(), _tracker.marks.size()]
	else:
		_subject_status.text = "Tracked ✓  Scrub to check the green box. Press Result to see the cut-out on any frame."


func _proxy_image_at_index(i: int) -> Image:
	if _proxy_dir == "" or i < 0 or i >= _proxy_count:
		return null
	var img := Image.load_from_file(_proxy_dir.path_join("f_%05d.jpg" % (i + 1)))
	if img == null or img.is_empty():
		return null
	return img


func _proxy_image_at_time(t: float) -> Image:
	return _proxy_image_at_index(clampi(int(round(t * _proxy_fps)), 0, maxi(0, _proxy_count - 1)))


func _on_track_pressed() -> void:
	if _tracking:
		_cancel = true
		return
	await _track_subject()


## Learns the subject's colours and follows it over the import range.
func _track_subject() -> bool:
	if not _tracker.has_keys():
		_subject_status.text = "Drag a box around the subject first."
		return false
	_tracking = true
	_cancel = false
	_playing = false
	_update_play_button()
	while not _proxy_done and _proxy_pid > 0:
		_subject_status.text = "Waiting for the preview to finish loading…"
		await get_tree().create_timer(0.3).timeout
	if _proxy_count == 0:
		_subject_status.text = "The preview couldn't be decoded, so the subject can't be tracked."
		_tracking = false
		return false
	_subject_status.text = "Learning what the subject looks like…"
	await get_tree().process_frame
	_tracker.build_model(_proxy_image_at_time)
	var r := _range()
	var t0 := r.x
	var t1 := r.y
	for k in _tracker.keys:
		var d: Dictionary = k
		t0 = minf(t0, float(d["t"]))
		t1 = maxf(t1, float(d["t"]))
	var i0 := clampi(int(floor(t0 * _proxy_fps)), 0, _proxy_count - 1)
	var i1 := clampi(int(ceil(t1 * _proxy_fps)), 0, _proxy_count - 1)
	var ok: bool = await _tracker.run_tracking(i0, i1, _proxy_fps, _proxy_image_at_index, _on_track_progress, _should_stop, get_tree())
	_tracking = false
	if not ok:
		_subject_status.text = "Tracking stopped."
		_cancel = false
		return false
	_cancel = false
	_sync_subject()
	_result_mode = true
	_request_result()
	return true


func _on_track_progress(done: int, total: int) -> void:
	_subject_status.text = "Tracking… %d%%  (press Track subject again to stop)" % int(100.0 * done / maxf(1.0, total))


func _should_stop() -> bool:
	return _cancel


func _preview_pick_ready() -> void:
	if _preview != null and not _preview.gui_input.is_connected(_on_preview_input):
		_preview.gui_input.connect(_on_preview_input)
		_preview.mouse_filter = Control.MOUSE_FILTER_STOP


func _update_elements_ui() -> void:
	var mode := str(_matte_settings()["mode"])
	_e_box.visible = mode != "everything"
	_e_key_row.visible = mode == "colour"
	(_e_spill.get_parent() as Control).visible = mode == "colour"
	_e_crop_box.visible = _e_crop.button_pressed
	_subject_box_ui.visible = mode == "subject" or mode == "object"
	(_e_edge.get_parent() as Control).visible = mode == "subject" or mode == "object" or mode == "auto"
	match mode:
		"auto":
			_e_hint.text = "No picking needed: colours along the edges of the frame are treated as background and the main subject in the middle is kept. Works best when the subject stands out from the background. Raise Sensitivity to keep more, lower it to remove more."
		"object":
			_e_hint.text = "Drag a box around the thing to remove (and paint + on it, − on what must stay), then Track. The object is cut out of every frame, leaving it transparent."
		"subject":
			_e_hint.text = "Sensitivity sets how much a colour must look like the subject to be kept. Raise Clean up if the edge is noisy."
		"background":
			_e_hint.text = "Keeps whatever moves. Strata builds a clean background from frames across the clip and removes anything that matches it. Works best with a still camera."
		"colour":
			_e_hint.text = "Removes one colour, like a green or blue screen. Click the preview to pick the colour."
		"light":
			_e_hint.text = "Removes bright areas — great for drawings on white paper or bright skies. Sensitivity sets how bright counts as background."
		"dark":
			_e_hint.text = "Removes dark areas, like a black background. Sensitivity sets how dark counts as background."
		_:
			_e_hint.text = ""
	_sync_overlay()
	_sync_subject()
	reset_size()


func _matte_settings() -> Dictionary:
	var mode: String = str(KEEP[clampi(_e_mode.selected, 0, KEEP.size() - 1)][1])
	var th := _e_threshold.value / 100.0
	if mode == "light":
		th = 1.0 - th * 1.2  # brightness above this is removed
	elif mode == "dark":
		th = th * 1.2  # brightness below this is removed
	if mode == "subject" or mode == "object" or mode == "auto":
		th = clampf(0.26 + _e_threshold.value * 0.02, 0.2, 0.9)
	var l := _e_left.value / 100.0
	var t := _e_top.value / 100.0
	return {
		"edge_detail": (_e_edge.value / 100.0) if _e_edge != null else 0.7,
		"mode": mode,
		"threshold": th,
		"softness": maxf(0.005, _e_softness.value / 100.0),
		"key_color": _e_key.color,
		"spill": _e_spill.value / 100.0,
		"invert": _e_invert.button_pressed,
		"cleanup": _e_cleanup.value,
		"grow": _e_grow.value / 10.0,
		"crop": _e_crop.button_pressed,
		"box": Rect2(l, t, maxf(0.01, _e_right.value / 100.0 - l), maxf(0.01, _e_bottom.value / 100.0 - t)),
		"feather": _e_feather.value / 100.0,
	}


## On the preview: drag a box to keep only that area of the frame; a plain
## click in colour-key mode picks the colour to remove.
func _on_preview_input(event: InputEvent) -> void:
	if _subject_mode():
		_on_subject_input(event)
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_down = true
			_box_drag = false
			_press_pos = mb.position
		elif _press_down:
			_press_down = false
			if _box_drag:
				_box_drag = false
				_on_roto_changed(0.0)
			else:
				_pick_key_colour(mb.position)
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _press_down:
		if not _box_drag and mm.position.distance_to(_press_pos) > UI.px(5):
			_box_drag = true
			_e_crop.set_pressed_no_signal(true)
			_update_elements_ui()
		if _box_drag:
			var ir := _pv_overlay.image_rect()
			var a := ((_press_pos - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
			var b := ((mm.position - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
			var r := Rect2(a, Vector2.ZERO).expand(b)
			_e_left.set_value_no_signal(roundf(r.position.x * 100.0))
			_e_top.set_value_no_signal(roundf(r.position.y * 100.0))
			_e_right.set_value_no_signal(roundf(r.end.x * 100.0))
			_e_bottom.set_value_no_signal(roundf(r.end.y * 100.0))
			_sync_overlay()


## Subject mode: drag a box (key) or paint + / − marks at the playhead.
func _on_subject_input(event: InputEvent) -> void:
	var ir := _pv_overlay.image_rect()
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if _playing:
				_playing = false
				_update_play_button()
			_press_down = true
			_box_drag = false
			_press_pos = mb.position
			_last_mark_pos = Vector2(-999, -999)
			if _subject_tool != "box":
				_add_subject_mark(mb.position, ir)
		elif _press_down:
			_press_down = false
			if _subject_tool == "box" and _box_drag:
				var a := ((_press_pos - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
				var b := ((mb.position - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
				var r := Rect2(a, Vector2.ZERO).expand(b)
				if r.size.x > 0.01 and r.size.y > 0.01:
					_tracker.set_key(_time, r)
					_tracker.lut_image = null
					_result_mode = true
					_request_result()
			_box_drag = false
			_pv_overlay.show_box = bool(_matte_settings()["crop"])
			_sync_overlay()
			_sync_subject()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _press_down:
		if _subject_tool == "box":
			if mm.position.distance_to(_press_pos) > UI.px(4):
				_box_drag = true
			if _box_drag:
				var a := ((_press_pos - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
				var b := ((mm.position - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
				_pv_overlay.show_subject = true
				_pv_overlay.subject_is_key = true
				_pv_overlay.subject_box = Rect2(a, Vector2.ZERO).expand(b)
				_pv_overlay.queue_redraw()
		else:
			_add_subject_mark(mm.position, ir)


func _add_subject_mark(pos: Vector2, ir: Rect2) -> void:
	if pos.distance_to(_last_mark_pos) < UI.px(6):
		return
	_last_mark_pos = pos
	var uv := (pos - ir.position) / ir.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return
	_tracker.add_mark(_time, uv, 0.012, _subject_tool == "fg")
	_tracker.lut_image = null
	_sync_subject()


func _pick_key_colour(pos: Vector2) -> void:
	if _matte_settings()["mode"] != "colour":
		return
	var src: Image = _preview_source if _show_result and _preview_source != null else null
	if src == null and _pv_tex.get_image() != null:
		src = _pv_tex.get_image()
	if src == null or src.is_empty():
		return
	var ir := _pv_overlay.image_rect()
	var uv := (pos - ir.position) / ir.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return
	var c := src.get_pixelv(Vector2i(uv * Vector2(src.get_size())))
	c.a = 1.0
	_e_key.color = c
	App.status("Removing colour #" + c.to_html(false))
	_on_roto_changed(0.0)


# ================================================================ video preview

func _build_video_preview(parent: Control) -> void:
	var frame := PanelContainer.new()
	frame.theme_type_variation = "CanvasFrame"
	parent.add_child(frame)
	_pv_frame = TextureRect.new()
	_pv_frame.custom_minimum_size = UI.size2(640, 340)
	_pv_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_pv_frame.tooltip_text = "Drag a box to import only that part of the frame"
	_pv_frame.gui_input.connect(_on_preview_input)
	frame.add_child(_pv_frame)
	_preview = _pv_frame
	_pv_overlay = PreviewOverlay.new()
	_pv_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(_pv_overlay)
	_pv_frame.add_child(_pv_overlay)
	_pv_status = UI.label("", "Small")
	_pv_status.position = UI.size2(8, 6)
	_pv_frame.add_child(_pv_status)
	_pv_tex = ImageTexture.new()
	_result_tex = ImageTexture.new()
	_preview_tex = _result_tex

	var controls := UI.hbox(6)
	parent.add_child(controls)
	_pv_play = UI.icon_button("play", "Play the selected range (Space)")
	_pv_play.pressed.connect(_toggle_play)
	controls.add_child(_pv_play)
	_pv_time = UI.label("", "ValueLabel")
	_pv_time.custom_minimum_size.x = UI.px(110)
	controls.add_child(_pv_time)
	var set_in := UI.button("Set in", "", "Start the import at the playhead", "FlatButton")
	set_in.pressed.connect(_set_in)
	controls.add_child(set_in)
	var set_out := UI.button("Set out", "", "End the import at the playhead", "FlatButton")
	set_out.pressed.connect(_set_out)
	controls.add_child(set_out)
	var whole := UI.button("Whole video", "", "Import from the start to the end", "FlatButton")
	whole.pressed.connect(func() -> void:
		_start.value = 0.0
		_length.value = 0.0)
	controls.add_child(whole)
	controls.add_child(UI.spacer())
	var group := ButtonGroup.new()
	_pv_original = UI.button("Original", "", "Show the video as it is", "FlatButton")
	_pv_original.toggle_mode = true
	_pv_original.button_group = group
	_pv_original.button_pressed = true
	_pv_original.pressed.connect(func() -> void:
		_result_mode = false
		_set_show_result(false))
	controls.add_child(_pv_original)
	_pv_result = UI.button("Result", "eye", "Show the frame under the playhead with the chosen elements and look", "FlatButton")
	_pv_result.toggle_mode = true
	_pv_result.button_group = group
	_pv_result.pressed.connect(func() -> void:
		_result_mode = true
		_pv_result.set_pressed_no_signal(false)  # stays on Original until the result is ready
		_pv_original.set_pressed_no_signal(true)
		_refresh_result())
	controls.add_child(_pv_result)
	var clear_box := UI.icon_button("reset", "Use the whole frame again")
	clear_box.pressed.connect(func() -> void:
		_e_crop.button_pressed = false)
	controls.add_child(clear_box)

	_pv_bar = RangeBar.new()
	_pv_bar.custom_minimum_size.y = UI.px(30)
	_pv_bar.tooltip_text = "Drag the IN / OUT handles to choose exactly which part gets imported; click or drag elsewhere to scrub"
	_pv_bar.scrubbed.connect(_seek)
	_pv_bar.range_moved.connect(_on_range_moved)
	_pv_bar.range_released.connect(func() -> void:
		if _matte_settings()["mode"] == "background" and _preview_source != null:
			_plate_sources.clear())
	parent.add_child(_pv_bar)
	var tip := UI.label("Choose the part to import: drag IN / OUT on the bar (or use Set in / Set out at the playhead), and drag a box on the picture to keep only that area. Only that part is cut out and rotoscoped.", "Small")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(tip)
	_update_play_button()


func _duration_known() -> float:
	if _duration > 0.0:
		return _duration
	return float(_proxy_count) / _proxy_fps if _proxy_fps > 0.0 else 0.0


func _range() -> Vector2:
	var d := _duration_known()
	var a := _start.value
	var b := a + _length.value if _length.value > 0.0 else d
	return Vector2(a, maxf(a, b))


func _sync_bar() -> void:
	if _pv_bar == null:
		return
	var r := _range()
	_pv_bar.duration = _duration_known()
	_pv_bar.loaded = float(_proxy_count) / _proxy_fps if _proxy_fps > 0.0 else 0.0
	if _proxy_done:
		_pv_bar.loaded = _pv_bar.duration
	_pv_bar.t_in = r.x
	_pv_bar.t_out = r.y
	_pv_bar.playhead = _time
	_pv_bar.queue_redraw()
	_pv_time.text = "%s  ·  %s → %s" % [_fmt_time(_time), _fmt_time(r.x), _fmt_time(r.y)]
	_sync_overlay()
	_sync_subject()


func _sync_overlay() -> void:
	if _pv_overlay == null or _e_feather == null or _e_mode == null or not App.has_project():
		return
	var m := _matte_settings()
	_pv_overlay.aspect = float(App.project.width) / float(App.project.height)
	_pv_overlay.show_box = bool(m["crop"])
	_pv_overlay.box = m["box"]
	_pv_overlay.queue_redraw()


static func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	return "%d:%04.1f" % [m, t - m * 60]


func _on_range_moved(t_in: float, t_out: float) -> void:
	var d := _duration_known()
	_start.set_value_no_signal(snappedf(t_in, 0.1))
	if d > 0.0 and t_out >= d - 0.05:
		_length.set_value_no_signal(0.0)
	else:
		_length.set_value_no_signal(snappedf(t_out - t_in, 0.1))
	_update_info()
	_sync_bar()


func _set_in() -> void:
	var r := _range()
	_start.value = snappedf(minf(_time, r.y - 0.1), 0.1)
	if _length.value > 0.0:
		_length.value = snappedf(maxf(0.1, r.y - _start.value), 0.1)


func _set_out() -> void:
	var a := _start.value
	if _time <= a:
		App.status("The end has to be after the start")
		return
	var d := _duration_known()
	_length.value = 0.0 if d > 0.0 and _time >= d - 0.05 else snappedf(_time - a, 0.1)


func _seek(t: float) -> void:
	_time = clampf(t, 0.0, maxf(0.0, _duration_known()))
	if _show_result and absf(_result_time - _time) > 0.01:
		_set_show_result(false)
	_show_proxy_frame()
	_sync_bar()
	if _result_mode:
		_request_result()  # refreshes once you stop scrubbing


func _toggle_play() -> void:
	if _proxy_count == 0:
		return
	_playing = not _playing
	if _playing:
		var r := _range()
		if _time < r.x or _time >= r.y - 0.05:
			_time = r.x
		if _show_result:
			_set_show_result(false)
	elif _result_mode:
		_request_result()
	_update_play_button()


func _update_play_button() -> void:
	if _pv_play != null:
		_pv_play.icon = Icons.tex("pause" if _playing else "play")


func _set_show_result(on: bool) -> void:
	_show_result = on
	if _pv_result != null:
		_pv_result.set_pressed_no_signal(on)
		_pv_original.set_pressed_no_signal(not on)
	if on and _result_tex.get_image() != null:
		_pv_frame.texture = _result_tex
	else:
		_show_result = false
		_shown_index = -1
		_show_proxy_frame()


func _process(delta: float) -> void:
	if not _playing or not visible:
		return
	var r := _range()
	_time += delta
	if _time >= r.y:
		_time = r.x
	_show_proxy_frame()
	_sync_bar()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_SPACE and visible:
		_toggle_play()
		set_input_as_handled()


func _show_proxy_frame() -> void:
	if _show_result or _proxy_count == 0:
		return
	var idx := clampi(int(_time * _proxy_fps), 0, _proxy_count - 1)
	if idx == _shown_index:
		return
	var img := Image.load_from_file(_proxy_dir.path_join("f_%05d.jpg" % (idx + 1)))
	if img == null or img.is_empty():
		return
	_shown_index = idx
	if _pv_tex.get_image() != null and _pv_tex.get_size() == Vector2(img.get_size()):
		_pv_tex.update(img)
	else:
		_pv_tex.set_image(img)
	_pv_frame.texture = _pv_tex


## Decodes small preview frames of the whole video in the background, so it
## can be played and scrubbed right away while the rest arrives.
func _start_proxy() -> void:
	_stop_proxy()
	_proxy_gen += 1
	var gen := _proxy_gen
	_proxy_count = 0
	_proxy_done = false
	_shown_index = -1
	_time = 0.0
	_preview_source = null
	_result_time = -1.0
	_set_show_result(false)
	_pv_frame.texture = null
	if _ffmpeg == "" or _path == "" or not App.has_project():
		_sync_bar()
		return
	_proxy_dir = OS.get_user_data_dir().path_join("video_proxy")
	DirAccess.make_dir_recursive_absolute(_proxy_dir)
	for f in DirAccess.get_files_at(_proxy_dir):
		DirAccess.remove_absolute(_proxy_dir.path_join(f))
	var p: ProjectData = App.project
	var w := PROXY_WIDTH
	var h := int(round(float(PROXY_WIDTH) * p.height / float(p.width) / 2.0)) * 2
	_proxy_fps = 12.0
	if _duration > 0.0:
		_proxy_fps = clampf(float(PROXY_MAX_FRAMES) / _duration, 1.0, 12.0)
	var vf := "fps=%f,scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=black" % [_proxy_fps, w, h, w, h]
	var args := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error", "-i", _path, "-vf", vf, "-q:v", "5", "-an", _proxy_dir.path_join("f_%05d.jpg")])
	_proxy_pid = OS.create_process(_ffmpeg, args)
	if _proxy_pid <= 0:
		_pv_status.text = "Couldn't start FFmpeg for the preview"
		return
	_pv_status.text = "Loading preview…"
	while _proxy_gen == gen and _proxy_pid > 0 and OS.is_process_running(_proxy_pid):
		await get_tree().create_timer(0.3).timeout
		if _proxy_gen != gen:
			return
		# The newest file may still be being written; count all but the last.
		_proxy_count = maxi(0, DirAccess.get_files_at(_proxy_dir).size() - 1)
		if _proxy_count > 0 and _shown_index < 0:
			_pv_status.text = ""
			_show_proxy_frame()
		_sync_bar()
	if _proxy_gen != gen:
		return
	_proxy_pid = -1
	_proxy_count = DirAccess.get_files_at(_proxy_dir).size()
	_proxy_done = true
	_pv_status.text = "" if _proxy_count > 0 else "Couldn't decode a preview of this video"
	_show_proxy_frame()
	_sync_bar()


func _stop_proxy() -> void:
	_proxy_gen += 1
	if _proxy_pid > 0 and OS.is_process_running(_proxy_pid):
		OS.kill(_proxy_pid)
	_proxy_pid = -1


func _scale_filter(p: ProjectData) -> String:
	return "scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=black@0,format=rgba" % [p.width, p.height, p.width, p.height]


## No FFmpeg (e.g. on iPad): put a picked series of image frames on a new
## layer, one per frame (or per step), starting at frame 1.
func _import_frame_files(paths: PackedStringArray) -> void:
	if not App.has_project():
		return
	var list := Array(paths)
	list.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var p: ProjectData = App.project
	var images: Array = []
	for item in list:
		var src := Image.load_from_file(str(item))
		if src != null and not src.is_empty():
			images.append(CaptureWorkspace._fill_canvas(src, p.width, p.height))
	if images.is_empty():
		App.status("Couldn't read those images")
		return
	var layer := Ops.add_layer("Frames", "drawing")
	if layer == null:
		return
	Ops.add_photos(layer, 0, images, _step.selected + 1, "Import %d frames" % images.size())
	App.status("Imported %d frames onto a new layer" % images.size())
	hide()


## Opens the dialog, optionally with a file already chosen (drag & drop).
func open(path: String = "") -> void:
	if not App.has_project():
		App.status("Create or open a project first")
		return
	_ffmpeg = RenderExporter.find_ffmpeg()
	_locate_btn.visible = _ffmpeg == "" and Platform.can_run_programs()
	_frames_btn.visible = _ffmpeg == ""
	_progress.visible = false
	if path != "":
		set_file(path)
	else:
		_path = ""
		_file_label.text = "No file chosen"
		_update_info()
		_start_proxy()
	popup_centered()
	if path == "" and _ffmpeg != "":
		_file_dialog.popup_centered_ratio(0.6)


func set_file(path: String) -> void:
	_path = path
	_file_label.text = path.get_file()
	_file_label.tooltip_text = path
	_start.value = 0.0
	_length.value = 0.0
	_centers.clear()
	_probe()
	_update_info()
	_start_proxy()


func _on_locate(path: String) -> void:
	if FFmpeg.set_custom(path):
		_ffmpeg = FFmpeg.find()
		_locate_btn.visible = false
		App.status("FFmpeg found: " + _ffmpeg)
		if _path != "":
			_probe()
			_start_proxy()
	else:
		App.status("That doesn't look like a working ffmpeg: " + path)
	_update_info()


## Reads duration, frame rate and size from FFmpeg's description of the file.
func _probe() -> void:
	_duration = 0.0
	_src_fps = 0.0
	_src_size = Vector2i.ZERO
	if _ffmpeg == "" or _path == "":
		return
	var out := []
	OS.execute(_ffmpeg, PackedStringArray(["-hide_banner", "-i", _path]), out, true)
	var text := "\n".join(PackedStringArray(out))
	var re := RegEx.new()
	re.compile("Duration: (\\d+):(\\d+):(\\d+(?:\\.\\d+)?)")
	var m := re.search(text)
	if m != null:
		_duration = int(m.get_string(1)) * 3600 + int(m.get_string(2)) * 60 + float(m.get_string(3))
	re.compile("(\\d+(?:\\.\\d+)?) fps")
	m = re.search(text)
	if m != null:
		_src_fps = float(m.get_string(1))
	re.compile("Video:.*?, (\\d{2,5})x(\\d{2,5})")
	m = re.search(text)
	if m != null:
		_src_size = Vector2i(int(m.get_string(1)), int(m.get_string(2)))


func _frames_estimate() -> int:
	var fps: int = App.project.fps
	var span := _length.value
	if span <= 0.0:
		span = maxf(0.0, _duration - _start.value)
	return int(ceilf(span * fps / float(_step.selected + 1)))


func _update_info() -> void:
	if _ffmpeg == "" and not Platform.can_run_programs():
		_info.text = Platform.no_ffmpeg_text()
		_info.modulate = Color("#ffd166")
		get_ok_button().disabled = true
		return
	if _ffmpeg == "":
		var looked := ""
		if not FFmpeg.report.is_empty():
			looked = "\n" + "\n".join(FFmpeg.report)
		_info.text = "FFmpeg is needed to read video files, but Strata couldn't find a working copy.\n" + FFmpeg.help_text() + looked
		_info.modulate = Palette.DANGER
		get_ok_button().disabled = true
		return
	_info.modulate = Color.WHITE
	if _path == "":
		_info.text = "Supported: " + ", ".join(PackedStringArray(VIDEO_EXTENSIONS)).to_upper()
		get_ok_button().disabled = true
		return
	get_ok_button().disabled = _running
	var n := _frames_estimate()
	var p: ProjectData = App.project
	var mb := n * p.width * p.height * 4 * 0.2 / 1048576.0  # PNG ≈ 20% of raw RGBA
	var lines := []
	if _duration > 0.0:
		lines.append("Video: %.1f s%s%s" % [_duration, " · %.2f fps" % _src_fps if _src_fps > 0.0 else "", " · %d×%d" % [_src_size.x, _src_size.y] if _src_size.x > 0 else ""])
	lines.append("Creates %d drawings at %d×%d, %d fps timing, starting at frame %d (≈ %.0f MB on disk). The video is scaled to fit the canvas." % [n, p.width, p.height, p.fps, App.frame + 1, mb])
	if n > 1500:
		lines.append("That's a lot of frames — consider a shorter range or importing on 2s.")
	_info.text = "\n".join(PackedStringArray(lines))


# ================================================================ import

func _on_import() -> void:
	if _running or _path == "" or _ffmpeg == "":
		return
	if _subject_mode():
		if not _tracker.has_keys():
			_subject_status.text = "Drag a box around the subject on the preview first."
			App.status("Pick the subject first: drag a box around it on the preview")
			return
		if not _tracker.tracked:
			if _tracking:
				return
			var tracked_ok: bool = await _track_subject()
			if not tracked_ok:
				return
	var s := App.current_scene()
	var p: ProjectData = App.project
	var step := _step.selected + 1
	var at: int = App.frame
	var layer := LayerData.new(_path.get_file().get_basename(), "reference" if _reference.button_pressed else "drawing")
	layer.locked = _reference.button_pressed
	var dir := p.root_dir.path_join("scenes").path_join(s.id).path_join(layer.id)
	DirAccess.make_dir_recursive_absolute(dir)
	var prefix := "v" + Ids.make()
	var out_fps := p.fps / float(step)
	var vf := "fps=%f,%s" % [out_fps, _scale_filter(p)]
	var args := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error"])
	args.append_array(_range_args())
	args.append_array(PackedStringArray(["-i", _path, "-vf", vf, "-an", dir.path_join(prefix + "_%05d.png")]))

	_running = true
	_cancel = false
	get_ok_button().disabled = true
	_progress.visible = true
	_progress.value = 0
	var expected := maxi(1, _frames_estimate())
	_progress.max_value = expected
	_info.text = "Decoding video frames…"
	var ok := await _run(args, func() -> void:
		var count := 0
		for f in DirAccess.get_files_at(dir):
			if f.begins_with(prefix):
				count += 1
		_progress.value = count
		_info.text = "Decoding video frames… %d / ~%d" % [count, expected])
	var files := []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(prefix) and f.ends_with(".png"):
			files.append(f)
	files.sort()
	if _cancel or not ok or files.is_empty():
		for f in files:
			DirAccess.remove_absolute(dir.path_join(str(f)))
		_finish("Video import cancelled" if _cancel else "FFmpeg could not decode this video")
		return
	if _matte_active() and _matte_settings()["mode"] == "background":
		_info.text = "Building the clean background…"
		var plate_imgs := []
		for n in 9:
			var fi := int(float(n) / 9.0 * files.size())
			var im := Image.load_from_file(dir.path_join(str(files[mini(fi, files.size() - 1)])))
			if im != null and not im.is_empty():
				plate_imgs.append(im)
		await _matte.build_plate(plate_imgs)
	if _matte_active() or _roto.button_pressed:
		var proc_ok := await _process_frames(dir, files)
		if not proc_ok:
			for f in files:
				DirAccess.remove_absolute(dir.path_join(str(f)))
			_finish("Video import cancelled")
			return
	for i in files.size():
		var fname: String = files[i]
		var cel := CelData.new(fname.get_basename())
		cel.file_path = dir.path_join(fname)
		cel.dirty = false
		layer.cels[at + i * step] = cel

	var clip: AudioClipData = null
	if _audio.button_pressed:
		_info.text = "Extracting sound…"
		var rel := "audio".path_join(Ids.make() + ".wav")
		var dest := p.root_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var aargs := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error"])
		aargs.append_array(_range_args())
		aargs.append_array(PackedStringArray(["-i", _path, "-vn", "-ac", "2", "-ar", "44100", "-c:a", "pcm_s16le", dest]))
		var aok := await _run(aargs, Callable())
		if aok and FileAccess.file_exists(dest) and Audio.length_of(rel) > 0.0:
			clip = AudioClipData.new()
			clip.name = layer.name
			clip.file = rel
			clip.start_frame = at
			clip.length = Audio.length_of(rel)
		elif FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
	var end_frame := at + files.size() * step
	Ops.add_video_layer(layer, clip, end_frame)
	_finish("Imported %d %svideo frames as “%s”%s" % [files.size(), ("rotoscoped " if _roto.button_pressed else "") + ("cut-out " if _matte_active() else ""), layer.name, " with sound" if clip != null else ""])
	hide()


## Applies the chosen elements (matte) and/or the auto-rotoscope look to
## every decoded frame, in place.
func _process_frames(dir: String, files: Array) -> bool:
	var p: ProjectData = App.project
	var use_matte := _matte_active()
	var use_roto := _roto.button_pressed
	var settings := _matte_settings()
	var out_fps := p.fps / float(_step.selected + 1)
	var was_low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	if use_matte:
		_matte.setup(p.width, p.height, settings)
	if use_roto and _centers.is_empty():
		# No preview was made: pick the palette from a few (matted) frames across the clip.
		var picks := []
		var count := mini(6, files.size())
		for n in count:
			var fi := int(float(n) / maxf(1.0, count) * files.size())
			var im := Image.load_from_file(dir.path_join(str(files[fi])))
			if im == null or im.is_empty():
				continue
			if use_matte:
				im = await _matte_frame(im, _start.value + fi / out_fps, settings)
			picks.append(im)
		_extract_palette(picks)
	if use_roto:
		_processor.setup(p.width, p.height, _roto_settings())
	var steady := _r_steady.value / 100.0 if use_roto else 0.0
	_steady.reset()
	_progress.max_value = files.size()
	var ok := true
	for i in files.size():
		if _cancel:
			ok = false
			break
		var path := dir.path_join(str(files[i]))
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			continue
		if use_matte:
			img = await _matte_frame(img, _start.value + i / out_fps, settings)
		if use_roto:
			var src := img
			img = await _processor.process(img.duplicate() as Image)
			if steady > 0.0:
				img = await _steady.process(src, img, steady, p.height / 1080.0)
		img.save_png(path)
		_progress.value = i + 1
		_info.text = "Processing frame %d of %d…" % [i + 1, files.size()]
	OS.low_processor_usage_mode = was_low
	return ok


func _range_args() -> PackedStringArray:
	var a := PackedStringArray()
	if _start.value > 0.0:
		a.append_array(PackedStringArray(["-ss", "%.3f" % _start.value]))
	if _length.value > 0.0:
		a.append_array(PackedStringArray(["-t", "%.3f" % _length.value]))
	return a


## Runs FFmpeg as a separate process, polling so the UI stays responsive and
## the import can be cancelled. Returns true if it finished normally.
func _run(args: PackedStringArray, on_tick: Callable) -> bool:
	_pid = OS.create_process(_ffmpeg, args)
	if _pid <= 0:
		return false
	while OS.is_process_running(_pid):
		if _cancel:
			OS.kill(_pid)
			_pid = -1
			return false
		if on_tick.is_valid():
			on_tick.call()
		await get_tree().create_timer(0.25).timeout
	var code := OS.get_process_exit_code(_pid)
	_pid = -1
	return code == 0 or code == -1


func _finish(message: String) -> void:
	_running = false
	_progress.visible = false
	get_ok_button().disabled = false
	App.status(message)
	_info.text = message
