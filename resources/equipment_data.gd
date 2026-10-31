extends Resource
class_name EquipmentData
## ラン中のみ保持する装備インスタンス。SaveManagerには保存しない。

@export var instance_id: String = ""
@export var template_id: String = ""
@export var display_name: String = ""
@export var slot: String = "weapon"
@export var attack_kind: String = "slash"
@export var rarity: String = "uncommon"
@export var icon_path: String = ""
@export var stats: Dictionary = {}
@export var special_effects: Array[String] = []
## Run-scoped marker used by the item box. It does not grant stats or forge protection.
@export var is_favorite: bool = false
## Reserved for inventory safety. Locked items are never selected as merge materials.
@export var is_locked: bool = false
## 特殊効果ごとの実数値。効果IDはspecial_effectsに残し、レアリティ別の強さだけを
## ドロップ時にスナップショットとして保持することで、後からJSONを調整しやすくする。
@export var special_effect_values: Dictionary = {}

func get_stat(stat_name: String) -> float:
	return float(stats.get(stat_name, 0.0))

func get_rarity_display_name() -> String:
	match rarity:
		"rare": return "Rare / レア"
		"epic": return "Epic / エピック"
		"legendary": return "Legendary / レジェンダリー"
		"mythic": return "Mythic / ミシック"
		_: return "Uncommon / アンコモン"

func get_rarity_color() -> Color:
	match rarity:
		"rare": return Color("67a1d3")
		"epic": return Color("ac82ca")
		"legendary": return Color("d5a35f")
		"mythic": return Color("d16c70")
		_: return Color("6bb88c")

func get_slot_display_name() -> String:
	return {"weapon":"武器", "head":"頭", "body":"胴", "arms":"腕", "legs":"脚", "accessory":"アクセサリー"}.get(slot, slot)

func get_special_value(effect_id: String, value_name: String, fallback: float = 0.0) -> float:
	var values: Dictionary = special_effect_values.get(effect_id, {})
	return float(values.get(value_name, fallback))
