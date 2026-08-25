extends Resource
class_name BossAttackStrategy
## ボス固有攻撃のStrategyパターン基底クラス(疑似インターフェース)。
## components/ai/enemy_behavior_strategy.gdが「移動ロジック」のStrategyであるのに
## 対し、こちらは移動とは独立した「攻撃ロジック」のStrategyを担う。
## BossAttackComponentがintervalごとにexecute()をawaitで呼び出す。
## サブクラスでexecute()をオーバーライドするだけで新しい固有攻撃を追加できる
## (開放閉鎖の原則)。

## 次の発動までの間隔(秒)。サブクラスの_init()で上書きする想定。
@export var interval: float = 6.0
## 攻撃終了後、近接職が安全に接近して通常攻撃を差し込める硬直時間。
@export var recovery_duration: float = 1.25

## 実際の攻撃処理。bossは攻撃元のEnemyBasic、playerは対象(通常はプレイヤー)。
## 溜め演出や警告円など複数フレームにまたがる処理を行うため、awaitを使う
## コルーチンとして実装してよい(呼び出し側のBossAttackComponentがawaitする)。
func execute(_boss: EnemyBasic, _player: Node2D) -> void:
	pass

func wait_recovery(boss: EnemyBasic) -> void:
	if not is_instance_valid(boss):
		return
	boss.set_movement_locked(true)
	boss.movement_component.direction = Vector2.ZERO
	await boss.get_tree().create_timer(recovery_duration).timeout
	if is_instance_valid(boss):
		boss.set_movement_locked(false)
