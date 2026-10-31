extends RefCounted
class_name EquipmentMergeSystem
## Run-local equipment promotion. This is intentionally separate from element Fusion.

const MATERIAL_COUNT := 3
const RARITY_ORDER := ["uncommon", "rare", "epic", "legendary", "mythic"]
const DROP_TABLE_PATH := "res://data/equipment/drop_table.json"
const TEMPLATES_PATH := "res://data/equipment/templates.json"

var _drop_table: Dictionary = {}
var _templates: Array[Dictionary] = []
var _templates_by_id: Dictionary = {}
var _serial := 0
var last_failure_loss := 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
	_drop_table = _read_json_dictionary(DROP_TABLE_PATH)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES_PATH))
	if typeof(parsed) == TYPE_ARRAY:
		for raw_entry in parsed:
			var entry := Dictionary(raw_entry)
			_templates.append(entry)
			_templates_by_id[String(entry.get("id", ""))] = entry

static func required_count(rarity: String) -> int:
	return 3 if rarity in ["uncommon", "rare", "epic", "legendary"] else 0

func success_rate(rarity: String) -> float:
	return float(_drop_table.get("merge_rules", {}).get(rarity, {}).get("success_rate", 0.0))

func failure_loss(rarity: String) -> int:
	return int(_drop_table.get("merge_rules", {}).get(rarity, {}).get("failure_loss", 1))

func get_next_rarity(rarity: String) -> String:
	var index := RARITY_ORDER.find(rarity)
	if index < 0 or index >= RARITY_ORDER.size() - 1:
		return ""
	return String(RARITY_ORDER[index + 1])

## Backward-compatible helper used by the Test Lab. Unlike the old implementation,
## the selected item's template/name is irrelevant; every safe item of the same
## rarity can fill the remaining material slots.
func get_merge_materials(component: EquipmentComponent, selected: EquipmentData) -> Array[EquipmentData]:
	var materials: Array[EquipmentData] = []
	if component == null or selected == null or get_next_rarity(selected.rarity) == "":
		return materials
	for candidate in component.get_all_inventory():
		if candidate == null or candidate.rarity != selected.rarity:
			continue
		if candidate.is_locked or component.is_equipped(candidate):
			continue
		materials.append(candidate)
	materials.sort_custom(func(a: EquipmentData, b: EquipmentData):
		return a.instance_id.naturalnocasecmp_to(b.instance_id) < 0
	)
	if selected in materials:
		materials.erase(selected)
		materials.push_front(selected)
	return materials

func get_merge_count(component: EquipmentComponent, selected: EquipmentData) -> int:
	return get_merge_materials(component, selected).size()

func can_merge(component: EquipmentComponent, selected: EquipmentData) -> bool:
	return selected != null and required_count(selected.rarity) > 0 and get_merge_count(component, selected) >= required_count(selected.rarity)

func get_mergeable_groups(component: EquipmentComponent) -> Array[Dictionary]:
	var groups := {}
	if component == null:
		return []
	for item in component.get_all_inventory():
		if item == null or item.is_locked or component.is_equipped(item) or get_next_rarity(item.rarity) == "":
			continue
		if not groups.has(item.rarity):
			groups[item.rarity] = {"rarity": item.rarity, "item": item, "count": 0}
		groups[item.rarity]["count"] = int(groups[item.rarity]["count"]) + 1
	var result: Array[Dictionary] = []
	for group in groups.values():
		if int(group["count"]) >= required_count(String(group["rarity"])):
			result.append(group)
	return result

