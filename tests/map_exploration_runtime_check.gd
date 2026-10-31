extends Node
## game.tscnを通常のMain Runtimeとして起動したまま、3MAP→各Boss→Boss宝箱→
## 次MAP→Run Clearを実経路で短縮確認する。`-- --map-runtime-check`でのみ動く。

var failures: Array[String] = []
var controller: MapRunController
var boss_spawner: BossSpawner
var player: Player
var equipment_drop_system: EquipmentDropSystem
var stage_environment: StageEnvironment
var wave_spawner: WaveSpawner
var _combat_target_id := 0
var _combat_ignored_target_id := 0
var _combat_last_target_distance := INF
var _combat_stuck_ticks := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	controller = get_parent().get_node("MapRunController") as MapRunController
	boss_spawner = get_parent().get_node("BossSpawner") as BossSpawner
	player = get_parent().get_node("Player") as Player
	equipment_drop_system = get_parent().get_node("EquipmentDropSystem") as EquipmentDropSystem
	stage_environment = get_parent().get_node("StageEnvironment") as StageEnvironment
	wave_spawner = get_parent().get_node("WaveSpawner") as WaveSpawner
	_run.call_deferred()

func _run() -> void:
	if "--map-phase2-check" in OS.get_cmdline_user_args():
		await _run_phase2_check()
		return
	if "--map-gui-capture" in OS.get_cmdline_user_args():
		await _run_gui_capture()
		return
	if "--map-combat-check" in OS.get_cmdline_user_args():
		await _run_combat_gate_check()
		return
	if "--map-soak-check" in OS.get_cmdline_user_args():
		await _run_soak()
		return
	await _wait_frames(8)
	_expect(GameManager.map_mode_active, "通常起動がMAP modeではありません")
	_expect(GameManager.current_map_index == 1, "MAP 1から開始していません")
	# 属性祭壇廃止後の構成は宝箱4 + 回復祭壇1 + Boss Gate1。
	_expect(get_tree().get_nodes_in_group("map_content").size() >= 6, "MAP配置物が不足しています")
	player.health_component.max_hp = 1000000.0
	player.health_component.current_hp = 1000000.0
	# XP Level Upが属性Lv・属性深化・汎用を含む単一3択へ接続されることを確認。
	EventBus.player_leveled_up.emit(2)
	await _wait_frames(2)
	var level_up_select := get_parent().get_node("LevelUpSelect") as LevelUpSelect
	_expect(level_up_select.visible, "Level Upで統合3択が開きません")
	_press_first_enabled_button(level_up_select)
	await _wait_frames(2)
	_expect(not level_up_select.visible, "Level Up選択を確定できません")

	for expected_map in [1, 2, 3]:
		_expect(GameManager.current_map_index == expected_map, "MAP %dへ遷移していません" % expected_map)
		await _verify_surges_for_current_map(expected_map)
		controller.debug_force_boss_ready()
		controller.debug_start_boss()
		await _wait_frames(3)
		_expect(is_instance_valid(boss_spawner.debug_get_current_boss()), "MAP %d Bossが生成されません" % expected_map)
		boss_spawner.debug_defeat_current_boss()
		await _wait_frames(5)
		await _close_visible_reward_modals()
		var boss_chest := _find_boss_chest()
		_expect(is_instance_valid(boss_chest), "MAP %d Boss宝箱が生成されません" % expected_map)
		if not is_instance_valid(boss_chest):
			break
		var cleanup_probe_ref: WeakRef = null
		if expected_map < 3:
			var cleanup_probe := equipment_drop_system.debug_drop_equipment(_make_ground_cleanup_probe(expected_map), player.global_position)
			await _wait_frames(2)
			_expect(is_instance_valid(cleanup_probe), "MAP %d cleanup probe床装備を生成できません" % expected_map)
			if is_instance_valid(cleanup_probe):
				cleanup_probe_ref = weakref(cleanup_probe)
		boss_chest._on_body_entered(player)
		_expect(boss_chest.interact(player), "MAP %d Boss宝箱をE相当で開けません" % expected_map)
		await _wait_frames(3)
		await _close_visible_reward_modals()
		if expected_map < 3:
			await _wait_until_map(expected_map + 1, 240)
			await _wait_frames(2)
			_expect(cleanup_probe_ref != null and cleanup_probe_ref.get_ref() == null, "MAP %d遷移後も旧MAPの床装備が残っています" % expected_map)
			var profile: Dictionary = controller.debug_get_map_state().get("transition_profile", {})
			var max_slice := float(profile.get("max_slice_ms", 999.0))
			print("MAP_RUNTIME_TRANSITION map=%d total_ms=%.3f max_slice_ms=%.3f max_phase=%s frames=%d" % [expected_map + 1, float(profile.get("total_ms", 0.0)), max_slice, String(profile.get("max_phase", "")), int(profile.get("frames", 0))])
			_expect(max_slice < 50.0, "MAP transition frame sliceが50ms以上です: %.3fms" % max_slice)
		else:
			await _wait_frames(6)

	_expect(GameManager.run_state == GameManager.RunState.RESULT, "MAP 3後にRun Clearへ到達しません")
	if failures.is_empty():
		_finish_test(0, "MAP_EXPLORATION_RUNTIME_CHECK: PASS")
	else:
		for message in failures:
			push_error("MAP_EXPLORATION_RUNTIME_CHECK: %s" % message)
		_finish_test(1, "")

