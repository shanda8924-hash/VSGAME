extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const MATRIX := [
	["fire", "ice", "frostfire"], ["fire", "lightning", "plasma"], ["fire", "light", "solar"], ["fire", "dark", "inferno"],
	["ice", "lightning", "superconductor"], ["ice", "light", "aurora"], ["ice", "dark", "void_frost"],
	["lightning", "light", "judgment"], ["lightning", "dark", "voidstorm"], ["light", "dark", "eclipse"],
]
var failures: Array[String] = []
var fusion_effects: Array[Dictionary] = []
var element_effect_count := 0
var _stage := "boot"

func _ready() -> void:
	get_tree().create_timer(35.0, true, false, true).timeout.connect(_watchdog_timeout)
	GameManager.selected_character_id = "swordsman"
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
	var baseline_weapons := player.weapon_manager.get_weapon_instances().size()
	var combat := game.get_node("ElementCombatSystem") as ElementCombatSystem
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	manager.fusion_effect_spawned.connect(func(id, mode, effect): fusion_effects.append({"id": id, "mode": mode, "effect": effect}))
	manager.element_effect_spawned.connect(func(_id, _effect): element_effect_count += 1)
	for entry in MATRIX:
		_stage = String(entry[2])
		print("FUSION_RUNTIME_INTEGRATION stage=%s" % _stage)
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		combat.reset_runtime()
		for _rank in 3:
			GameManager.add_fragment(entry[0])
		for _rank in 3:
			GameManager.add_fragment(entry[1])
		_check(player.weapon_manager.get_weapon_instances().size() == baseline_weapons, "%s does not create a legacy fragment weapon" % entry[2])
		fusion_effects.clear()
		element_effect_count = 0
		var targets: Array[EnemyBasic] = []
		for index in 6:
			var target := _spawn_enemy(game, player.global_position + Vector2(85 + index * 42, 0), "%s_%d" % [entry[2], index])
			targets.append(target)
			if index > 0:
				(target.get_node("StatusEffectComponent") as StatusEffectComponent).apply_effect("slow", 4.0, 0.4)
		combat.apply_element_damage(targets[0].hurtbox_component, 30.0, player.global_position)
		await get_tree().process_frame
		_check(fusion_effects.any(func(info): return info["id"] == entry[2] and info["mode"] == "attack"), "%s real combat hit reaches its dedicated attack VFX" % entry[2])
		_check(element_effect_count == 0, "%s combat presentation does not stack normal element sprites" % entry[2])
		for mode in ["attack", "trail", "hit", "burst", "formation"]:
			_stage = "%s_%s" % [entry[2], mode]
			var mode_effect := manager.play_fusion_effect(entry[2], player.global_position, targets[0].global_position, mode, 1.0)
			_check(mode_effect != null and mode_effect.mode == mode, "%s exposes its dedicated %s visual mode" % [entry[2], mode])
			_check(bool(mode_effect.get_meta("visual_only", false)) and _count_collisions(mode_effect) == 0, "%s %s mode remains visual-only" % [entry[2], mode])
			var asset_mode: String = "intro" if mode == "formation" else String(mode)
			var expected_path := "/assets/vfx/fusions/%s/fx_fusion_%s_%s_6f.png" % [entry[2], entry[2], asset_mode]
			_check(bool(mode_effect.get_meta("generated_pixel_art", false)), "%s %s renders generated Pixel Art" % [entry[2], mode])
			_check(String(mode_effect.get_meta("pixel_art_texture", "")).ends_with(expected_path), "%s %s reaches its dedicated generated PNG" % [entry[2], mode])
		for info in fusion_effects:
			var effect: Node = info["effect"]
			if is_instance_valid(effect):
				_check(_count_collisions(effect) == 0, "%s runtime VFX remains visual-only" % entry[2])
				effect.queue_free()
		await get_tree().process_frame
		await _clear_enemies()
	for failure in failures:
		push_error(failure)
	print("FUSION_RUNTIME_INTEGRATION_CHECK failures=%d fusions=%d" % [failures.size(), MATRIX.size()])
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _watchdog_timeout() -> void:
	push_error("FUSION_RUNTIME_INTEGRATION_CHECK watchdog stage=%s" % _stage)
	get_tree().paused = false
	get_tree().quit(1)

func _spawn_enemy(game: Node, position: Vector2, id: String) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = id
	data.display_name = "Fusion Integration Target"
	data.max_hp = 100000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
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

func _count_collisions(root: Node) -> int:
	var count := 1 if root is CollisionObject2D or root is CollisionShape2D else 0
	for child in root.get_children():
		count += _count_collisions(child)
	return count

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
