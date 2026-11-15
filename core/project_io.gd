extends Node
## "ProjectIO" autoload: creating, opening, saving and autosaving projects,
## plus app settings and the recent-projects list.
##
## Saving is incremental: only drawings whose pixels changed are rewritten.
## The structure file is written to a temp file first and then swapped in,
## with the previous version kept as project.strata.json.bak.

const PROJECT_FILE := "project.strata.json"
const SETTINGS_PATH := "user://settings.cfg"
const AUTOSAVE_SECONDS := 120.0
const CACHE_TRIM_SECONDS := 15.0
const CACHE_KEEP_RADIUS := 36  # frames around the playhead kept in memory

var settings := ConfigFile.new()
var _autosave_timer: Timer
var _trim_timer: Timer


func _ready() -> void:
	settings.load(SETTINGS_PATH)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_SECONDS
	_autosave_timer.timeout.connect(_on_autosave)
	add_child(_autosave_timer)
	_autosave_timer.start()
	_trim_timer = Timer.new()
	_trim_timer.wait_time = CACHE_TRIM_SECONDS
	_trim_timer.timeout.connect(trim_cache)
	add_child(_trim_timer)
	_trim_timer.start()


# ================================================================ settings

func get_setting(key: String, default: Variant = null) -> Variant:
	return settings.get_value("app", key, default)


func set_setting(key: String, value: Variant) -> void:
	settings.set_value("app", key, value)
	settings.save(SETTINGS_PATH)


func recent_projects() -> Array:
	var list: Array = get_setting("recent", [])
	var out := []
	for p in list:
		if FileAccess.file_exists(str(p)):
			out.append(str(p))
	return out


func _add_recent(path: String) -> void:
	var list := recent_projects()
	list.erase(path)
	list.push_front(path)
	while list.size() > 8:
		list.pop_back()
	set_setting("recent", list)


func default_projects_dir() -> String:
	return Platform.projects_dir()


# ================================================================ create / open

## Returns "" on success, otherwise a readable error message.
func create_project(project_name: String, parent_dir: String, w: int, h: int, fps: int, mode: String = "2d3d") -> String:
	var folder_name := project_name.validate_filename()
	if folder_name.strip_edges() == "":
		folder_name = "Untitled"
	if parent_dir.strip_edges() == "":
		parent_dir = default_projects_dir()
	var root := parent_dir.path_join(folder_name)
	if FileAccess.file_exists(root.path_join(PROJECT_FILE)):
		return "A project already exists in:\n%s\nChoose another name or location." % root
	var err := DirAccess.make_dir_recursive_absolute(root)
	if err != OK:
		return "Could not create the project folder:\n%s\n(%s)" % [root, error_string(err)]
	var p := ProjectData.new()
	p.name = project_name
	p.root_dir = root
	p.width = w
	p.height = h
	p.fps = fps
	p.created = Time.get_datetime_string_from_system()
	p.mode = mode
	p.scenes.append(SceneData.create_for_mode("Scene 1", mode))
	App.open_project(p)
	var save_err := save_project()
	if save_err != "":
		return save_err
	App.status("Created project “%s”" % project_name)
	return ""


func open_project(path: String) -> String:
	if DirAccess.dir_exists_absolute(path):
		path = path.path_join(PROJECT_FILE)
	if not FileAccess.file_exists(path):
		return "No Strata project found at:\n" + path
	var root := path.get_base_dir()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var recovered := false
	if typeof(data) != TYPE_DICTIONARY:
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			data = JSON.parse_string(FileAccess.get_file_as_string(bak))
			recovered = typeof(data) == TYPE_DICTIONARY
		if not recovered:
			return "The project file is damaged and no usable backup was found:\n" + path
	var d: Dictionary = data
	if str(d.get("format", "")) != "strata-project":
		return "This file is not a Strata project:\n" + path
	if int(d.get("version", 1)) > ProjectData.FORMAT_VERSION:
		return "This project was saved by a newer version of Strata."
	var p := ProjectData.from_dict(d, root)
	App.open_project(p)
	_cleanup_orphans(p)
	_add_recent(path)
	var missing := _count_missing(p)
	for rel in _audio_files(p):
		if not FileAccess.file_exists(root.path_join(str(rel))):
			missing += 1
	if recovered:
		App.status("Project file was damaged — recovered from the last backup")
		App.mark_modified()
	elif missing > 0:
		App.status("%d drawing or audio file(s) are missing on disk — drawings appear blank, audio clips show “missing”" % missing)
	else:
		App.status("Opened “%s”" % p.name)
	return ""


## Every drawing dictionary in the project paired with its folder on disk.
func _cel_dirs(p: ProjectData, root: String) -> Array:
	var out := []
	for s in p.scenes:
		for l in s.layers:
			out.append([l.cels, root.path_join("scenes").path_join(s.id).path_join(l.id)])
		out.append([s.prop_paint, root.path_join("scenes").path_join(s.id).path_join("props")])
	for c in p.clips:
		out.append([c.cels, root.path_join("clips").path_join(c.id)])
	out.append([p.library_cels, root.path_join("library")])
	for ch in p.characters:
		for v in ch.views.keys():
			for pt in ch.views[v]:
				var part: PartData = pt
				out.append([part.layer.cels, root.path_join("characters").path_join(ch.id).path_join(str(v)).path_join(part.layer.id)])
	return out


func _count_missing(p: ProjectData) -> int:
	var n := 0
	for pair in _cel_dirs(p, p.root_dir):
		var cels: Dictionary = pair[0]
		for k in cels.keys():
			var cel: CelData = cels[k]
			if not FileAccess.file_exists(cel.file_path):
				n += 1
	return n


