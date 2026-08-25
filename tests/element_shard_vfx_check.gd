extends Node
## 実game.tscn上で主属性切替、HUD、居合軌跡、属性Hit、run resetを確認する。

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const PROJECTILE_SCENE := preload("res://entities/projectiles/projectile.tscn")
const OUTPUT_DIR := "res://artifacts/equipment_element_polish"

var failures: Array[String] = []
var _spawned_element_effects: Dictionary = {}
var _captured_paths: Array[String] = []
var _can_capture := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_can_capture = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_check_registry()
	await _run_actual_game_check()
	for failure in failures:
		push_error(failure)
	print("ELEMENT_SHARD_VFX_CHECK failures=%d screenshots=%s" % [failures.size(), _captured_paths])
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_registry() -> void:
	var expected := {
		"element_fire": ["vfx_iai_fire_trail", "vfx_fire_hit"],
		"element_ice": ["vfx_iai_ice_trail", "vfx_ice_hit"],
		"element_lightning": ["vfx_iai_lightning_trail", "vfx_lightning_hit"],
		"element_light": ["vfx_iai_light_trail", "vfx_light_hit"],
		"element_dark": ["vfx_iai_dark_trail", "vfx_dark_hit"],
	}
	_check(DataLoader.element_vfx_effects.size() == expected.size(), "all five Element VFX resources are registered")
	for element_id in expected:
		var data: ElementVFXData = DataLoader.element_vfx_effects.get(element_id)
		_check(data != null, "%s resource resolves" % element_id)
		if data:
			_check(data.iai_trail_vfx_id == expected[element_id][0], "%s iai VFX ID" % element_id)
			_check(data.hit_vfx_id == expected[element_id][1], "%s hit VFX ID" % element_id)
			_check(data.iai_trail_sprite_sheet.get_size() == Vector2(384, 64), "%s trail sheet is 384x64" % element_id)
			_check(data.hit_sprite_sheet.get_size() == Vector2(384, 64), "%s hit sheet is 384x64" % element_id)
			if element_id == "element_lightning":
				_check(data.projectile_vfx_id == "vfx_lightning_projectile", "lightning projectile VFX ID")
				_check(data.chain_vfx_id == "vfx_lightning_chain", "lightning chain VFX ID")
				_check(data.projectile_sprite_sheet.get_size() == Vector2(384, 64), "lightning projectile sheet is 384x64")
				_check(data.chain_sprite_sheet.get_size() == Vector2(384, 64), "lightning chain sheet is 384x64")

