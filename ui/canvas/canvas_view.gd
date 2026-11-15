class_name CanvasView
extends Control
## The 2D drawing canvas: pan/zoom/rotate view, layer compositing, onion skin
## and all raster tools. Pixels are edited in the active cel's Image; every
## finished stroke is recorded as a region undo step.

signal view_changed

const MIN_ZOOM := 0.03
const MAX_ZOOM := 32.0
const ONION_SHADER := preload("res://shaders/onion.gdshader")
const PAINT_TOOLS := ["brush", "pencil", "eraser"]
const SHAPE_TOOLS := ["line", "rect", "ellipse"]
const SELECT_TOOLS := ["select", "lasso"]

## Shared clipboard so you can copy in Draw and paste in Animate (or another scene).
static var clipboard: Image = null
static var clipboard_pos: Vector2i = Vector2i.ZERO

var zoom: float = 0.5
var pan: Vector2 = Vector2.ZERO
var rotation_deg: float = 0.0

var _fit_pending: bool = true
var _checker: ImageTexture
var _onion_view: OnionView
var _art_view: ArtView

var _panning: bool = false
var _pan_with_left: bool = false
var _active: bool = false
var _start: Vector2 = Vector2.ZERO
var _last: Vector2 = Vector2.ZERO
var _last_pressure: float = 1.0
## The first dab waits for the first real pressure reading (pen press events
## carry no pressure, and hovering reports 0).
var _pending_start: bool = false
var _stroke_has_pressure: bool = false
## Set once any pressure-sensitive device has been used, so a tap with a pen
## draws a light dot instead of a full-size one.
static var _pen_seen: bool = false
var _smoothed: Vector2 = Vector2.ZERO
var _carry: float = 0.0
var _hovering: bool = false
var cursor: Vector2 = Vector2(-99999, -99999)
var move_offset: Vector2 = Vector2.ZERO

var _cel: CelData = null
var _before: Image = null
var _dirty_rect: Rect2i = Rect2i()
var _has_dirty: bool = false
var _held_hint_frame: int = -1
# ---- touch (iPad / iPhone)
var _touches: Dictionary = {}  # finger index -> screen position
var _gesture: bool = false     # two or more fingers down: view gesture, no drawing
var _g_center: Vector2 = Vector2.ZERO
var _g_dist: float = 0.0
var _g_angle: float = 0.0
var _g_fingers: int = 0
var _g_moved: bool = false
var _g_start_ms: int = 0
var _touch_pressure: float = -1.0  # Apple Pencil pressure from touch events

## Where the canvas gets its layers from. null = the current scene (App).
## The Character Studio supplies a provider that exposes character parts.
var provider: CanvasProvider = null

# selection state
var sel_poly: PackedVector2Array = PackedVector2Array()
var floating: Image = null
var float_rect: Rect2 = Rect2()
var _float_tex: ImageTexture = null
var _float_cel: CelData = null
var _float_before: Image = null
var _float_origin: Rect2i = Rect2i()
var _sel_mode: String = ""
var _sel_start_rect: Rect2 = Rect2()
var _corner: int = -1


class OnionView extends Control:
	var canvas: CanvasView

	func _draw() -> void:
		canvas.draw_onion(self)


class ArtView extends Control:
	var canvas: CanvasView

	func _draw() -> void:
		canvas.draw_art(self)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_checker = _make_checker()

	_onion_view = OnionView.new()
	_onion_view.canvas = self
	var mat := ShaderMaterial.new()
	mat.shader = ONION_SHADER
	_onion_view.material = mat
	_art_view = ArtView.new()
	_art_view.canvas = self
	for c: Control in [_onion_view, _art_view]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		UI.full_rect(c)
		add_child(c)

	resized.connect(_on_resized)
	mouse_entered.connect(func() -> void: _hovering = true)
	mouse_exited.connect(func() -> void:
		_hovering = false
		_art_view.queue_redraw())
	App.project_opened.connect(func() -> void:
		_fit_pending = true
		_on_resized())
	for sig: Signal in [App.scene_switched, App.layers_changed, App.layer_selected, App.frame_changed,
			App.pixels_changed, App.onion_changed, App.timeline_changed, App.tool_changed, App.stage_changed,
			App.camera_changed, App.camera_view_changed]:
		sig.connect(refresh)
	# A floating selection is applied before the context it belongs to changes.
	for sig: Signal in [App.scene_switched, App.layer_selected, App.frame_changed, App.project_closed]:
		sig.connect(commit_floating)
	App.tool_changed.connect(func() -> void:
		if not SELECT_TOOLS.has(App.tool):
			commit_floating())


