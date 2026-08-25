extends Resource
class_name EquipmentData
## ラン中のみ保持する装備インスタンス。SaveManagerには保存しない。

@export var instance_id: String = ""
@export var template_id: String = ""
@export var display_name: String = ""
@export var slot: String = "weapon"
@export var rarity: String = "uncommon"
@export var icon_path: String = ""
@export var stats: Dictionary = {}
@export var special_effects: Array[String] = []
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
		"rare": return Color(0.25, 0.55, 1.0)
		"epic": return Color(0.72, 0.3, 1.0)
		"legendary": return Color(1.0, 0.5, 0.08)
		"mythic": return Color(1.0, 0.12, 0.12)
		_: return Color(0.25, 0.9, 0.35)

func get_slot_display_name() -> String:
	return {"weapon":"武器", "head":"頭", "body":"胴", "arms":"腕", "legs":"脚", "accessory":"アクセサリー"}.get(slot, slot)

func get_special_value(effect_id: String, value_name: String, fallback: float = 0.0) -> float:
	var values: Dictionary = special_effect_values.get(effect_id, {})
	return float(values.get(value_name, fallback))
