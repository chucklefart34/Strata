extends Node
## "Audio" autoload: loads audio files, computes waveforms (in a background
## thread, cached next to the audio as .peaks), plays the current scene's
## tracks in sync with the picture, scrubs audio while stepping through
## frames, and mixes a scene down to a WAV file for rendering.

signal peaks_ready(path: String)
signal mixdown_progress(fraction: float)

const PEAKS_PER_SEC := 100
const EXTENSIONS := ["wav", "ogg", "mp3"]
const RESYNC_SECONDS := 0.09

var scrub_enabled: bool = true

var _streams: Dictionary = {}  # absolute path -> AudioStream (or null if unreadable)
var _peaks: Dictionary = {}  # absolute path -> PackedFloat32Array
var _pending: Array = []  # [path, stream] waiting for waveform analysis
var _thread: Thread = null
var _players: Dictionary = {}  # clip id -> AudioStreamPlayer
var _clips: Dictionary = {}  # clip id -> [AudioClipData, AudioTrackData]
var _scrub_timer: Timer

# Episode preview drives audio with its own clock instead of App playback.
var external_time: float = -1.0  # scene-local seconds of the current scene
var episode_time: float = 0.0
var _ep_players: Dictionary = {}
var _ep_clips: Dictionary = {}


func _ready() -> void:
	_scrub_timer = Timer.new()
	_scrub_timer.one_shot = true
	_scrub_timer.timeout.connect(_stop_all)
	add_child(_scrub_timer)
	for sig: Signal in [App.project_opened, App.scene_switched, App.audio_changed]:
		sig.connect(rebuild)
	App.project_closed.connect(_clear_players)
	App.playback_changed.connect(_on_playback_changed)
	App.playback_looped.connect(_resync_all)
	App.frame_changed.connect(_on_frame_changed)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


# ================================================================ files & streams

static func is_audio_file(path: String) -> bool:
	return EXTENSIONS.has(path.get_extension().to_lower())


func abs_path(rel: String) -> String:
	if rel.is_absolute_path() or not App.has_project():
		return rel
	return App.project.root_dir.path_join(rel)


func stream_for(rel: String) -> AudioStream:
	var path := abs_path(rel)
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	if FileAccess.file_exists(path):
		match path.get_extension().to_lower():
			"wav":
				stream = AudioStreamWAV.load_from_file(path)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(path)
			"mp3":
				stream = AudioStreamMP3.load_from_file(path)
	_streams[path] = stream
	if stream != null:
		_queue_peaks(path, stream)
	return stream


func length_of(rel: String) -> float:
	var s := stream_for(rel)
	return s.get_length() if s != null else 0.0


func is_missing(rel: String) -> bool:
	return stream_for(rel) == null


# ================================================================ waveforms

func peaks_for(rel: String) -> PackedFloat32Array:
	var path := abs_path(rel)
	if _peaks.has(path):
		return _peaks[path]
	stream_for(rel)
	return PackedFloat32Array()


## Loudest sample between two source times (0..1), from the waveform cache.
func peak_between(rel: String, from_s: float, to_s: float) -> float:
	var p := peaks_for(rel)
	if p.is_empty():
		return 0.0
	var a := clampi(int(from_s * PEAKS_PER_SEC), 0, p.size() - 1)
	var b := clampi(int(ceilf(to_s * PEAKS_PER_SEC)), a + 1, p.size())
	var m := 0.0
	for i in range(a, b):
		m = maxf(m, p[i])
	return m


func _queue_peaks(path: String, stream: AudioStream) -> void:
	var cache := path + ".peaks"
	if FileAccess.file_exists(cache) and FileAccess.get_modified_time(cache) >= FileAccess.get_modified_time(path):
		var bytes := FileAccess.get_file_as_bytes(cache)
		if not bytes.is_empty():
			_peaks[path] = bytes.to_float32_array()
			return
	_pending.append([path, stream])
	_start_next_job()


func _start_next_job() -> void:
	if _pending.is_empty():
		return
	if _thread != null:
		if _thread.is_alive():
			return
		_thread.wait_to_finish()
	var job: Array = _pending.pop_front()
	_thread = Thread.new()
	_thread.start(_compute_peaks.bind(str(job[0]), job[1]))


## Runs on a worker thread: decodes the stream and keeps one peak per 10 ms.
func _compute_peaks(path: String, stream: AudioStream) -> void:
	var peaks := PackedFloat32Array()
	var pb := stream.instantiate_playback()
	if pb != null and pb.has_method("mix_audio"):
		var rate := AudioServer.get_mix_rate()
		var hop := maxi(1, int(rate / PEAKS_PER_SEC))
		var total := int(stream.get_length() * rate)
		peaks.resize(total / hop + 1)
		pb.start(0.0)
		var done := 0
		var idx := 0
		while done < total and idx < peaks.size():
			var want := mini(hop * 64, total - done)
			var frames: PackedVector2Array = pb.mix_audio(1.0, want)
			var n := frames.size()
			if n == 0:
				break
			var i := 0
			while i < n and idx < peaks.size():
				var end := mini(i + hop, n)
				var m := 0.0
				var j := i
				while j < end:
					var v := frames[j]
					var a := maxf(absf(v.x), absf(v.y))
					if a > m:
						m = a
					j += 3  # sampling every 3rd frame is plenty for a display envelope
				peaks[idx] = minf(m, 1.0)
				idx += 1
				i = end
			done += n
		pb.stop()
		peaks.resize(idx)
	_finish_peaks.call_deferred(path, peaks)


