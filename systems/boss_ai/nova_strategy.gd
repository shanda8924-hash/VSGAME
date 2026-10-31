extends BossAttackStrategy
class_name NovaStrategy
## 「nova」攻撃: 一定間隔で自分を中心に全方向へ弾をばら撒く。
## 既存のentities/projectiles/projectile.tscn(プレイヤーの武器と同じ弾)を
## そのまま流用し、collision_layerだけプレイヤーのHurtboxComponentが検知する
## 層(16、ContactHitboxと同じ)に差し替えることで、既存の被弾パイプライン
## (HurtboxComponent -> HealthComponent.apply_damage)をそのまま利用する。

const PLAYER_HIT_LAYER := 16 # HurtboxComponent(Player).collision_mask=16と一致させる

@export var bullet_count: int = 12
@export var bullet_speed: float = 260.0
@export var telegraph_duration: float = 0.85
## ボスの接触ダメージに対する各弾1発あたりの倍率。等倍(1.0)だと、全弾が
## 同じ発射点(ボス自身)から出るためプレイヤーが近くにいると複数発が
## ほぼ同時に命中し、合算で接触ダメージの何倍もの被害になり得た
## (実際に即死する事故が発生したため引き下げた)。HealthComponent側の
## 被弾上限キャップとあわせた二重の安全策としている。
@export var damage_multiplier: float = 0.4

func _init() -> void:
	interval = 5.0
	recovery_duration = 1.35

func execute(boss: EnemyBasic, _player: Node2D) -> void:
	if not alive(boss):
		return
	begin_attack(boss)
	var warning := warning_circle(boss, boss.global_position, 90.0, telegraph_duration)
	warning.radial_rays = bullet_count
	await boss.get_tree().create_timer(telegraph_duration, false).timeout
	if is_instance_valid(warning):
		warning.queue_free()
	if not alive(boss):
		return

	var projectile_scene: PackedScene = load("res://entities/projectiles/projectile.tscn")
	var weapon_data := _build_synthetic_weapon_data(boss)
	var origin: Vector2 = boss.global_position
	for i in bullet_count:
		var angle: float = TAU * float(i) / float(bullet_count)
		var direction := Vector2(cos(angle), sin(angle))
		var bullet := projectile_scene.instantiate()
		bullet.name = "BossNovaProjectile_%02d" % i
		bullet.add_to_group("boss_projectiles")
		bullet.collision_layer = PLAYER_HIT_LAYER
		bullet.is_player_attack = false
		bullet.uses_player_element_vfx = false
		bullet.speed = bullet_speed
		GameManager.get_runtime_world(boss).add_child(bullet)
		bullet.global_position = origin
		bullet.launch(origin + direction * 100.0, weapon_data)
		# Player弾の白/属性色と即座に区別できる敵性の紫紅色。Sprite自体と
		# collision/damage/lifetimeは共通Projectileのまま維持する。
		bullet.get_node("Visual").modulate = Color(1.0, 0.32, 0.72, 1.0)
		bullet.get_node("Glow").modulate = Color(1.0, 0.12, 0.55, 0.5)
	await wait_recovery(boss)

## Projectile.launch()はWeaponData(base_damage/crit_chance等)を要求するため、
## ボスのcontact_damageを元にした最小限のWeaponDataをその場で組み立てる
## (クリティカルは発生させない=crit_chance 0、属性演出テーマも既定色で表示)。
func _build_synthetic_weapon_data(boss: EnemyBasic) -> WeaponData:
	var data := WeaponData.new()
	data.base_damage = boss.contact_hitbox.damage * damage_multiplier
	data.crit_chance = 0.0
	data.crit_multiplier = 1.0
	data.vfx_theme_id = ""
	return data
