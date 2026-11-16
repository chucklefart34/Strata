class_name StudioWorkspace
extends Control
## The Draw and Animate workspaces. Same canvas engine, different emphasis:
## Draw puts brushes first with a compact timeline; Animate gives the
## timeline (dope sheet) and onion skin the most room.

var animate_mode: bool = false
var canvas: CanvasView
var timeline: TimelineView
var _zoom_label: Label
var _rot: HSlider
var _exporter: RenderExporter
var _render_btn: Button
var _export_dialog: ExportDialog


func _init(p_animate: bool = false) -> void:
	animate_mode = p_animate


func _ready() -> void:
	var root := UI.hbox(10)
	UI.full_rect(root)
	add_child(root)

	root.add_child(ToolBar.new())

	# ---------------------------------------------------------- center
	var center := UI.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	if animate_mode:
		center.add_child(HintBar.new("animate", "Each orange block in the timeline is a drawing; the bar after it shows how long it is held. Press N for a new drawing on the next frame, D to duplicate the current one, Enter to play. Onion skin shows earlier drawings in red and later ones in green. Double-click an empty cell to start a drawing there, drag a block to retime it."))
	else:
		center.add_child(HintBar.new("draw", "Pick a tool on the left and draw. Each layer is separate artwork — in a 2D + 3D project you can also place layers in depth in the Depth workspace. Space + drag pans, the mouse wheel zooms, [ and ] change brush size."))

	var frame := PanelContainer.new()
	frame.theme_type_variation = "CanvasFrame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0
	center.add_child(frame)
	canvas = CanvasView.new()
	frame.add_child(canvas)

	var footer := UI.hbox(6)
	center.add_child(footer)
	var fit := UI.button("Fit", "fit", "Fit canvas to view (Ctrl+0)", "FlatButton")
	fit.pressed.connect(canvas.fit_view)
	footer.add_child(fit)
	var hundred := UI.button("100%", "", "Actual pixels (Ctrl+1)", "FlatButton")
	hundred.pressed.connect(func() -> void: canvas.set_zoom(1.0))
	footer.add_child(hundred)
	_zoom_label = UI.label("", "Small")
	footer.add_child(_zoom_label)
	footer.add_child(UI.spacer())
	footer.add_child(UI.label("Rotate view", "Small"))
	_rot = HSlider.new()
	_rot.min_value = -180
	_rot.max_value = 180
	_rot.step = 1
	_rot.custom_minimum_size.x = UI.px(160)
	_rot.focus_mode = Control.FOCUS_NONE
	_rot.value_changed.connect(canvas.set_rotation_deg)
	footer.add_child(_rot)
	var reset := UI.icon_button("reset", "Reset rotation")
	reset.pressed.connect(func() -> void: _rot.value = 0)
	footer.add_child(reset)
	if animate_mode:
		# Render lives here too, so 2D and stop-motion projects (no Depth tab) can export.
		footer.add_child(UI.vsep())
		_render_btn = UI.button("Export…", "render", "Export this scene: choose resolution, frame rate, quality and format", "AccentButton")
		_render_btn.pressed.connect(_on_render_pressed)
		footer.add_child(_render_btn)
		_exporter = RenderExporter.new()
		add_child(_exporter)
		_export_dialog = ExportDialog.new()
		add_child(_export_dialog)
	canvas.view_changed.connect(_on_view_changed)

	var tl_card := PanelContainer.new()
	tl_card.theme_type_variation = "Section"
	center.add_child(tl_card)
	var tl_box := UI.vbox(6)
	tl_card.add_child(tl_box)
	tl_box.add_child(TransportBar.new(animate_mode))
	timeline = TimelineView.new()
	timeline.show_audio_rows = animate_mode
	timeline.custom_minimum_size.y = UI.px(230 if animate_mode else 120)
	tl_box.add_child(timeline)

	# ---------------------------------------------------------- sidebar
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = UI.px(300)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(side_scroll)
	var side := UI.vbox(10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)
	if animate_mode:
		side.add_child(PosePanel.new())
		side.add_child(LayerPanel.new())
		side.add_child(LibraryPanel.new(true))
		side.add_child(AiDrawPanel.new())
		side.add_child(CameraPanel.new())
		side.add_child(ClipsPanel.new())
		side.add_child(BrushPanel.new())
	else:
		side.add_child(BrushPanel.new())
		side.add_child(LayerPanel.new())
		side.add_child(AiDrawPanel.new())
		side.add_child(LibraryPanel.new(false))


func _on_render_pressed() -> void:
	open_export()


## Opens the CapCut-style Export sheet for the current scene.
func open_export() -> void:
	if not App.has_project() or DepthView.instance == null:
		return
	App.stop()
	if _exporter == null:
		_exporter = RenderExporter.new()
		add_child(_exporter)
	if _export_dialog == null:
		_export_dialog = ExportDialog.new()
		add_child(_export_dialog)
	_export_dialog.open_scene(_exporter)


func _on_view_changed() -> void:
	_zoom_label.text = "%d%%" % roundi(canvas.zoom * 100.0)
	if not is_equal_approx(_rot.value, canvas.rotation_deg):
		_rot.set_value_no_signal(canvas.rotation_deg)
