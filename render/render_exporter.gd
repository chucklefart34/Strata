class_name RenderExporter
extends Node
## Renders the current scene through its animated camera, frame by frame,
## into a PNG sequence at project resolution. If FFmpeg is available (next to
## the app or on PATH) it can also encode an MP4 — the user never has to run
## FFmpeg themselves.

signal progress(done: int, total: int, message: String)
signal finished(ok: bool, message: String, output_dir: String)

var busy: bool = false
var _cancel: bool = false
var _thread: Thread
var _was_low_processor: bool = true


func cancel() -> void:
	_cancel = true


static func find_ffmpeg() -> String:
	var found := FFmpeg.find()
	if found == "":
		found = FFmpeg.find(true)  # look again: it may have been installed since
	return found


func render_scene(depth: DepthView, out_dir: String, transparent: bool, make_mp4: bool) -> void:
	if busy or not App.has_project():
		return
	busy = true
	_cancel = false
	var p: ProjectData = App.project
	var s := App.current_scene()
	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK:
		busy = false
		finished.emit(false, "Could not create the output folder (%s)" % error_string(err), out_dir)
		return

	var vp := SubViewport.new()
	vp.size = Vector2i(p.width, p.height)
	vp.world_3d = depth.world
	vp.transparent_bg = transparent
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.cull_mask = DepthView.ART_MASK  # set + drawings — no grid, frustum or gizmos
	# Same ambient light as the stage, with the scene background.
	cam.environment = depth.make_environment(s.bg_color, transparent)
	vp.add_child(cam)
	cam.current = true

	var was_frame: int = App.frame
	App.stop()
	_was_low_processor = OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false  # draw every frame while rendering
	var total := s.frame_count
	var base := s.name.validate_filename().replace(" ", "_")
	if base == "":
		base = "scene"
	for f in total:
		if _cancel:
			break
		App.set_frame(f)
		depth.refresh()
		depth.apply_scene_camera(cam, f, false)
		await RenderingServer.frame_post_draw
		if Rigs.count() > 0:
			# Character viewports render in the same frame; wait one more to be safe.
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path := out_dir.path_join("%s_%05d.png" % [base, f + 1])
		if img.save_png(path) != OK:
			_cleanup(vp, was_frame)
			finished.emit(false, "Could not write " + path, out_dir)
			return
		progress.emit(f + 1, total, "Rendering frame %d of %d" % [f + 1, total])
	_cleanup(vp, was_frame)
	if _cancel:
		finished.emit(false, "Render cancelled", out_dir)
		return

	# Scene audio is always mixed next to the frames (and muxed into the MP4).
	var wav := out_dir.path_join(base + ".wav")
	var has_audio := false
	if not s.audio_tracks.is_empty():
		busy = true
		progress.emit(total, total, "Mixing audio…")
		has_audio = await Audio.mixdown(s, wav)
	busy = false
	if not make_mp4:
		finished.emit(true, "Rendered %d frames%s" % [total, " + audio (WAV)" if has_audio else ""], out_dir)
		return
	var ffmpeg := find_ffmpeg()
	if ffmpeg == "":
		finished.emit(true, "Rendered %d PNG frames. MP4 skipped: FFmpeg was not found — set its location in Home → Interface → FFmpeg." % total, out_dir)
		return
	busy = true
	progress.emit(total, total, "Encoding MP4…")
	var mp4 := out_dir.path_join(base + ".mp4")
	var args := PackedStringArray(["-y", "-framerate", str(p.fps), "-i", out_dir.path_join(base + "_%05d.png")])
	if has_audio:
		args.append_array(PackedStringArray(["-i", wav]))
	args.append_array(PackedStringArray([
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
		"-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
	]))
	if has_audio:
		args.append_array(PackedStringArray(["-c:a", "aac", "-b:a", "192k"]))
	args.append(mp4)
	_thread = Thread.new()
	_thread.start(_run_ffmpeg.bind(ffmpeg, args))
	while _thread.is_alive():
		await get_tree().create_timer(0.2).timeout
	var code: int = _thread.wait_to_finish()
	_thread = null
	busy = false
	if code == 0:
		finished.emit(true, "Rendered %d frames and encoded %s%s" % [total, mp4.get_file(), " with audio" if has_audio else ""], out_dir)
	else:
		finished.emit(false, "PNG frames rendered, but FFmpeg failed (exit code %d)" % code, out_dir)


