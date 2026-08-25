extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const OUTPUT_DIR := "res://artifacts/targeted_regression"

var failures: Array[String] = []
var plasma_bursts := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	GameManager.selected_character_id = "swordsman"
	GameManager.debug_force_element_state({"element_fire": 3, "element_lightning": 3}, "plasma")
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_disable_automatic_systems(game)
	await _clear_enemies()
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var combat := game.get_node("ElementCombatSystem") as ElementCombatSystem
	var runtime := combat._fusion_runtime as FusionCombatRuntime
	runtime.signature_triggered.connect(_on_signature_triggered)

	await _check_reentrant_multi_core_expiry(game, player, runtime)
	await _check_timed_core_disconnects_death_callback(game, player, runtime)
	await _check_enemy_death_and_reset_cleanup(game, player, runtime)
	await _check_freed_enemy_cleanup(game, player, runtime)

	for failure in failures:
		push_error(failure)
	print("PLASMA_CORE_LIFECYCLE_CHECK failures=%d bursts=%d snapshot=%s" % [failures.size(), plasma_bursts, runtime.get_debug_snapshot()])
	runtime.reset_runtime()
	game.queue_free()
	GameManager.debug_force_element_state({})
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_reentrant_multi_core_expiry(game: Node, player: Player, runtime: FusionCombatRuntime) -> void:
	runtime.reset_runtime()
	var targets: Array[EnemyBasic] = []
	for index in 4:
		var target := _spawn_enemy(game, player.global_position + Vector2(56 + index * 18, 0), "plasma_race_%d" % index, 20.0)
		targets.append(target)
		runtime.apply_chain_reaction("plasma", player.global_position, target.global_position, target, target.health_component, 120.0)
	for target in targets:
		var id := target.get_instance_id()
		var core: Dictionary = runtime._plasma_cores.get(id, {})
		core["remaining"] = 0.0
		runtime._plasma_cores[id] = core
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await _capture_non_black_viewport("%s/plasma_multi_core_after_detonation.png" % OUTPUT_DIR)
	_check(targets.all(func(target): return target.health_component.current_hp <= 0.0), "simultaneously expiring Plasma cores can kill multiple marked enemies")
	_check(int(runtime.get_debug_snapshot().get("plasma_cores", -1)) == 0, "reentrant death callbacks leave no Plasma core behind")

func _check_timed_core_disconnects_death_callback(game: Node, player: Player, runtime: FusionCombatRuntime) -> void:
	runtime.reset_runtime()
	var target := _spawn_enemy(game, player.global_position + Vector2(90, 40), "plasma_timed", 1000000.0)
	var baseline_connections := target.health_component.died.get_connections().size()
	runtime.apply_chain_reaction("plasma", player.global_position, target.global_position, target, target.health_component, 1.0)
	_check(target.health_component.died.get_connections().size() == baseline_connections + 1, "one active Plasma core owns one death callback")
	var id := target.get_instance_id()
	var core: Dictionary = runtime._plasma_cores.get(id, {})
	core["remaining"] = 0.0
	runtime._plasma_cores[id] = core
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not runtime._plasma_cores.has(id), "timed Plasma detonation retires its core")
	_check(target.health_component.died.get_connections().size() == baseline_connections, "timed Plasma detonation disconnects its obsolete death callback")
	for _iteration in 4:
		runtime.apply_chain_reaction("plasma", player.global_position, target.global_position, target, target.health_component, 1.0)
		core = runtime._plasma_cores.get(id, {})
		core["remaining"] = 0.0
		runtime._plasma_cores[id] = core
		await get_tree().process_frame
	_check(target.health_component.died.get_connections().size() == baseline_connections, "repeated Plasma use does not accumulate delayed death callbacks")
	target.queue_free()
	await get_tree().process_frame

func _check_enemy_death_and_reset_cleanup(game: Node, player: Player, runtime: FusionCombatRuntime) -> void:
	runtime.reset_runtime()
	var target := _spawn_enemy(game, player.global_position + Vector2(90, -40), "plasma_death", 20.0)
	var id := target.get_instance_id()
	runtime.apply_chain_reaction("plasma", player.global_position, target.global_position, target, target.health_component, 50.0)
	target.health_component.apply_secondary_damage(50.0)
	await get_tree().process_frame
	_check(not runtime._plasma_cores.has(id), "enemy death detonates and retires its Plasma core once")

	var reset_target := _spawn_enemy(game, player.global_position + Vector2(130, -40), "plasma_reset", 1000000.0)
	var baseline_connections := reset_target.health_component.died.get_connections().size()
	runtime.apply_chain_reaction("plasma", player.global_position, reset_target.global_position, reset_target, reset_target.health_component, 1.0)
	runtime.reset_runtime()
	_check(runtime._plasma_cores.is_empty(), "runtime reset clears Plasma core data")
	_check(reset_target.health_component.died.get_connections().size() == baseline_connections, "runtime reset disconnects Plasma death callbacks")
	reset_target.queue_free()
	await get_tree().process_frame

func _check_freed_enemy_cleanup(game: Node, player: Player, runtime: FusionCombatRuntime) -> void:
	runtime.reset_runtime()
	var target := _spawn_enemy(game, player.global_position + Vector2(150, 40), "plasma_freed", 1000000.0)
	var id := target.get_instance_id()
	runtime.apply_chain_reaction("plasma", player.global_position, target.global_position, target, target.health_component, 1.0)
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not runtime._plasma_cores.has(id), "queue-freed enemy retires its Plasma core without touching a freed HealthComponent")

func _spawn_enemy(game: Node, position: Vector2, enemy_id: String, max_hp: float) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = enemy_id
	data.display_name = enemy_id
	data.max_hp = max_hp
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _disable_automatic_systems(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _on_signature_triggered(fusion_id: String, signature_id: String, _affected_targets: int, _is_echo: bool) -> void:
	if fusion_id == "plasma" and signature_id == "overcharge_explosion":
		plasma_bursts += 1

func _capture_non_black_viewport(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var lit_samples := 0
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			if image.get_pixel(x, y).get_luminance() > 0.08:
				lit_samples += 1
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_check(error == OK, "Plasma runtime screenshot saves")
	_check(lit_samples > 20, "Plasma failure does not black out the game viewport")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