## Returns a Japanese reason for every invalid state so UI and automated checks use
## the exact same rules. Validation is repeated immediately before the transaction.
func get_merge_validation(component: EquipmentComponent, materials: Array[EquipmentData]) -> Dictionary:
	if component == null:
		return _invalid("装備インベントリを確認できません")
	if materials.is_empty() or materials[0] == null:
		return _invalid("同じレア度の素材を選択してください")
	var needed := required_count(materials[0].rarity)
	if needed == 0 or materials.size() != needed:
		return _invalid("素材を%d個選択してください（%d / %d）" % [needed, materials.size(), needed])

	var seen := {}
	var rarity := ""
	for item in materials:
		if item == null:
			return _invalid("選択した素材を確認できません")
		var identity := str(item.get_instance_id())
		if seen.has(identity):
			return _invalid("同じ装備を複数の素材スロットには入れられません")
		seen[identity] = true
		if item not in component.inventory:
			return _invalid("所持していない装備が含まれています")
		if component.is_equipped(item):
			return _invalid("装備中のアイテムは素材にできません")
		if item.is_locked:
			return _invalid("ロック中のアイテムは素材にできません")
		if rarity == "":
			rarity = item.rarity
		elif item.rarity != rarity:
			return _invalid("素材のレアリティを統一してください")

	var next_rarity := get_next_rarity(rarity)
	if next_rarity == "":
		return _invalid("最高レアリティの装備は合成できません")
	if _templates_for_rarity(next_rarity).is_empty():
		return _invalid("次レアリティの生成候補がありません")
	return {
		"valid": true,
		"reason": "合成できます",
		"input_rarity": rarity,
		"output_rarity": next_rarity,
	}

func can_merge_materials(component: EquipmentComponent, materials: Array[EquipmentData]) -> bool:
	return bool(get_merge_validation(component, materials).get("valid", false))

func build_preview(component: EquipmentComponent, selected: EquipmentData) -> EquipmentData:
	var candidates := get_merge_materials(component, selected)
	if selected == null or candidates.size() < required_count(selected.rarity):
		return null
	var materials: Array[EquipmentData] = []
	materials.assign(candidates.slice(0, required_count(selected.rarity)))
	if not can_merge_materials(component, materials):
		return null
	return _build_promoted_item(materials)

## Compatibility entry point for debug code. Production UI calls merge_materials()
## with the three explicit slot references.
func merge(component: EquipmentComponent, selected: EquipmentData) -> EquipmentData:
	var candidates := get_merge_materials(component, selected)
	if selected == null or candidates.size() < required_count(selected.rarity):
		return null
	var materials: Array[EquipmentData] = []
	materials.assign(candidates.slice(0, required_count(selected.rarity)))
	return merge_materials(component, materials)

## Atomic 3 -> 1 transaction: validate references, construct a complete output,
## then ask EquipmentComponent to replace all three in one inventory mutation.
func merge_materials(component: EquipmentComponent, materials: Array[EquipmentData]) -> EquipmentData:
	last_failure_loss = 0
	if not can_merge_materials(component, materials):
		return null
	var result := _build_promoted_item(materials)
	if result == null:
		return null
	if rng.randf() >= success_rate(materials[0].rarity):
		var loss := failure_loss(materials[0].rarity)
		var consumed: Array[EquipmentData] = []
		consumed.assign(materials.slice(0, loss))
		if component.replace_merge_materials(consumed, null):
			last_failure_loss = loss
		return null
	if not component.replace_merge_materials(materials, result):
		return null
	return result

func _build_promoted_item(materials: Array[EquipmentData]) -> EquipmentData:
	if materials.is_empty() or materials[0] == null or materials.size() != required_count(materials[0].rarity):
		return null
	var source_rarity := materials[0].rarity
	for material in materials:
		if material == null or material.rarity != source_rarity:
			return null
	var next_rarity := get_next_rarity(source_rarity)
	var template := _select_output_template(materials, next_rarity)
	if template.is_empty():
		return null

	var result := EquipmentData.new()
	_serial += 1
	result.instance_id = "%s_merge_%d_%d" % [template.get("id", "equipment"), Time.get_ticks_usec(), _serial]
	result.template_id = String(template.get("id", ""))
	result.display_name = String(template.get("display_name", "装備"))
	result.slot = String(template.get("slot", "weapon"))
	result.rarity = next_rarity
	result.icon_path = String(template.get("icon_path", ""))

	var available_stats: Array = Array(template.get("stats", [])).duplicate()
	var target_affix_count := int(_rarity_definition(next_rarity).get("affix_count", available_stats.size()))
	var fallback_quality := _best_material_quality(materials, source_rarity)
	for stat_name_variant in available_stats.slice(0, mini(target_affix_count, available_stats.size())):
		var stat_name := String(stat_name_variant)
		var quality := _best_quality_for_stat(materials, stat_name, source_rarity, fallback_quality)
		result.stats[stat_name] = _value_at_quality(stat_name, next_rarity, quality)

	if bool(_rarity_definition(next_rarity).get("special_effect", false)):
		var effect_id := _select_special_effect(materials, result.template_id)
		if effect_id != "":
			result.special_effects.append(effect_id)
			result.special_effect_values[effect_id] = _special_values(effect_id, next_rarity)
	return result

