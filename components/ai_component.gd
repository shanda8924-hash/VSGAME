extends Node
class_name AIComponent
## 敵の思考(Strategy呼び出し)のみを責務とするコンポーネント。
## 実際の移動はMovementComponentに委譲し、AIComponentは「方向を計算するだけ」に徹する。

@export var behavior: EnemyBehaviorStrategy
var target: Node2D

func compute_direction(self_position: Vector2) -> Vector2:
	if behavior == null or target == null:
		return Vector2.ZERO
	return behavior.compute_direction(self_position, target.global_position)
