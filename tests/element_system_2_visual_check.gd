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
var captures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	_disable_background(game)
	await _clear_enemies()
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	var select := game.get_node("FragmentSelect") as FragmentSelect
	await _capture_reward_states(select)
	await _capture_fusion_formation(player)
	await _capture_fusion_reward(select)
	await _capture_all_fusions(game, manager, player)
	await _capture_fusion_modes(game, manager, player)
	await _capture_matrix(game, manager, player)
	for failure in failures:
		push_error(failure)
	print("ELEMENT_SYSTEM_2_VISUAL_CHECK failures=%d screenshots=%d" % [failures.size(), captures.size()])
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture_reward_states(select: FragmentSelect) -> void:
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	await _open_and_capture(select, "boss_reward_0_elements.png")
	GameManager.add_fragment("fire")
	await _open_and_capture(select, "boss_reward_1_element.png")
	GameManager.add_fragment("light")
	await _open_and_capture(select, "boss_reward_2_elements_locked.png")
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	for _rank in 3:
		GameManager.add_fragment("lightning")
	await _open_and_capture(select, "boss_reward_lv3_mastery.png")

func _capture_fusion_formation(player: Player) -> void:
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	for _rank in 3:
		GameManager.add_fragment("fire")
	GameManager.add_fragment("lightning")
	GameManager.add_fragment("lightning")
	await get_tree().create_timer(0.82, true, false, true).timeout
	GameManager.add_fragment("lightning")
	await get_tree().create_timer(0.28, true, false, true).timeout
	await _save_viewport("%s/fusion_formation_plasma.png" % OUTPUT_DIR)
	_check(GameManager.active_fusion_id == "plasma", "formation capture uses a real Lv3 + Lv3 fusion")
	await get_tree().create_timer(1.45, true, false, true).timeout
	player.global_position = player.global_position

func _capture_fusion_reward(select: FragmentSelect) -> void:
	await _open_and_capture(select, "boss_reward_fusion_mastery.png")

func _capture_all_fusions(game: Node, manager: AttackVFXManager, player: Player) -> void:
	var origin := player.global_position
	for entry in MATRIX:
		_force_fusion_state(entry)
		await _clear_enemies()
		await _clear_transient_vfx()
		var target := _spawn_enemy(game, origin + Vector2(150, 0), entry[2], false)
		var effect := manager.play_fusion_effect(entry[2], origin - Vector2(55, 0), target.global_position, "attack", 1.2)
		manager.play_fusion_effect(entry[2], target.global_position, target.global_position, "signature", 1.3)
		_check(effect != null and bool(effect.get_meta("visual_only", false)), "%s attack is visual-only" % entry[2])
		_check(_count_collisions(effect) == 0, "%s attack has no collision" % entry[2])
		await get_tree().create_timer(0.18, true, false, true).timeout
		await _save_viewport("%s/%s_attack_hit.png" % [OUTPUT_DIR, entry[2]])
		await get_tree().create_timer(0.85, true, false, true).timeout

		await _clear_enemies()
		for index in 14:
			var angle := index * TAU / 14.0
			_spawn_enemy(game, origin + Vector2.from_angle(angle) * (95.0 + (index % 3) * 34.0), "%s_mass_%d" % [entry[2], index], false)
		for index in 5:
			var enemy_position := origin + Vector2.from_angle(index * TAU / 5.0) * 125.0
			manager.play_fusion_effect(entry[2], origin, enemy_position, "attack", 1.05)
		manager.play_fusion_effect(entry[2], origin, origin, "burst", 1.45)
		await get_tree().create_timer(0.18, true, false, true).timeout
		await _save_viewport("%s/%s_mass_battle.png" % [OUTPUT_DIR, entry[2]])
		await get_tree().create_timer(0.9, true, false, true).timeout

		await _clear_enemies()
		var boss := _spawn_enemy(game, origin + Vector2(155, 0), "%s_boss" % entry[2], true)
		manager.play_fusion_effect(entry[2], origin, boss.global_position, "attack", 1.35)
		manager.play_fusion_effect(entry[2], boss.global_position, boss.global_position, "signature", 1.5)
		await get_tree().create_timer(0.18, true, false, true).timeout
		await _save_viewport("%s/%s_boss.png" % [OUTPUT_DIR, entry[2]])
		await get_tree().create_timer(0.9, true, false, true).timeout

