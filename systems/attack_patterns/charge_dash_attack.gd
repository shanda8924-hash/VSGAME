extends AttackPatternBase
class_name ChargeDashAttack
## Knight(charge_dash): 一定間隔で最も近い敵の方向へ自動突進する。突進中は
## Player.set_movement_locked()で通常の入力移動を止め、MovementComponentを
## 直接制御する(EnemyBasicのBossAttackStrategyと同じ「移動ロック」の考え方)。
## 通過した敵にはダメージ+簡易ノックバック(位置を弾き飛ばすだけの簡易実装)を与える。
## dash_invincible(CharacterData)がtrueの間は突進中HealthComponent.invincibleを立てる。

const DEFAULT_DASH_SPEED := 480.0
const DEFAULT_DASH_DURATION := 0.3
const DEFAULT_HIT_RADIUS := 55.0
const DEFAULT_KNOCKBACK_DISTANCE := 60.0
## 職業専用強化(ability_level、2026年8月追加、Knight固有)。
const LV2_DASH_DURATION_MULTIPLIER := 1.5   # Lv2: 突進距離+50%(速度そのままで持続時間を延ばす)
const LV4_EXPLOSION_RADIUS := 70.0          # Lv4: 着地地点に小爆発
const LV5_REDASH_DELAY := 0.12              # Lv5: 短間隔で2連続突進

func get_interval(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var interval := super.get_interval(character_data, weapon_manager)
	if ability_level >= 3:
		interval *= 0.75
	return interval

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	await _do_dash(attacker, character_data, weapon_manager)
	if ability_level >= 5 and is_instance_valid(attacker):
		await attacker.get_tree().create_timer(LV5_REDASH_DELAY, false).timeout
		if is_instance_valid(attacker):
			await _do_dash(attacker, character_data, weapon_manager)

func _do_dash(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	var target := weapon_manager.find_nearest_enemy(attacker.global_position)
	var direction: Vector2 = (target.global_position - attacker.global_position).normalized() if target else Vector2.RIGHT
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	var params := character_data.attack_pattern_params
	var dash_speed: float = params.get("dash_speed", DEFAULT_DASH_SPEED)
	var dash_duration: float = params.get("dash_duration", DEFAULT_DASH_DURATION)
	if ability_level >= 2:
		dash_duration *= LV2_DASH_DURATION_MULTIPLIER
	var hit_radius: float = params.get("hit_radius", DEFAULT_HIT_RADIUS)
	var knockback_distance: float = params.get("knockback_distance", DEFAULT_KNOCKBACK_DISTANCE)

	var original_speed: float = attacker.movement_component.base_speed
	attacker.set_movement_locked(true)
	attacker.movement_component.direction = direction
	attacker.movement_component.base_speed = dash_speed
	if character_data.dash_invincible:
		attacker.health_component.invincible = true

	var hit_entity_ids: Array = []
	var character_level := weapon_manager.get_owner_character_level()
	var start_time := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start_time) < dash_duration * 1000.0:
		if not is_instance_valid(attacker):
			return
		_hit_enemies_along_dash(attacker, direction, hit_radius, knockback_distance, character_data, weapon_manager, character_level, hit_entity_ids)
		# 円範囲の物理クエリ(query_enemy_hurtboxes)は、直前の物理ステップで
		# 敵の位置が同期されている必要があるため、process_frameではなく
		# physics_frameを待つ(process_frameは物理ステップの完了を保証しないため、
		# 通過した敵を取りこぼすことがある)。
		await attacker.get_tree().physics_frame

	if not is_instance_valid(attacker):
		return
	var landing_position := attacker.global_position
	attacker.movement_component.direction = Vector2.ZERO
	attacker.movement_component.base_speed = original_speed
	attacker.set_movement_locked(false)
	if character_data.dash_invincible:
		attacker.health_component.invincible = false
	if ability_level >= 4:
		apply_area_damage(attacker.get_world_2d(), landing_position, LV4_EXPLOSION_RADIUS, character_data, weapon_manager, landing_position)

## 攻撃者自身がダッシュで高速移動し続けている最中の判定のため、spawn_point_hit()の
## 「Area2Dを生成して次の物理ステップの検出を待つ」2段階判定だと、その1ステップの
## 間に対象(あるいはダッシュ中のプレイヤー自身)が動いてしまい取りこぼす恐れがある。
## そのためapply_direct_damage()でクエリ結果へその場で直接ダメージを適用する。
func _hit_enemies_along_dash(attacker: Player, direction: Vector2, hit_radius: float, knockback_distance: float, character_data: CharacterData, weapon_manager: WeaponManagerComponent, character_level: int, hit_entity_ids: Array) -> void:
	var hurtboxes := query_enemy_hurtboxes(attacker.get_world_2d(), attacker.global_position, hit_radius)
	for hurtbox in hurtboxes:
		var target_entity: Node2D = hurtbox.get_owner_entity()
		if target_entity == null or not is_instance_valid(target_entity):
			continue
		if hit_entity_ids.has(target_entity.get_instance_id()):
			continue
		hit_entity_ids.append(target_entity.get_instance_id())
		var roll := roll_damage(character_data, weapon_manager)
		apply_direct_damage(hurtbox, roll["damage"], roll["is_critical"], character_data, character_level, attacker.global_position)
		var knockback_direction := direction
		if target_entity.global_position != attacker.global_position:
			knockback_direction = (target_entity.global_position - attacker.global_position).normalized()
		target_entity.global_position += knockback_direction * knockback_distance
