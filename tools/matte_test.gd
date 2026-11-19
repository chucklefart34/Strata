extends SceneTree
## CI diagnostic: runs MatteProcessor (the real GPU passes) on synthetic
## frames for every background-removal mode, prints how much background was
## removed and how much subject was kept, and saves the results as PNGs.

const W := 640
const H := 360
var out_dir := "user://matte_test"


func _initialize() -> void:
	_run.call_deferred()


func frame(bg: String, t: float) -> Image:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var c: Color
			match bg:
				"green":
					c = Color(0.1, 0.75, 0.2)
				"white":
					c = Color(0.95, 0.95, 0.95)
				"black":
					c = Color(0.03, 0.03, 0.04)
				_:
					# textured room: gradient + stripes + a "window"
					var s := 0.5 + 0.5 * sin(x * 0.05) * sin(y * 0.03)
					c = Color(0.35 + 0.25 * s, 0.45 + 0.1 * float(y) / H, 0.6 - 0.2 * s)
					if x > 420 and x < 560 and y > 40 and y < 160:
						c = Color(0.85, 0.9, 1.0)
			img.set_pixel(x, y, c)
	var cx := 180.0 + 260.0 * t
	var cy := 200.0
	for y in H:
		for x in W:
			var d := Vector2(x - cx, (y - cy) * 0.8).length()
			if d < 70.0:
				var c := Color(0.85, 0.35, 0.15) if int(y / 12) % 2 == 0 else Color(0.6, 0.2, 0.35)
				img.set_pixel(x, y, c)
	return img


func stats(img: Image, t: float) -> Vector2:
	var cx := 180.0 + 260.0 * t
	var cy := 200.0
	var bg_a := 0.0
	var bg_n := 0
	var fg_a := 0.0
	var fg_n := 0
	for y in range(0, H, 3):
		for x in range(0, W, 3):
			var d := Vector2(x - cx, (y - cy) * 0.8).length()
			var a := img.get_pixel(x, y).a
			if d < 55.0:
				fg_a += a
				fg_n += 1
			elif d > 90.0:
				bg_a += a
				bg_n += 1
	return Vector2(1.0 - bg_a / maxf(1, bg_n), fg_a / maxf(1, fg_n))


func save(img: Image, label: String) -> void:
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var shown := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	shown.fill(Color(1, 0, 1))
	shown.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	shown.save_png(out_dir.path_join(label + ".png"))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("MATTE TEST renderer=", RenderingServer.get_current_rendering_method(), " driver=", RenderingServer.get_current_rendering_driver_name(), " gpu=", RenderingServer.get_video_adapter_name())
	var m := MatteProcessor.new()
	root.add_child(m)
	var base := {"threshold": 0.12, "softness": 0.06, "cleanup": 2.0, "grow": 0.0, "crop": false, "invert": false, "spill": 0.6, "key_color": Color(0.1, 0.75, 0.2), "feather": 0.0, "edge_detail": 0.7}
	var cases := [
		["background", "room"], ["colour", "green"], ["light", "white"], ["dark", "black"], ["auto", "room"], ["auto", "green"], ["object", "room"],
	]
	for c in cases:
		var mode: String = c[0]
		var bg: String = c[1]
		var s := base.duplicate()
		s["mode"] = mode
		if mode == "light":
			s["threshold"] = 1.0 - 0.12 * 1.2
		elif mode == "dark":
			s["threshold"] = 0.12 * 1.2
		elif mode == "auto" or mode == "object":
			s["threshold"] = 0.26 + 12.0 * 0.02
		var src := frame(bg, 0.5)
		save(src, "%s_%s_in" % [mode, bg])
		if mode == "background":
			var plates := []
			for i in 9:
				plates.append(frame(bg, float(i) / 8.0))
			await m.build_plate(plates)
			save(m._plate_tex.get_image(), "background_plate")
		m.setup(W, H, s)
		if mode == "auto":
			var tr := SubjectTracker.new()
			tr.build_auto_model(src)
			var mask := tr.support_mask(src, Rect2(0, 0, 1, 1), float(s["threshold"]), false)
			save(mask, "auto_%s_mask" % bg)
			m.set_subject(tr.lut_image, mask)
		elif mode == "object":
			var tr2 := SubjectTracker.new()
			tr2.set_key(0.0, Rect2(0.37, 0.3, 0.23, 0.48))
			tr2.build_model(func(_t: float) -> Image: return src)
			var mask2 := tr2.support_mask(src, tr2.box_at(0.0), float(s["threshold"]))
			save(mask2, "object_room_mask")
			m.set_subject(tr2.lut_image, mask2)
		var out := await m.process(src.duplicate() as Image)
		if out == null:
			print("MATTE %s/%s: process returned null" % [mode, bg])
			continue
		var st := stats(out, 0.5)
		save(out, "%s_%s_out" % [mode, bg])
		print("MATTE %-10s on %-5s  out=%s fmt=%d  background removed=%3d%%  subject kept=%3d%%" % [mode, bg, out.get_size(), out.get_format(), int(st.x * 100), int(st.y * 100)])
	# rotoscope a cut-out: the transparency must survive the toon passes
	var s2 := base.duplicate()
	s2["mode"] = "colour"
	m.setup(W, H, s2)
	var cut := await m.process(frame("green", 0.5))
	var toon := ToonProcessor.new()
	root.add_child(toon)
	toon.setup(W, H, {"simplify": 7, "smooth": 6, "thickness": 2.0, "trace": true})
	var tout := await toon.process(cut.duplicate() as Image)
	var tst := stats(tout, 0.5)
	save(tout, "roto_on_cutout_out")
	print("MATTE roto on cut-out          background removed=%3d%%  subject kept=%3d%%" % [int(tst.x * 100), int(tst.y * 100)])
	print("MATTE TEST done, files in ", ProjectSettings.globalize_path(out_dir))
	quit()
