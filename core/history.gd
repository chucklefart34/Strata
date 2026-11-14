extends Node
## "History" autoload: one undo/redo stack for the whole application.
## Pixel edits store only the changed rectangle (before/after), structural
## edits store snapshots of the small dictionaries/arrays they change.

const MAX_STEPS := 120

var ur: UndoRedo


func _ready() -> void:
	ur = UndoRedo.new()
	ur.max_steps = MAX_STEPS


func _exit_tree() -> void:
	if ur != null:
		ur.free()
		ur = null


func clear() -> void:
	if ur != null:
		ur.clear_history()


func can_undo() -> bool:
	return ur != null and ur.has_undo()


func can_redo() -> bool:
	return ur != null and ur.has_redo()


func undo() -> void:
	if not can_undo():
		App.status("Nothing to undo")
		return
	var action_name := ur.get_current_action_name()
	ur.undo()
	App.status("Undo: " + action_name)


func redo() -> void:
	if not can_redo():
		App.status("Nothing to redo")
		return
	ur.redo()
	App.status("Redo: " + ur.get_current_action_name())


## Records a finished pixel edit. Pixels are already applied, so the action
## is committed without executing it.
func commit_pixels(action_name: String, cel: CelData, rect: Rect2i, before: Image, after: Image) -> void:
	ur.create_action(action_name)
	ur.add_do_method(_apply_region.bind(cel, after, rect.position))
	ur.add_undo_method(_apply_region.bind(cel, before, rect.position))
	ur.commit_action(false)


func _apply_region(cel: CelData, region: Image, pos: Vector2i) -> void:
	var img := cel.get_image()
	img.blit_rect(region, Rect2i(Vector2i.ZERO, region.get_size()), pos)
	cel.mark_changed()
	App.notify_pixels()
