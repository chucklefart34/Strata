class_name InbetweenPanel
extends VBoxContainer
## Auto in-betweens: reads how the lines move from one keyframe to the next
## on the selected layer and fills the frames between — motion in-betweens,
## smears, wipes or fades. One undo step.

const STYLE_LABELS := ["Motion (lines slide into place)", "Smear (streaks along the motion)", "Wipe (new drawing sweeps in)", "Fade (cross-dissolve)"]
const STYLE_HINTS := [
	"Each line slides from where it is to where it goes next, and the two drawings blend. Best for small to medium moves.",
	"The drawing stretches into streaks along its motion — the classic smear frame for fast moves.",
	"The next drawing sweeps in along the direction of motion, with a smear at the edge. Good for fast actions and transitions.",
	"A simple cross-dissolve between the two drawings, without movement.",
]

var _proc: InbetweenProcessor
var _style: OptionButton
var _hint: Label
var _smear: HSlider
var _step: SpinBox
var _scope: OptionButton
var _go: Button
var _status: Label
var _busy: bool = false


func _ready() -> void:
	_proc = InbetweenProcessor.new()
	add_child(_proc)
	var sec := UI.section(self, "Auto in-between")
	var h := UI.label("Fills the frames between your drawings on the selected layer by reading where the lines are on each side.", "Small")
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(h)
	sec.add_child(UI.label("Style", "FieldLabel"))
	_style = UI.option(STYLE_LABELS, 0)
	_style.item_selected.connect(func(_i: int) -> void: _sync())
	sec.add_child(_style)
	_hint = UI.label("", "Small")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_hint)
	_smear = UI.slider(sec, "Smear length", 5, 100, 1, 45, _on_smear, "%d%%")
	var row := UI.hbox(6)
	sec.add_child(row)
	row.add_child(UI.label("Draw every", "FieldLabel"))
	_step = UI.spin(1, 12, 1, 1, " fr")
	row.add_child(_step)
	sec.add_child(UI.label("Where", "FieldLabel"))
	_scope = UI.option(["Between the drawings around the playhead", "Every gap on this layer"], 0)
	sec.add_child(_scope)
	_go = UI.button("Fill in-betweens", "", "Draw the in-between frames", "AccentButton")
	_go.pressed.connect(_run)
	sec.add_child(_go)
	_status = UI.label("", "Small")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(_status)
	_sync()


func _on_smear(_v: float) -> void:
	pass


func _sync() -> void:
	var i := clampi(_style.selected, 0, 3)
	_hint.text = STYLE_HINTS[i]
	_smear.get_parent().visible = i == 1 or i == 2


## [frame_a, frame_b] pairs to fill.
func _gaps(layer: LayerData) -> Array:
	var keys: Array = layer.sorted_keys()
	var out: Array = []
	var step := int(_step.value)
	for i in range(keys.size() - 1):
		var a := int(keys[i])
		var b := int(keys[i + 1])
		if b - a <= step:
			continue
		if _scope.selected == 0 and not (App.frame >= a and App.frame < b):
			continue
		out.append([a, b])
	return out


func _run() -> void:
	if _busy or not App.has_project():
		return
	var layer := App.current_layer()
	if layer == null or layer.is_character():
		_status.text = "Pick a drawing layer first."
		return
	var gaps := _gaps(layer)
	if gaps.is_empty():
		if _scope.selected == 0:
			_status.text = "Put the playhead between two drawings on this layer that have empty frames between them (more than %d apart)." % int(_step.value)
		else:
			_status.text = "This layer needs at least two drawings with empty frames between them."
		return
	_busy = true
	_go.disabled = true
	var style: String = InbetweenProcessor.STYLES[clampi(_style.selected, 0, 3)]
	var smear := _smear.value / 100.0
	var step := int(_step.value)
	var made := {}
	for g in gaps:
		var fa := int(g[0])
		var fb := int(g[1])
		var ca: CelData = layer.cels[fa]
		var cb: CelData = layer.cels[fb]
		_status.text = "Reading the lines on frames %d and %d…" % [fa + 1, fb + 1]
		await _proc.prepare(ca.get_image(), cb.get_image())
		var f := fa + step
		while f < fb:
			_status.text = "Drawing frame %d…" % [f + 1]
			made[f] = await _proc.frame(float(f - fa) / float(fb - fa), style, smear)
			f += step
	Ops.add_drawings(layer, made, "Auto in-between")
	_busy = false
	_go.disabled = false
	_status.text = "Drew %d in-between%s. Undo removes them all; redraw any frame by hand to fix it." % [made.size(), "" if made.size() == 1 else "s"]