func _capture_matrix(game: Node, manager: AttackVFXManager, player: Player) -> void:
	await _clear_enemies()
	var origin := player.global_position
	var labels: Array[Label] = []
	for index in MATRIX.size():
		var col := index % 5
		var row := index / 5
		var point := origin + Vector2((col - 2) * 126.0, (row - 0.5) * 180.0)
		_spawn_enemy(game, point, "matrix_%d" % index, false)
		manager.play_fusion_effect(MATRIX[index][2], point - Vector2(42, 0), point + Vector2(22, 0), "signature", 0.92)
		var label := Label.new()
		label.text = GameManager.get_fusion_display_name(String(MATRIX[index][2])).get_slice(" / ", 0)
		label.size = Vector2(120, 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		game.add_child(label)
		label.global_position = point + Vector2(-60, -62)
		labels.append(label)
	await get_tree().create_timer(0.18, true, false, true).timeout
	await _save_viewport("%s/fusion_matrix_all_10.png" % OUTPUT_DIR)
	for label in labels:
		label.queue_free()

func _capture_fusion_modes(game: Node, manager: AttackVFXManager, player: Player) -> void:
	var modes := ["attack", "trail", "hit", "burst", "formation"]
	var origin := player.global_position
	for entry in MATRIX:
		_force_fusion_state(entry)
		await _clear_enemies()
		await _clear_transient_vfx()
		var labels: Array[Label] = []
		for index in modes.size():
			var point := origin + Vector2((index - 2) * 125.0, 0)
			_spawn_enemy(game, point, "%s_mode_%s" % [entry[2], modes[index]], false)
			var start := point - Vector2(54, 0) if modes[index] in ["attack", "trail"] else point
			manager.play_fusion_effect(entry[2], start, point, modes[index], 1.08 if modes[index] != "formation" else 1.25)
			var label := Label.new()
			label.text = "INTRO" if modes[index] == "formation" else String(modes[index]).to_upper()
			label.size = Vector2(112, 22)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 12)
			game.add_child(label)
			label.global_position = point + Vector2(-56, -58)
			labels.append(label)
		await get_tree().create_timer(0.16, true, false, true).timeout
		await _save_viewport("%s/%s_modes.png" % [OUTPUT_DIR, entry[2]])
		for label in labels:
			label.queue_free()
		await get_tree().create_timer(0.72, true, false, true).timeout

func _force_fusion_state(entry: Array) -> void:
	GameManager.debug_force_element_state({
		"element_%s" % entry[0]: 3,
		"element_%s" % entry[1]: 3,
	}, String(entry[2]))

func _clear_transient_vfx() -> void:
	for effect in get_tree().get_nodes_in_group("transient_vfx"):
		effect.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _open_and_capture(select: FragmentSelect, file_name: String) -> void:
	select.show_choices("BOSS REWARD：属性ビルドを1つ選択")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(select.visible and select.grid_container.get_child_count() == 4, "%s shows four reward cards" % file_name)
	await _save_viewport("%s/%s" % [OUTPUT_DIR, file_name])
	select.visible = false
	for child in select.grid_container.get_children():
		child.queue_free()
	GameManager.close_modal()
	await get_tree().process_frame

func _spawn_enemy(game: Node, position: Vector2, id: String, boss: bool) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data: EnemyData = BossData.new() if boss else EnemyData.new()
	data.id = id
	data.display_name = "Fusion Boss" if boss else "Fusion Target"
	data.max_hp = 12000.0 if boss else 3000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	enemy.visual_scale_multiplier = 1.8 if boss else 1.0
	game.add_child(enemy)
	enemy.global_position = position
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _disable_background(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

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

func _save_viewport(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_check(error == OK, "%s screenshot writes" % path)
	if error == OK:
		captures.append(path)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
