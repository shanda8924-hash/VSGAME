extends AttackPatternBase
class_name HomingBoltAttack
## Wizard(homing_bolt): 射程長めの魔法弾を1発発射する。強化オプション
## homing_upgrade未取得でも、attack_pattern_paramsのhoming_strengthぶんは
## 必ず緩やかに敵を追尾する(取得済みの強化値の方が高ければそちらを優先、
## Projectile.set_minimum_homing()参照)。
##
## 職業専用強化(ability_level、2026年8月追加、Wizard固有)。
## Lv2 誘導性能+30% / Lv3 弾速+20% / Lv4 着弾時に小爆発(周囲へ追加ダメージ)/
## Lv5 2発同時発射、それぞれ別の敵を追尾する。

const DEFAULT_HOMING_STRENGTH := 0.5
const PROJECTILE_SCENE_PATH := "res://entities/projectiles/projectile.tscn"
const LV2_HOMING_BONUS := 0.3
const LV3_SPEED_MULTIPLIER := 1.2
const LV4_EXPLOSION_RADIUS := 60.0
const LV4_EXPLOSION_DAMAGE_MULTIPLIER := 0.5

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	var target := weapon_manager.find_nearest_enemy(attacker.global_position)
	if target == null:
		return
	_fire_bolt(attacker, target.global_position, character_data, weapon_manager)
	for index in weapon_manager.get_survival_extra_projectiles():
		var offset := (target.global_position - attacker.global_position).rotated(deg_to_rad(16.0 if index % 2 == 0 else -16.0))
		_fire_bolt(attacker, attacker.global_position + offset, character_data, weapon_manager)
	if ability_level >= 5:
		var second_target := _find_second_nearest_enemy(attacker, target)
		var second_target_position: Vector2 = second_target.global_position if second_target else target.global_position
		_fire_bolt(attacker, second_target_position, character_data, weapon_manager)
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades and randf() < upgrades.multishot_chance:
		_fire_bolt(attacker, target.global_position, character_data, weapon_manager)
	if weapon_manager.sector_follow_up_level > 0 and randf() < 0.23 * weapon_manager.sector_follow_up_level:
		_sector_follow_up(attacker, character_data, weapon_manager)
	AudioManager.play_sfx("wizard_cast")
	weapon_manager.weapon_fired.emit()

func _find_second_nearest_enemy(attacker: Player, exclude: Node2D) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in attacker.get_tree().get_nodes_in_group("enemies"):
		if e == exclude:
			continue
		var health: HealthComponent = e.get_node_or_null("HealthComponent")
		if health == null or health.current_hp <= 0.0:
			continue
		var dist := attacker.global_position.distance_to(e.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e
	return nearest

func _fire_bolt(attacker: Player, target_position: Vector2, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	var weapon_data := _build_weapon_data(character_data)
	var upgrades := weapon_manager.get_owner_upgrades()
	var stat_modifier := weapon_manager.get_owner_stat_modifier()
	var character_level := weapon_manager.get_owner_character_level()

	var bolt_scene: PackedScene = load(PROJECTILE_SCENE_PATH)
	var bolt := bolt_scene.instantiate()
	bolt.use_wizard_magic()
	if ability_level >= 3:
		bolt.speed *= LV3_SPEED_MULTIPLIER
	if ability_level >= 4:
		bolt.landed.connect(_on_bolt_landed.bind(character_data, weapon_manager))
	bolt.applied_status_id = applied_status_id()
	bolt.pierce_remaining = weapon_manager.sector_pierce_level + 1
	bolt.chain_remaining = weapon_manager.sector_chain_level
	GameManager.get_runtime_world(attacker).add_child(bolt)
	bolt.global_position = attacker.global_position
	bolt.launch(target_position, weapon_data, character_level, stat_modifier, upgrades)

	var baseline_homing: float = character_data.attack_pattern_params.get("homing_strength", DEFAULT_HOMING_STRENGTH)
	if ability_level >= 2:
		baseline_homing += LV2_HOMING_BONUS
	bolt.set_minimum_homing(baseline_homing)

func _sector_follow_up(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	await attacker.get_tree().create_timer(0.18, false).timeout
	if not is_instance_valid(attacker) or attacker._is_dead:
		return
	var target := weapon_manager.find_nearest_enemy(attacker.global_position, character_data.attack_range, true)
	if target:
		_fire_bolt(attacker, target.global_position, character_data, weapon_manager)

## Lv4: 着弾時、着弾位置の周囲へ追加ダメージ(本体ダメージの50%相当)を与える
## 小爆発。命中したhurtbox自身は既存のHitboxComponentパイプラインで既にダメージ
## 済みのため、ここでは周囲の巻き込みぶんだけを追加で適用する。
func _on_bolt_landed(hurtbox: HurtboxComponent, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	var entity: Node2D = hurtbox.get_owner_entity() as Node2D
	if entity == null or not is_instance_valid(entity):
		return
	var character_level := weapon_manager.get_owner_character_level()
	for other_hurtbox in query_enemy_hurtboxes(entity.get_world_2d(), entity.global_position, LV4_EXPLOSION_RADIUS):
		if other_hurtbox == hurtbox:
			continue
		var roll := roll_damage(character_data, weapon_manager)
		apply_direct_damage(other_hurtbox, roll["damage"] * LV4_EXPLOSION_DAMAGE_MULTIPLIER, roll["is_critical"], character_data, character_level, entity.global_position)

func _build_weapon_data(character_data: CharacterData) -> WeaponData:
	var data := WeaponData.new()
	data.base_damage = character_data.base_damage
	data.attack_range = character_data.attack_range
	data.crit_chance = character_data.crit_chance
	data.crit_multiplier = character_data.crit_multiplier
	# 職業通常攻撃は現在ElementではなくWizard本来のThemeを維持する。
	data.vfx_theme_id = character_data.vfx_theme_id
	data.projectile_scene = load(PROJECTILE_SCENE_PATH)
	return data

## この攻撃パターンが命中時に付与する状態異常。追尾魔法弾の帯電。
func applied_status_id() -> String:
	return "charged"
