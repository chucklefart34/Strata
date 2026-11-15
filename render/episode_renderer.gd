class_name EpisodeRenderer
extends Node
## Renders a whole episode, frame by frame, in order: every scene through its
## camera, transitions, title cards, credits and overlays, then mixes one
## soundtrack (scene audio + episode music) and encodes a single MP4.

signal progress(done: int, total: int, message: String)
signal finished(ok: bool, message: String, output_dir: String)

var _fx_node: FxProcessor = null
var busy: bool = false
var _cancel: bool = false


func cancel() -> void:
	_cancel = true


static func overlay_alpha(e: Dictionary, rel: int) -> float:
	if str(e.get("overlay_text", "")).strip_edges() == "":
		return 0.0
	var a := int(e.get("overlay_start", 0))
	var b := int(e.get("overlay_end", 72))
	if rel < a or rel >= b:
		return 0.0
	return clampf(minf(float(rel - a) / 6.0, float(b - rel) / 6.0), 0.0, 1.0)


## CapCut-style export of the whole episode (see ExportSettings). Frames are
## rendered at project size, then scaled / retimed / encoded by FFmpeg.
func export_episode(ep: EpisodeData, depth: DepthView, o: Dictionary) -> void:
	var fmt := ExportSettings.extension(o)
	var dir := str(o.get("dir", ""))
	DirAccess.make_dir_recursive_absolute(dir)
	var fname := str(o.get("name", "")).validate_filename()
	if fname == "":
		fname = "episode"
	var out_file := RenderExporter.unique_path(dir, fname, "" if fmt == "png" else "." + fmt)
	var frames_dir := out_file if fmt == "png" else dir.path_join(".strata_frames_%d" % Time.get_ticks_msec())
	var opts := o.duplicate()
	opts["_out_file"] = out_file
	render(ep, depth, frames_dir, false, opts)


func render(ep: EpisodeData, depth: DepthView, out_dir: String, make_mp4: bool, export_opts: Dictionary = {}) -> void:
	if busy or not App.has_project():
		return
	busy = true
	_cancel = false
	var p: ProjectData = App.project
	var sched := ep.schedule(p)
	var total := EpisodeData.total_frames(sched)
	if total <= 0:
		busy = false
		finished.emit(false, "The episode is empty — add scenes or title cards first.", out_dir)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var was_scene: int = App.scene_index
	var was_frame: int = App.frame
	var was_low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	App.stop()

	var feed := SceneFeed.new()
	add_child(feed)
	feed.setup(depth, p.width, p.height, true)
	var comp := EpisodeCompositor.new()
	add_child(comp)
	comp.setup(p.width, p.height)
	var fx := FxProcessor.new()
	add_child(fx)
	fx.setup(p.width, p.height)
	_fx_node = fx
	var tex_a := ImageTexture.new()
	var tex_b := ImageTexture.new()
	var tex_fx := ImageTexture.new()
	var base := ("ep%02d_%s" % [ep.number, ep.title]).validate_filename().replace(" ", "_")

	for f in total:
		if _cancel:
			break
		var st := EpisodeData.frame_state(sched, f)
		var ov_text := ""
		var ov_style := "lower_third"
		var ov_alpha := 0.0
		for which in ["b", "a"]:
			var slot_state: Variant = st[which]
			if slot_state == null:
				continue
			var sd: Dictionary = slot_state
			var sch: Dictionary = sd["sched"]
			var e: Dictionary = sch["entry"]
			var slot := comp.slot_a if which == "a" else comp.slot_b
			var scene: SceneData = sch["scene"]
			if str(e.get("type", "")) == "scene":
				if scene == null:
					comp.set_picture(slot, null)
					continue
				feed.show_scene_frame(p.scenes.find(scene), int(sd["local"]))
				await RenderingServer.frame_post_draw
				if Rigs.count() > 0:
					await RenderingServer.frame_post_draw
				var img := feed.get_texture().get_image()
				var t := tex_a if which == "a" else tex_b
				t.set_image(img)
				comp.set_picture(slot, t)
				if which == "a":
					ov_text = str(e.get("overlay_text", ""))
					ov_style = str(e.get("overlay_style", "lower_third"))
					ov_alpha = overlay_alpha(e, f - int(sch["start"]))
			else:
				comp.set_title(slot, e, int(sd["local"]), p.fps)
		comp.compose(st, ov_text, ov_style, ov_alpha)
		await RenderingServer.frame_post_draw
		var out := comp.get_texture().get_image()
		var active := VideoFx.active_at(ep.effects, f)
		if not active.is_empty():
			# The effects read the finished composite (and last frame's result).
			tex_fx.set_image(out)
			var fx_tex := fx.process(tex_fx, active, f, p.fps)
			await RenderingServer.frame_post_draw
			out = fx_tex.get_image()
		else:
			fx.process(null, active, f, p.fps)
		var path := out_dir.path_join("%s_%06d.png" % [base, f + 1])
		if out.save_png(path) != OK:
			_finish(feed, comp, was_scene, was_frame, was_low)
			finished.emit(false, "Could not write " + path, out_dir)
			return
		progress.emit(f + 1, total, "Rendering episode frame %d of %d" % [f + 1, total])

	_finish(feed, comp, was_scene, was_frame, was_low)
	if _cancel:
		finished.emit(false, "Episode render cancelled", out_dir)
		return
	busy = true
	progress.emit(total, total, "Mixing the episode soundtrack…")
	var wav := out_dir.path_join(base + ".wav")
	var has_audio: bool = false
	if export_opts.is_empty() or bool(export_opts.get("audio", true)):
		has_audio = await Audio.mix_jobs(Audio.episode_jobs(ep, sched, p.fps), total / float(p.fps), wav)
	if not export_opts.is_empty():
		await _encode_export(out_dir, base, total, wav if has_audio else "", export_opts)
		return
	if not make_mp4:
		busy = false
		finished.emit(true, "Rendered %d frames%s" % [total, " + soundtrack (WAV)" if has_audio else ""], out_dir)
		return
	var ffmpeg := RenderExporter.find_ffmpeg()
	if ffmpeg == "":
		busy = false
		finished.emit(true, "Rendered %d frames. MP4 skipped: FFmpeg was not found — set its location in Home → Interface → FFmpeg." % total, out_dir)
		return
	progress.emit(total, total, "Encoding the episode MP4…")
	var mp4 := out_dir.path_join(base + ".mp4")
	var args := PackedStringArray(["-y", "-framerate", str(p.fps), "-i", out_dir.path_join(base + "_%06d.png")])
	if has_audio:
		args.append_array(PackedStringArray(["-i", wav]))
	args.append_array(PackedStringArray(["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2"]))
	if has_audio:
		args.append_array(PackedStringArray(["-c:a", "aac", "-b:a", "192k"]))
	args.append(mp4)
	var th := Thread.new()
	th.start(func() -> int:
		var o := []
		return OS.execute(ffmpeg, args, o, true))
	while th.is_alive():
		await get_tree().create_timer(0.25).timeout
	var code: int = th.wait_to_finish()
	busy = false
	if code == 0:
		finished.emit(true, "Episode rendered: %s (%d frames%s)" % [mp4.get_file(), total, ", with sound" if has_audio else ""], out_dir)
	else:
		finished.emit(false, "Frames rendered, but FFmpeg failed (exit code %d)" % code, out_dir)


