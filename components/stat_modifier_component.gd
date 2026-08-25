extends Node
class_name StatModifierComponent
## バフ/デバフによるステータス補正の集約コンポーネント(設計提案書2.3に対応)。
## 現状は「レベルアップに伴う固定攻撃力・クリティカル率の底上げ」のみを持つ。
## EventBus.player_leveled_upを自ら購読するため、他のComponentから明示的に
## 呼び出さなくても常に最新のプレイヤーレベルを反映する。

@export var damage_flat_per_level: float = 1.0 # 1レベルごとに固定攻撃力+1
@export var crit_chance_bonus_per_level: float = 0.01 # 1レベルごとにクリティカル率+1%
@export var crit_chance_bonus_cap: float = 0.5 # クリティカル率補正の上限(暴走防止)

var _level: int = 1

func _ready() -> void:
	EventBus.player_leveled_up.connect(_on_leveled_up)

func _on_leveled_up(new_level: int) -> void:
	_level = new_level

func get_damage_flat_bonus() -> float:
	return damage_flat_per_level * float(_level - 1)

## 旧呼び出しとの互換用。レベル成長は固定値層へ移したため倍率は常に1.0。
func get_damage_multiplier() -> float:
	return 1.0

func get_crit_chance_bonus() -> float:
	return min(crit_chance_bonus_per_level * float(_level - 1), crit_chance_bonus_cap)
