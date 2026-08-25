extends BossAttackStrategy
class_name ChargeAttackStrategy
## 「charge」攻撃: プレイヤーの位置に向かって数秒溜めた後、素早く直線的に突進する
## (突進中は接触ダメージが通常より高い)。溜め中は通常のプレイヤー追跡移動を
## EnemyBasic.set_movement_locked(true)で一時的に止め、突進の瞬間だけ
## MovementComponentの速度・方向をこのStrategyが直接制御する。

@export var telegraph_duration: float = 1.0
@export var dash_speed: float = 700.0
@export var dash_duration: float = 0.4
@export var damage_multiplier: float = 1.8
@export var telegraph_flash_color: Color = Color(1.6, 0.35, 0.35, 1.0)

func _init() -> void:
	interval = 6.0
	recovery_duration = 1.4

func execute(boss: EnemyBasic, player: Node2D) -> void:
	if not is_instance_valid(boss) or not is_instance_valid(player):
		return

	# 溜め: 移動を止めてスプライトを赤く明滅させ、突進方向を予告する。
	boss.set_movement_locked(true)
	boss.movement_component.direction = Vector2.ZERO
	# 予備動作開始時の位置へ方向を固定する。溜め中に横へ移動すれば回避できる。
	var dash_direction: Vector2 = (player.global_position - boss.global_position).normalized()
	_play_telegraph_flash(boss)
	await boss.get_tree().create_timer(telegraph_duration).timeout

	if not is_instance_valid(boss):
		return
	if not is_instance_valid(player):
		boss.set_movement_locked(false)
		return

	# 突進: 溜め終了時点のプレイヤー位置へ向けて直線的に高速移動しつつ、
	# 接触ダメージを一時的に引き上げる。
	var original_speed: float = boss.movement_component.base_speed
	var original_damage: float = boss.contact_hitbox.damage
	boss.movement_component.base_speed = dash_speed
	boss.movement_component.direction = dash_direction
	boss.contact_hitbox.damage = original_damage * damage_multiplier
	var hit_player := false
	var elapsed := 0.0
	while elapsed < dash_duration and is_instance_valid(boss):
		await boss.get_tree().physics_frame
		elapsed += boss.get_physics_process_delta_time()
		if not hit_player and is_instance_valid(player) and boss.global_position.distance_to(player.global_position) <= 55.0:
			var hurtbox: HurtboxComponent = player.get_node_or_null("HurtboxComponent")
			if hurtbox:
				hurtbox.apply_hitbox_damage(boss.contact_hitbox)
				hit_player = true

	if is_instance_valid(boss):
		boss.movement_component.base_speed = original_speed
		boss.contact_hitbox.damage = original_damage
		boss.movement_component.direction = Vector2.ZERO
		await wait_recovery(boss)

func _play_telegraph_flash(boss: EnemyBasic) -> void:
	var sprite: AnimatedSprite2D = boss.animated_sprite
	if sprite == null:
		return
	var tween := boss.create_tween()
	var half := maxf(telegraph_duration / 6.0, 0.05)
	tween.set_loops(3)
	tween.tween_property(sprite, "modulate", telegraph_flash_color, half)
	tween.tween_property(sprite, "modulate", Color(1, 1, 1, 1), half)
