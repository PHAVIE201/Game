extends Node
## Loads every script, scene, resource and shader in the project and reports failures.
## Usage: godot --headless --path . res://tools/validate.tscn
## Exit code 0 = everything loaded, 1 = at least one failure.

const ROOTS := ["res://scripts", "res://scenes", "res://resources", "res://shaders", "res://tools"]
const EXTS := ["gd", "tscn", "tres", "gdshader"]

var _failures: Array[String] = []
var _count := 0


func _ready() -> void:
	for root in ROOTS:
		_scan(root)
	# Scenes must also instantiate.
	for path in _collect("res://scenes", "tscn"):
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		if inst == null:
			_failures.append("instantiate failed: " + path)
		else:
			inst.free()
	print("[validate] checked %d files, %d failures" % [_count, _failures.size()])
	for f in _failures:
		print("[validate] FAIL ", f)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _scan(dir_path: String) -> void:
	for ext in EXTS:
		for path in _collect(dir_path, ext):
			_count += 1
			var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			if res == null:
				_failures.append("load failed: " + path)
			elif res is GDScript and not (res as GDScript).can_instantiate():
				_failures.append("script cannot instantiate (parse error?): " + path)


func _collect(dir_path: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == ext:
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_collect(dir_path.path_join(d), ext))
	return out