## CapCut-style export: renders the scene at the chosen size, then encodes
## the chosen format at the chosen frame rate and quality (see ExportSettings).
## `finished` reports the file (or, for PNG frames, the folder) it made.
func export_scene(depth: DepthView, o: Dictionary) -> void:
	if busy or not App.has_project():
		return
	busy = true
	_cancel = false
	var p: ProjectData = App.project
	var s := App.current_scene()
	var fmt := ExportSettings.extension(o)
	var dir := str(o.get("dir", ""))
	var fname := str(o.get("name", "")).validate_filename()
	if fname == "":
		fname = "export"
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		busy = false
		finished.emit(false, "Could not create the folder " + dir, dir)
		return
	var out_file := unique_path(dir, fname, "" if fmt == "png" else "." + fmt)
	var frames_dir := out_file if fmt == "png" else dir.path_join(".strata_frames_%d" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var sz := ExportSettings.output_size(o)
	var transparent := fmt == "png" and bool(o.get("transparent", false))

	var vp := SubViewport.new()
	vp.size = sz
	vp.world_3d = depth.world
	vp.transparent_bg = transparent
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.cull_mask = DepthView.ART_MASK
	cam.environment = depth.make_environment(s.bg_color, transparent)
	vp.add_child(cam)
	cam.current = true

	var was_frame: int = App.frame
	App.stop()
	_was_low_processor = OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var total := s.frame_count
	for f in total:
		if _cancel:
			break
		App.set_frame(f)
		depth.refresh()
		depth.apply_scene_camera(cam, f, false)
		await RenderingServer.frame_post_draw
		if Rigs.count() > 0:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path := frames_dir.path_join("frame_%05d.png" % (f + 1))
		if img.save_png(path) != OK:
			_cleanup(vp, was_frame)
			finished.emit(false, "Could not write " + path, dir)
			return
		progress.emit(f + 1, total + 1, "Rendering %d%%" % int(100.0 * (f + 1) / (total + 1)))
	_cleanup(vp, was_frame)
	if _cancel:
		_remove_dir(frames_dir)
		finished.emit(false, "Export cancelled", dir)
		return
	busy = true
	var wav := ""
	if bool(o.get("audio", true)) and not s.audio_tracks.is_empty():
		progress.emit(total, total + 1, "Mixing sound…")
		var wav_path := (out_file + ".wav") if fmt == "png" else frames_dir.path_join("sound.wav")
		if await Audio.mixdown(s, wav_path):
			wav = wav_path
	var result: Array = await encode_frames(frames_dir.path_join("frame_%05d.png"), p.fps, wav, o, out_file, total)
	if fmt != "png":
		_remove_dir(frames_dir)
	busy = false
	finished.emit(bool(result[0]), str(result[1]), out_file)


## Encodes rendered frames into `out_file` (or keeps the PNG frames).
## Returns [ok, message]. Shared by scene and episode exports.
func encode_frames(pattern: String, in_fps: int, wav: String, o: Dictionary, out_file: String, frames: int) -> Array:
	var fmt := ExportSettings.extension(o)
	if fmt == "png":
		return [true, "Saved %d frames%s" % [frames, " and the sound (WAV)" if wav != "" else ""]]
	var ffmpeg := find_ffmpeg()
	if ffmpeg == "":
		return [false, "Video files need FFmpeg, which isn't available here — choose “PNG frames” instead."]
	progress.emit(frames, frames + 1, "Encoding %s…" % fmt.to_upper())
	var args := ExportSettings.ffmpeg_args(pattern, in_fps, wav, o, out_file)
	_thread = Thread.new()
	_thread.start(_run_ffmpeg.bind(ffmpeg, args))
	while _thread.is_alive():
		await get_tree().create_timer(0.2).timeout
	var code: int = _thread.wait_to_finish()
	_thread = null
	if code != 0 or not FileAccess.file_exists(out_file):
		return [false, "Encoding failed (FFmpeg exit code %d)" % code]
	var sz := ExportSettings.output_size(o)
	return [true, "Exported %s · %d×%d · %d fps · %s" % [out_file.get_file(), sz.x, sz.y, ExportSettings.output_fps(o), ExportSettings.human_size(_file_size(out_file))]]


static func unique_path(dir: String, base_name: String, ext: String) -> String:
	var path := dir.path_join(base_name + ext)
	var n := 2
	while FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		path = dir.path_join("%s (%d)%s" % [base_name, n, ext])
		n += 1
	return path


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


static func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _run_ffmpeg(ffmpeg: String, args: PackedStringArray) -> int:
	var out := []
	return OS.execute(ffmpeg, args, out, true)


func _cleanup(vp: SubViewport, frame: int) -> void:
	vp.queue_free()
	OS.low_processor_usage_mode = _was_low_processor
	App.set_frame(frame)
	busy = false