## Outline of what the camera sees (when not already viewing through it),
## once the scene's camera has been moved or animated.
func _draw_camera_frame(ci: CanvasItem, cs: Vector2) -> void:
	if provider != null or App.camera_view or not App.has_project():
		return
	var s := App.current_scene()
	if s == null or s.camera_keys.is_empty():
		return
	var inv := camera_xform(_frame_for(null)).affine_inverse()
	var pts := PackedVector2Array([inv * Vector2.ZERO, inv * Vector2(cs.x, 0), inv * cs, inv * Vector2(0, cs.y), inv * Vector2.ZERO])
	var w := 2.0 / maxf(0.05, zoom)
	ci.draw_polyline(pts, Color(Palette.DEPTH, 0.9), w)
	ci.draw_string(get_theme_default_font(), pts[0] + Vector2(6, 16) / maxf(0.05, zoom), "CAMERA", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 / maxf(0.05, zoom)), Palette.DEPTH)


## The Depth set rendered through the scene camera (Draw/Animate only), or null.
func _guide_texture() -> Texture2D:
	var dv := DepthView.instance
	if dv == null or provider != null or not App.has_project():
		return null
	var s := App.current_scene()
	if s == null or not bool(s.stage_value("draw_guide")) or not DepthView.scene_has_set(s):
		return null
	if not dv.guide_updated.is_connected(_on_guide_updated):
		dv.guide_updated.connect(_on_guide_updated)
	if not dv.guide_wanted or not dv.guide_ready:
		dv.guide_wanted = true
		dv.request_guide()
	return dv.guide_texture()


func _on_guide_updated() -> void:
	if is_visible_in_tree():
		_art_view.queue_redraw()


func refresh() -> void:
	queue_redraw()
	_onion_view.queue_redraw()
	_art_view.queue_redraw()


func _make_checker() -> ImageTexture:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color("#f4f4f6"))
	img.fill_rect(Rect2i(0, 0, 16, 16), Color("#e2e2e7"))
	img.fill_rect(Rect2i(16, 16, 16, 16), Color("#e2e2e7"))
	return ImageTexture.create_from_image(img)


# ================================================================ view transform

func canvas_size() -> Vector2:
	if not App.has_project():
		return Vector2(1920, 1080)
	return Vector2(App.project.width, App.project.height)


func view_xform() -> Transform2D:
	var cs := canvas_size()
	var xf := Transform2D(deg_to_rad(rotation_deg), Vector2(zoom, zoom), 0.0, size * 0.5 + pan) * Transform2D(0.0, -cs * 0.5)
	if App.camera_view and provider == null:
		xf = xf * camera_xform(_frame_for(null))
	return xf


## Canvas → canvas transform that frames the drawing like the scene camera
## at `frame` (pan, zoom, dolly, roll, shake), as in the flat 2D render.
func camera_xform(frame: int) -> Transform2D:
	if not App.has_project() or App.current_scene() == null:
		return Transform2D.IDENTITY
	var s := App.current_scene()
	var st := s.camera_at(frame)
	var x: float = st["x"]
	var y: float = st["y"]
	var shake: float = st["shake"]
	if shake > 0.0:
		x += (sin(frame * 12.9898) * 0.6 + sin(frame * 4.1414 + 1.3) * 0.4) * shake
		y += (cos(frame * 9.7310) * 0.6 + cos(frame * 3.3700 + 0.7) * 0.4) * shake
	var z := maxf(0.05, float(st["zoom"]))
	if DepthView.instance != null:
		var d := DepthView.instance.base_dist()
		z *= d / maxf(0.5, d - float(st["dolly"]))
	var c := canvas_size() * 0.5
	return Transform2D(0.0, c) * Transform2D(deg_to_rad(-float(st["roll"])), Vector2(z, z), 0.0, Vector2.ZERO) * Transform2D(0.0, -(c + Vector2(x, y)))


func to_canvas(screen_pos: Vector2) -> Vector2:
	return view_xform().affine_inverse() * screen_pos


func fit_view() -> void:
	var cs := canvas_size()
	if size.x < 10 or size.y < 10:
		_fit_pending = true
		return
	var margin := UI.px(40)
	zoom = clampf(minf((size.x - margin) / cs.x, (size.y - margin) / cs.y), MIN_ZOOM, MAX_ZOOM)
	pan = Vector2.ZERO
	_fit_pending = false
	_view_changed()


func set_zoom(z: float) -> void:
	zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)
	_view_changed()


func set_rotation_deg(r: float) -> void:
	rotation_deg = r
	_view_changed()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var anchor := to_canvas(screen_pos)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var moved := view_xform() * anchor
	pan += screen_pos - moved
	_view_changed()


func _view_changed() -> void:
	refresh()
	view_changed.emit()


