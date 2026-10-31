extends AttackPatternBase
class_name PiercingThrustAttack
## Lancer用。長く細い前方HitBoxを命中フレームに生成する。
##
## 職業専用強化(ability_level、2026年8月追加、Lancer固有)。MeleeHitの直線判定は
## 元々「線上の敵を全員貫通」する実装のため、Lv2「貫通数+1」は追加の踏み込み
## (刺突の間合いの伸び)として表現する(Lv3の射程+30%とは別に、さらに一段
## 伸ばす形)。Lv2 貫通数+1(間合い+15%)/ Lv3 射程+30% / Lv4 クールダウン-20% /
## Lv5 3方向同時の突き。

const DEFAULT_THRUST_WIDTH := 18.0
const HOMING_TO_RANGE_BONUS_FACTOR := 0.5
const LV5_SPREAD_DEGREES := 18.0

func get_interval(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var interval := super.get_interval(character_data, weapon_manager)
	if ability_level >= 4:
		interval *= 0.8
	return interval

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	var facing := attacker.get_facing_direction()
	if ability_level >= 5:
		_thrust(attacker, character_data, weapon_manager, facing)
		_thrust(attacker, character_data, weapon_manager, facing.rotated(deg_to_rad(LV5_SPREAD_DEGREES)))
		_thrust(attacker, character_data, weapon_manager, facing.rotated(deg_to_rad(-LV5_SPREAD_DEGREES)))
	else:
		_thrust(attacker, character_data, weapon_manager, facing)
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades and randf() < upgrades.multishot_chance:
		_thrust(attacker, character_data, weapon_manager, facing)

func _thrust(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent, facing: Vector2) -> void:
	var thrust_range := _get_effective_range(character_data, weapon_manager)
	var width: float = character_data.attack_pattern_params.get("thrust_width", DEFAULT_THRUST_WIDTH)
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades:
		width *= 1.0 + upgrades.melee_range_bonus
	var active_seconds: float = character_data.attack_pattern_params.get("hitbox_active_seconds", 0.08)
	var knockback: float = character_data.attack_pattern_params.get("knockback_distance", 6.0)
	spawn_line_hit(attacker, thrust_range, width, facing, active_seconds, knockback, character_data, weapon_manager)

func _get_effective_range(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var thrust_range := character_data.attack_range * weapon_manager.get_melee_range_multiplier()
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades:
		thrust_range *= 1.0 + upgrades.homing_strength * HOMING_TO_RANGE_BONUS_FACTOR
	if ability_level >= 2:
		thrust_range *= 1.15
	if ability_level >= 3:
		thrust_range *= 1.3
	return thrust_range

## この攻撃パターンが命中時に付与する状態異常。貫通の一撃で動きを止める。
func applied_status_id() -> String:
	return "frozen"
