extends Node
## game.tscn上でCatalog→4枠UI→購入/補充→遺物武器→リロール→2回来店帯を確認する。

var failures: Array[String] = []
var shop_system: ShopSystem
var shop_screen: ShopScreen
var player: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shop_system = get_parent().get_node("ShopSystem") as ShopSystem
	shop_screen = get_parent().get_node("ShopScreen") as ShopScreen
	player = get_parent().get_node("Player") as Player
	_run.call_deferred()

func _run() -> void:
	await _wait_frames(8)
	_validate_catalog()
	GameManager.add_run_gold(4000, "shop_test_seed")
	player.health_component.current_hp = player.health_component.max_hp * 0.35
	shop_screen.show_shop(1)
	await _wait_frames(3)
	_expect(shop_screen.visible, "Shop画面が開きません")
	if "--shop-gui-capture" in OS.get_cmdline_user_args():
		await _wait_frames(20)
		var capture_error := get_viewport().get_texture().get_image().save_png("res://artifacts/shop_screen.png")
		_expect(capture_error == OK, "Shop画面のGUI capture保存に失敗")
	_expect(GameManager.active_modal_count == 1 and get_tree().paused, "ShopがModal停止へ接続されていません")
	var stock := shop_system.get_stock()
	print("SHOP_RUNTIME_STOCK visit=1 catalog=%d state=%s stock=%s" % [shop_system._catalog.size(), player.weapon_manager.get_applied_status_id(), str(stock)])
	_expect(_categories(stock) == ["generic", "recovery", "state", "weapon"], "1店舗が4カテゴリ各1枠ではありません: %s" % [str(_categories(stock))])
	var weapon := _category_product(stock, "weapon")
	_expect(int(weapon.get("price", 0)) >= 450 and int(weapon.get("price", 0)) <= 550, "1回目武器が450〜550G外です")
	var state := _category_product(stock, "state")
	_expect(String(state.get("required_state", "")) == player.weapon_manager.get_applied_status_id(), "状態異常枠が職業状態と一致しません")

	var recovery := _category_product(stock, "recovery")
	var hp_before := player.health_component.current_hp
	_expect(shop_system.buy_product(String(recovery.get("id", ""))), "回復商品を購入できません")
	_expect(player.health_component.current_hp > hp_before, "回復商品の効果が適用されません")
	_expect(not shop_system.get_stock().is_empty() and _category_product(shop_system.get_stock(), "recovery").size() > 0, "購入後に回復枠が補充されません")

	stock = shop_system.get_stock()
	weapon = _category_product(stock, "weapon")
	var weapon_data: WeaponData = DataLoader.weapons.get(String(weapon.get("ref_id", "")))
	_expect(weapon_data != null and weapon_data.is_relic and weapon_data.required_fragment_ids.is_empty(), "遺物武器が欠片条件から独立していません")
	_expect(shop_system.buy_product(String(weapon.get("id", ""))), "遺物武器を購入できません")
	if weapon_data:
		_expect(player.weapon_manager.has_weapon(weapon_data.id), "購入した遺物武器がWeaponManagerへ追加されません")
		var projectile := weapon_data.projectile_scene.instantiate() as Projectile
		get_parent().add_child(projectile)
		projectile.global_position = player.global_position
		projectile.launch(player.global_position + Vector2.RIGHT * 100.0, weapon_data, 1, null, player.upgrades_component)
		_expect(not projectile.get_node("Visual").visible, "遺物ProjectileにArrow画像が表示されています")
		projectile.queue_free()

	stock = shop_system.get_stock()
	state = _category_product(stock, "state")
	var state_upgrade: UpgradeData = DataLoader.upgrades.get(String(state.get("ref_id", "")))
	if state_upgrade:
		var count_before := player.upgrades_component.get_state_upgrade_count(state_upgrade.effect_type)
		_expect(shop_system.buy_product(String(state.get("id", ""))), "旧状態カードを購入できません")
		_expect(player.upgrades_component.get_state_upgrade_count(state_upgrade.effect_type) == count_before + 1, "旧状態カードの効果が適用されません")

	var reroll_cost_before := shop_system.get_reroll_cost()
	_expect(reroll_cost_before == 100 and shop_system.reroll(), "初回100Gリロールに失敗")
	_expect(shop_system.get_reroll_cost() == 150, "リロール価格が段階上昇しません")
	shop_screen.debug_close_shop()
	await _wait_frames(2)
	_expect(not get_tree().paused and GameManager.active_modal_count == 0, "Shop終了後にゲーム停止が残ります")

	shop_screen.show_shop(2)
	await _wait_frames(3)
	stock = shop_system.get_stock()
	weapon = _category_product(stock, "weapon")
	_expect(int(weapon.get("price", 0)) >= 600 and int(weapon.get("price", 0)) <= 800, "2回目武器が600〜800G外です")
	_expect(_categories(stock) == ["generic", "recovery", "state", "weapon"], "2回目も4枠ではありません")
	shop_screen.debug_close_shop()
	await _wait_frames(2)
	_validate_all_old_card_application()

	if failures.is_empty():
		_finish(0, "SHOP_RUNTIME_CHECK: PASS visit1=450-550 visit2=600-800 slots=4 refill=ok reroll=100/150 relics=ok old_cards=ok")
	else:
		for failure in failures:
			push_error("SHOP_RUNTIME_CHECK: %s" % failure)
		_finish(1, "")

