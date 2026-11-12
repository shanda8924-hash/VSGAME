extends Node
## 実際のgame.tscnと通常攻撃ループを動かし、攻撃・命中VFXと地面装備を検証する。

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const GROUND_EQUIPMENT_SCENE := preload("res://entities/pickups/ground_equipment_item.tscn")
const OUTPUT_DIR := "res://artifacts/visual_checks"

var failures: Array[String] = []
var _spawned_effects: Dictionary = {}
var _captured_paths: Array[String] = []
var _can_capture := false

func _ready() -> void:
	_can_capture = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_check_vfx_registry()
	await _run_character_case("swordsman", "", false)
	await _run_character_case("archer", "attack_projectile", true)
	for failure in failures:
		push_error(failure)
	print("GAMEPLAY_VFX_CAPTURE failures=%d screenshots=%s" % [failures.size(), _captured_paths])
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_vfx_registry() -> void:
	var expected_ids := ["attack_slash", "attack_projectile", "attack_pulse", "hit_normal", "hit_critical"]
	_check(DataLoader.attack_vfx_effects.size() == expected_ids.size(), "five Pixel VFX resources are registered")
	for effect_id in expected_ids:
		var data: AttackVFXData = DataLoader.attack_vfx_effects.get(effect_id)
		_check(data != null, "%s resource resolves" % effect_id)
		if data:
			_check(data.frame_count == 6, "%s resource declares six frames" % effect_id)
			_check(data.sprite_sheet != null and int(data.sprite_sheet.get_width()) == int(data.sprite_sheet.get_height()) * 6, "%s sprite sheet has 6 square frames" % effect_id)
	var character_ids: Array = DataLoader.characters.keys()
	character_ids.sort()
	_check(character_ids.size() == 10, "VFX mapping covers ten playable characters")
	for character_id in character_ids:
		var character_data: CharacterData = DataLoader.characters[character_id]
		_check(
			AttackVFXManager.PATTERN_EFFECT_IDS.has(character_data.attack_pattern_id),
			"%s attack pattern maps to Pixel VFX" % character_id
		)

