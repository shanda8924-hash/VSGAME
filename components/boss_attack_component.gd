extends Node
class_name BossAttackComponent
## ボス固有攻撃(systems/boss_ai/のBossAttackStrategy)を一定間隔で発動させる
## だけの責務を持つコンポーネント。AIComponent(移動)とは完全に独立して動作する。
## EnemyBasicがBossData.attack_pattern_idを検出した場合のみ動的に生成・
## アタッチされる(通常の雑魚敵には付与されないため、大量に湧く雑魚のオーバー
## ヘッドにはならない)。

var attack_strategy: BossAttackStrategy
var boss: EnemyBasic
var target: Node2D
## ROOM進行側から設定する固有攻撃間隔倍率。1未満ほど高頻度。
var interval_multiplier: float = 1.0

var _timer: float = 0.0
## 攻撃実行中(溜め〜攻撃終了まで)は次の攻撃発動を重ねないためのロック。
var _is_attacking: bool = false

func _ready() -> void:
	_timer = _resolved_interval()

func _process(delta: float) -> void:
	if attack_strategy == null or _is_attacking:
		return
	if not _is_boss_alive():
		return
	if target == null or not is_instance_valid(target):
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _resolved_interval()
		_run_attack()

func _resolved_interval() -> float:
	return maxf((attack_strategy.interval if attack_strategy else 6.0) * interval_multiplier, 0.35)

func stop() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	_is_attacking = false

func _is_boss_alive() -> bool:
	return is_instance_valid(boss) and boss.health_component != null and boss.health_component.current_hp > 0.0

func _run_attack() -> void:
	_is_attacking = true
	await attack_strategy.execute(boss, target)
	_is_attacking = false
