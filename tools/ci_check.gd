extends SceneTree
## CI check: loads every script and compiles every shader in the project, so
## parse and shader errors show up in the build log (even for code that only
## runs later, like effects or the video import). Run with:
##   godot --headless --path . --script res://tools/ci_check.gd


func _initialize() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	var count := 0
	for path in files:
		var res: Resource = load(path)
		if res == null:
			printerr("CHECK FAILED: could not load ", path)
		elif res is Shader:
			# Compiling happens when a material uses it.
			var mat := ShaderMaterial.new()
			mat.shader = res as Shader
		count += 1
	print("ci_check: loaded %d scripts and shaders" % count)
	quit()


func _collect(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "tools" or d == "build":
			continue
		_collect(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