func _on_resized() -> void:
	if _fit_pending and is_visible_in_tree():
		fit_view()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree() and _fit_pending:
			fit_view.call_deferred()
		elif not is_visible_in_tree():
			commit_floating()
			# Stop re-rendering the 3D guide while no canvas shows it.
			if DepthView.instance != null and provider == null:
				DepthView.instance.guide_wanted = false


# ================================================================ drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.DESK)
	if not App.has_project():
		return
	var cs := canvas_size()
	draw_set_transform_matrix(view_xform())
	var shadow := UI.px(6) / zoom
	draw_rect(Rect2(Vector2(shadow * 0.4, shadow), cs), Color(0, 0, 0, 0.45))
	draw_texture_rect(_checker, Rect2(Vector2.ZERO, cs), true)


func draw_onion(ci: CanvasItem) -> void:
	if not App.has_project() or not App.onion_enabled or App.playing or provider != null:
		return
	var layer := App.current_layer()
	if layer == null or not layer.visible:
		return
	ci.draw_set_transform_matrix(view_xform())
	var keys := layer.sorted_keys()
	var cur_key := layer.key_at_or_before(App.frame)
	var idx := keys.find(cur_key)
	var before: int = App.onion_before
	var after: int = App.onion_after
	for i in range(before, 0, -1):
		var k := idx - i
		if idx < 0 or k < 0:
			continue
		var cel: CelData = layer.cels[keys[k]]
		var c := Palette.ONION_BEFORE
		c.a = 0.5 / i
		ci.draw_texture(cel.get_texture(), Vector2.ZERO, c)
	for i in range(after, 0, -1):
		var k := idx + i
		if k >= keys.size():
			continue
		var cel: CelData = layer.cels[keys[k]]
		var c := Palette.ONION_AFTER
		c.a = 0.5 / i
		ci.draw_texture(cel.get_texture(), Vector2.ZERO, c)


func draw_art(ci: CanvasItem) -> void:
	if not App.has_project():
		return
	var cs := canvas_size()
	ci.draw_set_transform_matrix(view_xform())
	var active := _active_layer()
	var moving := _active and App.tool == "move"
	var guide := _guide_texture()
	var guide_front := false
	var guide_op := 1.0
	if guide != null:
		var s := App.current_scene()
		guide_front = bool(s.stage_value("draw_guide_front"))
		guide_op = clampf(float(s.stage_value("draw_guide_opacity")), 0.0, 1.0)
		if not guide_front:
			ci.draw_texture_rect(guide, Rect2(Vector2.ZERO, cs), false, Color(1, 1, 1, guide_op))
	for item in _layers():
		var layer: LayerData = item
		if not layer.visible:
			continue
		var tex: Texture2D = null
		if layer.is_character():
			tex = Rigs.texture_for(layer)
		else:
			var cel := layer.cel_at(_frame_for(layer))
			if cel != null:
				tex = cel.get_texture()
		if tex == null:
			continue
		var pos := Vector2.ZERO
		if moving and layer == active:
			pos = move_offset.round()
		var op := layer.opacity
		if provider == null:
			op = clampf(float(layer.motion_at(App.frame)["opacity"]), 0.0, 1.0)
		elif layer != active:
			op *= provider.inactive_opacity()
		if layer.is_reference():
			op = minf(op, 0.6)
		ci.draw_texture(tex, pos, Color(1, 1, 1, op))
	if guide != null and guide_front:
		ci.draw_texture_rect(guide, Rect2(Vector2.ZERO, cs), false, Color(1, 1, 1, guide_op))
	_draw_camera_frame(ci, cs)
	ci.draw_rect(Rect2(Vector2.ZERO, cs), Color(0, 0, 0, 0.25), false, -1.0)
	if provider != null:
		provider.draw_overlay(ci, self)

	if _active and SHAPE_TOOLS.has(App.tool):
		var col: Color = App.color
		col.a = 0.85
		var pts := _shape_points(_start, _last)
		ci.draw_polyline(pts, col, maxf(App.brush_size, 1.0 / zoom), true)

	_draw_selection(ci)

	if _hovering and PAINT_TOOLS.has(App.tool) and not _panning:
		var r := maxf(App.brush_size * 0.5, 1.5 / zoom)
		ci.draw_arc(cursor, r + 1.0 / zoom, 0.0, TAU, 48, Color(0, 0, 0, 0.55), -1.0, true)
		ci.draw_arc(cursor, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9), -1.0, true)


# ================================================================ input