func _categories(stock: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for product in stock:
		result.append(String(product.get("category", "")))
	result.sort()
	return result

func _validate_catalog() -> void:
	var relic_count := 0
	var first_visit_relics := 0
	var second_visit_relics := 0
	var old_state_card_count := 0
	for product in shop_system._catalog:
		var kind := String(product.get("item_kind", ""))
		if kind == "weapon":
			relic_count += 1
			var data: WeaponData = DataLoader.weapons.get(String(product.get("ref_id", "")))
			_expect(data != null and data.is_relic, "Catalog武器が遺物としてロードされません: %s" % product.get("ref_id", ""))
			if data:
				_expect(DataLoader.effect_themes.has(data.vfx_theme_id), "遺物武器のHit Themeがありません: %s" % data.id)
			var visits: Array = product.get("visits", [])
			var price := int(product.get("price", 0))
			if _has_visit(visits, 1):
				first_visit_relics += 1
				_expect(price >= 450 and price <= 550, "1回目Catalog武器が価格帯外: %s" % product.get("id", ""))
			if _has_visit(visits, 2):
				second_visit_relics += 1
				_expect(price >= 600 and price <= 800, "2回目Catalog武器が価格帯外: %s" % product.get("id", ""))
		elif String(product.get("category", "")) == "state":
			old_state_card_count += 1
			_expect(DataLoader.upgrades.has(String(product.get("ref_id", ""))), "旧カード定義がロードされません: %s" % product.get("ref_id", ""))
	_expect(relic_count == 15 and first_visit_relics == 10 and second_visit_relics == 5, "遺物Catalogが15種（10/5）ではありません")
	_expect(old_state_card_count == 16, "旧カードCatalogが16枚ではありません")

func _has_visit(visits: Array, expected: int) -> bool:
	for visit in visits:
		if int(visit) == expected:
			return true
	return false

func _validate_all_old_card_application() -> void:
	var applied := 0
	for product in shop_system._catalog:
		if String(product.get("category", "")) != "state":
			continue
		var upgrade: UpgradeData = DataLoader.upgrades.get(String(product.get("ref_id", "")))
		if upgrade == null:
			continue
		var before := player.upgrades_component.get_state_upgrade_count(upgrade.effect_type)
		player.upgrades_component.apply_upgrade(upgrade)
		_expect(player.upgrades_component.get_state_upgrade_count(upgrade.effect_type) == before + 1, "旧カードを適用できません: %s" % upgrade.id)
		applied += 1
	_expect(applied == 16, "旧カード16枚すべてを適用できていません")
	_expect(player.upgrades_component.get_burn_duration_multiplier() > 1.0, "灰燼が燃焼時間へ接続されていません")
	_expect(player.upgrades_component.get_burn_damage_multiplier() > 1.0, "焦熱が燃焼Damageへ接続されていません")
	_expect(player.upgrades_component.get_frozen_duration_multiplier() > 1.0, "永久凍土が凍結時間へ接続されていません")
	_expect(player.upgrades_component.get_cursed_duration_multiplier() > 1.0, "呪縛が呪い時間へ接続されていません")
	_expect(player.upgrades_component.get_cursed_bonus_damage_taken() > StatusApplySystem.CURSED_BONUS_DAMAGE_TAKEN, "深淵が呪い脆弱率へ接続されていません")

func _category_product(stock: Array[Dictionary], category: String) -> Dictionary:
	for product in stock:
		if String(product.get("category", "")) == category:
			return product
	return {}

func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish(exit_code: int, message: String) -> void:
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(exit_code, message)
