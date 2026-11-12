extends Node
## Phase 4：育成。装備の持ち越し（勝利＝全部／敗北＝ロック品＋確率1点）、職業の熟練の累積と持ち込み、
## 深度の鎖（攻略で+1、敵倍率とHUD表示）、拠点の装備・鍛造画面を実経路で確かめる。
var game: Node2D
var actor: Player
var failures: Array[String] = []
var OUT := "res://artifacts/meta_growth"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	SaveManager.data["meta_currency"] = 0
	SaveManager.clear_persistent_equipment()
	SaveManager.data["class_mastery"] = {}
	SaveManager.data["class_memory"] = {}
	SaveManager.data["survival_depth"] = 1
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

func enter(character: String, map_index: int = 1) -> void:
	if is_instance_valid(game):
		get_tree().paused = false
		game.queue_free()
		await frames(4)
	GameManager.selected_character_id = character
	GameManager.selected_survival_map = map_index
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

func gear(template: String, rarity: String) -> EquipmentData:
	return game.get_node("EquipmentDropSystem").debug_generate_equipment(template, rarity) as EquipmentData

func _run() -> void:
	check(AudioServer.get_driver_name() == "Dummy" and AudioServer.is_bus_mute(0), "Checks must be silent")
	# 1. 敗北：ロック品は必ず残り、未ロック品は最大1点。欠片は到達時間ぶん増える。
	await enter("swordsman")
	check(actor.equipment_component.get_all_inventory().is_empty(), "Fresh profile starts with equipment")
	var sword := gear("wanderer_iron_sword", "uncommon")
	var locked := gear("wanderer_iron_sword", "rare")
	var loose := gear("wanderer_iron_sword", "uncommon")
	locked.is_locked = true
	for item in [sword, locked, loose]: actor.equipment_component.add_item(item)
	actor.equipment_component.equip(sword)
	GameManager.elapsed_seconds = 125.0
	GameManager.kill_count = 40
	var currency_before := int(SaveManager.data.meta_currency)
	GameManager.end_run()
	await frames(3)
	var carried := SaveManager.get_persistent_equipment()
	var carried_ids: Array[String] = []
	for entry in carried.inventory: carried_ids.append(String(entry.instance_id))
	for slot in carried.equipped: carried_ids.append(String(carried.equipped[slot].instance_id))
	check(locked.instance_id in carried_ids, "Locked item was lost on defeat")
	check(carried_ids.size() <= 2, "Defeat carried more than the locked item plus one (%d)" % carried_ids.size())
	check(int(SaveManager.data.meta_currency) - currency_before >= 40 + 12, "Defeat reward lacks the time bonus")
	check(game.get_node("ResultScreen").reward_label.text.contains("持ち帰った装備"), "Result screen hides the carry-back")
	await capture("result_defeat")
	# 2. 次のランでロック品が所持品に戻る。熟練はまだ0段階。
	await enter("swordsman")
	var restored_ids: Array[String] = []
	for item in actor.equipment_component.get_all_inventory(): restored_ids.append(item.instance_id)
	check(locked.instance_id in restored_ids, "Locked item did not come back in the next run")
	check(SaveManager.get_mastery_tier("swordsman") == 0 and actor.weapon_manager.get_class_school() == "none", "Mastery granted too early")
	# 3. 勝利：装備は全部、熟練は流派・レベル・攻略分、最初の強化を記憶、深度+1、次の出撃先はMAP2（解放済みなら）。
	SaveManager.unlock_map(2, 0)
	var helm := gear("wanderer_iron_sword", "epic")
	actor.equipment_component.add_item(helm)
	var weapon := actor.equipment_component.get_all_inventory()[0]
	actor.equipment_component.equip(weapon)
	actor.weapon_manager.select_class_school("rengeki")
	actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_chain)
	actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_haste)
	actor.experience_component.add_exp(400)
	await frames(3)
	var level := actor.experience_component.level
	var controller := game.get_node("MapRunController") as MapRunController
	GameManager.survival_completed = true
	controller._advance_map()
	await frames(3)
	check(SaveManager.get_survival_depth() == 2 and GameManager.selected_survival_map == 2, "Victory did not advance the depth chain")
	carried = SaveManager.get_persistent_equipment()
	check(carried.equipped.has("weapon") and String(carried.equipped.weapon.instance_id) == weapon.instance_id, "Equipped weapon not persisted on victory")
	check(carried.inventory.size() == actor.equipment_component.get_all_inventory().size() - 1, "Victory inventory not fully persisted")
	var expected_points := 1 + level / 5 + 2
	check(SaveManager.get_class_mastery("swordsman") == expected_points, "Mastery points wrong (%d vs %d)" % [SaveManager.get_class_mastery("swordsman"), expected_points])
	var memory := SaveManager.get_class_memory("swordsman")
	check(String(memory.get("first_upgrade", "")) == "survival_chain" and String(memory.get("school", "")) == "rengeki", "Build memory not recorded: " + str(memory))
	check(game.get_node("ResultScreen").reward_label.text.contains("深度 1 → 2"), "Victory result hides the depth chain")
	await capture("result_victory")
	# 4. 深度2・MAP2のラン：装備が装備済みで戻り、敵倍率が上がり、HUDに深度、熟練1段階で流派を持ち込む。
	await enter("swordsman", 2)
	check(GameManager.current_depth == 2 and GameManager.current_map_index == 2, "Depth/map not applied to the new run")
	var equipped := actor.equipment_component.get_equipped("weapon")
	check(equipped != null and equipped.instance_id == weapon.instance_id, "Carried weapon is not equipped at start")
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	check(is_equal_approx(wave._map_hp_multiplier, 0.85 * 1.12), "Depth does not scale enemy HP (%.3f)" % wave._map_hp_multiplier)
	controller = game.get_node("MapRunController")
	controller._tick_survival()
	check(game.hud.room_status_label.text.contains("深度2"), "HUD hides the depth")
	check(SaveManager.get_mastery_tier("swordsman") >= 1 and actor.weapon_manager.get_class_school() == "rengeki" and actor.weapon_manager.get_class_ability_level() == 2, "Mastery tier 1 did not bring the school in")
	check(actor.upgrades_component.get_survival_rank("survival_chain") == 0, "Tier 2 perk applied at tier 1")
	await capture("depth2_run")
	# 5. 熟練2・3段階：最初の強化の持ち込みと最大HP+10%。
	SaveManager.data["class_mastery"] = {"swordsman": 15}
	await enter("swordsman", 2)
	check(actor.upgrades_component.get_survival_rank("survival_chain") == 1, "Tier 2 did not bring the remembered upgrade")
	var base_hp: float = DataLoader.characters.swordsman.max_hp
	check(actor.health_component.max_hp >= base_hp * 1.1 - 0.5, "Tier 3 HP bonus missing (%.0f)" % actor.health_component.max_hp)
	# 6. 拠点：深度と目標、持ち越し装備、装備・鍛造画面が開いて閉じると保存される。
	get_tree().paused = false
	game.queue_free()
	await frames(4)
	var home := preload("res://ui/home/home.tscn").instantiate()
	home.tree_entered.connect(func(): get_tree().current_scene = home)
	get_tree().root.add_child(home)
	await frames(4)
	check(home._meta_label.text.contains("深度 2") and home._meta_label.text.contains("次の目標"), "Home hides depth/objective: " + home._meta_label.text)
	check(home._forge_button.text.contains("持ち越し"), "Home forge button missing carried count")
	var mastery_labels: Array = home.character_grid.find_children("Mastery", "Label", true, false)
	check(not mastery_labels.is_empty(), "Home cards lack mastery")
	await capture("home_meta")
	home._forge_button.pressed.emit()
	await frames(4)
	check(home._equipment_screen.is_open(), "Home forge did not open")
	var loadout := home._loadout_player.equipment_component as EquipmentComponent
	check(loadout.get_equipped("weapon") != null and loadout.get_equipped("weapon").instance_id == weapon.instance_id, "Home forge shows wrong loadout")
	await capture("home_forge")
	var extra := EquipmentData.from_dict(helm.to_dict())
	extra.instance_id = "home_added_item"
	loadout.add_item(extra)
	home._equipment_screen._close()
	await frames(2)
	var after := SaveManager.get_persistent_equipment()
	var after_ids: Array[String] = []
	for entry in after.inventory: after_ids.append(String(entry.instance_id))
	check("home_added_item" in after_ids, "Changes made at the home forge are not saved")
	finish()

func finish() -> void:
	var f := FileAccess.open(OUT + "/check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures": failures}, "\t")); f.close()
	print("META_GROWTH " + ("PASS" if failures.is_empty() else "FAIL ") + JSON.stringify(failures))
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1, "META_GROWTH " + ("PASS" if failures.is_empty() else "FAIL"))
