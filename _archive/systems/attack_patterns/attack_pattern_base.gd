extends Resource
class_name AttackPatternBase
## 職業ごとの自動攻撃パターンのStrategyパターン基底クラス(疑似インターフェース)。
## systems/boss_ai/boss_attack_strategy.gdと同じ考え方: WeaponManagerComponentが
## intervalごとにexecute()を呼び出す。サブクラスでexecute()をオーバーライドする
## だけで新しい攻撃パターンを追加できる(開放閉鎖の原則)。
##
## ダメージ計算・射程計算・命中判定(点ヒット/円範囲クエリ)など、複数の
## パターンで共通する処理はここにヘルパーとしてまとめておく。

const MELEE_HIT_SCENE_PATH := "res://entities/melee_hit/melee_hit.tscn"

## この攻撃パターンが命中時に敵へ付与する状態異常。
## 各Strategyがoverrideして職業ごとの状態を返す(仕様書36.3参照)。
## ここはoverrideを持たないPatternのための既定値。
## TODO: 天賦図による付与状態の追加・変更は後日設計する。
func applied_status_id() -> String:
	return "burning"

## EnemyBasic.HurtboxComponentのcollision_layer(entities/enemies/enemy_basic.tscn参照)。
## 円範囲クエリで「敵の被弾判定だけ」を拾うためのマスク値として使う。
const ENEMY_HURTBOX_LAYER := 4

## 職業固有攻撃パターンの強化段階(2026年8月追加)。レベルアップの通常強化
## オプションプールに混ざる職業専用強化(class_ability_level_up、
## data/upgrades/参照)を選ぶたびにWeaponManagerComponent.increase_class_ability_level()
## が+1する。初期値1・最大5。各サブクラスはこの値を見てexecute()の挙動を
## 段階的に強化する。
const MAX_ABILITY_LEVEL := 5
var ability_level: int = 1

## 流派分岐(school、2026年8月追加、試験実装はSwordsman/MeleeArcAttackのみ)。
## "none"のまま(未選択)/ある職業固有の文字列(例: "rengeki"/"issen")のいずれか。
## school分岐に対応しないパターンでは常に"none"のまま無視される。分岐を持たない
## パターンでも共通のフィールドとして基底クラスに置くことで、WeaponManagerComponentが
## サブクラスの型を意識せず読み書きできるようにしている(ability_levelと同じ理由)。
var school: String = "none"

