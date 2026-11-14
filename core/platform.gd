class_name Platform
extends RefCounted
## Small platform helpers, so the desktop and iPad/iPhone builds share one
## codebase. iOS differences handled here:
##   * apps can't launch other programs → no FFmpeg (video import, MP4 export)
##   * no "show in folder" → tell the person where the Files app shows it
##   * projects live in the app's own Documents folder (visible in Files)


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["iOS", "Android"]


static func is_ios() -> bool:
	return OS.get_name() == "iOS"


## False on iOS/Android, where apps may not start other executables.
static func can_run_programs() -> bool:
	return not is_mobile()


static func projects_dir() -> String:
	if is_mobile():
		# On iOS user:// is the app's Documents folder, which the Files app
		# shows under "On My iPad › Strata" (file sharing is on in the export).
		return OS.get_user_data_dir().path_join("Projects")
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs == "":
		docs = OS.get_user_data_dir()
	return docs.path_join("Strata Projects")


## Opens a folder on desktop; on mobile says where to find it instead.
static func reveal(path: String) -> void:
	if is_mobile():
		var rel := path.replace(OS.get_user_data_dir(), "").trim_prefix("/")
		App.status("Saved. Open the Files app › On My %s › Strata › %s" % ["iPad" if _is_tablet() else "iPhone", rel])
		return
	OS.shell_open(path)


static func _is_tablet() -> bool:
	var sz := DisplayServer.screen_get_size()
	return minf(sz.x, sz.y) / maxf(1.0, DisplayServer.screen_get_scale()) >= 600.0


static func no_ffmpeg_text() -> String:
	return "Video files can't be read on iPhone or iPad: Apple doesn't allow apps to run FFmpeg, which Strata uses for video. Export the clip as a series of images (PNG or JPG) from your video or photo app and use “Import frames from images…” instead — or import the video on the desktop version and open the project here."
