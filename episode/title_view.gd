class_name TitleView
extends Control
## Draws a title card or scrolling credits for an episode entry, animated by
## time. Sizes are relative to the frame height so previews and full-size
## renders look identical.

static var _regular: SystemFont
static var _bold: SystemFont

var entry: Dictionary = {}
var t: float = 0.0
var duration_s: float = 3.0


static func fonts() -> Array:
	if _regular == null:
		_regular = SystemFont.new()
		_regular.font_names = PackedStringArray(ThemeBuilder.FONT_NAMES)
		_bold = SystemFont.new()
		_bold.font_names = PackedStringArray(ThemeBuilder.FONT_NAMES)
		_bold.font_weight = 750
	return [_regular, _bold]


func show_entry(e: Dictionary, local_frame: int, fps: int) -> void:
	entry = e
	t = local_frame / float(maxi(fps, 1))
	duration_s = maxf(0.1, int(e.get("duration", 72)) / float(maxi(fps, 1)))
	queue_redraw()


func _draw() -> void:
	if entry.is_empty():
		return
	var f := fonts()
	var reg: Font = f[0]
	var bold: Font = f[1]
	var h := size.y
	var w := size.x
	var bg := Color.from_string(str(entry.get("bg", "101116ff")), Color.BLACK)
	var fg := Color.from_string(str(entry.get("color", "ffffffff")), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	if str(entry.get("type", "")) == "credits":
		_draw_credits(reg, bold, fg)
		return
	var anim := str(entry.get("animation", "fade"))
	var alpha := 1.0
	var rise := 0.0
	var reveal := 1.0
	var tin := minf(0.6, duration_s * 0.3)
	var tout := minf(0.5, duration_s * 0.25)
	if anim == "fade" or anim == "rise":
		alpha = clampf(t / tin, 0.0, 1.0) * clampf((duration_s - t) / tout, 0.0, 1.0)
	if anim == "rise":
		var k := clampf(t / tin, 0.0, 1.0)
		rise = (1.0 - k * k * (3.0 - 2.0 * k)) * h * 0.05
	if anim == "typewriter":
		reveal = clampf(t / maxf(0.3, duration_s * 0.5), 0.0, 1.0)
		alpha = clampf((duration_s - t) / tout, 0.0, 1.0)
	var col := fg
	col.a *= alpha
	var title := str(entry.get("text", ""))
	var subtitle := str(entry.get("subtitle", ""))
	if reveal < 1.0:
		title = title.substr(0, int(round(title.length() * reveal)))
	var accent := Palette.ACCENT
	accent.a *= alpha
	match str(entry.get("preset", "classic")):
		"bold":
			var fs := int(h * 0.13)
			var y := h * 0.5 + fs * 0.35 + rise
			draw_string_outline(bold, Vector2(0, y), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, fs, int(h * 0.012), Color(0, 0, 0, 0.5 * alpha))
			draw_string(bold, Vector2(0, y), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
			draw_rect(Rect2(w * 0.5 - w * 0.06, y + h * 0.035, w * 0.12, h * 0.008), accent)
			draw_string(reg, Vector2(0, y + h * 0.1), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.045), col)
		"minimal":
			var fs := int(h * 0.065)
			var x := w * 0.08
			var y := h * 0.78 + rise
			draw_string(bold, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, w - x, fs, col)
			draw_string(reg, Vector2(x, y + h * 0.06), subtitle, HORIZONTAL_ALIGNMENT_LEFT, w - x, int(h * 0.035), col)
		"chapter":
			var bar := h * 0.12
			draw_rect(Rect2(0, 0, w, bar), Color(0, 0, 0, 0.85))
			draw_rect(Rect2(0, h - bar, w, bar), Color(0, 0, 0, 0.85))
			draw_string(reg, Vector2(0, h * 0.42 + rise), subtitle.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.035), Color(accent, alpha))
			draw_string(bold, Vector2(0, h * 0.56 + rise), title, HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.1), col)
		_:
			var fs := int(h * 0.09)
			var y := h * 0.5 + rise
			draw_string(bold, Vector2(0, y), title, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
			draw_line(Vector2(w * 0.42, y + h * 0.04), Vector2(w * 0.58, y + h * 0.04), accent, maxf(1.0, h * 0.003))
			draw_string(reg, Vector2(0, y + h * 0.11), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.042), col)


