extends Node
class_name ExperienceComponent
## 経験値・レベルアップ管理。レベルアップ時はEventBus経由で通知するだけで、
## 実際の3択UI表示はLevelUpSelect側が購読して行う(疎結合)。
## 経験値の獲得源はEventBus.enemy_died(敵撃破)を自ら購読して賄う。

signal leveled_up(new_level: int)
## HUDの経験値ゲージ表示用(2026年8月追加)。add_exp()のたびに(レベルアップが
## 発生してもしなくても)最新のcurrent_exp/exp_to_next_levelを通知する。
signal exp_changed(current_exp: int, exp_to_next_level: int)

@export var level: int = 1
@export var current_exp: int = 0
@export var exp_to_next_level: int = 5

func _ready() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)

func _on_enemy_died(enemy_data: Resource, _death_position: Vector2) -> void:
	add_exp(int(round(enemy_data.exp_value * _get_exp_gain_multiplier())))

## 職業パッシブ(CharacterData.exp_gain_multiplier)由来の獲得経験値倍率を、
## 兄弟ノードのPlayerUpgradesComponentから読み取る(無ければ1.0=補正なし)。
func _get_exp_gain_multiplier() -> float:
	var parent := get_parent()
	if parent == null:
		return 1.0
	var upgrades: PlayerUpgradesComponent = parent.get_node_or_null("PlayerUpgradesComponent")
	return upgrades.exp_gain_multiplier if upgrades else 1.0

func add_exp(amount: int) -> void:
	current_exp += amount
	while current_exp >= exp_to_next_level:
		current_exp -= exp_to_next_level
		level += 1
		exp_to_next_level = int(exp_to_next_level * 1.25) + 3
		leveled_up.emit(level)
		EventBus.player_leveled_up.emit(level)
	exp_changed.emit(current_exp, exp_to_next_level)
