extends AttackPatternBase
class_name SpreadShotAttack
## Archer(spread_shot): 最も近い敵を中心に、同時にprojectile_count方向(既定3)へ
## 矢を発射する。既存のWeaponManagerComponent.spawn_projectile()をそのまま使うため、
## multishot_chance_up(追加の1本)・crit・homing_upgrade等は一切読み替えずそのまま
## 意味を持つ(通常のProjectile発射経路をなぞっているだけのため)。
##
## 職業専用強化(ability_level、2026年8月追加、Archer固有)。
## Lv2 同時発射+1本 / Lv3 拡散を絞り集中射撃(命中率向上)/ Lv4 クールダウン-15% /
## Lv5 15%の確率で全方位(8方向)発射に切り替わる。

const DEFAULT_PROJECTILE_COUNT := 3
const DEFAULT_SPREAD_ANGLE_DEGREES := 24.0
const PROJECTILE_SCENE_PATH := "res://entities/projectiles/projectile.tscn"
const LV5_OMNI_CHANCE := 0.15
const LV5_OMNI_COUNT := 8

func get_interval(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var interval := super.get_interval(character_data, weapon_manager)
	if ability_level >= 4:
		interval *= 0.85
	return interval

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	var target := weapon_manager.find_nearest_enemy(attacker.global_position)
	var base_direction: Vector2 = (target.global_position - attacker.global_position).normalized() if target else Vector2.RIGHT

	var weapon_data := _build_weapon_data(character_data)

	if ability_level >= 5 and randf() < LV5_OMNI_CHANCE:
		for i in LV5_OMNI_COUNT:
			var direction := Vector2.RIGHT.rotated(TAU * float(i) / float(LV5_OMNI_COUNT))
			weapon_manager.spawn_projectile(weapon_data, attacker.global_position, attacker.global_position + direction * 100.0)
		return

	var count: int = character_data.attack_pattern_params.get("projectile_count", DEFAULT_PROJECTILE_COUNT)
	if ability_level >= 2:
		count += 1
	var spread_degrees: float = character_data.attack_pattern_params.get("spread_angle_degrees", DEFAULT_SPREAD_ANGLE_DEGREES)
	if ability_level >= 3:
		spread_degrees *= 0.6

	var mid := float(count - 1) / 2.0
	for i in count:
		var offset_degrees := (float(i) - mid) * spread_degrees
		var direction := base_direction.rotated(deg_to_rad(offset_degrees))
		weapon_manager.spawn_projectile(weapon_data, attacker.global_position, attacker.global_position + direction * 100.0)

func _build_weapon_data(character_data: CharacterData) -> WeaponData:
	var data := WeaponData.new()
	data.base_damage = character_data.base_damage
	data.attack_range = character_data.attack_range
	data.crit_chance = character_data.crit_chance
	data.crit_multiplier = character_data.crit_multiplier
	# 職業通常攻撃は現在ElementではなくArcher本来のThemeを維持する。
	data.vfx_theme_id = character_data.vfx_theme_id
	data.projectile_scene = load(PROJECTILE_SCENE_PATH)
	return data