func _gui_input(event: InputEvent) -> void:
	if not App.has_project():
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		return
	if _gesture and (event is InputEventMouseButton or event is InputEventMouseMotion):
		accept_event()  # the finger that started the gesture also sends mouse events
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.12 if mb.factor <= 0.0 else pow(1.12, mb.factor))
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / (1.12 if mb.factor <= 0.0 else pow(1.12, mb.factor)))
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
				accept_event()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					grab_focus()
					if Input.is_key_pressed(KEY_SPACE) or App.tool == "hand":
						_panning = true
						_pan_with_left = true
					else:
						_begin(to_canvas(mb.position), _last_pressure)
				else:
					if _pan_with_left:
						_panning = false
						_pan_with_left = false
					else:
						_end(to_canvas(mb.position))
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		cursor = to_canvas(mm.position)
		_hovering = true
		if _panning:
			pan += mm.relative
			_view_changed()
			return
		if _active:
			_continue(cursor, _read_pressure(mm))
		_art_view.queue_redraw()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		pan -= pg.delta * UI.px(18)
		_view_changed()
		accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
		accept_event()


# ================================================================ tools

func _layers() -> Array:
	if provider != null:
		return provider.layers()
	var s := App.current_scene()
	return s.layers if s != null else []


func _active_layer() -> LayerData:
	if provider != null:
		return provider.active_layer()
	return App.current_layer()


func _frame_for(layer: LayerData) -> int:
	if provider != null:
		return provider.frame_for(layer)
	return App.frame


func _editable_layer() -> LayerData:
	var layer := _active_layer()
	if layer == null:
		App.status("Add a layer first" if provider == null else "Add a part first")
		return null
	if layer.is_character():
		App.status("“%s” is a character — draw it in Characters, pose it in Animate" % layer.name)
		return null
	if layer.locked:
		App.status("“%s” is locked — unlock it in the Layers panel" % layer.name)
		return null
	if not layer.visible:
		App.status("“%s” is hidden — show it to draw on it" % layer.name)
		return null
	return layer


func _editable_cel(create: bool) -> CelData:
	var layer := _editable_layer()
	if layer == null:
		return null
	var f := _frame_for(layer)
	var cel := layer.cel_at(f)
	if provider != null:
		if layer.cels.has(f):
			return layer.cels[f]
		return provider.create_cel(layer, f) if create else null
	if cel == null and create:
		cel = Ops.create_key(layer, App.frame)
	elif cel != null:
		var k := layer.key_at_or_before(App.frame)
		if k != App.frame and _held_hint_frame != App.frame:
			_held_hint_frame = App.frame
			App.status("Editing the drawing held from frame %d. Press N for a new drawing here." % (k + 1))
	return cel


## Fingers: one finger draws (through the emulated mouse); two or more
## fingers pinch-zoom, pan and rotate the view. A quick two-finger tap is
## undo, a three-finger tap redo (like most iPad drawing apps).
func _touch_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st != null:
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
			if _touches.is_empty():
				_touch_pressure = -1.0
		if _touches.size() >= 2 and not _gesture:
			_cancel_stroke()
			_gesture = true
			_g_moved = false
			_g_start_ms = Time.get_ticks_msec()
			_g_fingers = 0
			_gesture_reset()
		if _gesture:
			_g_fingers = maxi(_g_fingers, _touches.size())
			if _touches.size() >= 2:
				_gesture_reset()
			elif _touches.is_empty():
				_gesture = false
				if not _g_moved and Time.get_ticks_msec() - _g_start_ms < 350:
					if _g_fingers == 2:
						_tap_history(false)
					elif _g_fingers >= 3:
						_tap_history(true)
		accept_event()
		return
	var sd := event as InputEventScreenDrag
	if sd == null:
		return
	_touches[sd.index] = sd.position
	if "pressure" in sd:
		var pr: float = sd.get("pressure")
		if pr > 0.0:
			_touch_pressure = pr
	if not _gesture or _touches.size() < 2:
		return
	var pts := _two_touches()
	var center := (pts[0] + pts[1]) * 0.5
	var dist := maxf(1.0, pts[0].distance_to(pts[1]))
	var angle := (pts[1] - pts[0]).angle()
	if center.distance_to(_g_center) > 2.0 or absf(dist - _g_dist) > 2.0:
		if (center - _g_center).length() + absf(dist - _g_dist) > UI.px(10):
			_g_moved = true
	pan += center - _g_center
	_zoom_at(center, dist / maxf(1.0, _g_dist))
	var turn := wrapf(angle - _g_angle, -PI, PI)
	if absf(turn) > 0.0 and _g_moved:
		set_rotation_deg(rotation_deg + rad_to_deg(turn))
	_g_center = center
	_g_dist = dist
	_g_angle = angle
	_view_changed()
	accept_event()


func _two_touches() -> Array[Vector2]:
	var ks := _touches.keys()
	ks.sort()
	var a: Vector2 = _touches[ks[0]]
	var b: Vector2 = _touches[ks[1]]
	return [a, b]


func _gesture_reset() -> void:
	var pts := _two_touches()
	_g_center = (pts[0] + pts[1]) * 0.5
	_g_dist = maxf(1.0, pts[0].distance_to(pts[1]))
	_g_angle = (pts[1] - pts[0]).angle()