func _finish_peaks(path: String, peaks: PackedFloat32Array) -> void:
	_peaks[path] = peaks
	if not peaks.is_empty():
		var f := FileAccess.open(path + ".peaks", FileAccess.WRITE)
		if f != null:
			f.store_buffer(peaks.to_byte_array())
			f.close()
	peaks_ready.emit(path)
	_start_next_job()


# ================================================================ playback

func _clear_players() -> void:
	for id in _players.keys():
		var p: Node = _players[id]
		p.queue_free()
	_players.clear()
	_clips.clear()


func rebuild() -> void:
	_clear_players()
	if not App.has_project():
		return
	AudioServer.set_bus_volume_db(0, App.project.master_volume_db)
	var s := App.current_scene()
	if s == null:
		return
	for t in s.audio_tracks:
		for c in t.clips:
			var stream := stream_for(c.file)
			if stream == null:
				continue
			var p := AudioStreamPlayer.new()
			p.stream = stream
			add_child(p)
			_players[c.id] = p
			_clips[c.id] = [c, t]
	if App.playing:
		_resync_all()


func _any_solo() -> bool:
	var s := App.current_scene()
	if s == null:
		return false
	for t in s.audio_tracks:
		if t.solo:
			return true
	return false


func is_audible(t: AudioTrackData) -> bool:
	if t.muted:
		return false
	return t.solo or not _any_solo()


## Episode preview: play the episode soundtrack and follow an external clock.
func begin_external(ep: EpisodeData) -> void:
	end_external()
	external_time = 0.0
	episode_time = 0.0
	for t in ep.audio_tracks:
		for c in t.clips:
			var stream := stream_for(c.file)
			if stream == null:
				continue
			var p := AudioStreamPlayer.new()
			p.stream = stream
			add_child(p)
			_ep_players[c.id] = p
			_ep_clips[c.id] = [c, t]


func end_external() -> void:
	external_time = -1.0
	for id in _ep_players.keys():
		var p: Node = _ep_players[id]
		p.queue_free()
	_ep_players.clear()
	_ep_clips.clear()
	_stop_all()


func _on_playback_changed() -> void:
	if App.playing:
		_resync_all()
	else:
		_stop_all()


func _stop_all() -> void:
	for id in _players.keys():
		var p: AudioStreamPlayer = _players[id]
		p.stop()


func _resync_all() -> void:
	_sync(true)


func _process(_delta: float) -> void:
	if external_time >= 0.0:
		_sync_with(_players, _clips, external_time, false, _any_solo())
		_sync_with(_ep_players, _ep_clips, episode_time, false, false)
	elif App.playing:
		_sync(false)


func _sync(force: bool) -> void:
	if not App.has_project():
		return
	_sync_with(_players, _clips, App.playhead_seconds(), force, _any_solo())


func _sync_with(players: Dictionary, clips: Dictionary, t: float, force: bool, solo: bool) -> void:
	if not App.has_project():
		return
	var fps: int = App.project.fps
	for id in players.keys():
		var p: AudioStreamPlayer = players[id]
		var pair: Array = clips[id]
		var clip: AudioClipData = pair[0]
		var track: AudioTrackData = pair[1]
		var audible := not track.muted and (track.solo or not solo)
		var want := clip.source_pos(t, fps, p.stream.get_length()) if audible else -1.0
		if want < 0.0:
			if p.playing:
				p.stop()
			continue
		var g := clip.fade_gain(t, fps)
		p.volume_db = linear_to_db(maxf(g, 0.0001)) + clip.gain_db + track.volume_db
		if not p.playing:
			p.play(want)
		elif force or absf(p.get_playback_position() - want) > RESYNC_SECONDS:
			p.seek(want)


## While stepping or scrubbing (not playing), play a short slice at the new frame.
func _on_frame_changed() -> void:
	if external_time >= 0.0 or App.playing or not scrub_enabled or not App.has_project() or _players.is_empty():
		return
	var fps: int = App.project.fps
	var t := App.frame / float(fps)
	var solo := _any_solo()
	var any := false
	for id in _players.keys():
		var p: AudioStreamPlayer = _players[id]
		var pair: Array = _clips[id]
		var clip: AudioClipData = pair[0]
		var track: AudioTrackData = pair[1]
		if track.muted or (solo and not track.solo):
			continue
		var want := clip.source_pos(t, fps, p.stream.get_length())
		if want >= 0.0:
			p.volume_db = clip.gain_db + track.volume_db
			p.play(want)
			any = true
		else:
			p.stop()
	if any:
		_scrub_timer.start(maxf(0.07, 1.6 / fps))


