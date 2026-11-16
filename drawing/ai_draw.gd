class_name AiDraw
extends Node
## Draws a picture from a text prompt with an online or local image model.
## Your own drawings guide it:
##   - a sketch on the frame being drawn sets the pose and layout,
##   - your other keyframes on the layer keep the character and style the same,
##   - for in-betweens, the two keyframes around the frame are blended.
## Services:
##   openai     — OpenAI Images (gpt-image models): text, or text + images
##   stability  — Stability AI: Control Sketch (with a sketch) / Core (text)
##   local      — Automatic1111 / Forge web UI started with --api (free, on
##                your own computer): txt2img / img2img
## Keys are kept in this computer's settings, never in project files.

const SERVICES := ["openai", "stability", "local"]
const SERVICE_LABELS := ["OpenAI (GPT Image)", "Stability AI", "My computer (Automatic1111 / Forge)"]
const STYLES := ["lines", "colour", "colour_cut"]
const STYLE_LABELS := ["Line art (see-through)", "Coloured drawing", "Coloured, no background"]
const STYLE_TEXT := {
	"lines": "Clean black ink line art on a plain pure white background, hand-drawn 2D animation style, confident even outlines, no shading, no colour, no text.",
	"colour": "Hand-drawn 2D animation frame, clean ink outlines with flat cel colours, no text.",
	"colour_cut": "Hand-drawn 2D animation drawing of the subject only, clean ink outlines with flat cel colours, on a plain pure white background, no text.",
}

var last_error: String = ""
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 240.0
	_http.use_threads = true
	add_child(_http)


static func service() -> String:
	return str(ProjectIO.get_setting("ai_service", "openai"))


static func setting(key: String, default: String = "") -> String:
	return str(ProjectIO.get_setting("ai_" + key, default))


## How detailed the prompt is: 0 short, 1 medium, 2 long. More words → a
## higher quality setting (more detail, slower, costs more).
static func detail_level(prompt: String) -> int:
	var words := prompt.strip_edges().split(" ", false).size()
	if words >= 40:
		return 2
	if words >= 12:
		return 1
	return 0


## Draws one picture.
## `sketch`: the drawing on this frame (or null). `refs`: other keyframes of
## the same thing (up to 2). `blend`: for an in-between, [image_a, image_b, t].
## `follow`: 0..1, how closely to follow the sketch. Returns a canvas-sized
## RGBA image, or null with `last_error` set.
func generate(prompt: String, style: String, sketch: Image, refs: Array, blend: Array, follow: float, w: int, h: int) -> Image:
	last_error = ""
	var full := prompt.strip_edges()
	if full == "":
		last_error = "Type what to draw first."
		return null
	var detail := detail_level(full)
	full += "\n\n" + str(STYLE_TEXT.get(style, ""))
	var out: Image = null
	match service():
		"openai":
			out = await _openai(full, sketch, refs, blend, follow, detail, w, h)
		"stability":
			out = await _stability(full, sketch, refs, blend, follow, detail, w, h)
		_:
			out = await _local(full, sketch, refs, blend, follow, detail, w, h)
	if out == null:
		return null
	out.convert(Image.FORMAT_RGBA8)
	match style:
		"lines":
			out = to_line_art(out)
		"colour_cut":
			out = cut_white_background(out)
	return out


# ================================================================ OpenAI

