class_name Ids
extends RefCounted
## Generates short unique ids for scenes, layers and cels.
## Ids double as folder/file names inside the project, so they are filename-safe.

static var _counter: int = 0


static func make() -> String:
	_counter += 1
	return "%x%04x%04x" % [int(Time.get_unix_time_from_system()), _counter & 0xffff, randi() & 0xffff]
