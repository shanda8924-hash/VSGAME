extends Node
class_name EquipmentComponent
## ラン内インベントリと6スロットを管理する。Phase 4から、ラン開始時にSaveManagerの
## 持ち越し装備を復元し、ラン終了時に保存する（勝利＝全部、敗北＝ロック品＋1点を確率で）。

signal inventory_changed()
signal equipment_changed(slot: String, item: EquipmentData)
signal equipment_merged(result: EquipmentData)

const SLOTS := ["weapon", "head", "body", "arms", "legs", "accessory"]
const MAX_INVENTORY_SIZE := 50
var inventory: Array[EquipmentData] = []
var equipped: Dictionary = {}
var _applied_max_hp_bonus: float = 0.0
## 持ち越し装備の復元は1インスタンスにつき1回（検査の再出撃でも二重にしない）。
var _restored := false
## 敗北時にロックされていない品を1点だけ持ち帰れる確率。
const LOSS_CARRY_CHANCE := 0.5

func _ready() -> void:
	for slot in SLOTS:
		equipped[slot] = null
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.run_cleared.connect(_on_run_cleared)
	EventBus.run_started.connect(_on_run_started)

func _on_run_started() -> void:
	if GameManager.survival_mode_active:
		restore_from_save()

## SaveManagerの持ち越し装備を所持品と6枠へ戻す。
func restore_from_save() -> void:
	if _restored:
		return
	_restored = true
	var payload := SaveManager.get_persistent_equipment()
	# 持ち越し品は「入手」ではないので、HUDの入手通知は出さない。
	for entry in payload.get("inventory", []):
		if typeof(entry) == TYPE_DICTIONARY:
			add_item(EquipmentData.from_dict(entry), true)
	var equipped_entries: Dictionary = payload.get("equipped", {})
	for slot in equipped_entries.keys():
		var entry = equipped_entries[slot]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item := EquipmentData.from_dict(entry)
		if add_item(item, true):
			equip(item)

## 持ち帰る装備をSaveManagerへ書く。victory=falseはロック品＋1点（確率）だけ。
func store_for_next_run(victory: bool) -> Dictionary:
	var equipped_payload: Dictionary = {}
	var inventory_payload: Array = []
	var carried: Array[EquipmentData] = []
	if victory:
		carried.append_array(inventory)
	else:
		var unlocked: Array[EquipmentData] = []
		for item in inventory:
			if item.is_locked:
				carried.append(item)
			else:
				unlocked.append(item)
		if not unlocked.is_empty() and randf() < LOSS_CARRY_CHANCE:
			carried.append(unlocked.pick_random())
	for item in carried:
		if is_equipped(item):
			equipped_payload[item.slot] = item.to_dict()
		else:
			inventory_payload.append(item.to_dict())
	SaveManager.store_persistent_equipment(equipped_payload, inventory_payload)
	return {"equipped": equipped_payload, "inventory": inventory_payload}

func add_item(item: EquipmentData, silent: bool = false) -> bool:
	if item == null or inventory.size() >= MAX_INVENTORY_SIZE:
		return false
	inventory.append(item)
	inventory_changed.emit()
	if not silent:
		EventBus.equipment_picked_up.emit(item)
	return true

func is_inventory_full() -> bool:
	return inventory.size() >= MAX_INVENTORY_SIZE

func equip(item: EquipmentData) -> bool:
	if item == null or item not in inventory or item.slot not in SLOTS:
		return false
	equipped[item.slot] = item
	_recalculate_bonuses()
	equipment_changed.emit(item.slot, item)
	EventBus.equipment_equipped.emit(item)
	return true

func unequip(slot: String) -> bool:
	if slot not in SLOTS or get_equipped(slot) == null:
		return false
	equipped[slot] = null
	_recalculate_bonuses()
	equipment_changed.emit(slot, null)
	return true

func get_equipped(slot: String) -> EquipmentData:
	return equipped.get(slot) as EquipmentData

func get_all_inventory() -> Array[EquipmentData]:
	return inventory.duplicate()

func remove_item(item: EquipmentData) -> bool:
	if item == null or item not in inventory or is_equipped(item):
		return false
	inventory.erase(item)
	inventory_changed.emit()
	return true

func clear_all() -> void:
	inventory.clear()
	for slot in SLOTS:
		equipped[slot] = null
	_recalculate_bonuses()
	inventory_changed.emit()

