extends Node
## Phase 3: 連撃・進化レシピ・進化／相性カードの保証・リロール・「もう出さない」を実経路で確かめる。
var game: Node2D
var actor: Player
var failures: Array[String] = []
var OUT := "res://artifacts/synergy_evolution"
var double_strike_triggers := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	DirAccess.make_dir_recursive_absolute(OUT)
	EventBus.upgrade_triggered.connect(func(id: String, _p: Vector2): if id == "survival_double_strike": double_strike_triggers += 1)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/" + name + ".png")

func enter(character: String) -> void:
	if is_instance_valid(game):
		get_tree().paused = false
		game.queue_free()
		await frames(4)
	GameManager.selected_character_id = character
	GameManager.selected_survival_map = 1
	game = preload("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	await frames(2)
	while not (game.get_node("MapRunController") as MapRunController)._active: await frames(1)
	game.get_node("WaveSpawner").set_process(false)
	game.get_node("MapRunController").set_process(false)
	actor = game.get_node("Player")
	actor.weapon_manager.set_process(false)
	actor.health_component.invincible = true
	for e in get_tree().get_nodes_in_group("enemies"): e.queue_free()
	await frames(3)

func enemy(point: Vector2) -> EnemyBasic:
	var e := preload("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	e.enemy_data = DataLoader.enemies.slime
	e.room_hp_multiplier = 300
	e.room_move_speed_multiplier = 0
	e.position = actor.global_position + point
	GameManager.get_runtime_world(actor).add_child(e)
	return e

func apply(id: String, times: int = 1) -> void:
	for i in times: actor.upgrades_component.apply_upgrade(DataLoader.upgrades[id])

func evolution_ids() -> Array[String]:
	var ids: Array[String] = []
	for upgrade in actor.upgrades_component.get_available_evolutions(): ids.append(upgrade.id)
	return ids

func clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"): e.queue_free()
	await frames(3)

func _run() -> void:
	check(AudioServer.get_driver_name() == "Dummy" and AudioServer.is_bus_mute(0), "Checks must be silent")
	for id in ["survival_double_strike", "evo_thunder_strike", "evo_shadow_run", "evo_great_cleave", "evo_arrow_rain", "evo_charged_ward"]:
		var data: UpgradeData = DataLoader.upgrades.get(id)
		check(data != null and not data.trigger_text.is_empty() and not data.effect_text.is_empty(), "Phase 3 upgrade data missing: " + id)
		if data and data.category == "evolution": check(not data.requires.is_empty(), "Evolution without requirements: " + id)
	await enter("swordsman")
	var ui := game.get_node("LevelUpSelect") as LevelUpSelect
	var effects := actor.get_node("SurvivalUpgradeEffects")
	# 相性の保証：雷光連鎖だけ持っている間は、毎回1枚は「増やす側」のカードが出る
	# （流派の選択は2枠を使うので先に決めておく）
	actor.weapon_manager.select_class_school("rengeki")
	apply("survival_chain")
	for round in 4:
		ui._open(2)
		await frames(2)
		var boosted := false
		for card: Control in ui.grid_container.get_children():
			if (card.get_node("MarginContainer/VBoxContainer/Description") as RichTextLabel).text.contains("✦"): boosted = true
		check(boosted, "No synergy card guaranteed while chain has open synergies: " + str(ui.debug_get_last_choice_ids()))
		ui.visible = false
		GameManager.close_modal()
	# 連撃：multishot_chanceへ積まれ、実際の斬撃で追加の一撃が出る
	apply("survival_double_strike", 3)
	check(actor.upgrades_component.get_survival_rank("survival_double_strike") == 3 and actor.upgrades_component.multishot_chance >= 0.6 - 0.001, "Double strike does not raise the real extra-hit chance")
	enemy(Vector2(45, 0))
	await frames(2)
	for i in 24:
		actor.weapon_manager._class_attack.execute(actor, DataLoader.characters.swordsman, actor.weapon_manager)
		await frames(2)
	check(double_strike_triggers >= 4, "Double strike never produced extra swings (%d / 24)" % double_strike_triggers)
	await clear_enemies()
	# 進化：雷光連鎖Lv3＋連撃Lv2 → 雷帝の連撃が必ず1枚出る（朱色の「進化」枠）
	apply("survival_chain", 2)
	check("evo_thunder_strike" in evolution_ids(), "Thunder strike recipe not available: " + str(evolution_ids()))
	ui._open(5)
	await frames(2)
	# 剣士は流派の選択が先頭に来ることがあるので、進化は「必ず含まれる」で見る。
	var evo_index := ui.debug_get_last_choice_ids().find("evo_thunder_strike")
	check(ui._chosen.size() == 3 and evo_index >= 0, "Evolution card not guaranteed: " + str(ui.debug_get_last_choice_ids()))
	var first := ui.grid_container.get_child(maxi(evo_index, 0)) as Button
	var category_label := first.find_child("Category", true, false) as Label
	check(category_label != null and category_label.text.begins_with("進化"), "Evolution card is not labelled as evolution")
	check((first.get_node("MarginContainer/VBoxContainer/Description") as RichTextLabel).text.contains("雷光連鎖Lv3"), "Evolution card does not name its recipe")
	await capture("evolution_card")
	# リロール：金貨を払って引き直す。「もう出さない」：選んだ強化がプールから消える
	GameManager.add_run_gold(60, "test")
	ui._refresh_extra_row()
	check(not ui.reroll_button.disabled and ui.reroll_cost() == 10, "Reroll button unavailable with gold")
	var gold_before := GameManager.run_gold
	ui._on_reroll_pressed()
	await frames(2)
	check(GameManager.run_gold == gold_before - 10 and ui.reroll_cost() == 15 and ui.grid_container.get_child_count() == 3, "Reroll did not spend gold / redraw")
	evo_index = ui.debug_get_last_choice_ids().find("evo_thunder_strike")
	check(evo_index >= 0, "Reroll dropped the guaranteed evolution")
	var ban_target: UpgradeData = null
	for candidate in ui._chosen:
		if candidate.category in ["survival", "arcana"]: ban_target = candidate
	check(ban_target != null, "No ordinary card to ban: " + str(ui.debug_get_last_choice_ids()))
	ui._select_choice(ban_target)
	check(not ui.ban_button.disabled, "Ban button stays disabled after selecting")
	ui._on_ban_pressed()
	await frames(2)
	check(ban_target.id in actor.upgrades_component.banned_upgrade_ids and actor.upgrades_component.ban_uses_remaining == 0, "Ban was not recorded")
	for upgrade in ui._get_compatible_upgrades(): check(upgrade.id != ban_target.id, "Banned upgrade still in the pool")
	check(ui.ban_button.disabled or ui._selected < 0, "Ban still available after its single use")
	# 進化を取得 → 雷光連鎖が命中ごとに必ず渡り、対象+1
	evo_index = ui.debug_get_last_choice_ids().find("evo_thunder_strike")
	check(evo_index >= 0, "Ban redraw dropped the guaranteed evolution")
	ui._select_choice(ui._chosen[maxi(evo_index, 0)])
	ui.confirm_selection()
	await frames(2)
	check(actor.upgrades_component.has_evolution("evo_thunder_strike") and "evo_thunder_strike" not in evolution_ids(), "Evolution not acquired")
	check(is_equal_approx(effects.chain_chance(3), 1.0) and effects.chain_targets(3) == 4, "Thunder strike does not change the chain proc")
	check(game.hud.debug_get_upgrade_chip("evo_thunder_strike") != null, "HUD has no chip for the evolution")
	var targets: Array[EnemyBasic] = []
	for point in [Vector2(45, 0), Vector2(66, 0), Vector2(80, 16), Vector2(70, 30), Vector2(60, -30)]: targets.append(enemy(point))
	await frames(2)
	var chain_before: int = effects.debug_chain_hits
	targets[0].health_component._iframe_remaining = 0.0
	targets[0].health_component.apply_damage(40, CombatEventMeta.create_direct("player_evolution_test"))
	await frames(12)
	check(effects.debug_chain_hits - chain_before == 4, "Evolved chain did not hit 4 targets on one hit (%d)" % (effects.debug_chain_hits - chain_before))
	# 秘技×雷：雷帝落雷が落ちた所から連鎖
	chain_before = effects.debug_chain_hits
	EventBus.upgrade_triggered.emit("arcana_thunderlord_descent", targets[3].global_position)
	await frames(12)
	check(effects.debug_chain_hits > chain_before, "Thunderlord strike does not chain with the lightning build")
	# 大断：広域Lv3＋強撃Lv3 → 範囲倍率+50%
	apply("survival_area", 3)
	apply("survival_power", 3)
	check("evo_great_cleave" in evolution_ids(), "Great cleave recipe not available")
	var range_before := actor.weapon_manager.get_attack_range_multiplier()
	apply("evo_great_cleave")
	check(is_equal_approx(actor.weapon_manager.get_attack_range_multiplier(), range_before + 0.5), "Great cleave has no real range effect")
	# 帯電結界：結界Lv3＋連鎖Lv2 → シールドが割れると周囲へ雷
	apply("survival_guard", 3)
	check("evo_charged_ward" in evolution_ids(), "Charged ward recipe not available")
	apply("evo_charged_ward")
	await frames(3)
	check(actor.health_component.shield_amount >= 24.0, "Guard shield missing before the ward test")
	var ward_before: int = effects.debug_ward_hits
	actor.health_component.invincible = false
	actor.health_component._iframe_remaining = 0.0
	actor.health_component.apply_damage(60)
	actor.health_component.invincible = true
	await frames(3)
	check(actor.health_component.shield_amount <= 0.0 and effects.debug_ward_hits - ward_before >= 3, "Charged ward did not strike nearby enemies when the shield broke (%d)" % (effects.debug_ward_hits - ward_before))
	# 影走り：残影Lv3＋高速Lv3 → 攻撃しなくても0.5秒ごとに影が斬る
	apply("survival_echo", 3)
	apply("survival_haste", 3)
	check("evo_shadow_run" in evolution_ids(), "Shadow run recipe not available")
	apply("evo_shadow_run")
	check(effects.echo_every_n(3) == 1, "Shadow run does not make the echo follow every hit")
	var shadow_before: int = effects.debug_shadow_hits
	await frames(75)
	check(effects.debug_shadow_hits - shadow_before >= 2, "Shadow does not strike on its own (%d)" % (effects.debug_shadow_hits - shadow_before))
	await capture("evolved_build")
	# 矢の雨：弓兵で貫通Lv2＋多重Lv2 → 扇状5本・貫通無制限
	await enter("archer")
	apply("survival_pierce", 2)
	apply("survival_multishot", 2)
	check("evo_arrow_rain" in evolution_ids(), "Arrow rain recipe not available for the archer")
	apply("evo_arrow_rain")
	check(actor.weapon_manager.get_survival_extra_projectiles() == 4, "Arrow rain does not fire 5 arrows")
	enemy(Vector2(120, 0))
	await frames(2)
	var before := get_tree().get_nodes_in_group("projectiles").size()
	actor.weapon_manager._class_attack.execute(actor, DataLoader.characters.archer, actor.weapon_manager)
	var shots := get_tree().get_nodes_in_group("projectiles")
	var base := int(DataLoader.characters.archer.attack_pattern_params.get("projectile_count", 1))
	check(shots.size() - before >= base + 4, "Arrow rain volley is short (%d)" % (shots.size() - before))
	check(shots.back() is Projectile and (shots.back() as Projectile).pierce_remaining >= 99, "Arrow rain arrows are not unlimited pierce")
	finish()

func finish() -> void:
	var f := FileAccess.open(OUT + "/check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures": failures}, "\t")); f.close()
	print("SYNERGY_EVOLUTION " + ("PASS" if failures.is_empty() else "FAIL ") + JSON.stringify(failures))
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1, "SYNERGY_EVOLUTION " + ("PASS" if failures.is_empty() else "FAIL"))
