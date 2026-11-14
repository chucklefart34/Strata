class_name FFmpeg
extends RefCounted
## Finds a working FFmpeg executable. Checks, in order:
##   1. the location chosen in Settings (Home → Interface → FFmpeg)
##   2. next to Strata / the project (including nested folders such as
##      tools/ffmpeg-7.1-essentials_build/bin/ffmpeg.exe)
##   3. every folder on PATH (read directly, so a stale PATH in a long-running
##      process doesn't matter)
##   4. common install locations (Homebrew, MacPorts, winget, Scoop,
##      Chocolatey, C:\ffmpeg, /usr/bin, Snap...)
## Every candidate is actually run with `-version` before it's accepted.

static var _cached: String = ""
static var _checked: bool = false
static var report: PackedStringArray = PackedStringArray()


static func exe_name() -> String:
	return "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"


## Returns the path of a working ffmpeg, or "" if none was found.
static func find(force: bool = false) -> String:
	if _checked and not force:
		return _cached
	_checked = true
	_cached = ""
	report = PackedStringArray()
	if not Platform.can_run_programs():
		report.append("This device doesn't allow apps to run other programs.")
		return ""
	for c in candidates():
		var path := str(c)
		if path == "" or not FileAccess.file_exists(path):
			continue
		if verify(path):
			_cached = path
			report.append("Found: " + path)
			return _cached
		report.append("Found but could not run: " + path)
	# Last resort: let the OS resolve the bare name.
	if verify(exe_name()):
		_cached = exe_name()
		report.append("Found on the system PATH")
	return _cached


## True if `path` runs and identifies itself as FFmpeg.
static func verify(path: String) -> bool:
	var out := []
	var code := OS.execute(path, PackedStringArray(["-hide_banner", "-version"]), out, true)
	var text := "\n".join(PackedStringArray(out)).to_lower()
	return code == 0 and text.contains("ffmpeg")


## Saves a user-chosen location. Returns true if it works.
static func set_custom(path: String) -> bool:
	path = path.strip_edges()
	if DirAccess.dir_exists_absolute(path):
		var inside := _search_dir(path, exe_name(), 3)
		if inside != "":
			path = inside
	if not verify(path):
		return false
	ProjectIO.set_setting("ffmpeg_path", path)
	_cached = path
	_checked = true
	return true


static func candidates() -> Array:
	var out := []
	var exe := exe_name()
	var custom := str(ProjectIO.get_setting("ffmpeg_path", ""))
	if custom != "":
		out.append(custom)

	# Next to the app / the Strata project / the user's project, searched a few levels deep.
	var roots := [
		OS.get_executable_path().get_base_dir(),
		ProjectSettings.globalize_path("res://"),
	]
	if OS.get_name() == "macOS":
		# Folder that contains Strata.app
		roots.append(OS.get_executable_path().get_base_dir().path_join("../../.."))
	if App.has_project():
		roots.append(App.project.root_dir)
	for r in roots:
		var root := str(r)
		out.append(root.path_join(exe))
		for sub in ["tools", "ffmpeg", "bin"]:
			var found := _search_dir(root.path_join(sub), exe, 3)
			if found != "":
				out.append(found)

	# Every folder on PATH.
	var sep := ";" if OS.get_name() == "Windows" else ":"
	for d in OS.get_environment("PATH").split(sep, false):
		out.append(d.strip_edges().trim_prefix("\"").trim_suffix("\"").path_join(exe))

	# Common install locations.
	match OS.get_name():
		"Windows":
			var local := OS.get_environment("LOCALAPPDATA")
			var home := OS.get_environment("USERPROFILE")
			var pf := OS.get_environment("ProgramFiles")
			for p in [
				"C:/ffmpeg/bin/ffmpeg.exe", "C:/ffmpeg/ffmpeg.exe",
				pf.path_join("ffmpeg/bin/ffmpeg.exe"),
				"C:/ProgramData/chocolatey/bin/ffmpeg.exe",
				home.path_join("scoop/shims/ffmpeg.exe"),
				local.path_join("Microsoft/WinGet/Links/ffmpeg.exe"),
			]:
				out.append(str(p))
			# winget keeps the real files in a versioned package folder.
			var pkgs := local.path_join("Microsoft/WinGet/Packages")
			if local != "" and DirAccess.dir_exists_absolute(pkgs):
				for d in DirAccess.get_directories_at(pkgs):
					if d.to_lower().contains("ffmpeg"):
						var found := _search_dir(pkgs.path_join(d), exe, 4)
						if found != "":
							out.append(found)
			for base in [home.path_join("Downloads"), home.path_join("Desktop"), "C:/"]:
				if DirAccess.dir_exists_absolute(str(base)):
					for d in DirAccess.get_directories_at(str(base)):
						if d.to_lower().begins_with("ffmpeg"):
							var found := _search_dir(str(base).path_join(d), exe, 3)
							if found != "":
								out.append(found)
		"macOS":
			for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg",
					OS.get_environment("HOME").path_join("bin/ffmpeg"), "/Applications/ffmpeg"]:
				out.append(str(p))
		_:
			for p in ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/snap/bin/ffmpeg",
					"/var/lib/flatpak/exports/bin/ffmpeg", OS.get_environment("HOME").path_join(".local/bin/ffmpeg"),
					OS.get_environment("HOME").path_join("bin/ffmpeg")]:
				out.append(str(p))
	return out


## Looks for `exe` inside `dir`, up to `depth` folder levels down.
static func _search_dir(dir: String, exe: String, depth: int) -> String:
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return ""
	var direct := dir.path_join(exe)
	if FileAccess.file_exists(direct):
		return direct
	for sub in DirAccess.get_directories_at(dir):
		var found := _search_dir(dir.path_join(sub), exe, depth - 1)
		if found != "":
			return found
	return ""


## A short help text for when FFmpeg isn't found, tailored to the OS.
static func help_text() -> String:
	match OS.get_name():
		"Windows":
			return "Download FFmpeg (e.g. the “essentials” build from gyan.dev), unzip it, then click “Locate FFmpeg…” and choose bin\\ffmpeg.exe. Installing with “winget install ffmpeg” also works (restart Strata afterwards)."
		"macOS":
			return "Install with Homebrew (“brew install ffmpeg”) or download a build, then click “Locate FFmpeg…”. If macOS blocks a downloaded ffmpeg, right-click it in Finder → Open once, or run: xattr -d com.apple.quarantine /path/to/ffmpeg"
		_:
			return "Install FFmpeg with your package manager (e.g. “sudo apt install ffmpeg”), or download a static build, make it executable (chmod +x ffmpeg) and click “Locate FFmpeg…”."