func _tap_history(redo: bool) -> void:
	commit_floating()
	if redo:
		History.redo()
	else:
		History.undo()


## Throws away a stroke that was just started (a second finger landed).
func _cancel_stroke() -> void:
	if not _active:
		return
	_active = false
	_pending_start = false
	if _cel != null and _before != null and PAINT_TOOLS.has(App.tool):
		_cel.image.copy_from(_before)
		_cel.mark_changed()
		App.notify_pixels()
	_cel = null
	_has_dirty = false
	refresh()


func _begin(pos: Vector2, pressure: float) -> void:
	if provider != null and provider.press(pos, self):
		refresh()
		return
	var tool: String = App.tool
	if PAINT_TOOLS.has(tool):
		var cel := _editable_cel(tool != "eraser")
		if cel == null:
			if tool == "eraser":
				App.status("Nothing to erase on this frame")
			return
		_stroke_begin(cel)
		_smoothed = pos
		_last = pos
		_stroke_has_pressure = false
		_pending_start = true  # first dab is placed on the first move, with real pressure
		_active = true
	elif SHAPE_TOOLS.has(tool):
		if _editable_layer() == null:
			return
		_start = pos
		_last = pos
		_active = true
	elif SELECT_TOOLS.has(tool):
		_sel_begin(pos)
		_active = true
	elif tool == "fill":
		_do_fill(pos)
	elif tool == "picker":
		_do_pick(pos)
	elif tool == "move":
		var cel := _editable_cel(false)
		if cel == null:
			return
		_stroke_begin(cel)
		_start = pos
		move_offset = Vector2.ZERO
		_active = true
	_art_view.queue_redraw()


## Pressure for a drag event. Mouse drags (never any pressure) count as full
## pressure; pen drags use the pen, lightly smoothed to remove touch-down
## spikes, and keep the last value if a reading drops to 0 mid-stroke.
func _read_pressure(mm: InputEventMouseMotion) -> float:
	if mm.pressure <= 0.0 and _touch_pressure > 0.0:
		# Touch screens: the mouse events made from touches carry no pressure,
		# but the matching touch-drag events from an Apple Pencil do.
		_pen_seen = true
		var tp := clampf(_touch_pressure, 0.0, 1.0)
		if _stroke_has_pressure:
			tp = lerpf(_last_pressure, tp, 0.6)
		_stroke_has_pressure = true
		return tp
	if mm.pressure > 0.0:
		_pen_seen = true
		var p := clampf(mm.pressure, 0.0, 1.0)
		if _stroke_has_pressure:
			p = lerpf(_last_pressure, p, 0.6)
		_stroke_has_pressure = true
		return p
	if _stroke_has_pressure:
		return _last_pressure
	return 1.0


func _continue(pos: Vector2, pressure: float) -> void:
	var tool: String = App.tool
	if PAINT_TOOLS.has(tool) and _cel != null:
		if _pending_start:
			_pending_start = false
			_last_pressure = pressure
			_dab(_last, pressure)
			_carry = _spacing()
		var stab: float = App.stabilizer
		var target := _smoothed.lerp(pos, 1.0 - stab * 0.9)
		_segment(_last, target, _last_pressure, pressure)
		_last = target
		_smoothed = target
		_last_pressure = pressure
		_cel.mark_changed()
	elif SHAPE_TOOLS.has(tool):
		_last = _constrain(_start, pos)
	elif SELECT_TOOLS.has(tool):
		_sel_continue(pos)
	elif tool == "move":
		move_offset = pos - _start


func _end(pos: Vector2) -> void:
	if not _active:
		return
	_active = false
	var tool: String = App.tool
	if PAINT_TOOLS.has(tool) and _cel != null:
		if _pending_start:
			# A tap without movement: a dot sized like a light press for pens.
			_pending_start = false
			_dab(_last, 0.35 if _pen_seen else 1.0)
		elif App.stabilizer > 0.0:
			_segment(_last, pos, _last_pressure, _last_pressure)
		_stroke_end("Erase" if tool == "eraser" else "Brush stroke")
	elif SHAPE_TOOLS.has(tool):
		var cel := _editable_cel(true)
		if cel == null:
			return
		_stroke_begin(cel)
		var pts := _shape_points(_start, _last)
		_dab(pts[0], 1.0)
		_carry = _spacing()
		for i in range(1, pts.size()):
			_segment(pts[i - 1], pts[i], 1.0, 1.0)
		_stroke_end("Draw " + tool)
	elif SELECT_TOOLS.has(tool):
		_sel_end()
	elif tool == "move" and _cel != null:
		var off := Vector2i(move_offset.round())
		if off != Vector2i.ZERO:
			var img := _cel.image
			img.fill(Color(0, 0, 0, 0))
			img.blit_rect(_before, Rect2i(Vector2i.ZERO, _before.get_size()), off)
			_mark_dirty(Rect2i(Vector2i.ZERO, img.get_size()))
		move_offset = Vector2.ZERO
		_stroke_end("Move drawing")
	refresh()


