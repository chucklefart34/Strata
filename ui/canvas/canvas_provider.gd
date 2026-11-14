class_name CanvasProvider
extends RefCounted
## Supplies layers to a CanvasView that is not showing the current scene
## (e.g. the Character Studio showing a character's parts). Override the
## methods below; emit `changed` when the canvas should redraw and
## `context_changed` when a floating selection should be applied first.

signal changed
signal context_changed


## Layers to draw, bottom to top.
func layers() -> Array:
	return []


## The layer the drawing tools edit.
func active_layer() -> LayerData:
	return null


## Which drawing (key) of `layer` to show and edit.
func frame_for(_layer: LayerData) -> int:
	return 0


## Creates (undoably) a blank drawing on `layer` at key `frame`.
func create_cel(_layer: LayerData, _frame: int) -> CelData:
	return null


## Opacity multiplier for layers other than the active one.
func inactive_opacity() -> float:
	return 1.0


## Extra drawing on top of the artwork, in canvas coordinates.
func draw_overlay(_ci: CanvasItem, _canvas: CanvasView) -> void:
	pass


## Lets the provider handle a click before the tools do. Return true if handled.
func press(_pos: Vector2, _canvas: CanvasView) -> bool:
	return false
