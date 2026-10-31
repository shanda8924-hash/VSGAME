extends Node
## Phase 2: スキルの可読性。カードの3行（発動／効果／相性）、相性の緑行、
## 命中回数ベースの発動、HUDのビルド表示（タグ・発動で光る石板）を実経路で確かめる。
var game: Node2D
var actor: Player
var failures: Array[String] = []
var OUT := "res://artifacts/skill_readability"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	DirAccess.make_dir_recursive_absolute(OUT)
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

func card_text(ui: LevelUpSelect, index: int) -> String:
	var card := ui.grid_container.get_child(index) as Button
	return (card.get_node("MarginContainer/VBoxContainer/Description") as RichTextLabel).text

func enemy(point: Vector2) -> EnemyBasic:
	var e := preload("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	e.enemy_data = DataLoader.enemies.slime
	e.room_hp_multiplier = 200
	e.room_move_speed_multiplier = 0
	e.position = point
	GameManager.get_runtime_world(actor).add_child(e)
	return e

func _run() -> void:
	GameManager.selected_character_id = "swordsman"
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
	# データ：戦闘強化と秘技はすべて発動・効果・タグを持つ
	for id in ["survival_area","survival_haste","survival_power","survival_echo","survival_chain","survival_guard","survival_multishot","survival_pierce","arcana_thunderlord_descent","arcana_glacial_spear_rain","arcana_inferno_pillar","arcana_radiant_blade_array","arcana_void_severance"]:
		var data: UpgradeData = DataLoader.upgrades.get(id)
		check(data != null and not data.trigger_text.is_empty() and not data.effect_text.is_empty() and not data.tags.is_empty(), "Readability data missing: " + id)
	var chain: UpgradeData = DataLoader.upgrades.survival_chain
	var haste: UpgradeData = DataLoader.upgrades.survival_haste
	var echo: UpgradeData = DataLoader.upgrades.survival_echo
	check(chain.is_boosted_by(haste) and echo.is_boosted_by(haste) and not haste.is_boosted_by(chain), "scales_with/tags matching is wrong")
	# カード：所持なし → 3行、相性は薄い「〜で発動が増える」
	var ui := game.get_node("LevelUpSelect") as LevelUpSelect
	GameManager.open_modal()
	ui._show_choices([chain, haste, DataLoader.upgrades.survival_area] as Array[UpgradeData])
	ui.visible = true
	await frames(2)
	var text := card_text(ui, 0)
	check(text.contains("発動") and text.contains("効果") and text.contains("相性") and text.contains("命中ごとに"), "Chain card lacks the 3 fixed lines: " + text)
	check(text.contains("攻速") and not text.contains("✦"), "Chain card without owned skills should list what scales it")
	await capture("cards_fresh")
	for card: Control in ui.grid_container.get_children():
		var column := card.get_node("MarginContainer/VBoxContainer") as VBoxContainer
		check(column.get_global_rect().end.y <= card.get_global_rect().end.y + 1.0, "3-line card overflows its frame")
	# 雷光連鎖を所持 → 高速攻撃のカードに緑の「✦ 雷光連鎖が増える」
	actor.upgrades_component.apply_upgrade(chain)
	ui._show_choices([haste, DataLoader.upgrades.survival_guard] as Array[UpgradeData])
	await frames(2)
	text = card_text(ui, 0)
	check(text.contains("✦") and text.contains("雷光連鎖が増える") and text.contains(LevelUpSelect.SYNERGY_COLOR.to_html(false)), "Haste card does not show the green synergy line: " + text)
	check(not card_text(ui, 1).contains("✦"), "Guard card claims a synergy it does not have")
	await capture("cards_synergy")
	# 高速攻撃を所持 → 雷光連鎖のカードに「✦ 高速攻撃で増える」
	actor.upgrades_component.apply_upgrade(haste)
	ui._show_choices([chain] as Array[UpgradeData])
	await frames(2)
	text = card_text(ui, 0)
	check(text.contains("✦") and text.contains("高速攻撃で増える"), "Chain card does not show it is boosted by haste: " + text)
	ui.visible = false
	GameManager.close_modal()
	# HUD：ビルドのタグと、発動で光る石板
	var hud := game.hud as HUD
	await frames(3)
	check(hud._build_tags_label.visible and hud._build_tags_label.text.contains("雷") and hud._build_tags_label.text.contains("攻速"), "HUD build tags missing: " + hud._build_tags_label.text)
	var chip := hud.debug_get_upgrade_chip("survival_chain")
	check(chip != null, "HUD has no chip for the owned chain upgrade")
	var targets: Array[EnemyBasic] = []
	for point in [Vector2(45, 0), Vector2(66, 0), Vector2(80, 16)]: targets.append(enemy(point))
	await frames(2)
	var effects := actor.get_node("SurvivalUpgradeEffects")
	# Lv1=35%：貯金式なので3回目の命中で必ず渡る
	for hit in 3:
		targets[0].health_component._iframe_remaining = 0.0
		targets[0].health_component.apply_damage(30, CombatEventMeta.create_direct("player_readability_test"))
		await frames(2)
		if hit < 2: check(effects.debug_chain_hits == 0, "Chain fired before the accumulated chance reached 100%")
		await frames(5)
	await frames(2)
	check(effects.debug_chain_hits >= 1, "Chain never fired on the third hit")
	check(chip != null and chip.modulate != Color.WHITE, "Chip does not flash when the upgrade triggers")
	await capture("hud_build")
	await frames(40)
	check(chip != null and chip.modulate.is_equal_approx(Color.WHITE), "Chip flash never fades")
	finish()

func finish() -> void:
	var f := FileAccess.open(OUT + "/check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures": failures}, "\t")); f.close()
	print("SKILL_READABILITY " + ("PASS" if failures.is_empty() else "FAIL ") + JSON.stringify(failures))
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1, "SKILL_READABILITY " + ("PASS" if failures.is_empty() else "FAIL"))