func _run_phase2_check() -> void:
	await _wait_frames(10)
	wave_spawner.set_spawning_paused(true)
	var character := DataLoader.characters.get(GameManager.selected_character_id) as CharacterData
	_expect(character != null, "選択職業Dataを読めません")
	if character:
		_expect(is_equal_approx(player.movement_component.base_speed, character.move_speed * Player.MOVE_SPEED_MULTIPLIER), "Player移動速度10%減が反映されません")
	_expect(player.animated_sprite.scale.is_equal_approx(Vector2(1.65, 1.65)), "Player表示倍率が1.65ではありません")
	_expect(player.experience_component.exp_to_next_level == 10, "MAP1初回必要EXPが通常敵約10体分になっていません")
	_expect(ExperienceComponent.required_exp_for_level(9) == 26, "Lv10までの必要EXPが軽快な曲線ではありません")
	_expect(ExperienceComponent.required_exp_for_level(10) == 28, "Lv10境界の必要EXPが不正です")
	_expect(ExperienceComponent.required_exp_for_level(20) > ExperienceComponent.required_exp_for_level(19) + 4, "Lv10以降の必要EXPが徐々に重くなっていません")

	var map_started := wave_spawner._map_started_elapsed
	GameManager.elapsed_seconds = map_started
	var early := wave_spawner.debug_get_map_spawn_snapshot()
	GameManager.elapsed_seconds = map_started + 300.0
	var middle := wave_spawner.debug_get_map_spawn_snapshot()
	GameManager.elapsed_seconds = map_started + 600.0
	var late := wave_spawner.debug_get_map_spawn_snapshot()
	_expect(is_equal_approx(float(early.get("base_spawn_interval", 0.0)), 2.8), "序盤Spawn間隔が2.8秒ではありません")
	_expect(int(early.get("base_batch_max", 0)) == 1, "序盤が1体Spawnに制限されていません")
	_expect(float(middle.get("base_spawn_interval", 99.0)) < 1.4 and int(middle.get("base_batch_max", 0)) >= 3, "中盤Spawnが段階上昇していません")
	_expect(float(late.get("base_spawn_interval", 99.0)) < 0.7 and int(late.get("base_batch_min", 0)) >= 5 and int(late.get("base_batch_max", 0)) >= 8, "終盤Spawnが大群密度になっていません")
	_expect(int(late.get("enemy_cap", 0)) == 96, "MAP1の生存敵上限が96体ではありません")
	_expect(is_equal_approx(wave_spawner._map_hp_multiplier, 2.8), "MAP1通常敵HP倍率が2.8ではありません")

	var enemy := preload("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	enemy.enemy_data = DataLoader.enemies.get("basic_enemy")
	GameManager.get_runtime_world(self).add_child(enemy)
	_expect(enemy.animated_sprite.scale.is_equal_approx(Vector2(1.4, 1.4)), "通常敵表示倍率が1.40ではありません")
	var enemy_shape := enemy.hurtbox_component.get_node("CollisionShape2D") as CollisionShape2D
	_expect(enemy_shape.shape is RectangleShape2D and is_equal_approx((enemy_shape.shape as RectangleShape2D).size.x, 39.2), "通常敵の見た目と被弾判定が同じ倍率で拡大されていません")
	enemy.queue_free()
	await _wait_frames(2)

	var source_heights := {
		"black_knight_a": 33.0, "black_knight_b": 24.0, "black_knight_c": 31.0,
		"demon_a": 22.0, "demon_b": 21.0, "demon_c": 28.0, "demon_d": 27.0,
		"demon_e": 25.0, "flame_golem": 31.0, "minotaur": 22.0,
	}
	for boss_id: String in source_heights.keys():
		var boss := boss_spawner._spawn_boss_by_id(boss_id, player.global_position + Vector2(160.0, 0.0)) as EnemyBasic
		_expect(is_instance_valid(boss), "%sを生成できません" % boss_id)
		if not is_instance_valid(boss):
			continue
		var visible_height := float(source_heights[boss_id]) * boss.animated_sprite.scale.y
		_expect(absf(visible_height - 65.0) <= 0.2, "%sの実表示高が共通65pxから外れています: %.2f" % [boss_id, visible_height])
		if boss_id == "minotaur":
			await _verify_minotaur_patterns(boss)
		boss_spawner.clear_room_boss()
		await _wait_frames(2)

	_expect(get_tree().get_nodes_in_group("boss_attack_transient").is_empty(), "ボス攻撃予兆/剣撃が終了後に残っています")
	Engine.time_scale = 1.0
	if failures.is_empty():
		_finish_test(0, "MAP_PHASE2_CHECK: PASS player_speed=90% exp=10->progressive spawn_batch=1->8-12 cap=96 boss_height=65px minotaur_patterns=4")
	else:
		for message in failures:
			push_error("MAP_PHASE2_CHECK: %s" % message)
		_finish_test(1, "")

func _verify_minotaur_patterns(boss: EnemyBasic) -> void:
	_expect(boss.boss_attack_component != null, "ミノタウロスにBossAttackComponentがありません")
	if boss.boss_attack_component == null:
		return
	var strategy := boss.boss_attack_component.attack_strategy as MinotaurComboStrategy
	_expect(strategy != null, "ミノタウロスへ4攻撃Strategyが接続されていません")
	if strategy == null:
		return
	boss.boss_attack_component.set_process(false)
	player.health_component.max_hp = 1000000.0
	player.health_component.current_hp = 1000000.0
	Engine.time_scale = 8.0
	for expected_pattern in ["charge", "cleave", "ring", "barrage"]:
		if expected_pattern == "cleave":
			# 実描画を目視確認できるよう、剣撃が最大展開する瞬間だけ等速で保存する。
			Engine.time_scale = 1.0
			strategy.execute(boss, player)
			await get_tree().create_timer(1.22, true, false, true).timeout
			if DisplayServer.get_name() != "headless":
				_capture_viewport("res://artifacts/map_phase2_minotaur_cleave.png")
			await get_tree().create_timer(1.92, true, false, true).timeout
			Engine.time_scale = 8.0
		else:
			await strategy.execute(boss, player)
		_expect(strategy.last_pattern == expected_pattern, "ミノタウロス攻撃順が不一致です: %s" % expected_pattern)
	_expect(strategy.attack_count == 4, "ミノタウロス4攻撃を完走していません")
	_expect(boss.animated_sprite.sprite_frames.has_animation("cleave_side"), "元画像加工の全身薙ぎ払いAnimationが2Dへ接続されていません")
	Engine.time_scale = 1.0

func _make_ground_cleanup_probe(map_index: int) -> EquipmentData:
	var item := EquipmentData.new()
	item.instance_id = "map_cleanup_probe_%d" % map_index
	item.template_id = "performance_probe"
	item.display_name = "Map Cleanup Probe"
	item.slot = "weapon"
	item.rarity = "uncommon"
	item.icon_path = "res://assets/items/weapons/weapon_sword_uncommon_001.png"
	return item

func _verify_surges_for_current_map(map_index: int) -> void:
	var base_spawn := wave_spawner.debug_get_map_spawn_snapshot()
	var rewards_before := int(controller.debug_get_map_state().get("surge_reward_count", 0))
	var last_surge_interval := 0.0
	for trigger_reason in ["kills", "time", "kills"]:
		controller.debug_trigger_next_surge(trigger_reason)
		await _wait_frames(20)
		var active_state := controller.debug_get_map_state()
		var surge_spawn := wave_spawner.debug_get_map_spawn_snapshot()
		last_surge_interval = float(surge_spawn.get("spawn_interval", 0.0))
		_expect(bool(active_state.get("surge_active", false)), "MAP %d %s経路でSurgeが開始しません" % [map_index, trigger_reason])
		_expect(String(active_state.get("surge_trigger_reason", "")) == trigger_reason, "MAP %d Surge発動理由が不一致です" % map_index)
		_expect(float(surge_spawn.get("spawn_interval", 999.0)) <= float(surge_spawn.get("base_spawn_interval", 0.0)) * 0.55, "MAP %d Surge間隔が短縮されていません" % map_index)
		_expect(int(surge_spawn.get("batch_max", 0)) >= ceili(float(surge_spawn.get("base_batch_max", 0)) * 1.5), "MAP %d Surge同時出現数が増えていません" % map_index)
		_expect(int(surge_spawn.get("enemy_cap", -1)) == int(base_spawn.get("enemy_cap", -2)), "MAP %d SurgeがEnemy上限を変更しました" % map_index)
		_expect(is_equal_approx(float(surge_spawn.get("damage_multiplier", -1.0)), float(base_spawn.get("damage_multiplier", -2.0))), "MAP %d Surgeが敵Damage倍率を変更しました" % map_index)
		_expect(stage_environment._tile_map_layer.self_modulate != Color.WHITE, "MAP %d Surge色調変化が適用されません" % map_index)
		controller.debug_finish_surge()
		await _wait_frames(4)
		_expect(not bool(controller.debug_get_map_state().get("surge_active", true)), "MAP %d Surgeが終了しません" % map_index)
	_expect(int(controller.debug_get_map_state().get("surge_reward_count", 0)) == rewards_before + 3, "MAP %d Surge確定報酬が3回生成されません" % map_index)
	print("MAP_SURGE_RUNTIME map=%d completed=3 rewards=3 base_interval=%.3f surge_interval=%.3f cap=%d damage=%.2f" % [
		map_index,
		float(base_spawn.get("base_spawn_interval", 0.0)),
		last_surge_interval,
		int(base_spawn.get("enemy_cap", 0)),
		float(base_spawn.get("damage_multiplier", 0.0)),
	])

func _run_gui_capture() -> void:
	player.health_component.max_hp = 1000000.0
	player.health_component.current_hp = 1000000.0
	await _wait_frames(90)
	_capture_viewport("res://artifacts/map_exploration_start.png")
	var map := GameManager.dungeon_map
	for region_type in DungeonMap.COMBAT_REGION_TYPES:
		var room_index := _find_region_room_index(map, region_type)
		_expect(room_index >= 0, "GUI capture対象%sがありません" % region_type)
		if room_index < 0:
			continue
		player.global_position = map.grid_to_world(map.rooms[room_index].position + map.rooms[room_index].size / 2)
		await _wait_frames(24)
		_capture_viewport("res://artifacts/map_region_%s.png" % region_type)
	controller.debug_trigger_next_surge("kills")
	await _wait_frames(30)
	_capture_viewport("res://artifacts/map_surge.png")
	controller.debug_finish_surge()
	controller.debug_force_boss_ready()
	if is_instance_valid(controller._boss_gate):
		player.global_position = controller._boss_gate.global_position + Vector2(-72, 0)
	await _wait_frames(20)
	_capture_viewport("res://artifacts/map_exploration_boss_gate.png")
	controller.debug_start_boss()
	await _wait_frames(25)
	_capture_viewport("res://artifacts/map_exploration_boss_fight.png")
	_finish_test(0, "MAP_EXPLORATION_GUI_CAPTURE: PASS")

func _find_region_room_index(map: DungeonMap, region_type: String) -> int:
	for room_index_variant in map.combat_region_by_room.keys():
		var room_index := int(room_index_variant)
		if String(map.combat_region_by_room[room_index]) == region_type:
			return room_index
	return -1

func _capture_viewport(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	_expect(error == OK, "GUI capture保存失敗: %s" % path)

func _run_combat_gate_check() -> void:
	await _wait_frames(8)
	player.health_component.max_hp = 1000000000.0
	player.health_component.current_hp = 1000000000.0
	Engine.time_scale = 4.0
	await _open_regular_chests()
	# MAP開始直後に宝箱を全開封する機械TestではAttribute未取得のためSkill候補が
	# 空になり、今回のMain Loop（Attribute→大型Skill→大量殲滅）を評価できない。
	# 実プレイのMAP1中盤相当として雷Lv3＋雷帝落雷Lv1を再現し、通常移動/実Hitboxと
	# Cooldown自動大技の合算で撃破Gateへ届くかを測る。
	var concept := get_parent().get_node("ConceptSystem") as ConceptSystem
	concept.acquire_completed_skill("thunderlord_descent")
	concept.set_active(true)
	var kill_requirement := int(controller._current_config.get("boss_kill_requirement", 420))
	var local_started := GameManager.elapsed_seconds
	var next_wall_status := Time.get_ticks_msec() + 10000
	# 代表的なMAP1完成Skill Buildで想定上限（14分）内に条件へ届くことを確認する。
	while int(controller.debug_get_map_state().get("kills", 0)) < kill_requirement and GameManager.elapsed_seconds - local_started < 840.0:
		await _close_visible_reward_modals()
		_drive_soak_combat()
		await _wait_frames(4)
		if Time.get_ticks_msec() >= next_wall_status:
			next_wall_status += 10000
			print("MAP_EXPLORATION_COMBAT progress kills=%d/%d elapsed=%.1f scale=%.2f paused=%s modals=%d" % [int(controller.debug_get_map_state().get("kills", 0)), kill_requirement, GameManager.elapsed_seconds - local_started, Engine.time_scale, get_tree().paused, GameManager.active_modal_count])
	_release_soak_movement()
	var natural_kills := int(controller.debug_get_map_state().get("kills", 0))
	_expect(natural_kills >= kill_requirement, "MAP1の自然撃破数がBoss条件未達です: %d/%d" % [natural_kills, kill_requirement])
	Engine.time_scale = 1.0
	if failures.is_empty():
		_finish_test(0, "MAP_EXPLORATION_COMBAT_CHECK: PASS natural_kills=%d required=%d logical_seconds=%.1f" % [natural_kills, kill_requirement, GameManager.elapsed_seconds - local_started])
	else:
		for message in failures:
			push_error("MAP_EXPLORATION_COMBAT_CHECK: %s" % message)
		_finish_test(1, "")

func _run_soak() -> void:
	await _wait_frames(8)
	player.health_component.max_hp = 1000000000.0
	player.health_component.current_hp = 1000000000.0
	# 論理30分のLifecycleを短時間化する。自然Spawn/移動/攻撃のHitbox確認は同じ
	# Testを4倍でMAP1解放条件まで別途実測し、Soak本体は20倍で全3MAPを回す。
	Engine.time_scale = 20.0
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_movement_locked(true)
	var run_started_at := GameManager.elapsed_seconds
	for expected_map in [1, 2, 3]:
		# 直前MAPのBoss撃破Hit Stopは正常に1倍へ復帰するため、Test短縮倍率だけ
		# 各MAP開始時に張り直す。
		Engine.time_scale = 20.0
		_expect(GameManager.current_map_index == expected_map, "Soak MAP %d開始に失敗" % expected_map)
		await _open_regular_chests()
		var required := float(controller._current_config.get("target_duration_seconds", 660.0))
		var local_started := GameManager.elapsed_seconds
		var next_combat_status := local_started + 20.0
		while GameManager.elapsed_seconds - local_started < required + 1.0:
			await _close_visible_reward_modals()
			_resolve_soak_elites()
			await _wait_frames(4)
			if GameManager.elapsed_seconds >= next_combat_status:
				next_combat_status += 120.0
				_print_soak_combat_status(expected_map)
		_release_soak_movement()
		var enemy_cap := int(controller._current_config.get("enemy_cap", 60))
		var kill_requirement := int(controller._current_config.get("boss_kill_requirement", 60))
		var map_state := controller.debug_get_map_state()
		var natural_kills := int(map_state.get("kills", 0))
		var living_enemies := get_tree().get_nodes_in_group("enemies").size()
		print("MAP_EXPLORATION_SOAK map=%d natural_kills=%d required=%d living=%d" % [expected_map, natural_kills, kill_requirement, living_enemies])
		_expect(living_enemies > 0, "MAP %dで自然Spawnが動いていません" % expected_map)
		_expect(int(map_state.get("surge_index", 0)) == 3, "MAP %dで時間経路Surge 3回が完了していません" % expected_map)
		_expect(int(map_state.get("surge_reward_count", 0)) == 3, "MAP %dでSurge確定報酬が3回出ていません" % expected_map)
		# 通常上限外に、部屋Elite最大2×複数Triggerと巡回Eliteが一時共存し得る。
		_expect(living_enemies <= enemy_cap + 6, "MAP %d enemy cap超過" % expected_map)
		controller.debug_force_boss_ready()
		controller.debug_start_boss()
		await _wait_frames(3)
		_expect(is_instance_valid(boss_spawner.debug_get_current_boss()), "Soak MAP %d Boss生成失敗" % expected_map)
		boss_spawner.debug_defeat_current_boss()
		await _wait_frames(5)
		await _close_visible_reward_modals()
		var boss_chest := _find_boss_chest()
		if is_instance_valid(boss_chest):
			boss_chest._on_body_entered(player)
			boss_chest.interact(player)
			await _wait_frames(3)
			await _close_visible_reward_modals()
		else:
			_expect(false, "Soak MAP %d Boss宝箱なし" % expected_map)
		if expected_map < 3:
			await _wait_until_map(expected_map + 1, 360)
		else:
			await _wait_frames(8)
	var logical_duration := GameManager.elapsed_seconds - run_started_at
	_expect(logical_duration >= 1800.0, "30分未満で終了しました: %.1f秒" % logical_duration)
	_expect(GameManager.run_state == GameManager.RunState.RESULT, "Soak完走後にResultへ到達しません")
	Engine.time_scale = 1.0
	if failures.is_empty():
		_finish_test(0, "MAP_EXPLORATION_SOAK_CHECK: PASS logical_seconds=%.1f" % logical_duration)
	else:
		for message in failures:
			push_error("MAP_EXPLORATION_SOAK_CHECK: %s" % message)
		_finish_test(1, "")

func _open_regular_chests() -> void:
	_release_soak_movement()
	var chests: Array[TreasureChest] = []
	for node in get_tree().get_nodes_in_group("map_content"):
		if node is TreasureChest and not node.is_boss_chest and not node.is_opened:
			chests.append(node as TreasureChest)
	for chest in chests:
		chest._on_body_entered(player)
		chest.interact(player)
		await _wait_frames(2)
		await _close_visible_reward_modals()

func _drive_soak_combat() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies").filter(func(enemy):
		return is_instance_valid(enemy) and enemy.get_node_or_null("HealthComponent") != null and (enemy.get_node("HealthComponent") as HealthComponent).current_hp > 0.0
	)
	if enemies.is_empty():
		_release_soak_movement()
		return
	var nearest: Node2D = null
	var nearest_distance := INF
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if enemy.get_instance_id() == _combat_target_id:
			nearest = enemy
			nearest_distance = player.global_position.distance_to(enemy.global_position)
			break
	if nearest == null:
		for enemy_variant in enemies:
			var enemy := enemy_variant as Node2D
			if enemy.get_instance_id() == _combat_ignored_target_id and enemies.size() > 1:
				continue
			var distance := player.global_position.distance_to(enemy.global_position)
			if distance < nearest_distance:
				nearest = enemy
				nearest_distance = distance
		_combat_target_id = nearest.get_instance_id()
		_combat_last_target_distance = INF
		_combat_stuck_ticks = 0
		_combat_ignored_target_id = 0
	if nearest_distance > 58.0 and nearest_distance >= _combat_last_target_distance - 1.5:
		_combat_stuck_ticks += 1
	else:
		_combat_stuck_ticks = 0
	_combat_last_target_distance = nearest_distance
	if _combat_stuck_ticks >= 90:
		_combat_ignored_target_id = _combat_target_id
		_combat_target_id = 0
		_combat_last_target_distance = INF
		_combat_stuck_ticks = 0
		_set_soak_movement(Vector2.ZERO)
		return
	var direction := (nearest.global_position - player.global_position).normalized() if nearest_distance > 42.0 else Vector2.ZERO
	_set_soak_movement(direction)

func _resolve_soak_elites() -> void:
	# 20倍速では0.08秒近接Hitboxが物理1Frame未満になるため、Elite Encounterの
	# Cleanup/Signal/確定装備経路だけはDebug damageで完了させる。
	for enemy_variant in get_tree().get_nodes_in_group("elite_enemies"):
		var enemy := enemy_variant as EnemyBasic
		if enemy == null or not is_instance_valid(enemy) or enemy.enemy_data is BossData:
			continue
		enemy.health_component.current_hp = minf(enemy.health_component.current_hp, 1.0)
		enemy.health_component.apply_secondary_damage(99999999.0, CombatEventMeta.create_secondary("map_soak_elite_clear", [], false))

func _print_soak_combat_status(map_index: int) -> void:
	var nearest_distance := INF
	var living := 0
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy := enemy_variant as Node2D
		if not is_instance_valid(enemy):
			continue
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			continue
		living += 1
		nearest_distance = minf(nearest_distance, player.global_position.distance_to(enemy.global_position))
	print("MAP_EXPLORATION_SOAK combat map=%d kills=%d living=%d nearest=%.1f player=%s room_mode=%s elite=%d boss=%s floor=%d timer=%.2f state=%d" % [map_index, int(controller.debug_get_map_state().get("kills", 0)), living, nearest_distance, player.global_position, controller.wave_spawner._spawning_paused, controller.wave_spawner._active_elite_rooms, controller.wave_spawner._boss_fight_active, controller.wave_spawner._floor_cells.size(), controller.wave_spawner._timer, GameManager.run_state])

func _set_soak_movement(direction: Vector2) -> void:
	if direction.x < -0.18: Input.action_press("ui_left", -direction.x)
	else: Input.action_release("ui_left")
	if direction.x > 0.18: Input.action_press("ui_right", direction.x)
	else: Input.action_release("ui_right")
	if direction.y < -0.18: Input.action_press("ui_up", -direction.y)
	else: Input.action_release("ui_up")
	if direction.y > 0.18: Input.action_press("ui_down", direction.y)
	else: Input.action_release("ui_down")

func _release_soak_movement() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)