func _openai(prompt: String, sketch: Image, refs: Array, blend: Array, follow: float, detail: int, w: int, h: int) -> Image:
	var key := setting("key_openai")
	if key == "":
		last_error = "Add your OpenAI API key under Service."
		return null
	var model := setting("model_openai", "gpt-image-1.5")
	var size := Vector2i(1024, 1024)
	var aspect := float(w) / float(h)
	if aspect > 1.15:
		size = Vector2i(1536, 1024)
	elif aspect < 0.87:
		size = Vector2i(1024, 1536)
	var quality: String = ["low", "medium", "high"][detail]
	var images: Array = []  # [Image]
	var notes: Array = []
	if not blend.is_empty():
		images.append(blend[0])
		images.append(blend[1])
		var pct := int(round(float(blend[2]) * 100.0))
		notes.append("Image 1 and image 2 are two hand-drawn keyframes of an animation. Draw the in-between frame that sits %d%% of the way from image 1 to image 2: same character, same design, same line style and framing, with the pose and positions moved %d%% of the way." % [pct, pct])
	else:
		if sketch != null:
			images.append(sketch)
			if follow >= 0.66:
				notes.append("Image 1 is my rough sketch of this frame. Trace over it closely: keep the exact pose, proportions, positions and framing, and only clean up and add the detail described.")
			elif follow >= 0.33:
				notes.append("Image 1 is my rough sketch of this frame. Keep its pose, layout and framing, and finish it with the detail described.")
			else:
				notes.append("Image 1 is a loose sketch of this frame. Use it as a guide for the layout; you may improve the drawing.")
		for r in refs:
			images.append(r)
		if not refs.is_empty():
			var first := 2 if sketch != null else 1
			notes.append("Image %d%s %s my other keyframes of the same scene. Keep the character design, colours and drawing style consistent with them." % [first, "" if refs.size() == 1 else " onward", "is one of" if refs.size() == 1 else "are"])
	var full := prompt
	if not notes.is_empty():
		full = " ".join(notes) + "\n\n" + prompt
	var rect := Rect2i()
	var body: PackedByteArray
	var headers := PackedStringArray(["Authorization: Bearer " + key])
	var url := "https://api.openai.com/v1/images/generations"
	if images.is_empty():
		headers.append("Content-Type: application/json")
		body = JSON.stringify({"model": model, "prompt": full, "size": "%dx%d" % [size.x, size.y], "quality": quality, "n": 1}).to_utf8_buffer()
	else:
		url = "https://api.openai.com/v1/images/edits"
		var mp := Multipart.new()
		mp.field("model", model)
		mp.field("prompt", full)
		mp.field("size", "%dx%d" % [size.x, size.y])
		mp.field("quality", quality)
		mp.field("n", "1")
		for i in images.size():
			var fitted := fit_into(images[i], size.x, size.y)
			if i == 0:
				rect = fitted[1]
			var fimg: Image = fitted[0]
			mp.file("image[]", "image%d.png" % i, fimg.save_png_to_buffer())
		headers.append("Content-Type: multipart/form-data; boundary=" + mp.boundary)
		body = mp.finish()
	var res := await _post(url, headers, body)
	if res.is_empty():
		return null
	var data: Variant = JSON.parse_string(res[1].get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		last_error = "OpenAI sent back something unexpected."
		return null
	var d: Dictionary = data
	var list: Array = d.get("data", [])
	if list.is_empty():
		last_error = "OpenAI returned no picture."
		return null
	var item: Dictionary = list[0]
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(str(item.get("b64_json", "")))) != OK:
		last_error = "Couldn't read the picture OpenAI sent."
		return null
	if rect.size == Vector2i.ZERO:
		rect = fit_rect(w, h, size.x, size.y)
	return _uncrop(img, rect, size, w, h)


# ================================================================ Stability

func _stability(prompt: String, sketch: Image, refs: Array, blend: Array, follow: float, detail: int, w: int, h: int) -> Image:
	var key := setting("key_stability")
	if key == "":
		last_error = "Add your Stability AI API key under Service."
		return null
	var guide: Image = sketch
	var strength := lerpf(0.35, 0.9, follow)
	if not blend.is_empty():
		guide = mix_images(blend[0], blend[1], float(blend[2]), 1024)
		strength = 0.75
	elif guide == null and not refs.is_empty():
		guide = refs[0]
		strength = 0.35  # only a loose hint from another keyframe
	var mp := Multipart.new()
	mp.field("prompt", prompt)
	mp.field("output_format", "png")
	var url: String
	var size := Vector2i.ZERO
	var rect := Rect2i()
	if guide != null:
		url = "https://api.stability.ai/v2beta/stable-image/control/sketch"
		size = Vector2i(1024, int(round(1024.0 * h / w / 64.0)) * 64) if w >= h else Vector2i(int(round(1024.0 * w / h / 64.0)) * 64, 1024)
		var fitted := fit_into(guide, size.x, size.y)
		rect = fitted[1]
		var gimg: Image = fitted[0]
		mp.file("image", "sketch.png", gimg.save_png_to_buffer())
		mp.field("control_strength", "%.2f" % strength)
	else:
		url = "https://api.stability.ai/v2beta/stable-image/generate/" + ("ultra" if detail == 2 else "core")
		mp.field("aspect_ratio", _stability_aspect(w, h))
	var headers := PackedStringArray(["Authorization: Bearer " + key, "Accept: image/*", "Content-Type: multipart/form-data; boundary=" + mp.boundary])
	var res := await _post(url, headers, mp.finish())
	if res.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(res[1]) != OK:
		last_error = "Couldn't read the picture Stability sent."
		return null
	if guide == null:
		return _cover(img, w, h)
	return _uncrop(img, rect, size, w, h)


