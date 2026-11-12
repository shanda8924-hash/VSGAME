extends Resource
class_name EnemyBehaviorStrategy
## 敵AIのStrategyパターン基底クラス(疑似インターフェース)。
## サブクラスでcompute_direction()をオーバーライドするだけで、
## 「直進型/遠距離型/ボス型」等の新しい挙動を既存コードを一切変更せず追加できる(開放閉鎖の原則)。

func compute_direction(_self_position: Vector2, _target_position: Vector2) -> Vector2:
	return Vector2.ZERO