## 次の発動までの間隔(秒)。character_data.attack_intervalに、強化オプション
## (rapid_barrage等)由来の攻撃間隔短縮率を掛け合わせたものを返す。
func get_interval(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var multiplier := weapon_manager.get_melee_attack_interval_multiplier() if character_data.attack_pattern_id in WeaponManagerComponent.MELEE_PATTERN_IDS else weapon_manager.get_attack_interval_multiplier()
	return maxf(character_data.attack_interval * multiplier, 0.05)

## 実際の攻撃処理。attackerは攻撃元(Player)、weapon_managerは強化値・射程倍率参照用。
## PlayerとしてTypeすることで、movement_component/health_component等の
## Entity/Player固有メンバーへ安全にアクセスできる(BossAttackStrategy.execute()が
## bossをEnemyBasicとして受け取るのと同じ考え方)。
func execute(_attacker: Player, _character_data: CharacterData, _weapon_manager: WeaponManagerComponent) -> void:
	pass

func get_effective_range(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	return character_data.attack_range * weapon_manager.get_attack_range_multiplier()

## 近接通常攻撃の短い踏み込み。対象が攻撃レンジ内にいる場合だけ実行し、
## CharacterBody2D.move_and_collide()を使うため壁や障害物をすり抜けない。
## 長距離追尾にはせず、JSONのstep_distance（既定25px）を上限とする。
func try_melee_step(attacker: Player, target: Node2D, character_data: CharacterData, attack_range: float, default_step_distance: float = 25.0) -> bool:
	if attacker == null or target == null or not is_instance_valid(target):
		return false
	var offset: Vector2 = target.global_position - attacker.global_position
	var target_distance := offset.length()
	if target_distance > attack_range:
		return false
	if target_distance <= 1.0:
		return true
	var configured_step: float = float(character_data.attack_pattern_params.get("step_distance", default_step_distance))
	var stop_distance := minf(28.0, attack_range * 0.35)
	var step_distance := minf(configured_step, maxf(target_distance - stop_distance, 0.0))
	if step_distance > 0.0:
		attacker.move_and_collide(offset.normalized() * step_distance)
	return true

## 共通ダメージ計算(レベル成長・強化オプション・アイテム・職業パッシブを反映した
## 会心判定込みのダメージ)。Projectile.launch()と同じ計算式をクラス攻撃パターン側でも
## 再現する(Projectileを経由しない近接/AoE系はこちらを使う)。
## bonus_crit_chanceは職業専用強化(例: 一閃派Lv4クリティカル率+25%)向けの追加加算、
## force_criticalがtrueの場合は乱数判定をせず必ず会心にする(例: 乱撃派Lv5の
## 最後の一撃)。
## 戻り値: {"damage": float, "is_critical": bool}
func roll_damage(character_data: CharacterData, weapon_manager: WeaponManagerComponent, bonus_crit_chance: float = 0.0, force_critical: bool = false) -> Dictionary:
	var upgrades := weapon_manager.get_owner_upgrades()
	var stat_modifier := weapon_manager.get_owner_stat_modifier()
	var crit_chance := character_data.crit_chance + bonus_crit_chance
	var damage_multiplier := 1.0
	var flat_damage := character_data.base_damage
	if stat_modifier:
		crit_chance += stat_modifier.get_crit_chance_bonus()
		flat_damage += stat_modifier.get_damage_flat_bonus()
	if upgrades:
		crit_chance += upgrades.crit_rate_bonus + upgrades.equipment_crit_rate_bonus
		flat_damage += upgrades.equipment_attack_flat
		damage_multiplier *= upgrades.damage_multiplier * upgrades.get_equipment_conditional_damage_multiplier()
		if character_data.attack_pattern_id in WeaponManagerComponent.MELEE_PATTERN_IDS:
			damage_multiplier *= upgrades.melee_damage_multiplier
	var is_critical := true if force_critical else (randf() < crit_chance)
	var crit_multiplier := character_data.crit_multiplier + (upgrades.equipment_crit_damage_bonus if upgrades else 0.0)
	var damage: float = flat_damage * damage_multiplier * (crit_multiplier if is_critical else 1.0)
	return {"damage": damage, "is_critical": is_critical}

## 円範囲(centerからradius以内)にいる敵のHurtboxComponentを、物理クエリで直接取得する。
## Area2Dのarea_enteredシグナルを待たず、その場で判定したい(扇状の角度フィルタ等を
## 攻撃側のロジックで行いたい)ケース向け。
func query_enemy_hurtboxes(world: World2D, center: Vector2, radius: float) -> Array:
	if world == null:
		return []
	var space_state := world.direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = ENEMY_HURTBOX_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var results := space_state.intersect_shape(query, 64)
	var hurtboxes: Array = []
	for r in results:
		hurtboxes.append(r["collider"])
	return hurtboxes

## targetからの方向がfacing_directionを中心にhalf_angle_degrees以内かどうか。
func is_within_arc(from: Vector2, target: Vector2, facing_direction: Vector2, half_angle_degrees: float) -> bool:
	if facing_direction == Vector2.ZERO:
		return true
	var to_target := (target - from)
	if to_target == Vector2.ZERO:
		return true
	var angle := rad_to_deg(absf(facing_direction.normalized().angle_to(to_target.normalized())))
	return angle <= half_angle_degrees

## 指定位置にちょうどその敵だけを狙う点ヒット(MeleeHit)を1つ生成し、既存の
## Hitbox/Hurtbox被弾パイプライン(会心判定込みダメージ・VFX・hit_impact SE・
## damage_dealt通知)をそのまま利用してダメージを与える。
## 【注意】これはHitbox側がArea2Dとして次の物理ステップで敵のHurtboxComponentに
## 検出されるのを待つ2段階の判定のため、攻撃側(プレイヤー)自身が同時に高速で
## 移動し続けている場合(charge_dash等)は、命中対象がその1ステップの間に
## 移動してしまい取りこぼす可能性がある。攻撃者が静止した状態で発動する
## melee_arc/self_pulse/piercing_thrust等はこちらを使う。
func spawn_point_hit(scene_tree: SceneTree, position: Vector2, damage: float, is_critical: bool, character_data: CharacterData, character_level: int, origin_position: Vector2) -> void:
	var hit_scene: PackedScene = load(MELEE_HIT_SCENE_PATH)
	var hit := hit_scene.instantiate()
	hit.damage = damage
	hit.is_critical = is_critical
	hit.applied_status_id = applied_status_id()
	hit.setup(character_data.vfx_theme_id, character_level, origin_position)
	scene_tree.current_scene.add_child(hit)
	hit.global_position = position

## damage_multiplierは職業専用強化(例: Armored AxemanのLv3ダメージ+25%)向けの
## 追加倍率(既定1.0=補正なし)。bonus_crit_chance/force_criticalはroll_damage()に
## そのまま渡す(職業専用強化のクリティカル率上昇・確定クリティカル用)。戻り値の
## MeleeHitは、命中時コールバック(職業専用強化のスタン付与・弱体付与等)を
## 呼び出し側がlanded signalへ接続できるよう返す。
func spawn_arc_hit(attacker: Player, radius: float, facing: Vector2, half_angle_degrees: float, active_seconds: float, knockback_distance: float, character_data: CharacterData, weapon_manager: WeaponManagerComponent, damage_multiplier: float = 1.0, bonus_crit_chance: float = 0.0, force_critical: bool = false) -> MeleeHit:
	var hit_scene: PackedScene = load(MELEE_HIT_SCENE_PATH)
	var hit := hit_scene.instantiate() as MeleeHit
	var roll := roll_damage(character_data, weapon_manager, bonus_crit_chance, force_critical)
	hit.damage = roll["damage"] * damage_multiplier
	hit.is_critical = roll["is_critical"]
	hit.applied_status_id = applied_status_id()
	hit.setup(character_data.vfx_theme_id, weapon_manager.get_owner_character_level(), attacker.global_position)
	GameManager.get_runtime_world(attacker).add_child(hit)
	hit.global_position = attacker.global_position
	var upgrades := weapon_manager.get_owner_upgrades()
	var lifesteal := character_data.melee_lifesteal_percent + (upgrades.melee_lifesteal_percent if upgrades else 0.0)
	var heal_cap := maxf(character_data.melee_lifesteal_cap_per_hit, upgrades.melee_lifesteal_cap_per_hit if upgrades else 0.0)
	hit.configure_arc(radius, facing, half_angle_degrees, active_seconds, knockback_distance, lifesteal, heal_cap, attacker.health_component)
	return hit

func spawn_line_hit(attacker: Player, length: float, half_width: float, facing: Vector2, active_seconds: float, knockback_distance: float, character_data: CharacterData, weapon_manager: WeaponManagerComponent, damage_multiplier: float = 1.0) -> MeleeHit:
	var hit_scene: PackedScene = load(MELEE_HIT_SCENE_PATH)
	var hit := hit_scene.instantiate() as MeleeHit
	var roll := roll_damage(character_data, weapon_manager)
	hit.damage = roll["damage"] * damage_multiplier
	hit.is_critical = roll["is_critical"]
	hit.applied_status_id = applied_status_id()
	hit.setup(character_data.vfx_theme_id, weapon_manager.get_owner_character_level(), attacker.global_position)
	GameManager.get_runtime_world(attacker).add_child(hit)
	hit.global_position = attacker.global_position
	var upgrades := weapon_manager.get_owner_upgrades()
	var lifesteal := character_data.melee_lifesteal_percent + (upgrades.melee_lifesteal_percent if upgrades else 0.0)
	var heal_cap := maxf(character_data.melee_lifesteal_cap_per_hit, upgrades.melee_lifesteal_cap_per_hit if upgrades else 0.0)
	hit.configure_line(length, half_width, facing, active_seconds, knockback_distance, lifesteal, heal_cap, attacker.health_component)
	return hit

## query_enemy_hurtboxes()で見つけたHurtboxComponent群へ、まとめてダメージを
## 適用する簡易AoEヘルパー(charge_dashの着地爆発、summon_minionの味方死亡爆発等、
## 「一点を中心に周囲へ即時ダメージ」を職業専用強化から手軽に呼べるようにするため)。
func apply_area_damage(world: World2D, center: Vector2, radius: float, character_data: CharacterData, weapon_manager: WeaponManagerComponent, origin_position: Vector2) -> void:
	var character_level := weapon_manager.get_owner_character_level()
	for hurtbox in query_enemy_hurtboxes(world, center, radius):
		var roll := roll_damage(character_data, weapon_manager)
		apply_direct_damage(hurtbox, roll["damage"], roll["is_critical"], character_data, character_level, origin_position)

## query_enemy_hurtboxes()で見つけたHurtboxComponentへ、Area2D同士の物理検出を
## 経由せずその場で直接ダメージを適用する(会心判定込みダメージ・VFX・hit_impact SE・
## damage_dealt通知は既存パイプラインと同じものを再現する)。攻撃者自身が高速で
## 移動し続けるcharge_dash等、spawn_point_hit()の2段階判定だと対象の移動により
## 取りこぼしうるケース向け。
func apply_direct_damage(hurtbox: HurtboxComponent, damage: float, is_critical: bool, character_data: CharacterData, character_level: int, origin_position: Vector2) -> void:
	var target_entity: Node = hurtbox.get_owner_entity()
	if target_entity == null or not is_instance_valid(target_entity):
		return
	var health: HealthComponent = target_entity.get_node_or_null("HealthComponent")
	if health == null:
		return
	var metadata := CombatEventMeta.create_direct("player_direct_attack", is_critical)
	var actual_damage := health.apply_damage(damage, metadata)
	if actual_damage <= 0.0:
		return
	EventBus.damage_dealt.emit(actual_damage, target_entity.global_position, is_critical)
	if target_entity.is_in_group("enemies"):
		EventBus.enemy_physical_damage_dealt.emit(actual_damage, target_entity.global_position, is_critical)
	var status_system := hurtbox.get_tree().get_first_node_in_group("status_apply_system") as StatusApplySystem
	if status_system and target_entity.is_in_group("enemies"):
		status_system.apply_state(target_entity, applied_status_id(), actual_damage)
	if target_entity.is_in_group("enemies"):
		AudioManager.play_sfx("combat_hit")
	var manager: Node = hurtbox.get_tree().get_first_node_in_group("effect_theme_manager")
	if manager:
		manager.play_weapon_hit(character_data.vfx_theme_id, target_entity.global_position, character_level, hurtbox, origin_position, is_critical, character_data.vfx_theme_id == "lightning")
