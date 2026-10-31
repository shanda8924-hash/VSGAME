extends EnemyBehaviorStrategy
class_name RangedStrategy
## 遠距離型の敵。射程の内側まで近づいたら立ち止まり、近づかれ過ぎたら下がる。
## 「プレイヤーが立ち止まると弾が飛んでくる」役割を作るためのもの（Phase 1）。
## 射程と保持距離はEnemyData.ranged_rangeから与える。

var hold_distance: float = 200.0
var retreat_distance: float = 110.0

func compute_direction(self_position: Vector2, target_position: Vector2) -> Vector2:
	var offset := target_position - self_position
	var distance := offset.length()
	if distance > hold_distance:
		return offset.normalized()
	if distance < retreat_distance:
		return -offset.normalized()
	return Vector2.ZERO
