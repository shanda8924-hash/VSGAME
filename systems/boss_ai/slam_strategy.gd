extends BossAttackStrategy
class_name SlamStrategy
## 「slam」攻撃: 一定間隔でプレイヤーの現在地に範囲攻撃の予兆(床に警告円を
## 一定時間表示)を出し、その後ダメージ判定が発生する。判定は物理衝突ではなく、
## 警告円の表示時間が終わった瞬間のプレイヤー座標との距離チェックで行う
## (プレイヤーが警告円の外へ逃げていればダメージを受けない)。

@export var telegraph_duration: float = 0.9
@export var damage_radius: float = 110.0
@export var damage_multiplier: float = 2.2

func _init() -> void:
	interval = 7.0
	recovery_duration = 1.5

func execute(boss: EnemyBasic, player: Node2D) -> void:
	if not is_instance_valid(boss) or not is_instance_valid(player):
		return

	var target_position: Vector2 = player.global_position
	boss.set_movement_locked(true)
	boss.movement_component.direction = Vector2.ZERO
	var warning := WarningCircle.new()
	warning.radius = damage_radius
	GameManager.get_runtime_world(boss).add_child(warning)
	warning.global_position = target_position

	await boss.get_tree().create_timer(telegraph_duration).timeout

	if is_instance_valid(warning):
		warning.queue_free()
	if not is_instance_valid(boss):
		return
	_deal_area_damage(boss, target_position)
	await wait_recovery(boss)

func _deal_area_damage(boss: EnemyBasic, position: Vector2) -> void:
	var player_node := boss.get_tree().get_first_node_in_group("player")
	if player_node == null:
		return
	if player_node.global_position.distance_to(position) > damage_radius:
		return
	var health: HealthComponent = player_node.get_node_or_null("HealthComponent")
	if health:
		health.apply_damage(boss.contact_hitbox.damage * damage_multiplier)
