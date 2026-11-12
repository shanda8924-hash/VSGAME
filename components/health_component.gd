extends Node
class_name HealthComponent
## HP管理だけを担うコンポーネント。描画やUI更新は行わず、Signalで通知する。
## 防御・シールド・無敵時間などピボット前の戦闘ルールは _archive/ に退避済み。

signal damaged(amount: float, current_hp: float, max_hp: float)
signal healed(amount: float, current_hp: float, max_hp: float)
signal died()

@export var max_hp: float = 100.0
var current_hp: float

func _ready() -> void:
	current_hp = max_hp

## amount ぶんHPを減らす。実際に減った量を返す。
func apply_damage(amount: float) -> float:
	if current_hp <= 0.0 or amount <= 0.0:
		return 0.0
	var dealt := minf(amount, current_hp)
	current_hp -= dealt
	damaged.emit(dealt, current_hp, max_hp)
	if current_hp <= 0.0:
		died.emit()
	return dealt

func heal(amount: float) -> void:
	if current_hp <= 0.0 or amount <= 0.0:
		return
	var before := current_hp
	current_hp = minf(current_hp + amount, max_hp)
	if current_hp > before:
		healed.emit(current_hp - before, current_hp, max_hp)
