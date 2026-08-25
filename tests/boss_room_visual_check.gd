extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const OUTPUT_PATH := "res://artifacts/boss_room/room4_boss.png"

var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	seed(4812)
	GameManager.selected_character_id = "soldier"
	GameManager.debug_request_room_mode_for_next_game()
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	var controller := game.get_node("RoomRunController") as RoomRunController
	var hud := game.get_node("HUD") as HUD
	controller._begin_room(4, "boss", "large")
	_check(await _wait_for(func(): return controller.state == RoomRunController.RoomState.COMBAT and controller.current_room == 4, 4.0), "ROOM 4 enters BOSS combat")
	var boss := controller.boss_spawner.debug_get_current_boss() as EnemyBasic
	_check(is_instance_valid(boss), "ROOM 4 boss exists")
	_check(hud.boss_health_container.visible, "Japanese boss HP bar is visible")
	_check(hud.boss_name_label.text.begins_with("ボス　"), "boss HP bar uses Japanese label")
	await get_tree().create_timer(0.35, true, false, true).timeout
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	_check(not image.is_empty() and image.save_png(output_absolute) == OK, "Vulkan viewport screenshot saves successfully")
	if is_instance_valid(boss):
		boss.status_effect_component.apply_effect("stun", 1.0, 0.0)
		_check(boss.status_effect_component.has_effect("stun"), "Boss accepts shortened Freeze/Stun")
		controller.boss_spawner.debug_defeat_current_boss()
	_check(await _wait_for(func(): return controller.state != RoomRunController.RoomState.COMBAT, 3.0), "boss defeat advances the ROOM flow")
	await get_tree().create_timer(0.7, true, false, true).timeout
	_check(get_tree().get_nodes_in_group("boss_projectiles").is_empty(), "boss projectiles are cleaned")
	_check(get_tree().get_nodes_in_group("boss_attack_transient").is_empty(), "boss warnings are cleaned")
	_check(get_tree().get_nodes_in_group("boss_summons").is_empty(), "boss summons are cleaned")
	_check(Engine.time_scale == 1.0, "screen time state is restored after boss defeat")
	print("BOSS_ROOM_VISUAL_CHECK failures=%d boss=%s screenshot=%s" % [failures.size(), boss.enemy_data.id if is_instance_valid(boss) else "defeated", output_absolute])
	for failure in failures:
		push_error("BOSS_ROOM_VISUAL_CHECK: %s" % failure)
	get_tree().paused = false
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _wait_for(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().create_timer(0.04, true, false, true).timeout
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