func _constrain(a: Vector2, b: Vector2) -> Vector2:
	if not Input.is_key_pressed(KEY_SHIFT):
		return b
	var d := b - a
	if App.tool == "line":
		var ang := snappedf(d.angle(), PI / 4.0)
		return a + Vector2.from_angle(ang) * d.length()
	var m := maxf(absf(d.x), absf(d.y))
	return a + Vector2(signf(d.x) * m, signf(d.y) * m)


func _shape_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	match App.tool:
		"rect":
			return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a])
		"ellipse":
			var c := (a + b) * 0.5
			var rad := (b - a).abs() * 0.5
			var n := clampi(int(rad.length() * 0.4), 24, 180)
			var pts := PackedVector2Array()
			for i in n + 1:
				var t := TAU * float(i) / float(n)
				pts.append(c + Vector2(cos(t) * rad.x, sin(t) * rad.y))
			return pts
		_:
			return PackedVector2Array([a, b])


func _spacing() -> float:
	var s: float = App.brush_size
	return maxf(1.0, s * (0.2 if App.tool == "eraser" else 0.12))


## Per-dab flow so overlapping dabs add up to roughly the chosen opacity.
func _flow() -> float:
	var o: float = App.brush_opacity
	if o >= 0.999:
		return 1.0
	var overlap := 5.0 if App.tool == "eraser" else 8.0
	return 1.0 - pow(1.0 - o, 1.0 / overlap)


func _segment(a: Vector2, b: Vector2, pa: float, pb: float) -> void:
	var d := a.distance_to(b)
	if d <= 0.0001:
		return
	var spacing := _spacing()
	var dir := (b - a) / d
	var pos := _carry
	while pos <= d:
		_dab(a + dir * pos, lerpf(pa, pb, pos / d))
		pos += spacing
	_carry = pos - d


func _dab(p: Vector2, pressure: float) -> void:
	var tool: String = App.tool
	var size_px: float = App.brush_size
	if App.pressure_size and PAINT_TOOLS.has(tool):
		size_px *= clampf(pressure, 0.08, 1.0)
	var img := _cel.image
	var r: Rect2i
	if tool == "eraser":
		r = BrushEngine.erase_dab(img, p, size_px, App.brush_hardness, _flow())
	else:
		var hard: float = App.brush_hardness
		if tool == "pencil":
			hard = 1.0
		elif SHAPE_TOOLS.has(tool):
			hard = maxf(hard, 0.85)
		var c: Color = App.color
		c.a = _flow()
		r = BrushEngine.paint_dab(img, p, size_px, hard, c)
	_mark_dirty(r)


func _mark_dirty(r: Rect2i) -> void:
	if _has_dirty:
		_dirty_rect = _dirty_rect.merge(r)
	else:
		_dirty_rect = r
		_has_dirty = true


func _stroke_begin(cel: CelData) -> void:
	_cel = cel
	cel.get_image()
	_before = cel.image.duplicate() as Image
	_has_dirty = false


func _stroke_end(action_name: String) -> void:
	if _cel == null:
		return
	var img := _cel.image
	if _has_dirty:
		var r := _dirty_rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.has_area():
			var before := _before.get_region(r)
			var after := img.get_region(r)
			History.commit_pixels(action_name, _cel, r, before, after)
	_cel.mark_changed()
	_cel = null
	_before = null
	_has_dirty = false
	App.notify_pixels()


func _do_fill(pos: Vector2) -> void:
	var cel := _editable_cel(true)
	if cel == null:
		return
	_stroke_begin(cel)
	var c: Color = App.color
	c.a = App.brush_opacity
	var r := BrushEngine.flood_fill(cel.image, Vector2i(pos.floor()), c)
	if r.has_area():
		_mark_dirty(r)
	_stroke_end("Fill")


func _do_pick(pos: Vector2) -> void:
	var list := _layers()
	var ip := Vector2i(pos.floor())
	var cs := canvas_size()
	if ip.x < 0 or ip.y < 0 or ip.x >= int(cs.x) or ip.y >= int(cs.y):
		return
	for i in range(list.size() - 1, -1, -1):
		var l: LayerData = list[i]
		if not l.visible or l.is_character():
			continue
		var cel := l.cel_at(_frame_for(l))
		if cel == null:
			continue
		var c := cel.get_image().get_pixelv(ip)
		if c.a > 0.05:
			c.a = 1.0
			App.set_color(c)
			App.status("Picked #%s from “%s”" % [c.to_html(false), l.name])
			return
	App.status("No color under the cursor")