## All current characters use the same six equipment slots. Prefer a slot represented
## by the materials so the result is immediately useful, then fall back to the complete
## existing next-rarity pool. This is a preference, not an exact recipe.
func _select_output_template(materials: Array[EquipmentData], next_rarity: String) -> Dictionary:
	var all_candidates := _templates_for_rarity(next_rarity)
	if all_candidates.is_empty():
		return {}
	var material_slots := {}
	var seed_parts: Array[String] = [next_rarity]
	for material in materials:
		material_slots[material.slot] = true
		seed_parts.append(material.instance_id if material.instance_id != "" else str(material.get_instance_id()))
	var preferred: Array[Dictionary] = []
	for candidate in all_candidates:
		if material_slots.has(String(candidate.get("slot", ""))):
			preferred.append(candidate)
	var pool := preferred if not preferred.is_empty() else all_candidates
	var index := posmod("|".join(seed_parts).hash(), pool.size())
	return pool[index]

func _templates_for_rarity(rarity: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for template in _templates:
		if String(template.get("rarity", "")) == rarity:
			result.append(template)
	return result

func _best_material_quality(materials: Array[EquipmentData], rarity: String) -> float:
	var best := 0.5
	for material in materials:
		for stat_name in material.stats:
			best = maxf(best, _stat_quality(String(stat_name), material.get_stat(String(stat_name)), rarity))
	return best

func _best_quality_for_stat(materials: Array[EquipmentData], stat_name: String, rarity: String, fallback: float) -> float:
	var best := -1.0
	for material in materials:
		if material.stats.has(stat_name):
			best = maxf(best, _stat_quality(stat_name, material.get_stat(stat_name), rarity))
	return fallback if best < 0.0 else best

func _stat_quality(stat_name: String, value: float, rarity: String) -> float:
	var range_values: Array = _drop_table.get("stat_ranges", {}).get(rarity, {}).get(stat_name, [])
	if range_values.size() < 2 or float(range_values[1]) <= float(range_values[0]):
		return 0.5
	return clampf((value - float(range_values[0])) / (float(range_values[1]) - float(range_values[0])), 0.0, 1.0)

func _value_at_quality(stat_name: String, rarity: String, quality: float) -> float:
	var range_values: Array = _drop_table.get("stat_ranges", {}).get(rarity, {}).get(stat_name, [0.0, 0.0])
	var value := lerpf(float(range_values[0]), float(range_values[1]), clampf(quality, 0.0, 1.0))
	return roundf(value) if stat_name in ["attack_power", "defense", "max_hp"] else snappedf(value, 0.001)

func _select_special_effect(materials: Array[EquipmentData], template_id: String) -> String:
	for material in materials:
		if not material.special_effects.is_empty():
			return material.special_effects[0]
	var effects: Array = _drop_table.get("special_effects", [])
	if effects.is_empty():
		return ""
	var index := posmod(template_id.hash(), effects.size())
	return String(effects[index].get("id", ""))

func _special_values(effect_id: String, rarity: String) -> Dictionary:
	for effect in _drop_table.get("special_effects", []):
		if String(effect.get("id", "")) == effect_id:
			return Dictionary(effect.get(rarity, {})).duplicate(true)
	return {}

func _rarity_definition(rarity: String) -> Dictionary:
	for entry in _drop_table.get("rarities", []):
		if String(entry.get("id", "")) == rarity:
			return Dictionary(entry)
	return {}

func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason, "input_rarity": "", "output_rarity": ""}

func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