static func _stability_aspect(w: int, h: int) -> String:
	var a := float(w) / float(h)
	var best := "1:1"
	var best_d := 99.0
	for r in ["21:9", "16:9", "3:2", "5:4", "1:1", "4:5", "2:3", "9:16", "9:21"]:
		var p: PackedStringArray = str(r).split(":")
		var d := absf(log(float(p[0]) / float(p[1])) - log(a))
		if d < best_d:
			best_d = d
			best = r
	return best


# ================================================================ local (A1111 / Forge)

func _local(prompt: String, sketch: Image, refs: Array, blend: Array, follow: float, detail: int, w: int, h: int) -> Image:
	var base := setting("url_local", "http://127.0.0.1:7860").strip_edges().trim_suffix("/")
	var steps: int = [20, 28, 36][detail]
	var size := Vector2i(1024, int(round(1024.0 * h / w / 64.0)) * 64) if w >= h else Vector2i(int(round(1024.0 * w / h / 64.0)) * 64, 1024)
	var init: Image = sketch
	var denoise := lerpf(0.85, 0.4, follow)
	if not blend.is_empty():
		init = mix_images(blend[0], blend[1], float(blend[2]), 1024)
		denoise = 0.5
	elif init == null and not refs.is_empty():
		init = refs[0]
		denoise = 0.8
	var payload := {
		"prompt": prompt,
		"negative_prompt": "text, watermark, signature, blurry, photo, 3d render",
		"steps": steps, "cfg_scale": 6.5, "width": size.x, "height": size.y, "seed": -1,
	}
	var url := base + "/sdapi/v1/txt2img"
	var rect := fit_rect(w, h, size.x, size.y)
	if init != null:
		url = base + "/sdapi/v1/img2img"
		var fitted := fit_into(init, size.x, size.y)
		rect = fitted[1]
		var iimg: Image = fitted[0]
		payload["init_images"] = [Marshalls.raw_to_base64(iimg.save_png_to_buffer())]
		payload["denoising_strength"] = denoise
	var res := await _post(url, PackedStringArray(["Content-Type: application/json"]), JSON.stringify(payload).to_utf8_buffer())
	if res.is_empty():
		if last_error.begins_with("Couldn't connect"):
			last_error = "Couldn't reach %s. Start Automatic1111 or Forge with the --api option, or change the address under Service." % base
		return null
	var data: Variant = JSON.parse_string(res[1].get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		last_error = "The local service sent back something unexpected."
		return null
	var d: Dictionary = data
	var list: Array = d.get("images", [])
	if list.is_empty():
		last_error = "The local service returned no picture."
		return null
	var b64 := str(list[0])
	if b64.contains(","):
		b64 = b64.get_slice(",", 1)
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(b64)) != OK:
		last_error = "Couldn't read the picture the local service sent."
		return null
	return _uncrop(img, rect, size, w, h)


# ================================================================ HTTP

## Returns [code, body] or [] with last_error set.
func _post(url: String, headers: PackedStringArray, body: PackedByteArray) -> Array:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	var err := _http.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		last_error = "Couldn't start the request (error %d)." % err
		return []
	var res: Array = await _http.request_completed
	var result: int = res[0]
	var code: int = res[1]
	var rbody: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		last_error = "Couldn't connect" + (" (timed out)." if result == HTTPRequest.RESULT_TIMEOUT else " (network error %d)." % result)
		return []
	if code < 200 or code >= 300:
		last_error = "The service said no (%d): %s" % [code, _error_text(rbody)]
		return []
	return [code, rbody]


static func _error_text(body: PackedByteArray) -> String:
	var txt := body.get_string_from_utf8()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		var e: Variant = d.get("error", d.get("errors", d.get("message", d.get("detail", ""))))
		if typeof(e) == TYPE_DICTIONARY:
			var ed: Dictionary = e
			return str(ed.get("message", ed))
		if typeof(e) == TYPE_ARRAY:
			var ea: Array = e
			return ", ".join(PackedStringArray(ea.map(func(x: Variant) -> String: return str(x))))
		return str(e)
	return txt.left(200)


class Multipart:
	var boundary: String = "----StrataBoundary%d" % randi()
	var _buf := PackedByteArray()

	func field(field_name: String, value: String) -> void:
		_buf.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, field_name, value]).to_utf8_buffer())

	func file(field_name: String, file_name: String, data: PackedByteArray) -> void:
		_buf.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: image/png\r\n\r\n" % [boundary, field_name, file_name]).to_utf8_buffer())
		_buf.append_array(data)
		_buf.append_array("\r\n".to_utf8_buffer())

	func finish() -> PackedByteArray:
		var out := _buf.duplicate()
		out.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
		return out


# ================================================================ images

