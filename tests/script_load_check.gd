extends SceneTree
## 起動を阻害するGDScript構文/型エラーを全Scriptの実loadで検出する。
## Godot --headless --path . --script res://tests/script_load_check.gd
var checked := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_scan("res://")
	for path in failures:
		push_error("SCRIPT_LOAD_CHECK failed: " + path)
	print("SCRIPT_LOAD_CHECK checked=%d failures=%d" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _scan(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		failures.append(path)
		return
	for name in directory.get_directories():
		if name.begins_with(".") or name in ["assets", "artifacts", "data", "_archive"]:
			continue
		_scan(path.path_join(name))
	for name in directory.get_files():
		if not name.ends_with(".gd"):
			continue
		var file := path.path_join(name)
		var script := load(file) as GDScript
		checked += 1
		if script == null or not script.can_instantiate():
			failures.append(file)
