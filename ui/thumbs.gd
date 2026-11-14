class_name Thumbs
extends RefCounted
## Small flattened previews of a scene frame (for scene cards).


static func scene_frame(scene: SceneData, frame: int, w: int, h: int) -> ImageTexture:
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.fill(scene.bg_color)
	for layer in scene.layers:
		if not layer.visible or layer.is_reference() or layer.is_character():
			continue
		var cel := layer.cel_at(frame)
		if cel == null:
			continue
		var small := cel.get_image().duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		if layer.opacity < 0.999:
			var faded := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
			faded.fill(Color(0, 0, 0, 0))
			# Scale alpha by layer opacity through a blend onto transparent.
			for y in h:
				for x in w:
					var c := small.get_pixel(x, y)
					c.a *= layer.opacity
					faded.set_pixel(x, y, c)
			small = faded
		out.blend_rect(small, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return ImageTexture.create_from_image(out)
