class_name CelData
extends RefCounted
## One drawing ("cel"). Pixels live in an Image that is loaded lazily from
## disk and can be unloaded again, so long projects don't have to keep every
## drawing in memory. `dirty` marks pixels that still need to be written.

var id: String = ""
var image: Image = null
var texture: ImageTexture = null
var file_path: String = ""
var dirty: bool = false
var missing: bool = false
var _texture_stale: bool = false


func _init(p_id: String = "") -> void:
	id = p_id if p_id != "" else Ids.make()


static func create_blank(w: int, h: int) -> CelData:
	var c := CelData.new()
	c.image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	c.image.fill(Color(0, 0, 0, 0))
	c.dirty = true
	return c


func is_loaded() -> bool:
	return image != null


func get_image() -> Image:
	if image == null:
		var w: int = App.project.width
		var h: int = App.project.height
		if file_path != "" and FileAccess.file_exists(file_path):
			var img := Image.load_from_file(file_path)
			if img != null and not img.is_empty():
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)
				if img.get_width() != w or img.get_height() != h:
					# Canvas size changed since this was drawn: keep it anchored top-left.
					var fitted := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
					fitted.fill(Color(0, 0, 0, 0))
					var copy_size := Vector2i(mini(w, img.get_width()), mini(h, img.get_height()))
					fitted.blit_rect(img, Rect2i(Vector2i.ZERO, copy_size), Vector2i.ZERO)
					img = fitted
				image = img
		if image == null:
			missing = file_path != ""
			image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
			image.fill(Color(0, 0, 0, 0))
		_texture_stale = true
	return image


func get_texture() -> ImageTexture:
	var img := get_image()
	if texture == null:
		texture = ImageTexture.create_from_image(img)
		_texture_stale = false
	elif _texture_stale:
		if texture.get_width() == img.get_width() and texture.get_height() == img.get_height():
			texture.update(img)
		else:
			texture.set_image(img)
		_texture_stale = false
	return texture


## Call after editing `image` pixels.
func mark_changed() -> void:
	dirty = true
	_texture_stale = true


## Frees pixel memory if the drawing is safely on disk. Returns true if unloaded.
func unload() -> bool:
	if dirty or file_path == "" or image == null:
		return false
	image = null
	texture = null
	return true


func clone() -> CelData:
	var c := CelData.new()
	c.image = get_image().duplicate() as Image
	c.dirty = true
	return c