func _run_actual_game_check() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var background_node := game.get_node_or_null(node_name)
		if background_node:
			background_node.process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

	var player := game.get_node("Player") as Player
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	var hud := game.get_node("HUD") as HUD
	_check(player != null and manager != null and hud != null, "actual game element nodes load")
	if player == null or manager == null or hud == null:
		return
	manager.element_effect_spawned.connect(_on_element_effect_spawned)
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	_check(GameManager.active_element_id == GameManager.ELEMENT_NONE, "run starts with no active element")
	_check("なし" in hud.active_element_label.text, "HUD starts with no element")

	var character_data: CharacterData = DataLoader.characters.get("swordsman")
	var original_params := character_data.active_skill_params.duplicate(true)
	character_data.active_skill_params["windup"] = 0.01
	character_data.active_skill_params["dash_distance"] = 72.0
	character_data.active_skill_params["dash_steps"] = 3.0
	character_data.active_skill_params["afterimage_lifetime"] = 0.12
	var start_position := player.global_position
	var cases := [
		["fire", "element_fire", "vfx_iai_fire_trail", "vfx_fire_hit", "火"],
		["ice", "element_ice", "vfx_iai_ice_trail", "vfx_ice_hit", "氷"],
		["lightning", "element_lightning", "vfx_iai_lightning_trail", "vfx_lightning_hit", "雷"],
		["light", "element_light", "vfx_iai_light_trail", "vfx_light_hit", "光"],
		["dark", "element_dark", "vfx_iai_dark_trail", "vfx_dark_hit", "闇"],
	]
	for entry in cases:
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		GameManager.held_fragment_ids.clear()
		var trail_scales: Array[float] = []
		for stack_level in range(1, 4):
			_spawned_element_effects.clear()
			player.global_position = start_position
			player.face_direction(Vector2.RIGHT)
			GameManager.add_fragment(entry[0])
			_check(GameManager.active_element_id == entry[1], "%s shard becomes primary element" % entry[0])
			_check(GameManager.get_element_stack(entry[1]) == stack_level, "%s reaches Lv%d" % [entry[0], stack_level])
			_check(GameManager.get_active_element_theme_id() == entry[0], "%s active element resolves existing Theme" % entry[0])
			_check(entry[4] in hud.active_element_label.text and "Lv%d" % stack_level in hud.active_element_label.text, "HUD shows %s Lv%d" % [entry[0], stack_level])
			var before_position := player.global_position
			await player.active_skill_component._swordsman_iai()
			_check(player.global_position != before_position, "%s Lv%d Iai uses actual dash motion" % [entry[0], stack_level])
			var trail: AnimatedSprite2D = _last_effect(entry[2])
			_check(trail != null and is_instance_valid(trail), "%s Lv%d Iai spawns visible trail" % [entry[0], stack_level])
			if trail and is_instance_valid(trail):
				trail_scales.append(trail.scale.y)
				_check(trail.sprite_frames.get_frame_count("play") == 6, "%s Iai trail has six frames" % entry[0])
				_check(trail.is_playing(), "%s Iai trail animation is playing" % entry[0])

			var enemy := _spawn_test_enemy(game, player)
			var hp_before := enemy.health_component.current_hp
			player.active_skill_component._damage_enemy(enemy, 5.0, 0.0)
			_check(enemy.health_component.current_hp < hp_before - 5.0, "%s Lv%d adds separate element damage" % [entry[0], stack_level])
			var hit: AnimatedSprite2D = _last_effect(entry[3])
			_check(hit != null and is_instance_valid(hit), "%s hit spawns element animation" % entry[0])
			if hit and is_instance_valid(hit):
				_check(hit.sprite_frames.get_frame_count("play") == 6, "%s hit has six frames" % entry[0])
			if _can_capture:
				await _save_viewport("%s/iai_%s_lv%d.png" % [OUTPUT_DIR, entry[0], stack_level])
			enemy.queue_free()
			await get_tree().create_timer(0.65, false).timeout
			_check(trail == null or not is_instance_valid(trail), "%s Iai trail expires naturally" % entry[0])
		_check(trail_scales.size() == 3 and trail_scales[0] < trail_scales[1] and trail_scales[1] < trail_scales[2], "%s Iai visual strengthens Lv1 to Lv3" % entry[0])
		if entry[0] == "lightning":
			var weapon := WeaponData.new()
			weapon.base_damage = 10.0
			weapon.crit_chance = 0.0
			weapon.crit_multiplier = 2.0
			weapon.vfx_theme_id = "lightning"
			var projectile := PROJECTILE_SCENE.instantiate() as Projectile
			game.add_child(projectile)
			projectile.global_position = player.global_position + Vector2(84.0, -24.0)
			projectile.speed = 0.0
			projectile.launch(projectile.global_position + Vector2(300.0, 0.0), weapon)
			await get_tree().create_timer(0.08, false).timeout
			var projectile_vfx := projectile.get_node_or_null("ElementProjectile_vfx_lightning_projectile") as AnimatedSprite2D
			_check(projectile.get_node("Visual").visible, "lightning keeps the intentional class projectile")
			_check(projectile.get_node("Glow").visible, "lightning class projectile keeps compact weapon glow")
			_check(projectile_vfx == null, "active element does not inject a replacement projectile")
			if _can_capture:
				await _save_viewport("%s/lightning_projectile_lv3.png" % OUTPUT_DIR)
			projectile.queue_free()
			await get_tree().process_frame

			var chain_targets: Array[EnemyBasic] = []
			for index in 4:
				var chain_target := _spawn_test_enemy(game, player)
				chain_target.global_position = player.global_position + Vector2(60.0 + index * 105.0, 0.0)
				chain_targets.append(chain_target)
			player.active_skill_component._damage_enemy(chain_targets[0], 60.0, 0.0)
			await get_tree().process_frame
			if _can_capture:
				await _save_viewport("%s/lightning_chain_lv3.png" % OUTPUT_DIR)
			for chain_target in chain_targets:
				chain_target.queue_free()
			await get_tree().process_frame

	# Fireが2個目の欠片としてFusionを完成させる実UI経路。選択用の暗幕が残らず、
	# pauseとFusion FlashのCanvasLayerが必ず解除されることを確認する。
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	GameManager.add_fragment("fire")
	var fragment_select := game.get_node("FragmentSelect") as FragmentSelect
	var screen_effects := game.get_node("ScreenEffects") as ScreenEffects
	fragment_select._open("Fire reward regression")
	var fire_button: Button = null
	for button in fragment_select.grid_container.get_children():
		if button is Button:
			var choice: Dictionary = button.get_meta("reward_choice", {})
			if String(choice.get("element_id", "")) != "element_fire":
				continue
			fire_button = button
			break
	_check(fire_button != null, "owned Fire reward is present in the four-choice UI")
	if fire_button:
		fire_button.pressed.emit()
	_check(not fragment_select.visible and not get_tree().paused and GameManager.active_modal_count == 0, "Fire Lv2 reward closes its modal and resumes the game")
	await get_tree().create_timer(0.7, true).timeout
	var fusion_layers := screen_effects.get_children().filter(func(child): return child is CanvasLayer)
	_check(fusion_layers.is_empty(), "Fire reward leaves no blackout CanvasLayer")
	_check(GameManager.active_element_id == "element_fire" and GameManager.get_element_stack("element_fire") == 2, "four-choice Fire reward advances the owned element")

	# Fusionの自動攻撃自体は仕様どおり維持しつつ、全属性で共通Arrow画像を混ぜない。
	var fusion_projectile_data := WeaponData.new()
	fusion_projectile_data.id = "element_projectile_visual_check"
	fusion_projectile_data.required_fragment_ids = ["fire", "ice"]
	fusion_projectile_data.projectile_scene = PROJECTILE_SCENE
	for element_id in ["element_fire", "element_ice", "element_lightning", "element_light", "element_dark"]:
		GameManager.set_active_element(element_id)
		var fusion_projectile := PROJECTILE_SCENE.instantiate() as Projectile
		game.add_child(fusion_projectile)
		fusion_projectile.global_position = player.global_position
		fusion_projectile.launch(player.global_position + Vector2(300.0, 0.0), fusion_projectile_data)
		_check(not fusion_projectile.get_node("Visual").visible, "%s Fusion projectile does not show the shared Arrow" % element_id)
		_check(fusion_projectile.get_node("Glow").visible, "%s Fusion projectile keeps its own compact weapon glow" % element_id)
		fusion_projectile.queue_free()
		await get_tree().process_frame

	# 本来矢を撃つ職業Projectileは属性を取ってもArrowのまま。過剰な一括非表示を防ぐ。
	GameManager.set_active_element("element_fire")
	var class_projectile_data := WeaponData.new()
	class_projectile_data.projectile_scene = PROJECTILE_SCENE
	var class_projectile := PROJECTILE_SCENE.instantiate() as Projectile
	game.add_child(class_projectile)
	class_projectile.global_position = player.global_position
	class_projectile.launch(player.global_position + Vector2(300.0, 0.0), class_projectile_data)
	_check(class_projectile.get_node("Visual").visible, "fire does not remove Arrow from an intentional class projectile")
	class_projectile.queue_free()
	await get_tree().process_frame

	GameManager.end_run()
	_check(GameManager.active_element_id == GameManager.ELEMENT_NONE, "run end resets active element")
	_check("なし" in hud.active_element_label.text, "HUD resets to no element at run end")
	# 実ResultScreenはrun_endedでツリーを停止する。検証後のcleanupと結果出力だけ再開する。
	get_tree().paused = false
	character_data.active_skill_params = original_params
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _spawn_test_enemy(game: Node, player: Player) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "element_vfx_target"
	data.display_name = "Element VFX Target"
	data.max_hp = 1000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(42.0, 0.0)
	return enemy

func _on_element_effect_spawned(effect_id: String, effect: AnimatedSprite2D) -> void:
	if not _spawned_element_effects.has(effect_id):
		_spawned_element_effects[effect_id] = []
	_spawned_element_effects[effect_id].append(effect)

func _last_effect(effect_id: String) -> AnimatedSprite2D:
	var entries: Array = _spawned_element_effects.get(effect_id, [])
	return entries.back() as AnimatedSprite2D if not entries.is_empty() else null

func _save_viewport(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_check(error == OK, "%s screenshot write succeeds" % path)
	if error == OK:
		_captured_paths.append(path)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
