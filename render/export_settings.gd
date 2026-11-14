class_name ExportSettings
extends RefCounted
## CapCut-style export choices (resolution, frame rate, quality, format) and
## the FFmpeg command that turns rendered PNG frames into the final file.
##
## Options dictionary used everywhere:
##   name: String            file name without extension
##   dir: String             folder the file goes in
##   res: int                short side in pixels (480, 720, 1080, 1440, 2160), 0 = project
##   fps: int                output frame rate, 0 = project
##   quality: String         "lower", "recommended", "higher"
##   format: String          "mp4", "mov", "gif", "png"
##   transparent: bool       PNG frames only
##   audio: bool             include the sound

const RESOLUTIONS := [[480, "480p"], [720, "720p"], [1080, "1080p"], [1440, "2K"], [2160, "4K"]]
const FRAME_RATES := [12, 24, 25, 30, 50, 60]
const QUALITIES := [["lower", "Lower"], ["recommended", "Recommended"], ["higher", "Higher"]]
const FORMATS := [["mp4", "MP4"], ["mov", "MOV"], ["gif", "GIF"], ["png", "PNG frames"]]
## H.264 bits per pixel per frame for each quality (≈ 5 / 9 / 16 Mbps at 1080p30).
const BPP := {"lower": 0.08, "recommended": 0.15, "higher": 0.26}
const AUDIO_BPS := 192000


static func defaults() -> Dictionary:
	return {"name": "", "dir": "", "res": 0, "fps": 0, "quality": "recommended", "format": "mp4", "transparent": false, "audio": true}


## Output size: the project's shape, scaled so its short side is `res`.
static func output_size(o: Dictionary) -> Vector2i:
	var p: ProjectData = App.project
	var res := int(o.get("res", 0))
	if res <= 0:
		return Vector2i(p.width, p.height)
	var short_side := float(mini(p.width, p.height))
	var k := float(res) / short_side
	var w := int(round(p.width * k / 2.0)) * 2
	var h := int(round(p.height * k / 2.0)) * 2
	return Vector2i(maxi(2, w), maxi(2, h))


static func output_fps(o: Dictionary) -> int:
	var f := int(o.get("fps", 0))
	return f if f > 0 else App.project.fps


static func extension(o: Dictionary) -> String:
	return str(o.get("format", "mp4"))


static func video_bitrate(o: Dictionary) -> int:
	var sz := output_size(o)
	var bpp: float = BPP.get(str(o.get("quality", "recommended")), 0.15)
	return int(sz.x * sz.y * output_fps(o) * bpp)


## Rough file size in bytes for `frames` frames at the project frame rate.
static func estimate_bytes(o: Dictionary, frames: int, has_audio: bool) -> int:
	var secs := float(frames) / maxf(1.0, App.project.fps)
	var sz := output_size(o)
	match str(o.get("format", "mp4")):
		"gif":
			return int(sz.x * sz.y * secs * output_fps(o) * 0.12)
		"png":
			return int(sz.x * sz.y * 1.4 * frames)
	var bits := float(video_bitrate(o)) * secs
	if has_audio and bool(o.get("audio", true)):
		bits += AUDIO_BPS * secs
	return int(bits / 8.0)


static func human_size(bytes: int) -> String:
	if bytes >= 1024 * 1024 * 1024:
		return "%.1f GB" % (bytes / 1073741824.0)
	if bytes >= 1024 * 1024:
		return "%.0f MB" % (bytes / 1048576.0)
	return "%.0f KB" % maxf(1.0, bytes / 1024.0)


static func human_time(frames: int) -> String:
	var secs := float(frames) / maxf(1.0, App.project.fps)
	var m := int(secs) / 60
	return "%d:%04.1f" % [m, secs - m * 60]


## FFmpeg arguments turning a PNG sequence (rendered at `in_fps`) and an
## optional WAV into the chosen file.
static func ffmpeg_args(pattern: String, in_fps: int, wav: String, o: Dictionary, out_file: String) -> PackedStringArray:
	var sz := output_size(o)
	var fps := output_fps(o)
	var fmt := str(o.get("format", "mp4"))
	var args := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error", "-framerate", str(in_fps), "-i", pattern])
	var use_audio := wav != "" and bool(o.get("audio", true)) and fmt != "gif"
	if use_audio:
		args.append_array(PackedStringArray(["-i", wav]))
	var vf := "scale=%d:%d:flags=lanczos" % [sz.x, sz.y]
	if fps != in_fps:
		vf += ",fps=%d" % fps
	if fmt == "gif":
		var gw := mini(sz.x, 960)
		args.append_array(PackedStringArray([
			"-filter_complex",
			"[0:v]fps=%d,scale=%d:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" % [mini(fps, 25), gw],
			"-loop", "0",
		]))
	else:
		var br := video_bitrate(o)
		args.append_array(PackedStringArray([
			"-vf", vf + ",pad=ceil(iw/2)*2:ceil(ih/2)*2",
			"-c:v", "libx264", "-preset", "medium", "-profile:v", "high",
			"-b:v", str(br), "-maxrate", str(int(br * 1.5)), "-bufsize", str(br * 2),
			"-pix_fmt", "yuv420p", "-r", str(fps),
		]))
		if fmt == "mp4" or fmt == "mov":
			args.append_array(PackedStringArray(["-movflags", "+faststart"]))
		if use_audio:
			args.append_array(PackedStringArray(["-c:a", "aac", "-b:a", "192k", "-shortest"]))
	args.append(out_file)
	return args


## Video formats need FFmpeg; on iPhone/iPad (and without FFmpeg) only PNG frames.
static func can_encode_video() -> bool:
	return Platform.can_run_programs() and RenderExporter.find_ffmpeg() != ""
