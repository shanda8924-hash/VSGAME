extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const OUTPUT_DIR := "res://artifacts/light_dark_vfx_polish"

var failures: Array[String] = []
var _captures: Array[String] = []
var _last_feedback: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await _run_checks()
	for failure in failures:
		push_error(failure)
	print("LIGHT_DARK_VFX_VISUAL_CHECK failures=%d screenshots=%s" % [failures.size(), _captures])
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_checks() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	_disable_background(game)
	await _remove_enemies()
	var player := game.get_node("Player") as Player
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	manager.element_level_feedback_spawned.connect(func(_id, _level, effect): _last_feedback = effect)
	var origin := player.global_position

	for entry in [["light", "element_light", "rays"], ["dark", "element_dark", "rifts"]]:
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		GameManager.held_fragment_ids.clear()
		var data := DataLoader.element_vfx_effects.get(entry[1]) as ElementVFXData
		_check(data != null and data.stack_accent_style == entry[2], "%s uses the intended visual language" % entry[0])
		_check(data != null and data.iai_trail_sprite_sheet.get_size() == Vector2(384, 64), "%s keeps six-frame Trail sheet" % entry[0])
		_check(data != null and data.hit_sprite_sheet.get_size() == Vector2(384, 64), "%s keeps six-frame Hit sheet" % entry[0])
		for level in range(1, 4):
			_last_feedback = null
			GameManager.add_fragment(entry[0])
			await get_tree().create_timer(0.06, true, false, true).timeout
			if level >= 2:
				_check(_last_feedback != null and is_instance_valid(_last_feedback), "%s Lv%d has short level feedback" % [entry[0], level])
				if _last_feedback and is_instance_valid(_last_feedback):
					_check(_count_collision_nodes(_last_feedback) == 0, "%s Lv%d level feedback stays visual-only" % [entry[0], level])
				if DisplayServer.get_name() != "headless":
					await _save_viewport("%s/%s_level_up_lv%d.png" % [OUTPUT_DIR, entry[0], level])
			await get_tree().create_timer(0.78, true, false, true).timeout

			player.global_position = origin
			var trail := manager.play_iai_trail(origin - Vector2(118, 0), origin)
			var hit := manager.play_element_hit(origin + Vector2(58, 0), data, level)
			_check(trail != null and hit != null, "%s Lv%d Trail and Hit spawn" % [entry[0], level])
			_check(trail != null and trail.sprite_frames.get_frame_count("play") == 6, "%s Lv%d Trail keeps six frames" % [entry[0], level])
			_check(hit != null and hit.sprite_frames.get_frame_count("play") == 6, "%s Lv%d Hit keeps six frames" % [entry[0], level])
			var trail_accent := _find_accent(manager, entry[1], level, "_Trail_")
			var hit_accent := _find_accent(manager, entry[1], level, "_Hit_")
			if level == 1:
				_check(trail_accent == null and hit_accent == null, "%s Lv1 remains the restrained base sprite" % entry[0])
			else:
				_check(trail_accent != null and hit_accent != null, "%s Lv%d adds local secondary accents" % [entry[0], level])
				if entry[0] == "light":
					_check(_count_prefix(trail_accent, "LightTrailSpark_") >= (3 if level == 2 else 5), "light Lv%d adds fine Trail sparkles" % level)
					_check(_count_prefix(hit_accent, "LightRay_") == data.level2_accent_count if level == 2 else _count_prefix(hit_accent, "LightRay_") == data.level3_accent_count, "light Lv%d adds radial star rays" % level)
					if level == 3:
						_check(_count_prefix(hit_accent, "LightSacredStar") == 1, "light Lv3 adds a small sacred star core")
				else:
					_check(_count_prefix(trail_accent, "DarkVoidTrail") == 1, "dark Lv%d adds a thin void Trail core" % level)
					_check(_count_prefix(hit_accent, "DarkVoidRift") == 1, "dark Lv%d adds a localized void rift" % level)
			await get_tree().create_timer(0.09, true, false, true).timeout
			if DisplayServer.get_name() != "headless":
				await _save_viewport("%s/%s_lv%d_trail_hit.png" % [OUTPUT_DIR, entry[0], level])
			await get_tree().create_timer(0.62, true, false, true).timeout
		manager.play_element_hit(origin + Vector2(58, 0), data, 3)
		await get_tree().create_timer(0.09, true, false, true).timeout
		if DisplayServer.get_name() != "headless":
			await _save_viewport("%s/%s_hit_lv3.png" % [OUTPUT_DIR, entry[0]])
		await get_tree().create_timer(0.5, true, false, true).timeout

	await _capture_all_element_comparison(game, manager, player, origin)
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	GameManager.held_fragment_ids.clear()
	game.queue_free()
	await get_tree().process_frame

func _capture_all_element_comparison(game: Node, manager: AttackVFXManager, player: Player, origin: Vector2) -> void:
	var ids := ["element_fire", "element_ice", "element_lightning", "element_light", "element_dark"]
	var labels: Array[Label] = []
	var enemies: Array[EnemyBasic] = []
	for index in ids.size():
		var position := origin + Vector2((index - 2) * 112.0, 74.0)
		var enemy := _spawn_enemy_at(game, position, "comparison_%d" % index)
		enemies.append(enemy)
		var data := DataLoader.element_vfx_effects.get(ids[index]) as ElementVFXData
		manager.play_element_hit(position, data, 3)
		var label := Label.new()
		label.text = data.display_name
		label.size = Vector2(72, 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", data.secondary_tint)
		game.add_child(label)
		label.global_position = position + Vector2(-36, -54)
		labels.append(label)
	await get_tree().create_timer(0.09, true, false, true).timeout
	if DisplayServer.get_name() != "headless":
		await _save_viewport("%s/all_elements_hit_comparison.png" % OUTPUT_DIR)
	for label in labels:
		label.queue_free()
	for enemy in enemies:
		enemy.queue_free()
	player.global_position = origin
	await get_tree().process_frame

func _find_accent(manager: Node, element_id: String, level: int, name_part: String) -> Node2D:
	for child in manager.get_children():
		if child is Node2D and child.name.begins_with("ElementStackAccent_") and name_part in child.name and child.get_meta("element_id", "") == element_id and int(child.get_meta("variant_level", 0)) == level:
			return child
	return null

func _disable_background(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _remove_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

func _spawn_enemy_at(game: Node, position: Vector2, id: String) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = id
	data.display_name = "VFX Target"
	data.max_hp = 5000.0
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

func _count_prefix(root: Node, prefix: String) -> int:
	if root == null:
		return 0
	var count := 1 if root.name.begins_with(prefix) else 0
	for child in root.get_children():
		count += _count_prefix(child, prefix)
	return count

func _count_collision_nodes(root: Node) -> int:
	var count := 1 if root is CollisionObject2D or root is CollisionShape2D else 0
	for child in root.get_children():
		count += _count_collision_nodes(child)
	return count

func _save_viewport(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_check(error == OK, "%s screenshot write succeeds" % path)
	if error == OK:
		_captures.append(path)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
