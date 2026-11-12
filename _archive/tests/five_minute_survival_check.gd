extends Node
var game: Node2D
var player: Player
var controller: MapRunController
var wave: WaveSpawner
var OUT := "res://artifacts/open_field_survival"
var failures: Array[String] = []
var fired := 0
var level_times: Dictionary = {}
# ラムダはローカル変数を値で捕まえるので、信号で増やす数はメンバーに置く。
var pressure_hit := false
var rescues := 0
var surges_started := 0
var surges_ended := 0
var hits_taken := 0
var damage_total := 0.0
var min_hp_ratio := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--growth-benchmark" in OS.get_cmdline_user_args(): OUT = "res://artifacts/survival_growth"
	if "--touch-preview" in OS.get_cmdline_user_args(): OUT += "/mobile"
	get_tree().create_timer(900, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		if message not in failures: failures.append(message); push_error(message)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		var ui := game.get_node("LevelUpSelect") as LevelUpSelect
		if ui.visible and ui.grid_container.get_child_count() > 0:
			(ui.grid_container.get_child(0) as Button).pressed.emit()
			ui.confirm_selection()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/" + name + ".png")

func _run() -> void:
	game = get_parent()
	player = game.get_node("Player")
	controller = game.get_node("MapRunController")
	wave = game.get_node("WaveSpawner")
	DirAccess.make_dir_recursive_absolute(OUT)
	check(AudioServer.get_driver_name() == "Dummy" and AudioServer.is_bus_mute(0), "Tests must stay silent")
	check(GameManager.survival_mode_active and GameManager.dungeon_map.get_meta("floor_only", false), "Product entry is not floor-only")
	check(game.get_node("StageEnvironment")._tile_map_layer.get_used_cells().is_empty(), "Terrain walls/floor TileMap still built")
	check(DungeonGenerator.validate_reachability(GameManager.dungeon_map).reachable, "Reference floor connectivity validation must terminate")
	check(GameManager.dungeon_map.terrain_obstacle_cells.is_empty(), "Field contains obstacles")
	check(game.get_node("EliteRoomManager").process_mode == Node.PROCESS_MODE_DISABLED, "Strong roaming enemies still spawn")
	player.health_component.invincible = true
	player.weapon_manager.weapon_fired.connect(func(): fired += 1)
	var gear := game.get_node("EquipmentDropSystem").debug_generate_equipment("wanderer_iron_sword", "uncommon") as EquipmentData
	check(player.equipment_component.add_item(gear) and player.equipment_component.equip(gear), "Starter weapon failed")
	player.experience_component.leveled_up.connect(func(level: int):
		if level in [2,5,10,15,20,25,30]: level_times[str(level)] = GameManager.elapsed_seconds
	)
	if "--full-run" in OS.get_cmdline_user_args():
		await soak()
		return
	var peak := 0
	for i in 900:
		await frames(1)
		peak = maxi(peak, wave._active_enemy_count())
	check(peak >= 12 and fired > 0 and GameManager.kill_count > 0, "No natural automatic horde combat")
	await capture("field")
	var time := GameManager.elapsed_seconds
	GameManager.open_modal()
	await frames(30)
	check(is_equal_approx(time, GameManager.elapsed_seconds), "Menu consumes battle time")
	GameManager.close_modal()
	await _surge_phase1()
	controller.set_process(false)
	wave.set_process(false)
	controller._clear_combat_transients(true)
	await frames(5)
	await _roles_phase1()
	player.global_position = Vector2(22000, -17000)
	await frames(8)
	var map := GameManager.dungeon_map
	check(map.is_floor(map.world_to_grid(player.global_position)) and map.has_navigation_clearance(map.world_to_grid(player.global_position)), "Remote floor becomes void or a hidden wall")
	check(not player.test_move(player.global_transform, Vector2(160, 0)), "Empty field blocks movement")
	var before := player.global_position
	Input.action_press("ui_right")
	await frames(20)
	Input.action_release("ui_right")
	check(player.global_position.x > before.x + 10, "Real player cannot move beyond old arena bounds")
	var surface := game.get_node("StageEnvironment/PaintedSurfaces")
	check(surface.position.distance_to(player.camera.get_screen_center_position()) < 400, "Floor does not follow remote camera")
	var half := player.get_viewport_rect().size / player.camera.zoom * 0.5
	for i in 12:
		var point := wave._pick_spawn_position(player.global_position)
		check(point.is_finite() and (absf(point.x-player.position.x)>half.x or absf(point.y-player.position.y)>half.y), "Enemy pops into the visible field")
	var drop := game.get_node("EquipmentDropSystem").spawn_treasure_drop(player.global_position + Vector2(160, 0), "uncommon") as GroundEquipmentItem
	check(drop != null and drop.global_position.distance_to(player.global_position) < 400, "Remote loot returned to origin")
	await capture("remote_floor")
	if game.mobile_controls.visible:
		game.mobile_controls._update_stick(Vector2(204, 102))
		check(Input.is_action_pressed("ui_right"), "Touch movement is disconnected")
		game.mobile_controls._release_stick()
	GameManager.elapsed_seconds = 120
	controller._tick_survival()
	check(not controller._boss_active, "Boss appears before finale")
	GameManager.elapsed_seconds = 150
	controller._tick_survival()
	var supplies := get_tree().get_nodes_in_group("map_content").filter(func(n): return n is TreasureChest and not n.is_boss_chest)
	check(not supplies.is_empty(), "Mid-run supplies missing")
	var chest := supplies.back() as TreasureChest
	player.position = chest.position
	await frames(6)
	check(chest.interact(player) and game.get_node("ShopScreen").visible, "Supply chest did not offer useful shop")
	var shop_time := GameManager.elapsed_seconds
	await frames(20)
	check(shop_time == GameManager.elapsed_seconds, "Shop consumes stage time")
	game.get_node("ShopScreen")._close()
	GameManager.elapsed_seconds = 239
	controller._tick_survival()
	var early_ids: Array = WaveSpawner.MAP_ENEMY_ROSTERS[GameManager.current_map_index].strong
	for i in 50:
		for data in wave._survival_enemy_pool(): check(data.id not in early_ids, "Promoted strong enemy still in regular horde")
	var late := wave.debug_get_map_spawn_snapshot()
	GameManager.elapsed_seconds = 240
	controller._tick_survival()
	await frames(8)
	var boss := game.boss_spawner.debug_get_current_boss() as EnemyBasic
	check(boss != null and controller._boss_active and controller._survival_boss_index == 1 and wave._spawning_paused, "Final boss phase did not replace horde")
	check(boss.enemy_data.id in early_ids and boss.enemy_data is BossData and boss.strong_attack != null, "Final boss lost strong enemy identity/moves")
	check(boss.health_component.max_hp >= 4000, "Boss dies like a regular mob")
	var id := boss.get_instance_id()
	var hp := boss.health_component.current_hp
	boss.health_component.invincible = true
	GameManager.elapsed_seconds = 305
	controller._tick_survival()
	await frames(90)
	check(is_instance_valid(boss) and boss.get_instance_id() == id and boss.health_component.current_hp == hp and not GameManager.survival_completed, "Five minutes deletes or resets a living boss")
	check(game.hud.room_status_label.text.contains("ボス戦"), "HUD hides overtime boss fight")
	player.global_position = boss.global_position + Vector2(56, 0)
	player.camera.reset_smoothing()
	await frames(8)
	await capture("final_boss")
	controller._tick_survival()
	check(game.boss_spawner.debug_get_current_boss().get_instance_id() == id, "Final boss duplicated")
	drop.begin_cap_expiration(1.2)
	boss.health_component.invincible = false
	game.boss_spawner.debug_defeat_current_boss()
	await frames(95)
	check(GameManager.survival_completed and not game.get_node("ResultScreen").visible, "Boss defeat skips recovery")
	check(is_instance_valid(drop) and not drop.cap_expiration_pending, "Recovery still expires floor loot")
	chest = controller._boss_chest
	check(chest != null and not controller._stairs.available, "Victory reward/return missing")
	player.position = chest.position
	await frames(8)
	check(chest.interact(player), "Victory chest cannot be opened remotely")
	await frames(5)
	check(controller._stairs.available and not game.get_node("ResultScreen").visible, "Chest automatically ends stage")
	controller._tick_survival()
	await capture("recovery")
	var ground := get_tree().get_nodes_in_group("ground_equipment")
	check(not ground.is_empty(), "No physical victory loot")
	var picked := ground.back() as GroundEquipmentItem
	player.position = picked.position
	await frames(6)
	check(picked.collect(player), "Remote victory loot cannot be collected")
	var reward_before := int(SaveManager.data.meta_currency)
	var reward := GameManager.kill_count + GameManager.run_gold + GameManager.run_equipment_count * 5
	player.position = controller._stairs.position
	await frames(6)
	check(controller._stairs.interact(player), "Manual return failed")
	await frames(6)
	var result := game.get_node("ResultScreen") as ResultScreen
	check(result.visible and result.title_label.text == "ステージクリア", "Victory result still says survive timeout")
	check(int(SaveManager.data.meta_currency)-reward_before==reward, "Meta reward lost")
	await capture("result")
	get_tree().paused = false
	GameManager.start_run(true)
	check(not GameManager.survival_completed and GameManager.elapsed_seconds == 0, "Retry preserves previous victory")
	await _boss_moves()
	finish({"peak_early":peak,"late":late,"remote_floor":true,"boss_survives_overtime":true})

## Phase 1: 波の状態機械を実時間を待たずに通す。予告→開始（包囲湧き・役割）→強敵→終了（報酬）。
func _surge_phase1() -> void:
	var surface := game.get_node("StageEnvironment/PaintedSurfaces")
	var times: Array = controller._survival_surge_times()
	check(times.size() >= 4 and controller._survival_surge_enabled(), "Survival surges are not configured")
	var first := float(times[0])
	GameManager.elapsed_seconds = first - 12.0
	controller._tick_survival()
	check(game.hud.room_status_label.text.contains("次の波まで") and not controller._surge_active, "HUD does not show the next wave timer")
	GameManager.elapsed_seconds = first - 8.0
	controller._tick_survival()
	check(game.hud.room_status_label.text.contains("秒前") and surface.is_alarm_active(), "Wave warning (HUD + red vignette) missing")
	var before := wave._active_enemy_count()
	GameManager.elapsed_seconds = first
	controller._tick_survival()
	await frames(2)
	var state := controller.debug_get_map_state()
	check(state.surge_active and String(state.surge_role) != "" and wave.get_surge_role() == String(state.surge_role), "Wave did not start with a role")
	check(wave._active_enemy_count() >= before + 8, "Ring spawn did not surround the player")
	var role_count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if String(enemy.get_meta("role", "")) == String(state.surge_role): role_count += 1
	check(role_count >= 6, "Ring spawn ignores the wave role")
	check(game.hud.room_status_label.text.contains("第1波"), "HUD hides the active wave")
	GameManager.elapsed_seconds = first + 16.0
	controller._tick_survival()
	await frames(2)
	check(not get_tree().get_nodes_in_group("enemies").filter(func(n): return n.get_meta("surge_strong", false)).is_empty(), "Mid-wave strong enemy missing")
	var loot_before := get_tree().get_nodes_in_group("ground_equipment").size()
	GameManager.elapsed_seconds = first + 31.0
	controller._tick_survival()
	await frames(2)
	state = controller.debug_get_map_state()
	check(not state.surge_active and int(state.surge_index) == 1 and int(state.surge_reward_count) == 1, "Wave did not finish with a reward")
	check(get_tree().get_nodes_in_group("ground_equipment").size() > loot_before, "Wave reward equipment missing")
	check(not surface.is_alarm_active() and wave.get_surge_role() == "", "Wave end leaves alarm/role on")
	check(game.hud.room_status_label.text.contains("凌いだ"), "Wave end message missing")
	await capture("surge_end")

## Phase 1: 遠距離型は立ち止まって弾を撃ち、壁型はノックバック耐性と高HPを持つ。
func _roles_phase1() -> void:
	var archer: EnemyData = DataLoader.enemies.get("skeleton_archer")
	check(archer != null and archer.ranged_range > 0.0, "Ranged enemy data missing")
	var enemy := wave._spawn_enemy_at(archer, player.global_position + Vector2(archer.ranged_range * 0.7, 0), player) as EnemyBasic
	await frames(2)
	check(enemy.ai_component.behavior is RangedStrategy and enemy.get_meta("role", "") == "ranged", "Archer does not use the ranged strategy")
	var shots := 0
	for i in 150:
		await frames(1)
		shots = maxi(shots, get_tree().get_nodes_in_group("enemy_shots").size())
		if shots > 0: break
	check(shots > 0, "Ranged enemy never fires at a standing player")
	var guard := wave._spawn_enemy_at(DataLoader.enemies.get("shield_guard"), player.global_position + Vector2(-260, 0), player) as EnemyBasic
	await frames(2)
	check(guard.is_wall_role() and guard.health_component.max_hp > archer.max_hp, "Wall role is not applied")
	var origin := guard.global_position
	guard.apply_knockback(Vector2.LEFT, 80.0)
	await frames(12)
	var pushed := guard.global_position.distance_to(origin)
	check(pushed < 40.0, "Wall enemy is knocked back like a regular mob (%.1f)" % pushed)
	controller._clear_combat_transients(true)
	for shot in get_tree().get_nodes_in_group("enemy_shots"): shot.queue_free()
	await frames(3)

func soak() -> void:
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var peak := 0
	var captured := false
	var boss_at := 0.0
	# 無敵なしで3分間自動操作し、HP50%以下へ落ちる圧力があるかを見る（25%未満で救済回復し、死亡で止めない）。
	EventBus.map_surge_started.connect(func(_m, _i, _r, _d): surges_started += 1)
	EventBus.map_surge_ended.connect(func(_m, _i, _t, _p): surges_ended += 1)
	player.health_component.invincible = false
	player.health_component.damaged.connect(func(amount, current_hp, max_hp):
		hits_taken += 1
		damage_total += amount
		min_hp_ratio = minf(min_hp_ratio, current_hp / max_hp)
		if current_hp <= max_hp * 0.5: pressure_hit = true
		if current_hp <= max_hp * 0.25:
			rescues += 1
			player.health_component.heal(max_hp)
	)
	var density_60 := 0
	while not GameManager.survival_completed and GameManager.elapsed_seconds < 600:
		await frames(1)
		var alive := wave._active_enemy_count()
		peak = maxi(peak, alive)
		if GameManager.elapsed_seconds >= 60.0 and GameManager.elapsed_seconds < 62.0: density_60 = maxi(density_60, alive)
		if GameManager.elapsed_seconds >= 180.0 and not player.health_component.invincible:
			player.health_component.invincible = true
			check(pressure_hit, "Three minutes without invincibility never drops HP to 50%")
			check(density_60 >= 12, "Fewer than 12 enemies alive at 60s (%d)" % density_60)
		check(alive <= wave._map_enemy_cap, "Natural horde exceeds cap")
		if not captured and GameManager.elapsed_seconds >= 205:
			captured = true
			await capture("horde")
		if controller._boss_active and boss_at == 0: boss_at = GameManager.elapsed_seconds
		if controller._boss_active and GameManager.elapsed_seconds > 245:
			var boss := game.boss_spawner.debug_get_current_boss() as EnemyBasic
			if boss and player.position.distance_to(boss.position) > 70:
				player.global_position = boss.position + Vector2(50, 0)
	await frames(20)
	var boss_seconds := GameManager.elapsed_seconds - boss_at
	check(GameManager.survival_completed and boss_at >= 240 and peak >= 60, "Natural stage failed to complete")
	check(boss_seconds >= 35 and boss_seconds <= 180, "Baseline final boss duration needs tuning")
	check(not game.get_node("ResultScreen").visible, "Natural victory forced result")
	check(surges_started == 4 and surges_ended == 4, "Expected 4 wave start/end events (%d/%d)" % [surges_started, surges_ended])
	finish({"duration":GameManager.elapsed_seconds,"boss_seconds":boss_seconds,"surges":[surges_started, surges_ended],"pressure_hit_before_180s":pressure_hit,"rescues":rescues,"hits_taken":hits_taken,"damage_total":damage_total,"min_hp_ratio":min_hp_ratio,"player_max_hp":player.health_component.max_hp,"density_60":density_60,"boss_hp_data":"fixed, not player-scaled","peak":peak,"cap":wave._map_enemy_cap,"kills":GameManager.kill_count,"level":player.experience_component.level,"invincible_test_player":true,"auto_upgrades":true,"clock_not_skipped":true,"level_times":level_times,"upgrade_ranks":player.upgrades_component.survival_upgrade_counts}, "soak")

func finish(report: Dictionary, name: String = "check") -> void:
	report["failures"] = failures
	var f := FileAccess.open(OUT + "/" + name + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t")); f.close()
	print("OPEN_FIELD " + name + " " + JSON.stringify(report))
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1, "OPEN_FIELD " + ("PASS" if failures.is_empty() else "FAIL"))

func _boss_moves() -> void:
	for theme in [1, 2, 3]:
		for ident: String in WaveSpawner.MAP_ENEMY_ROSTERS[theme].strong:
			game.boss_spawner.prepare_map_run()
			var boss := game.boss_spawner.start_room_boss(theme, {"candidates":[ident], "is_final":true}, player.position + Vector2(56, 0)) as EnemyBasic
			check(boss != null and boss.strong_attack != null and boss.enemy_data.sprite_folder == DataLoader.enemies[ident].sprite_folder, "Promoted boss does not reuse original art/moves: "+ident)
			boss.health_component.invincible = true
			var performed := false
			for i in 360:
				await frames(1)
				if boss.strong_attack.active and boss.strong_attack.elapsed >= .1:
					performed = true
					await capture("boss_"+ident)
					break
			check(performed, "Boss never performs its authored attack: "+ident)
			game.boss_spawner.clear_room_boss()
			player.weapon_manager.cancel_current_attack()
			await frames(6)