func _close_visible_reward_modals() -> void:
	for _attempt in 12:
		var pressed := false
		var shop := get_parent().get_node_or_null("ShopScreen") as ShopScreen
		if shop and shop.visible:
			shop.debug_close_shop()
			pressed = true
		for ui_name in ["ConceptSelect", "LevelUpSelect", "ItemSelect"]:
			var ui := get_parent().get_node_or_null(ui_name) as CanvasLayer
			if ui and ui.visible:
				pressed = _press_first_enabled_button(ui) or pressed
		if not pressed:
			return
		await _wait_frames(2)

func _press_first_enabled_button(root: Node) -> bool:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.visible and not button.disabled:
			button.pressed.emit()
			if root is LevelUpSelect: root.confirm_selection()
			return true
	return false

func _find_boss_chest() -> TreasureChest:
	for node in get_tree().get_nodes_in_group("map_content"):
		if node is TreasureChest and node.is_boss_chest and not node.is_opened:
			return node as TreasureChest
	return null

func _wait_until_map(map_index: int, maximum_frames: int) -> void:
	for _frame in maximum_frames:
		if GameManager.current_map_index == map_index and not bool(controller.debug_get_map_state().get("transitioning", false)):
			return
		await get_tree().process_frame
	_expect(false, "MAP %d transitionがtimeoutしました" % map_index)

func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish_test(exit_code: int, success_message: String) -> void:
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(exit_code, success_message)