# ================================================================ selection

func has_selection() -> bool:
	return sel_poly.size() >= 3 or floating != null


static func _rect_corners(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


func _handle_at(pos: Vector2) -> int:
	if floating == null:
		return -1
	var tol := UI.px(9) / zoom
	var cs := _rect_corners(float_rect.abs())
	for i in 4:
		if pos.distance_to(cs[i]) <= tol:
			return i
	return -1


func _sel_begin(pos: Vector2) -> void:
	_start = pos
	var h := _handle_at(pos)
	if h >= 0:
		_sel_mode = "scale"
		_corner = h
		_sel_start_rect = float_rect.abs()
		return
	if floating != null and float_rect.abs().has_point(pos):
		_sel_mode = "move"
		_sel_start_rect = float_rect
		return
	if floating == null and sel_poly.size() >= 3 and Geometry2D.is_point_in_polygon(pos, sel_poly):
		if _lift():
			_sel_mode = "move"
			_sel_start_rect = float_rect
		return
	commit_floating()
	_sel_mode = "define"
	sel_poly = PackedVector2Array([pos])


func _sel_continue(pos: Vector2) -> void:
	match _sel_mode:
		"define":
			if App.tool == "select":
				var b := _constrain(_start, pos)
				sel_poly = _rect_corners(Rect2(_start, Vector2.ZERO).expand(b))
			elif sel_poly.is_empty() or sel_poly[sel_poly.size() - 1].distance_to(pos) > 2.0 / zoom:
				sel_poly.append(pos)
		"move":
			float_rect.position = _sel_start_rect.position + (pos - _start)
		"scale":
			var r := _sel_start_rect
			var opposite := _rect_corners(r)[(_corner + 2) % 4]
			var d := pos - opposite
			if Input.is_key_pressed(KEY_SHIFT) and r.size.y > 0.0:
				var aspect := r.size.x / r.size.y
				if absf(d.x) / aspect > absf(d.y):
					d.y = (1.0 if d.y >= 0.0 else -1.0) * absf(d.x) / aspect
				else:
					d.x = (1.0 if d.x >= 0.0 else -1.0) * absf(d.y) * aspect
			float_rect = Rect2(opposite, Vector2.ZERO).expand(opposite + d)
	_art_view.queue_redraw()


func _sel_end() -> void:
	if _sel_mode == "define":
		if sel_poly.size() < 3:
			sel_poly = PackedVector2Array()
		else:
			var b := _poly_bounds(sel_poly)
			if b.size.x < 2.0 or b.size.y < 2.0:
				sel_poly = PackedVector2Array()
	_sel_mode = ""
	refresh()


## Pixels of `img` inside `poly`: {"image", "mask", "bounds"} or {} if empty.
func _extract(img: Image, poly: PackedVector2Array) -> Dictionary:
	var pb := _poly_bounds(poly)
	var pos := Vector2i(pb.position.floor())
	var bounds := Rect2i(pos, Vector2i(pb.end.ceil()) - pos).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if not bounds.has_area():
		return {}
	var local := PackedVector2Array()
	for p in poly:
		local.append(p - Vector2(bounds.position))
	var mask := BrushEngine.polygon_mask(local, bounds.size)
	var region := img.get_region(bounds)
	var out := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect_mask(region, mask, Rect2i(Vector2i.ZERO, bounds.size), Vector2i.ZERO)
	return {"image": out, "mask": mask, "bounds": bounds}


## Cuts the selected pixels out of the drawing into a floating image.
func _lift() -> bool:
	var cel := _editable_cel(false)
	if cel == null:
		App.status("Nothing to move on this frame")
		return false
	var img := cel.get_image()
	var ex := _extract(img, sel_poly)
	if ex.is_empty():
		return false
	var bounds: Rect2i = ex["bounds"]
	_float_before = img.duplicate() as Image
	var clear := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	clear.fill(Color(0, 0, 0, 0))
	img.blit_rect_mask(clear, ex["mask"], Rect2i(Vector2i.ZERO, bounds.size), bounds.position)
	cel.mark_changed()
	floating = ex["image"]
	_float_cel = cel
	_float_origin = bounds
	float_rect = Rect2(bounds)
	_float_tex = ImageTexture.create_from_image(floating)
	sel_poly = PackedVector2Array()
	refresh()
	return true


func _floating_result() -> Dictionary:
	var r := float_rect.abs()
	var pos := Vector2i(r.position.round())
	var sz := Vector2i(maxi(1, roundi(r.size.x)), maxi(1, roundi(r.size.y)))
	var src := floating
	if sz != floating.get_size():
		src = floating.duplicate() as Image
		src.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
	return {"image": src, "pos": pos, "size": sz}


## Drops the floating selection into the drawing as one undo step.
func commit_floating() -> void:
	if floating == null or _float_cel == null:
		return
	var cel := _float_cel
	var img := cel.get_image()
	var res := _floating_result()
	var src: Image = res["image"]
	var pos: Vector2i = res["pos"]
	var sz: Vector2i = res["size"]
	img.blend_rect(src, Rect2i(Vector2i.ZERO, sz), pos)
	cel.mark_changed()
	var changed := _float_origin.merge(Rect2i(pos, sz)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if changed.has_area():
		History.commit_pixels("Transform selection", cel, changed, _float_before.get_region(changed), img.get_region(changed))
	sel_poly = _rect_corners(Rect2(Vector2(pos), Vector2(sz)))
	_clear_floating()
	App.notify_pixels()


func cancel_floating() -> void:
	if floating == null or _float_cel == null:
		return
	var img := _float_cel.get_image()
	img.blit_rect(_float_before, _float_origin, _float_origin.position)
	_float_cel.mark_changed()
	_clear_floating()
	App.notify_pixels()


func _clear_floating() -> void:
	floating = null
	_float_tex = null
	_float_cel = null
	_float_before = null
	_sel_mode = ""


func delete_selection() -> void:
	if floating == null:
		if sel_poly.size() < 3:
			return
		if not _lift():
			return
	var img := _float_cel.get_image()
	var r := _float_origin
	History.commit_pixels("Delete selection", _float_cel, r, _float_before.get_region(r), img.get_region(r))
	_float_cel.mark_changed()
	_clear_floating()
	sel_poly = PackedVector2Array()
	App.notify_pixels()


func copy_selection() -> bool:
	if floating != null:
		var res := _floating_result()
		clipboard = res["image"]
		clipboard_pos = res["pos"]
		App.status("Copied selection")
		return true
	if sel_poly.size() < 3:
		App.status("Select something first (S or A)")
		return false
	var al := _active_layer()
	var cel: CelData = al.cel_at(_frame_for(al)) if al != null else null
	if cel == null:
		return false
	var ex := _extract(cel.get_image(), sel_poly)
	if ex.is_empty():
		return false
	clipboard = ex["image"]
	var bb: Rect2i = ex["bounds"]
	clipboard_pos = bb.position
	App.status("Copied selection")
	return true


func cut_selection() -> void:
	if copy_selection():
		delete_selection()


func paste() -> void:
	if clipboard == null:
		App.status("Nothing to paste")
		return
	commit_floating()
	App.set_tool("select")
	var cel := _editable_cel(true)
	if cel == null:
		return
	var img := cel.get_image()
	_float_before = img.duplicate() as Image
	floating = clipboard.duplicate() as Image
	_float_cel = cel
	float_rect = Rect2(Vector2(clipboard_pos), Vector2(floating.get_size()))
	_float_origin = Rect2i(clipboard_pos, floating.get_size()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if not _float_origin.has_area():
		_float_origin = Rect2i(0, 0, 1, 1)
	_float_tex = ImageTexture.create_from_image(floating)
	sel_poly = PackedVector2Array()
	App.status("Pasted — drag to place, drag corners to scale, Enter to apply")
	refresh()


func select_all() -> void:
	commit_floating()
	sel_poly = _rect_corners(Rect2(Vector2.ZERO, canvas_size()))
	if not SELECT_TOOLS.has(App.tool):
		App.set_tool("select")
	refresh()


func deselect() -> void:
	commit_floating()
	sel_poly = PackedVector2Array()
	refresh()


func _draw_selection(ci: CanvasItem) -> void:
	var dash := 5.0 / zoom
	if floating != null and _float_tex != null:
		var r := float_rect.abs()
		ci.draw_texture_rect(_float_tex, r, false)
		var cs := _rect_corners(r)
		for i in 4:
			ci.draw_line(cs[i], cs[(i + 1) % 4], Color(0, 0, 0, 0.7), -1.0)
			ci.draw_dashed_line(cs[i], cs[(i + 1) % 4], Palette.ACCENT, -1.0, dash)
		var hs := UI.px(5) / zoom
		for c in cs:
			ci.draw_rect(Rect2(c - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color.WHITE, true)
			ci.draw_rect(Rect2(c - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Palette.ACCENT, false, -1.0)
	if sel_poly.size() >= 2:
		var n := sel_poly.size()
		var closed := _sel_mode != "define" or App.tool == "select"
		var count := n if closed else n - 1
		for i in count:
			var a := sel_poly[i]
			var b := sel_poly[(i + 1) % n]
			ci.draw_line(a, b, Color(0, 0, 0, 0.75), -1.0)
			ci.draw_dashed_line(a, b, Color.WHITE, -1.0, dash)
