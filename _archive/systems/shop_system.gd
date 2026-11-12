extends Node
class_name ShopSystem
## ボス後Shopの商品抽選・購入適用だけを担う。商品はCatalog駆動で、UIはStockを描画するだけ。

signal stock_changed(stock: Array[Dictionary], reroll_cost: int)
signal purchase_completed(product: Dictionary)
signal purchase_failed(reason: String)
signal rerolled(cost: int)

const CATALOG_PATH := "res://data/shop/shop_catalog.json"
const CATEGORY_ORDER: Array[String] = ["weapon", "generic", "state", "recovery"]
const BASE_REROLL_COST := 25
const REROLL_COST_STEP := 15

var _catalog: Array[Dictionary] = []
var _stock: Array[Dictionary] = []
var _purchased_ids: Dictionary = {}
var _purchased_in_run: Dictionary = {}
var _visit_index := 0
var _reroll_count := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_catalog = _load_catalog()
	EventBus.run_started.connect(_reset_run_purchases)

func begin_visit(visit_index: int) -> void:
	_visit_index = maxi(visit_index, 1)
	_reroll_count = 0
	_purchased_ids.clear()
	_stock.clear()
	_refill_all({})
	_emit_stock()

func get_stock() -> Array[Dictionary]:
	return _stock.duplicate(true)

func get_visit_index() -> int:
	return _visit_index

func get_reroll_cost() -> int:
	return roundi((BASE_REROLL_COST + REROLL_COST_STEP * _reroll_count) * _depth_price_scale())

func reroll() -> bool:
	var cost := get_reroll_cost()
	if not GameManager.try_spend_run_gold(cost, "shop_reroll"):
		purchase_failed.emit("ゴールドが足りません")
		return false
	_reroll_count += 1
	var previous_ids := _visible_product_ids()
	_stock.clear()
	_refill_all(previous_ids)
	_emit_stock()
	rerolled.emit(cost)
	return true

func buy_product(product_id: String) -> bool:
	var stock_index := _find_stock_index(product_id)
	if stock_index < 0:
		purchase_failed.emit("商品は既に入れ替わっています")
		return false
	var product: Dictionary = _stock[stock_index]
	var reason := _validate_purchase(product)
	if reason != "":
		purchase_failed.emit(reason)
		return false
	var price := int(product.get("price", 0))
	if not GameManager.try_spend_run_gold(price, "shop_purchase:%s" % product_id):
		purchase_failed.emit("ゴールドが足りません")
		return false
	_apply_product(product)
	_purchased_ids[product_id] = true
	if String(product.get("category", "")) != "recovery":
		_purchased_in_run[product_id] = true
	_stock.remove_at(stock_index)
	var replacement := _pick_product(String(product.get("category", "")), _visible_product_ids())
	if not replacement.is_empty():
		_stock.insert(stock_index, replacement)
	purchase_completed.emit(product.duplicate(true))
	_emit_stock()
	return true

func describe_product(product: Dictionary) -> Dictionary:
	var result := product.duplicate(true)
	match String(product.get("item_kind", "")):
		"weapon":
			var weapon: WeaponData = DataLoader.weapons.get(String(product.get("ref_id", "")))
			if weapon:
				result["display_name"] = weapon.display_name
				result["description"] = "%s\n攻撃力 %.0f / 間隔 %.2f秒" % [weapon.description, weapon.base_damage, weapon.attack_interval]
		"upgrade":
			var upgrade: UpgradeData = DataLoader.upgrades.get(String(product.get("ref_id", "")))
			if upgrade:
				result["display_name"] = upgrade.display_name
				result["description"] = upgrade.description
	return result

func _refill_all(previous_ids: Dictionary) -> void:
	var excluded := previous_ids.duplicate()
	for category in CATEGORY_ORDER:
		var product := _pick_product(category, excluded)
		if product.is_empty() and not previous_ids.is_empty():
			product = _pick_product(category, {})
		if not product.is_empty():
			_stock.append(product)
			excluded[String(product.get("id", ""))] = true