## Credits scroll from below the frame to above it over the entry's duration.
## A line starting with "#" is a heading; an empty line adds space.
func _draw_credits(reg: Font, bold: Font, fg: Color) -> void:
	var h := size.y
	var w := size.x
	var lines := str(entry.get("text", "")).split("\n")
	var line_h := h * 0.06
	var block := lines.size() * line_h
	var travel := h + block
	var y0 := h - (t / duration_s) * travel + line_h
	for i in lines.size():
		var line: String = lines[i]
		var y := y0 + i * line_h
		if y < -line_h or y > h + line_h:
			continue
		if line.begins_with("#"):
			draw_string(bold, Vector2(0, y), line.substr(1).strip_edges(), HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.05), fg)
		elif line.contains(" - "):
			var parts := line.split(" - ", true, 1)
			draw_string(reg, Vector2(0, y), parts[0].strip_edges(), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.48, int(h * 0.036), Color(fg, 0.7))
			draw_string(bold, Vector2(w * 0.52, y), parts[1].strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, w * 0.48, int(h * 0.036), fg)
		else:
			draw_string(reg, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.038), fg)


## Lower thirds, subtitles and captions drawn over a scene.
static func draw_overlay(ci: CanvasItem, rect_size: Vector2, text: String, style: String, alpha: float) -> void:
	if text.strip_edges() == "" or alpha <= 0.0:
		return
	var f := fonts()
	var reg: Font = f[0]
	var bold: Font = f[1]
	var h := rect_size.y
	var w := rect_size.x
	var lines := text.split("\n")
	match style:
		"subtitle":
			var fs := int(h * 0.045)
			var y := h * 0.9 - (lines.size() - 1) * fs * 1.2
			for line in lines:
				ci.draw_string_outline(reg, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, w, fs, int(h * 0.008), Color(0, 0, 0, 0.85 * alpha))
				ci.draw_string(reg, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(1, 1, 1, alpha))
				y += fs * 1.2
		"caption":
			var fs := int(h * 0.04)
			var pad := h * 0.02
			var box_w := w * 0.5
			ci.draw_rect(Rect2(w * 0.05, h * 0.06, box_w, fs * 1.3 * lines.size() + pad * 2), Color(0, 0, 0, 0.6 * alpha))
			var y := h * 0.06 + pad + fs
			for line in lines:
				ci.draw_string(reg, Vector2(w * 0.05 + pad, y), line, HORIZONTAL_ALIGNMENT_LEFT, box_w - pad * 2, fs, Color(1, 1, 1, alpha))
				y += fs * 1.3
		_:
			var name_fs := int(h * 0.05)
			var sub_fs := int(h * 0.032)
			var x := w * 0.06
			var y := h * 0.8
			var bar_w := w * 0.42
			ci.draw_rect(Rect2(x - h * 0.02, y - name_fs * 1.05, bar_w, name_fs * 1.4 + (sub_fs * 1.4 if lines.size() > 1 else 0.0)), Color(0.07, 0.075, 0.09, 0.82 * alpha))
			ci.draw_rect(Rect2(x - h * 0.02, y - name_fs * 1.05, h * 0.008, name_fs * 1.4 + (sub_fs * 1.4 if lines.size() > 1 else 0.0)), Color(Palette.ACCENT, alpha))
			ci.draw_string(bold, Vector2(x, y), lines[0], HORIZONTAL_ALIGNMENT_LEFT, bar_w, name_fs, Color(1, 1, 1, alpha))
			if lines.size() > 1:
				ci.draw_string(reg, Vector2(x, y + sub_fs * 1.35), lines[1], HORIZONTAL_ALIGNMENT_LEFT, bar_w, sub_fs, Color(1, 1, 1, 0.8 * alpha))