# ================================================================ mixdown

## Collects mix jobs for a scene. `offset` shifts scene time into output
## time; only audio inside [win_a, win_b) of output time is kept.
func scene_jobs(scene: SceneData, offset: float, win_a: float, win_b: float) -> Array:
	var jobs := []
	var solo := false
	for t in scene.audio_tracks:
		solo = solo or t.solo
	for t in scene.audio_tracks:
		if t.muted or (solo and not t.solo):
			continue
		jobs.append_array(_track_jobs(t, offset, win_a, win_b))
	return jobs


func _track_jobs(t: AudioTrackData, offset: float, win_a: float, win_b: float) -> Array:
	var jobs := []
	for c in t.clips:
		var st := stream_for(c.file)
		if st != null:
			jobs.append({"clip": c.to_dict(), "db": t.volume_db, "stream": st, "offset": offset, "a": win_a, "b": win_b})
	return jobs


func episode_jobs(ep: EpisodeData, sched: Array, fps: int) -> Array:
	var jobs := []
	for item in sched:
		var s: Dictionary = item
		var scene: SceneData = s["scene"]
		if scene == null:
			continue
		var e: Dictionary = s["entry"]
		var start_s := int(s["start"]) / float(fps)
		var offset := start_s - int(e.get("trim_in", 0)) / float(fps)
		jobs.append_array(scene_jobs(scene, offset, start_s, start_s + int(s["length"]) / float(fps)))
	for t in ep.audio_tracks:
		if not t.muted:
			jobs.append_array(_track_jobs(t, 0.0, 0.0, 1.0e9))
	return jobs


## Mixes the scene's audible tracks into a 16-bit stereo WAV the length of
## the scene. Runs on a thread; returns true on success.
func mixdown(scene: SceneData, out_path: String) -> bool:
	if not App.has_project():
		return false
	var fps: int = App.project.fps
	var seconds := scene.frame_count / float(fps)
	return await mix_jobs(scene_jobs(scene, 0.0, 0.0, seconds), seconds, out_path)


func mix_jobs(jobs: Array, seconds: float, out_path: String) -> bool:
	if jobs.is_empty() or not App.has_project():
		return false
	var fps: int = App.project.fps
	var th := Thread.new()
	th.start(_mix_thread.bind(jobs, fps, seconds, out_path))
	while th.is_alive():
		await get_tree().create_timer(0.1).timeout
	return bool(th.wait_to_finish())


func _mix_thread(jobs: Array, fps: int, seconds: float, out_path: String) -> bool:
	var rate := int(AudioServer.get_mix_rate())
	var total := int(seconds * rate)
	var buf := PackedFloat32Array()
	buf.resize(total * 2)
	var job_index := 0
	for item in jobs:
		var job: Dictionary = item
		var clip := AudioClipData.from_dict(job["clip"])
		var track_db: float = job["db"]
		var stream: AudioStream = job["stream"]
		var offset: float = job["offset"]
		var win_a := int(float(job["a"]) * rate)
		var win_b := int(minf(float(job["b"]), seconds) * rate)
		job_index += 1
		var pb := stream.instantiate_playback()
		if pb == null or not pb.has_method("mix_audio"):
			continue
		var start := int((clip.start_time(fps) + offset) * rate)
		var count := mini(int(clip.length * rate), total - start)
		if count <= 0 or start >= total:
			continue
		var base_gain := db_to_linear(clip.gain_db + track_db)
		var per_pass := int(maxf(0.0, stream.get_length() - clip.trim_in) * rate)
		if per_pass <= 0:
			continue
		if not clip.loop:
			count = mini(count, per_pass)
		pb.start(clip.trim_in)
		var done := 0
		var in_pass := 0
		while done < count:
			if in_pass >= per_pass:
				pb.start(clip.trim_in)
				in_pass = 0
			var frames: PackedVector2Array = pb.mix_audio(1.0, mini(4096, mini(count - done, per_pass - in_pass)))
			var n := frames.size()
			if n == 0:
				if clip.loop and in_pass > 0:
					in_pass = per_pass
					continue
				break
			in_pass += n
			for k in n:
				var idx := start + done + k
				if idx < win_a or idx >= win_b or idx < 0:
					continue
				var t_scene := idx / float(rate) - offset
				var g := base_gain * clip.fade_gain(t_scene, fps)
				var v := frames[k]
				buf[idx * 2] += v.x * g
				buf[idx * 2 + 1] += v.y * g
			done += n
		pb.stop()
		mixdown_progress.emit.call_deferred(float(job_index) / jobs.size() * 0.8)
	var bytes := PackedByteArray()
	bytes.resize(total * 4)
	for i in total * 2:
		bytes.encode_s16(i * 2, clampi(int(buf[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = rate
	wav.data = bytes
	mixdown_progress.emit.call_deferred(1.0)
	return wav.save_to_wav(out_path) == OK