func _encode_export(frames_dir: String, base: String, total: int, wav: String, o: Dictionary) -> void:
	var fmt := ExportSettings.extension(o)
	var out_file := str(o["_out_file"])
	if fmt == "png":
		busy = false
		finished.emit(true, "Saved %d episode frames%s" % [total, " and the soundtrack (WAV)" if wav != "" else ""], out_file)
		return
	var ffmpeg := RenderExporter.find_ffmpeg()
	if ffmpeg == "":
		busy = false
		finished.emit(false, "Video files need FFmpeg, which isn't available here — choose “PNG frames” instead.", frames_dir)
		return
	progress.emit(total, total + 1, "Encoding %s…" % fmt.to_upper())
	var args := ExportSettings.ffmpeg_args(frames_dir.path_join(base + "_%06d.png"), App.project.fps, wav, o, out_file)
	var th := Thread.new()
	th.start(func() -> int:
		var outp := []
		return OS.execute(ffmpeg, args, outp, true))
	while th.is_alive():
		await get_tree().create_timer(0.25).timeout
	var code: int = th.wait_to_finish()
	RenderExporter._remove_dir(frames_dir)
	busy = false
	if code == 0 and FileAccess.file_exists(out_file):
		var sz := ExportSettings.output_size(o)
		finished.emit(true, "Exported %s · %d×%d · %d fps · %s" % [out_file.get_file(), sz.x, sz.y, ExportSettings.output_fps(o), ExportSettings.human_size(RenderExporter._file_size(out_file))], out_file)
	else:
		finished.emit(false, "Encoding failed (FFmpeg exit code %d)" % code, frames_dir)


func _finish(feed: SceneFeed, comp: EpisodeCompositor, scene_index: int, frame: int, low: bool) -> void:
	feed.queue_free()
	comp.queue_free()
	if _fx_node != null:
		_fx_node.queue_free()
		_fx_node = null
	OS.low_processor_usage_mode = low
	App.set_scene(scene_index)
	App.set_frame(frame)
	busy = false
