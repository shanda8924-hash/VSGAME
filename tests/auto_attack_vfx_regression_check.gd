extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const OUTPUT_DIR := "res://artifacts/light_dark_vfx_polish"

var failures: Array[String] = []
var _attack_events := 0
var _element_damage_events := 0
var _level_feedback_events := 0
var _effect_ids: Array[String] = []
var _melee_themes: Array[String] = []
var _added_names: Array[String] = []
var _attack_animation_observed := false
var _captures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_check_ranged_theme_builders()
	await _run_case("light", "element_light")
	await _run_case("dark", "element_dark")
	for failure in failures:
		push_error(failure)
	print("AUTO_ATTACK_VFX_REGRESSION_CHECK failures=%d screenshots=%s" % [failures.size(), _captures])
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_case(element_name: String, element_id: String) -> void:
	_reset_observation()
	GameManager.selected_character_id = "swordsman"
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	_disable_background(game)
	await _remove_enemies()
	var player := game.get_node("Player") as Player
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	player.experience_component.level = 3
	GameManager.set_active_element(element_id)
	await get_tree().process_frame
	manager.effect_spawned.connect(_on_effect_spawned)
	manager.element_level_feedback_spawned.connect(func(_id, _level, _effect): _level_feedback_events += 1)
	player.weapon_manager.weapon_fired.connect(_on_weapon_fired.bind(player.weapon_manager))
	EventBus.element_damage_dealt.connect(_on_element_damage)
	get_tree().node_added.connect(_on_node_added)
	var enemy := _spawn_enemy(game, player)
	await get_tree().physics_frame
	var hp_before := enemy.health_component.current_hp
	player.weapon_manager._class_attack_cooldown = 0.01
	player.weapon_manager.process_mode = Node.PROCESS_MODE_INHERIT
	var elapsed := 0.0
	var captured := false
	while elapsed < 2.0 and (enemy.health_component.current_hp >= hp_before or not captured):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not captured and _attack_animation_observed and enemy.health_component.current_hp < hp_before:
			captured = true
			if DisplayServer.get_name() != "headless":
				await _save_viewport("%s/auto_attack_%s_clean.png" % [OUTPUT_DIR, element_name])
		if DisplayServer.get_name() == "headless" and _attack_events > 0:
			captured = true
	await get_tree().create_timer(0.2, true, false, true).timeout
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED

	_check(_attack_events == 1, "%s enemy approach triggers exactly one controlled auto attack" % element_name)
	_check(enemy.health_component.current_hp < hp_before, "%s auto attack keeps normal damage" % element_name)
	_check(_element_damage_events > 0, "%s auto attack keeps Element gameplay damage" % element_name)
	_check("attack_slash" not in _effect_ids and "hit_normal" not in _effect_ids and "hit_critical" not in _effect_ids, "%s removes the detached crescent and yellow Pixel Hit from Lightning melee" % element_name)
	_check(_level_feedback_events == 0, "%s auto attack does not replay level feedback" % element_name)
	_check(_melee_themes.size() == 1 and _melee_themes[0] == "lightning", "%s auto attack keeps Swordsman theme instead of active Element theme" % element_name)
	_check(_attack_animation_observed, "%s auto attack keeps the character attack animation" % element_name)
	_check("LightningHit" not in _added_names, "%s creates no base yellow Lightning particle" % element_name)
	_check(not ("LightHit" in _added_names or "LightHitEnhanced" in _added_names or "DarkHit" in _added_names or "DarkHitEnhanced" in _added_names), "%s auto attack adds no active Light/Dark Theme particle" % element_name)
	_check(_count_type(game, "Projectile") == 0, "%s melee auto attack creates no mystery Projectile" % element_name)
	_check(_count_prefix(game, "PixelVFX_attack_slash") == 0, "%s leaves no yellow crescent sprite in the live scene" % element_name)
	_check(_count_prefix(game, "PixelVFX_hit_") == 0, "%s leaves no yellow Pixel Hit sprite in the live scene" % element_name)
	_check(_count_prefix(game, "ElementLevelFeedback_") == 0, "%s auto attack leaves no level-up VFX" % element_name)

	get_tree().node_added.disconnect(_on_node_added)
	EventBus.element_damage_dealt.disconnect(_on_element_damage)
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _reset_observation() -> void:
	_attack_events = 0
	_element_damage_events = 0
	_level_feedback_events = 0
	_effect_ids.clear()
	_melee_themes.clear()
	_added_names.clear()
	_attack_animation_observed = false

func _check_ranged_theme_builders() -> void:
	GameManager.set_active_element("element_light")
	var archer_data := DataLoader.characters.get("archer") as CharacterData
	var archer_weapon := SpreadShotAttack.new()._build_weapon_data(archer_data)
	_check(archer_weapon.vfx_theme_id == archer_data.vfx_theme_id and archer_weapon.vfx_theme_id != "light", "Archer projectile keeps its class Theme under active Light")
	var wizard_data := DataLoader.characters.get("wizard") as CharacterData
	var wizard_weapon := HomingBoltAttack.new()._build_weapon_data(wizard_data)
	_check(wizard_weapon.vfx_theme_id == wizard_data.vfx_theme_id and wizard_weapon.vfx_theme_id != "light", "Wizard projectile keeps its class Theme under active Light")
	GameManager.set_active_element(GameManager.ELEMENT_NONE)

func _disable_background(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _remove_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

func _spawn_enemy(game: Node, player: Player) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "auto_attack_vfx_target"
	data.display_name = "Auto Attack Target"
	data.max_hp = 5000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(44, 0)
	return enemy

func _on_weapon_fired(manager: WeaponManagerComponent) -> void:
	_attack_events += 1
	var owner := manager.get_parent() as Player
	if owner and owner.animated_sprite.animation.begins_with("attack"):
		_attack_animation_observed = true
	manager._class_attack_cooldown = 999.0

func _on_element_damage(_amount: float, _position: Vector2, _element_id: String, _stack: int, _chain: int) -> void:
	_element_damage_events += 1

func _on_effect_spawned(effect_id: String, _effect: AnimatedSprite2D) -> void:
	_effect_ids.append(effect_id)

func _on_node_added(node: Node) -> void:
	_added_names.append(node.name)
	if node is MeleeHit:
		_melee_themes.append((node as MeleeHit).vfx_theme_id)

func _count_type(root: Node, type_name: String) -> int:
	var count := 1 if root.is_class(type_name) else 0
	for child in root.get_children():
		count += _count_type(child, type_name)
	return count

func _count_prefix(root: Node, prefix: String) -> int:
	var count := 1 if root.name.begins_with(prefix) else 0
	for child in root.get_children():
		count += _count_prefix(child, prefix)
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