## A drawing (transparent background) flattened onto white.
static func flatten(img: Image) -> Image:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color.WHITE)
	out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	return out


## Where a w×h picture sits when fitted (letterboxed) into tw×th.
static func fit_rect(w: int, h: int, tw: int, th: int) -> Rect2i:
	var k := minf(float(tw) / w, float(th) / h)
	var sz := Vector2i(maxi(1, int(round(w * k))), maxi(1, int(round(h * k))))
	return Rect2i((Vector2i(tw, th) - sz) / 2, sz)


## [white tw×th image with `img` flattened and fitted inside, the rect].
static func fit_into(img: Image, tw: int, th: int) -> Array:
	var flat := flatten(img)
	var r := fit_rect(flat.get_width(), flat.get_height(), tw, th)
	flat.resize(r.size.x, r.size.y, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	out.fill(Color.WHITE)
	out.blit_rect(flat, Rect2i(Vector2i.ZERO, r.size), r.position)
	return [out, r]


## Cuts the fitted area back out of a result and scales it to the canvas.
static func _uncrop(img: Image, rect: Rect2i, sent: Vector2i, w: int, h: int) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	if img.get_size() != sent:
		img.resize(sent.x, sent.y, Image.INTERPOLATE_LANCZOS)
	var out := img.get_region(rect)
	out.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return out


## Scales to cover w×h and crops the middle.
static func _cover(img: Image, w: int, h: int) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	var k := maxf(float(w) / img.get_width(), float(h) / img.get_height())
	img.resize(maxi(w, int(ceil(img.get_width() * k))), maxi(h, int(ceil(img.get_height() * k))), Image.INTERPOLATE_LANCZOS)
	return img.get_region(Rect2i((img.get_size() - Vector2i(w, h)) / 2, Vector2i(w, h)))


## Cross-fade of two drawings (flattened on white), longest side `max_side`.
static func mix_images(a: Image, b: Image, t: float, max_side: int) -> Image:
	var fa := flatten(a)
	var fb := flatten(b)
	var k := minf(1.0, float(max_side) / maxi(fa.get_width(), fa.get_height()))
	var sz := Vector2i(maxi(1, int(fa.get_width() * k)), maxi(1, int(fa.get_height() * k)))
	fa.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
	fb.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
	var da := fa.get_data()
	var db := fb.get_data()
	var wa := int(round((1.0 - t) * 256.0))
	var wb := 256 - wa
	for i in da.size():
		da[i] = (da[i] * wa + db[i] * wb) >> 8
	return Image.create_from_data(sz.x, sz.y, false, Image.FORMAT_RGBA8, da)


## Black-on-white picture → black lines on a see-through background
## (darkness becomes opacity, so soft edges stay smooth).
static func to_line_art(img: Image) -> Image:
	var g := img.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	var lum := g.get_data()
	var out := PackedByteArray()
	out.resize(lum.size() * 2)  # LA8, zero = black
	for i in lum.size():
		# white (≥ 235) → clear; dark (≤ 60) → solid
		out[i * 2 + 1] = clampi((235 - lum[i]) * 255 / 175, 0, 255)
	var la := Image.create_from_data(g.get_width(), g.get_height(), false, Image.FORMAT_LA8, out)
	la.convert(Image.FORMAT_RGBA8)
	return la


## Removes the white background around a coloured drawing: near-white areas
## connected to the edge of the picture become see-through.
static func cut_white_background(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var k := minf(1.0, 480.0 / w)
	var sw := maxi(2, int(w * k))
	var sh := maxi(2, int(h * k))
	var small := img.duplicate() as Image
	small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var px := small.get_data()  # RGBA8
	var bg := PackedByteArray()
	bg.resize(sw * sh)
	var queue := PackedInt32Array()
	for x in sw:
		queue.append(x)
		queue.append((sh - 1) * sw + x)
	for y in sh:
		queue.append(y * sw)
		queue.append(y * sw + sw - 1)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		if bg[p] != 0:
			continue
		var o := p * 4
		if mini(px[o], mini(px[o + 1], px[o + 2])) < 228:
			continue
		bg[p] = 255
		var x := p % sw
		var y := p / sw
		if x > 0:
			queue.append(p - 1)
		if x < sw - 1:
			queue.append(p + 1)
		if y > 0:
			queue.append(p - sw)
		if y < sh - 1:
			queue.append(p + sw)
	var mask := Image.create_from_data(sw, sh, false, Image.FORMAT_L8, bg)
	mask.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var m := mask.get_data()
	var data := img.get_data()
	for i in m.size():
		data[i * 4 + 3] = mini(data[i * 4 + 3], 255 - m[i])
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
