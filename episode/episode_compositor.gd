class_name EpisodeCompositor
extends SubViewport
## Combines what an episode shows at one frame: an incoming and an outgoing
## picture (scene render or title card) with dissolve or wipe, fades through
## black, and text overlays. Used by the live preview and the final render,
## so both look the same.

class Slot extends Control:
	var picture: TextureRect
	var title: TitleView

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture = TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(picture)
		title = TitleView.new()
		add_child(title)

	func set_full_size(s: Vector2) -> void:
		size = s
		picture.size = s
		title.size = s


class Overlay extends Control:
	var text: String = ""
	var style: String = "lower_third"
	var alpha: float = 0.0

	func _draw() -> void:
		TitleView.draw_overlay(self, size, text, style, alpha)


var slot_a: Slot
var slot_b: Slot
var _black: ColorRect
var _fade: ColorRect
var _overlay: Overlay


func _init() -> void:
	transparent_bg = false
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_black = ColorRect.new()
	_black.color = Color.BLACK
	add_child(_black)
	slot_b = Slot.new()
	add_child(slot_b)
	slot_a = Slot.new()
	add_child(slot_a)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	add_child(_fade)
	_overlay = Overlay.new()
	add_child(_overlay)


func setup(w: int, h: int) -> void:
	size = Vector2i(maxi(16, w), maxi(16, h))
	var s := Vector2(size)
	_black.size = s
	_fade.size = s
	_overlay.size = s
	slot_a.set_full_size(s)
	slot_b.set_full_size(s)


## Shows a scene picture in a slot.
func set_picture(slot: Slot, tex: Texture2D) -> void:
	slot.visible = true
	slot.picture.visible = tex != null
	slot.picture.texture = tex
	slot.title.visible = false


## Shows a title/credits entry in a slot.
func set_title(slot: Slot, entry: Dictionary, local: int, fps: int) -> void:
	slot.visible = true
	slot.picture.visible = false
	slot.title.visible = true
	slot.title.show_entry(entry, local, fps)


## Applies transition mix, fade and overlay for the current frame.
func compose(state: Dictionary, overlay_text: String, overlay_style: String, overlay_alpha: float) -> void:
	var s := Vector2(size)
	slot_b.visible = state.get("b") != null
	var mix: float = state.get("mix", 0.0)
	var mode := str(state.get("mode", ""))
	slot_a.modulate.a = 1.0
	slot_a.position = Vector2.ZERO
	slot_a.size = s
	if slot_b.visible:
		if mode == "wipe":
			slot_a.size = Vector2(s.x * mix, s.y)
		else:
			slot_a.modulate.a = mix
	_fade.color = Color(0, 0, 0, clampf(float(state.get("fade", 0.0)), 0.0, 1.0))
	_overlay.text = overlay_text
	_overlay.style = overlay_style
	_overlay.alpha = overlay_alpha
	_overlay.queue_redraw()
