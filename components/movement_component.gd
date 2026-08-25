extends Node
class_name MovementComponent
## 移動速度・移動方向の計算のみを責務とするコンポーネント。
## Player(入力駆動)/Enemy(AI駆動)どちらからも同じインターフェースで使える。

@export var base_speed: float = 100.0
var speed_multiplier: float = 1.0 # 状態異常(スロウ等)による一時的な倍率。Entityが毎フレーム上書きする。
## アイテム(swift_boots等)で永続的に蓄積する移動速度倍率。
## PlayerUpgradesComponentが同期する(Enemy側は誰も同期しないため既定の1.0のまま)。
var bonus_speed_multiplier: float = 1.0
var equipment_speed_multiplier: float = 1.0
var direction: Vector2 = Vector2.ZERO

func get_velocity() -> Vector2:
	return direction * base_speed * speed_multiplier * bonus_speed_multiplier * equipment_speed_multiplier
