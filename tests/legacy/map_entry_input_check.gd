extends Node
## GAME START→通常ゲーム→Soldier選択→MAP 1をInputMap Actionだけで通す。

var _tap_action := ""
var _release_frames := 0
var _next_action_msec := 0
var _started_msec := 0
var _last_scene_name := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_msec = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	_release_pending()
	if Time.get_ticks_msec() - _started_msec > 30000:
		_finish(false, "MAP_ENTRY_INPUT_CHECK: timeout")
		return
	var scene := get_tree().current_scene
	if scene != null and scene.name != _last_scene_name:
		_last_scene_name = scene.name
		print("MAP_ENTRY_INPUT_CHECK: scene=%s" % _last_scene_name)
	if scene is TitleScreen:
		var title := scene as TitleScreen
		if _ready_for_input():
			if title.start_button.visible or title.mode_select.visible:
				_tap("ui_accept")
	elif scene is HomeScreen:
		if _ready_for_input():
			_tap("ui_accept")
	elif scene and scene.is_in_group("game_runtime_world"):
		set_process(false)
		await get_tree().process_frame
		var controller := scene.get_node("MapRunController") as MapRunController
		var passed := GameManager.map_mode_active and not scene.has_node("RoomRunController") and GameManager.current_map_index == 1 and int(controller.debug_get_map_state().get("map_index", 0)) == 1
		_finish(passed, "MAP_ENTRY_INPUT_CHECK: PASS" if passed else "MAP_ENTRY_INPUT_CHECK: normal entry did not reach MAP 1")

func _ready_for_input() -> bool:
	return _tap_action == "" and Time.get_ticks_msec() >= _next_action_msec

func _tap(action: String) -> void:
	var action_event := InputEventAction.new()
	action_event.action = action
	action_event.pressed = true
	Input.parse_input_event(action_event)
	_tap_action = action
	_release_frames = 2
	_next_action_msec = Time.get_ticks_msec() + 120

func _release_pending() -> void:
	if _tap_action == "":
		return
	_release_frames -= 1
	if _release_frames <= 0:
		var action_event := InputEventAction.new()
		action_event.action = _tap_action
		action_event.pressed = false
		Input.parse_input_event(action_event)
		_tap_action = ""

func _finish(passed: bool, message: String) -> void:
	set_process(false)
	if not passed:
		push_error(message)
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if passed else 1, message if passed else "")