# ================================================================ save

func save_project() -> String:
	if not App.has_project():
		return "No project is open."
	return _save_to(App.project, App.project.root_dir)


func save_project_as(dir: String) -> String:
	if not App.has_project():
		return "No project is open."
	if FileAccess.file_exists(dir.path_join(PROJECT_FILE)) and dir != App.project.root_dir:
		return "That folder already contains a Strata project. Choose an empty folder."
	return _save_to(App.project, dir)


func _save_to(p: ProjectData, root: String) -> String:
	var err := DirAccess.make_dir_recursive_absolute(root)
	if err != OK:
		return "Could not create folder %s (%s)" % [root, error_string(err)]
	var failures := 0
	for pair in _cel_dirs(p, root):
		failures += _save_cels(pair[0], pair[1])
	if root != p.root_dir and p.root_dir != "":
		failures += _copy_audio(p, p.root_dir, root)
	var target := root.path_join(PROJECT_FILE)
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Could not write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(p.to_dict(), "\t"))
	f.close()
	if FileAccess.file_exists(target):
		DirAccess.copy_absolute(target, target + ".bak")
		DirAccess.remove_absolute(target)
	err = DirAccess.rename_absolute(tmp, target)
	if err != OK:
		return "Could not finalize the save (%s)" % error_string(err)
	p.root_dir = root
	_add_recent(target)
	App.mark_saved()
	if failures > 0:
		return "%d drawing(s) could not be written. Check disk space and permissions." % failures
	return ""


## Save As: audio files live outside the JSON, so copy every referenced one.
func _copy_audio(p: ProjectData, from_root: String, to_root: String) -> int:
	var failures := 0
	for rel in _audio_files(p):
		var src := from_root.path_join(rel)
		var dst := to_root.path_join(rel)
		if not FileAccess.file_exists(src) or FileAccess.file_exists(dst):
			continue
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		if DirAccess.copy_absolute(src, dst) != OK:
			failures += 1
		elif FileAccess.file_exists(src + ".peaks"):
			DirAccess.copy_absolute(src + ".peaks", dst + ".peaks")
	return failures


func _audio_files(p: ProjectData) -> Array:
	var out := []
	var tracks := []
	for s in p.scenes:
		tracks.append_array(s.audio_tracks)
	for e in p.episodes:
		tracks.append_array(e.audio_tracks)
	for item in tracks:
		var t: AudioTrackData = item
		for c in t.clips:
			if not out.has(c.file):
				out.append(c.file)
	return out


## Writes changed drawings of one cel dictionary into `dir`. Returns failures.
func _save_cels(cels: Dictionary, dir: String) -> int:
	if cels.is_empty():
		return 0
	DirAccess.make_dir_recursive_absolute(dir)
	var failures := 0
	for k in cels.keys():
		var cel: CelData = cels[k]
		var path := dir.path_join(cel.id + ".png")
		if not cel.dirty and cel.file_path == path and FileAccess.file_exists(path):
			continue
		var ok := false
		if cel.image != null:
			ok = cel.image.save_png(path) == OK
		elif cel.file_path != "" and FileAccess.file_exists(cel.file_path):
			ok = DirAccess.copy_absolute(cel.file_path, path) == OK
		else:
			# Nothing in memory and no source file: write a blank drawing.
			ok = cel.get_image().save_png(path) == OK
		if ok:
			cel.file_path = path
			cel.dirty = false
		else:
			failures += 1
	return failures


func _on_autosave() -> void:
	if App.has_project() and App.modified and App.project.root_dir != "":
		var err := save_project()
		App.status("Autosaved" if err == "" else "Autosave failed: " + err)


# ================================================================ memory

## Unloads drawings far from the playhead (and in other scenes) that are
## already safely written to disk. They reload transparently when needed.
func trim_cache() -> void:
	if not App.has_project():
		return
	var current := App.current_scene()
	var f: int = App.frame
	var freed := 0
	for s in App.project.scenes:
		for l in s.layers:
			for k in l.cels.keys():
				var cel: CelData = l.cels[k]
				if not cel.is_loaded():
					continue
				if s == current:
					var end := l.exposure_end(int(k), s.frame_count)
					if end + CACHE_KEEP_RADIUS >= f and int(k) - CACHE_KEEP_RADIUS <= f:
						continue
				if cel.unload():
					freed += 1
	for c in App.project.clips:
		for k in c.cels.keys():
			var cel: CelData = c.cels[k]
			if cel.unload():
				freed += 1


# ================================================================ cleanup

## Removes PNGs that no longer belong to any drawing. Runs right after opening,
## when the undo history is empty, so nothing can still refer to them.
func _cleanup_orphans(p: ProjectData) -> void:
	var valid := {}
	for pair in _cel_dirs(p, p.root_dir):
		var cels: Dictionary = pair[0]
		var dir: String = pair[1]
		for k in cels.keys():
			var cel: CelData = cels[k]
			valid[dir.path_join(cel.id + ".png")] = true
	for top in ["scenes", "clips", "characters"]:
		var d := p.root_dir.path_join(str(top))
		if DirAccess.dir_exists_absolute(d):
			_prune(d, valid)


## Deletes only unreferenced .png files and the folders they leave empty.
func _prune(dir: String, valid: Dictionary) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_prune(dir.path_join(sub), valid)
	for fn in DirAccess.get_files_at(dir):
		var path := dir.path_join(fn)
		if fn.ends_with(".png") and not valid.has(path):
			DirAccess.remove_absolute(path)
	if DirAccess.get_files_at(dir).is_empty() and DirAccess.get_directories_at(dir).is_empty():
		DirAccess.remove_absolute(dir)
