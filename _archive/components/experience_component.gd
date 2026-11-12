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
const BASE_EXP_TO_LEVEL := 15
const QUICK_LEVEL_END := 10

@export var exp_to_next_level: int = BASE_EXP_TO_LEVEL
var _requirement_multiplier: float = 1.0

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
		# Lv10までは短い間隔で成長し、その後は敵密度の上昇に負けない範囲で徐々に重くする。
		exp_to_next_level = _paced_requirement(level)
		leveled_up.emit(level)
		EventBus.player_leveled_up.emit(level)
	exp_changed.emit(current_exp, exp_to_next_level)

## Runごとの倍率を掛け直す。通常MAPは1.0なので、序盤の通常敵約10体で初回成長する。
func set_requirement_multiplier(multiplier: float) -> void:
	_requirement_multiplier = maxf(multiplier, 0.1)
	exp_to_next_level = _paced_requirement(level)
	exp_changed.emit(current_exp, exp_to_next_level)

func _paced_requirement(current_level: int) -> int:
	return maxi(int(round(float(required_exp_for_level(current_level)) * _requirement_multiplier)), 1)

static func required_exp_for_level(current_level: int) -> int:
	var safe_level := maxi(current_level, 1)
	if safe_level <= QUICK_LEVEL_END:
		return BASE_EXP_TO_LEVEL + (safe_level - 1) * 5
	var levels_after_ten := safe_level - QUICK_LEVEL_END
	return 60 + levels_after_ten * 7 + int(round(pow(float(levels_after_ten), 2.0) * 0.35))
