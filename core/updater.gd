extends Node
## Checks GitHub for a newer build of Strata and, on Windows, installs it:
## downloads the new zip, unpacks it next to the app's data, then a small
## script waits for Strata to close, copies the new files over the old ones
## and starts Strata again. On iPad it only says an update is out (sideloaded
## apps can't replace themselves).

signal state_changed

const REPO := "chucklefart34/Strata"
const CHECK_EVERY := 6 * 3600  # seconds between automatic checks

enum { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, INSTALLING, FAILED }

var state: int = IDLE
var message: String = ""
var latest_build: int = 0
var latest_commit: String = ""
var latest_date: String = ""
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.max_redirects = 10
	add_child(_http)
	if auto_check() and not OS.has_feature("editor"):
		var last := int(ProjectIO.get_setting("update_last_check", 0))
		if Time.get_unix_time_from_system() - last > CHECK_EVERY:
			get_tree().create_timer(4.0).timeout.connect(_auto_check)


static func auto_check() -> bool:
	return bool(ProjectIO.get_setting("update_auto_check", true))


static func can_install() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")


static func channel() -> String:
	return "ios-latest" if OS.get_name() == "iOS" else "windows-latest"


static func release_page() -> String:
	return "https://github.com/%s/releases/tag/%s" % [REPO, channel()]


static func zip_url() -> String:
	return "https://github.com/%s/releases/download/windows-latest/Strata-windows.zip" % REPO


static func current_text() -> String:
	if BuildInfo.BUILD == 0:
		return "development copy"
	return "build %d (%s%s)" % [BuildInfo.BUILD, BuildInfo.COMMIT.left(7), ", " + BuildInfo.DATE if BuildInfo.DATE != "" else ""]


func _auto_check() -> void:
	await check()
	if state == AVAILABLE:
		App.status("A Strata update is ready (build %d). Install it from Home › Updates." % latest_build)


func _set_state(st: int, msg: String) -> void:
	state = st
	message = msg
	state_changed.emit()


func busy() -> bool:
	return state == CHECKING or state == DOWNLOADING or state == INSTALLING


## Downloaded / total bytes while downloading.
func progress() -> Vector2i:
	if state != DOWNLOADING:
		return Vector2i.ZERO
	return Vector2i(_http.get_downloaded_bytes(), maxi(0, _http.get_body_size()))


func check() -> void:
	if busy():
		return
	_set_state(CHECKING, "Checking for updates…")
	ProjectIO.set_setting("update_last_check", int(Time.get_unix_time_from_system()))
	var url := "https://github.com/%s/releases/download/%s/version.json?t=%d" % [REPO, channel(), Time.get_ticks_msec()]
	_http.download_file = ""
	_http.timeout = 30.0
	if _http.request(url) != OK:
		_set_state(FAILED, "Couldn't check for updates.")
		return
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		_set_state(FAILED, "Couldn't reach GitHub to check for updates. Are you online?")
		return
	if int(res[1]) == 404:
		_set_state(FAILED, "A new build is being published right now — try again in a few minutes.")
		return
	if int(res[1]) != 200:
		_set_state(FAILED, "Couldn't check for updates (GitHub said %d)." % int(res[1]))
		return
	var body: PackedByteArray = res[3]
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_set_state(FAILED, "The update information was unreadable.")
		return
	var d: Dictionary = data
	latest_build = int(d.get("build", 0))
	latest_commit = str(d.get("commit", ""))
	latest_date = str(d.get("date", ""))
	if latest_build > BuildInfo.BUILD and latest_commit != BuildInfo.COMMIT:
		var what := "Build %d is out%s." % [latest_build, " (" + latest_date + ")" if latest_date != "" else ""]
		if can_install():
			_set_state(AVAILABLE, what + " Install it now — Strata saves your project, closes, updates and opens again.")
		else:
			_set_state(AVAILABLE, what + (" Download it from GitHub and install it the same way as before." if OS.get_name() == "iOS" else " Download it from GitHub."))
	else:
		_set_state(UP_TO_DATE, "You have the latest version.")


## Windows: download, unpack, then hand over to the swap script and quit.
func install() -> void:
	if busy() or not can_install():
		return
	var app_dir := OS.get_executable_path().get_base_dir()
	var probe := app_dir.path_join(".strata_update_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		_set_state(FAILED, "Strata can't write to its own folder (%s), so it can't update itself. Move the Strata folder somewhere like Documents, or download the update from GitHub." % app_dir)
		return
	f.close()
	DirAccess.remove_absolute(probe)

	var work := OS.get_user_data_dir().path_join("update")
	_remove_tree(work)
	DirAccess.make_dir_recursive_absolute(work)
	var zip_path := work.path_join("Strata-windows.zip")
	_set_state(DOWNLOADING, "Downloading the update…")
	_http.download_file = zip_path
	_http.timeout = 0.0
	var err := _http.request(zip_url())
	if err != OK:
		_http.download_file = ""
		_set_state(FAILED, "Couldn't start the download.")
		return
	var res: Array = await _http.request_completed
	_http.download_file = ""
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		_set_state(FAILED, "The download failed. Check your connection and try again.")
		return

	_set_state(INSTALLING, "Unpacking…")
	await get_tree().process_frame
	var new_dir := work.path_join("new")
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		_set_state(FAILED, "The downloaded update is damaged. Try again.")
		return
	var has_exe := false
	for entry in zip.get_files():
		var rel := str(entry)
		var dest := new_dir.path_join(rel)
		if rel.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest)
			continue
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out == null:
			zip.close()
			_set_state(FAILED, "Couldn't unpack the update.")
			return
		out.store_buffer(zip.read_file(rel))
		out.close()
		if rel.get_file().to_lower() == "strata.exe":
			has_exe = true
	zip.close()
	DirAccess.remove_absolute(zip_path)
	if not has_exe:
		_set_state(FAILED, "The update didn't contain Strata.exe.")
		return

	if App.has_project():
		var save_err := ProjectIO.save_project()
		if save_err != "":
			_set_state(FAILED, "Couldn't save your project before updating: %s" % save_err)
			return

	var script_path := work.path_join("update.cmd")
	var src := new_dir.replace("/", "\\").trim_suffix("\\")
	var dst := app_dir.replace("/", "\\").trim_suffix("\\")
	var pid := OS.get_process_id()
	var lines := [
		"@echo off",
		":wait",
		"tasklist /FI \"PID eq %d\" /NH 2>nul | find \" %d \" >nul" % [pid, pid],
		"if not errorlevel 1 (",
		"  ping -n 2 127.0.0.1 >nul",
		"  goto wait",
		")",
		"robocopy \"%s\" \"%s\" /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP >nul" % [src, dst],
		"if %ERRORLEVEL% GEQ 8 echo Strata couldn't finish updating. Download it again from %s > \"%s\\update-failed.txt\"" % [release_page(), dst],
		"start \"\" \"%s\\Strata.exe\"" % dst,
		"rmdir /s /q \"%s\"" % src,
	]
	var sf := FileAccess.open(script_path, FileAccess.WRITE)
	if sf == null:
		_set_state(FAILED, "Couldn't prepare the update.")
		return
	sf.store_string("\r\n".join(PackedStringArray(lines)) + "\r\n")
	sf.close()
	if OS.create_process("cmd.exe", ["/c", script_path.replace("/", "\\")]) <= 0:
		_set_state(FAILED, "Couldn't start the updater.")
		return
	_set_state(INSTALLING, "Restarting to finish the update…")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	for fl in dir.get_files():
		DirAccess.remove_absolute(path.path_join(fl))
	DirAccess.remove_absolute(path)