func _run_character_case(character_id: String, expected_attack_id: String, force_critical: bool) -> void:
	_spawned_effects.clear()
	GameManager.selected_character_id = character_id
	var character_data: CharacterData = DataLoader.characters.get(character_id)
	_check(character_data != null, "%s character data loads" % character_id)
	if character_data == null:
		return
	var original_crit_chance := character_data.crit_chance
	character_data.crit_chance = 1.0 if force_critical else 0.0

	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_disable_background_spawners(game)
	_remove_automatic_enemies()

	var player := game.get_node("Player") as Player
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	_check(player != null and manager != null, "%s actual game nodes load" % character_id)
	if player == null or manager == null:
		character_data.crit_chance = original_crit_chance
		game.queue_free()
		await get_tree().process_frame
		return
	manager.effect_spawned.connect(_on_effect_spawned)
	player.health_component.invincible = true
	player.upgrades_component.crit_rate_bonus = 0.0 if not force_critical else 1.0
	_spawn_ground_equipment(game, player)
	await get_tree().physics_frame
	_hide_ground_equipment_labels()
	if _can_capture and character_id == "swordsman":
		await _save_viewport("%s/ground_equipment_loot_beams.png" % OUTPUT_DIR)
	var enemy := _spawn_test_enemy(game, player, character_id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp_before := enemy.health_component.current_hp

	# 初期クールダウンだけ短縮し、その後は通常のWeaponManager._processから攻撃させる。
	player.weapon_manager._class_attack_cooldown = 0.01
	var attack_path := "%s/%s_attack.png" % [OUTPUT_DIR, character_id]
	var hit_path := "%s/%s_%s.png" % [OUTPUT_DIR, character_id, "critical_hit" if force_critical else "normal_hit"]
	if expected_attack_id == "":
		await _wait_for_attack_animation(player, attack_path, 3.0)
	else:
		await _wait_for_animated_effect(expected_attack_id, attack_path, 3.0)
	var expected_hit_id := "" if character_data.vfx_theme_id == "lightning" else ("hit_critical" if force_critical else "hit_normal")
	if expected_hit_id == "":
		await _wait_for_damage_without_yellow_hit(enemy, hp_before, hit_path, 3.0)
	else:
		await _wait_for_animated_effect(expected_hit_id, hit_path, 3.0)

	if expected_attack_id == "":
		_check(not _spawned_effects.has("attack_slash"), "%s normal attack omits the detached crescent sprite" % character_id)
	else:
		_check(_spawned_effects.has(expected_attack_id), "%s normal attack reaches %s" % [character_id, expected_attack_id])
	if expected_hit_id == "":
		_check(not _spawned_effects.has("hit_normal") and not _spawned_effects.has("hit_critical"), "%s actual hit omits the yellow Pixel Hit" % character_id)
	else:
		_check(_spawned_effects.has(expected_hit_id), "%s actual hit reaches %s" % [character_id, expected_hit_id])
	_check(enemy.health_component.current_hp < enemy.health_component.max_hp, "%s existing damage pipeline still applies damage" % character_id)
	if _can_capture:
		_check(FileAccess.file_exists(attack_path), "%s attack screenshot saved" % character_id)
		_check(FileAccess.file_exists(hit_path), "%s hit screenshot saved" % character_id)

	character_data.crit_chance = original_crit_chance
	game.queue_free()
	for node in get_children():
		if node != game and (node is MeleeHit or node is Projectile):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _disable_background_spawners(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _remove_automatic_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

func _spawn_test_enemy(game: Node, player: Player, character_id: String) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "vfx_capture_target"
	data.display_name = "VFX Capture Target"
	data.max_hp = 5000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	enemy.visual_scale_multiplier = 1.0
	game.add_child(enemy)
	var distance := 48.0 if character_id == "swordsman" else 112.0
	enemy.global_position = player.global_position + Vector2(distance, 0.0)
	return enemy

func _spawn_ground_equipment(game: Node, player: Player) -> void:
	var entries := [
		["rare", "res://assets/items/head/head_helm_rare_001.png", Vector2(-106, 62)],
		["epic", "res://assets/items/body/body_armor_epic_001.png", Vector2(-38, 72)],
		["legendary", "res://assets/items/weapons/weapon_axe_legendary_001.png", Vector2(38, 72)],
		["mythic", "res://assets/items/accessories/accessory_relic_mythic_001.png", Vector2(106, 62)],
	]
	for entry in entries:
		var data := EquipmentData.new()
		data.instance_id = "capture_%s" % entry[0]
		data.display_name = "%s Equipment" % String(entry[0]).capitalize()
		data.slot = "weapon"
		data.rarity = entry[0]
		data.icon_path = entry[1]
		var ground := GROUND_EQUIPMENT_SCENE.instantiate() as GroundEquipmentItem
		ground.setup(data)
		game.add_child(ground)
		ground.global_position = player.global_position + entry[2]

func _on_effect_spawned(effect_id: String, effect: AnimatedSprite2D) -> void:
	if not _spawned_effects.has(effect_id):
		_spawned_effects[effect_id] = effect

func _wait_for_animated_effect(effect_id: String, screenshot_path: String, timeout_seconds: float) -> void:
	var elapsed := 0.0
	var first_frame := -1
	while elapsed < timeout_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var effect: AnimatedSprite2D = _spawned_effects.get(effect_id)
		if effect == null or not is_instance_valid(effect):
			continue
		if first_frame < 0:
			first_frame = effect.frame
		if effect.frame >= 2 or effect.frame != first_frame:
			_check(effect.sprite_frames.get_frame_count("play") == 6, "%s uses six sprite frames" % effect_id)
			_check(effect.is_playing(), "%s AnimatedSprite2D is playing" % effect_id)
			if not _can_capture:
				return
			_hide_ground_equipment_labels()
			await _save_viewport(screenshot_path)
			return
	_check(false, "%s visible animation advances before timeout" % effect_id)

func _wait_for_attack_animation(player: Player, screenshot_path: String, timeout_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not player.animated_sprite.animation.begins_with("attack"):
			continue
		_check(not _spawned_effects.has("attack_slash"), "melee animation runs without the detached crescent sprite")
		if not _can_capture:
			return
		_hide_ground_equipment_labels()
		await _save_viewport(screenshot_path)
		return
	_check(false, "character attack animation starts before timeout")

func _wait_for_damage_without_yellow_hit(enemy: EnemyBasic, hp_before: float, screenshot_path: String, timeout_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if enemy.health_component.current_hp >= hp_before:
			continue
		await get_tree().process_frame
		_check(not _spawned_effects.has("hit_normal") and not _spawned_effects.has("hit_critical"), "Lightning melee damage lands without a yellow Pixel Hit")
		if not _can_capture:
			return
		_hide_ground_equipment_labels()
		await _save_viewport(screenshot_path)
		return
	_check(false, "Lightning melee damage lands before timeout")

func _hide_ground_equipment_labels() -> void:
	for ground in get_tree().get_nodes_in_group("ground_equipment"):
		if is_instance_valid(ground):
			ground._set_nearby_visible(false)

func _save_viewport(screenshot_path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(screenshot_path))
	_check(error == OK, "%s screenshot write succeeds" % screenshot_path)
	if error == OK:
		_captured_paths.append(screenshot_path)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