func _pick_product(category: String, excluded_ids: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var state_id := _current_state_id()
	var weapon_manager := _weapon_manager()
	for product in _catalog:
		if String(product.get("category", "")) != category:
			continue
		if _purchased_ids.has(String(product.get("id", ""))) or _purchased_in_run.has(String(product.get("id", ""))) or excluded_ids.has(String(product.get("id", ""))):
			continue
		var visits: Array = product.get("visits", [])
		var visit_allowed := false
		for visit in visits:
			if int(visit) == (2 if _visit_index > 20 else 1):
				visit_allowed = true
				break
		if not visit_allowed:
			continue
		if category == "state" and String(product.get("required_state", "")) != state_id:
			continue
		if category == "weapon" and weapon_manager and weapon_manager.has_weapon(String(product.get("ref_id", ""))):
			continue
		candidates.append(product)
	if candidates.is_empty():
		return {}
	var choice: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)].duplicate(true)
	choice["price"] = roundi(float(choice.get("price", 0)) * _depth_price_scale() / 5.0) * 5
	return choice

func _depth_price_scale() -> float:
	return 1.0 + float(maxi(_visit_index - 1, 0)) * 0.035

func _reset_run_purchases() -> void:
	_purchased_in_run.clear()

func _validate_purchase(product: Dictionary) -> String:
	match String(product.get("item_kind", "")):
		"weapon":
			var weapon_id := String(product.get("ref_id", ""))
			var manager := _weapon_manager()
			if not DataLoader.weapons.has(weapon_id) or manager == null:
				return "武器を取得できません"
			if manager.has_weapon(weapon_id):
				return "既に所持しています"
		"upgrade":
			if not DataLoader.upgrades.has(String(product.get("ref_id", ""))):
				return "強化データが見つかりません"
			var required_state := String(product.get("required_state", ""))
			if required_state != "" and required_state != _current_state_id():
				return "現在の職業では使用できません"
		"recovery":
			var player := _player()
			if player == null or player.health_component.current_hp >= player.health_component.max_hp:
				return "HPは満タンです"
		_:
			return "未対応の商品です"
	return ""

func _apply_product(product: Dictionary) -> void:
	var player := _player()
	match String(product.get("item_kind", "")):
		"weapon":
			var weapon: WeaponData = DataLoader.weapons.get(String(product.get("ref_id", "")))
			player.weapon_manager.add_weapon(weapon)
		"upgrade":
			var upgrade: UpgradeData = DataLoader.upgrades.get(String(product.get("ref_id", "")))
			player.upgrades_component.apply_upgrade(upgrade)
		"recovery":
			player.health_component.heal(player.health_component.max_hp * float(product.get("value", 0.0)))

func _current_state_id() -> String:
	var manager := _weapon_manager()
	return manager.get_applied_status_id() if manager else ""

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _weapon_manager() -> WeaponManagerComponent:
	var player := _player()
	return player.weapon_manager if player else null

func _find_stock_index(product_id: String) -> int:
	for index in _stock.size():
		if String(_stock[index].get("id", "")) == product_id:
			return index
	return -1

func _visible_product_ids() -> Dictionary:
	var result := {}
	for product in _stock:
		result[String(product.get("id", ""))] = true
	return result

func _emit_stock() -> void:
	stock_changed.emit(get_stock(), get_reroll_cost())

func _load_catalog() -> Array[Dictionary]:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("ShopSystem: Catalogがありません -> %s" % CATALOG_PATH)
		return []
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ShopSystem: CatalogのJSONが不正です")
		return []
	var result: Array[Dictionary] = []
	for entry in parsed.get("products", []):
		if typeof(entry) == TYPE_DICTIONARY:
			result.append(Dictionary(entry).duplicate(true))
	return result
