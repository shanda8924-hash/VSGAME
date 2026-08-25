extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const OUTPUT_DIR := "res://artifacts/element_system_2"
const MATRIX := [
	["fire", "ice", "frostfire"], ["fire", "lightning", "plasma"], ["fire", "light", "solar"], ["fire", "dark", "inferno"],
	["ice", "lightning", "superconductor"], ["ice", "light", "aurora"], ["ice", "dark", "void_frost"],
	["lightning", "light", "judgment"], ["lightning", "dark", "voidstorm"], ["light", "dark", "eclipse"],
]
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	GameManager.selected_character_id = "swordsman"
	var started := Time.get_ticks_msec()
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	await _clear_enemies()
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var combat := game.get_node("ElementCombatSystem") as ElementCombatSystem
	combat.set_proc_seed(99173)
	var targets: Array[EnemyBasic] = []
	for index in 64:
		var angle := index * TAU / 64.0
		var radius := 75.0 + (index % 8) * 28.0
		targets.append(_spawn_enemy(game, player.global_position + Vector2.from_angle(angle) * radius, index))
	var warm_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var warm_resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var peak_nodes := warm_nodes
	var peak_resources := warm_resources
	var peak_projectiles := 0
	var peak_transient_vfx := 0
	var min_fps := 10000.0
	var applied_hits := 0
	for entry in MATRIX:
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		combat.reset_runtime()
		for _rank in 3:
			GameManager.add_general_mastery("echo")
		for _rank in 3:
			GameManager.add_fragment(entry[0])
		for _rank in 3:
			GameManager.add_fragment(entry[1])
		for _rank in 3:
			GameManager.add_fusion_mastery("echo")
		for _rank in 3:
			GameManager.add_fusion_mastery("signature")
		# A real run forms one Fusion only. Let that one-shot formation presentation
		# finish before stressing the repeatable combat path for the next matrix row.
		await get_tree().create_timer(1.9, true, false, true).timeout
		for iteration in 36:
			var target := targets[(iteration * 7 + applied_hits) % targets.size()]
			if target.health_component.current_hp <= 0.0:
				target.health_component.current_hp = target.health_component.max_hp
			combat.apply_element_damage(target.hurtbox_component, 55.0, player.global_position)
			applied_hits += 1
			if iteration % 4 == 0:
				await get_tree().process_frame
				peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
				peak_resources = maxi(peak_resources, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
				peak_projectiles = maxi(peak_projectiles, get_tree().get_nodes_in_group("projectiles").size())
				peak_transient_vfx = maxi(peak_transient_vfx, get_tree().get_nodes_in_group("transient_vfx").size())
				var fps := Engine.get_frames_per_second()
				if fps > 0 and Engine.time_scale >= 0.99:
					min_fps = minf(min_fps, fps)
		await get_tree().create_timer(0.18, true, false, true).timeout
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	combat.reset_runtime()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/fusion_soak_peak.png" % OUTPUT_DIR))
	await get_tree().create_timer(3.0, true, false, true).timeout
	await get_tree().process_frame
	var remaining_vfx := get_tree().get_nodes_in_group("transient_vfx")
	var remaining_projectiles := get_tree().get_nodes_in_group("projectiles")
	var snapshot := combat.get_fusion_debug_snapshot()
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(remaining_vfx.is_empty(), "all bounded Fusion VFX and banners are released")
	_check(remaining_projectiles.is_empty(), "Fusion combat leaves no projectile")
	_check(int(snapshot.get("plasma_cores", -1)) == 0 and int(snapshot.get("inferno_souls", -1)) == 0 and int(snapshot.get("eclipse_gauge", -1)) == 0, "all Fusion runtime state resets")
	_check(orphans == 0, "Fusion soak leaves no orphan nodes")
	_check(peak_nodes < warm_nodes + 1800, "Fusion VFX node peak stays bounded")
	var metrics := {
		"hits": applied_hits,
		"warm_nodes": warm_nodes,
		"peak_nodes": peak_nodes,
		"warm_resources": warm_resources,
		"peak_resources": peak_resources,
		"peak_projectiles": peak_projectiles,
		"peak_transient_vfx": peak_transient_vfx,
		"remaining_projectiles": remaining_projectiles.size(),
		"remaining_vfx": remaining_vfx.size(),
		"orphans": orphans,
		"min_fps": 0.0 if min_fps == 10000.0 else min_fps,
		"wall_seconds": (Time.get_ticks_msec() - started) / 1000.0,
	}
	for failure in failures:
		push_error(failure)
	print("ELEMENT_SYSTEM_2_SOAK_CHECK failures=%d metrics=%s" % [failures.size(), metrics])
	for target in targets:
		if is_instance_valid(target):
			target.queue_free()
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _spawn_enemy(game: Node, position: Vector2, index: int) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "fusion_soak_%d" % index
	data.display_name = "Fusion Soak Target"
	data.max_hp = 100000000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