func is_equipped(item: EquipmentData) -> bool:
	if item == null:
		return false
	for slot in SLOTS:
		var equipped_item := get_equipped(slot)
		if equipped_item == item:
			return true
		if equipped_item and item.instance_id != "" and equipped_item.instance_id == item.instance_id:
			return true
	return false

## Replaces exactly three safe inventory materials with one promoted result.
## Validation and mutation live in one method so UI refreshes cannot partially consume items.
func replace_merge_materials(materials: Array[EquipmentData], result: EquipmentData) -> bool:
	if materials.is_empty():
		return false
	var seen_instance_ids := {}
	for item in materials:
		if item == null or item not in inventory or is_equipped(item) or item.is_locked:
			return false
		var identity := item.instance_id if item.instance_id != "" else str(item.get_instance_id())
		if seen_instance_ids.has(identity):
			return false
		seen_instance_ids[identity] = true
	for item in materials:
		inventory.erase(item)
	if result:
		inventory.append(result)
	inventory_changed.emit()
	if result:
		equipment_merged.emit(result)
	return true

func get_total_stat(stat_name: String) -> float:
	var total := 0.0
	for slot in SLOTS:
		var item := get_equipped(slot)
		if item:
			total += item.get_stat(stat_name)
	return total

func _recalculate_bonuses() -> void:
	var owner := get_parent()
	var upgrades := owner.get_node_or_null("PlayerUpgradesComponent") as PlayerUpgradesComponent
	var movement := owner.get_node_or_null("MovementComponent") as MovementComponent
	var health := owner.get_node_or_null("HealthComponent") as HealthComponent
	if upgrades:
		upgrades.equipment_damage_multiplier = 1.0 # 旧保存先は互換用。攻撃力は固定値層を使う。
		upgrades.equipment_attack_flat = get_total_stat("attack_power")
		upgrades.equipment_crit_rate_bonus = get_total_stat("crit_rate")
		upgrades.equipment_crit_damage_bonus = get_total_stat("crit_damage")
		upgrades.equipment_attack_speed_bonus = clampf(get_total_stat("attack_speed"), 0.0, 0.7)
		upgrades.equipment_low_hp_threshold = _get_strongest_special_value("low_hp_power", "hp_threshold")
		upgrades.equipment_low_hp_damage_bonus = _get_strongest_special_value("low_hp_power", "damage_bonus")
	if movement:
		movement.equipment_speed_multiplier = 1.0 + get_total_stat("move_speed")
	if health:
		var new_hp_bonus := get_total_stat("max_hp")
		var hp_delta := new_hp_bonus - _applied_max_hp_bonus
		health.max_hp = maxf(1.0, health.max_hp + hp_delta)
		health.current_hp = clampf(health.current_hp + maxf(hp_delta, 0.0), 0.0, health.max_hp)
		_applied_max_hp_bonus = new_hp_bonus
		health.damage_taken_multiplier = maxf(0.2, 1.0 - upgrades.damage_taken_multiplier if upgrades else 1.0)
		health.equipment_defense_flat = get_total_stat("defense")
		health.equipment_negate_chance = _get_strongest_special_value("negate_hit", "chance")

func _has_special(effect_id: String) -> bool:
	for slot in SLOTS:
		var item := get_equipped(slot)
		if item and effect_id in item.special_effects:
			return true
	return false

func _get_strongest_special_value(effect_id: String, value_name: String) -> float:
	var strongest := 0.0
	for slot in SLOTS:
		var item := get_equipped(slot)
		if item and effect_id in item.special_effects:
			strongest = maxf(strongest, item.get_special_value(effect_id, value_name))
	return strongest

func _on_enemy_died(_enemy_data: Resource, _position: Vector2) -> void:
	if not _has_special("kill_heal"):
		return
	var health := get_parent().get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.heal(_get_strongest_special_value("kill_heal", "heal_flat"))

func _on_run_ended(_survived_seconds: float, _kill_count: int) -> void:
	if GameManager.survival_mode_active:
		store_for_next_run(false)
	clear_all()

func _on_run_cleared(_room_count: int, _elapsed_seconds: float, _kill_count: int) -> void:
	if GameManager.survival_mode_active:
		store_for_next_run(true)
