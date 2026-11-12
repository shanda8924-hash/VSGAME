extends Node
class_name MovementComponent
## 移動速度と移動方向の計算だけを担うコンポーネント。

@export var base_speed: float = 100.0
## 一時的な速度倍率(1.0=等倍)。使う側が設定する。
var speed_multiplier: float = 1.0
var direction: Vector2 = Vector2.ZERO

func get_velocity() -> Vector2:
	return direction * base_speed * speed_multiplier
