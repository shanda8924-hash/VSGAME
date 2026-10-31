extends AttackPatternBase
class_name SelfPulseAttack
## Knight Templar用。短時間だけ有効な全周HitBoxを命中フレームに生成する。
## HolyPulseHealAttack(Priest)がこのクラスを継承して回復を追加する。
##
## 職業専用強化(ability_level、2026年8月追加)。発動間隔短縮(Lv3、-20%)は
## Knight Templar/Priestで共通の効果のためここに実装する。範囲拡大の倍率は
## 職業ごとに段階が異なる(Knight TemplarはLv2+30%、PriestはLv4+25%、
## HolyPulseHealAttackの_get_effective_radius継承先で分岐)ため、character_data.idで
## 分岐する。二重波動(Lv5)はKnight Templar固有(character_data.id判定で
## PriestのLv5「弱体付与」が誤って重複しないようにする)。

const DEFAULT_RADIUS := 70.0
const HOMING_TO_RADIUS_BONUS_FACTOR := 0.5
const LV4_KNOCKBACK_BONUS := 50.0

func get_interval(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var interval := super.get_interval(character_data, weapon_manager)
	if ability_level >= 3:
		interval *= 0.8
	return interval

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	_pulse(attacker, character_data, weapon_manager)
	if character_data.id == "knight_templar" and ability_level >= 5:
		# 二重波動: 確定でもう1回発生させる。
		_pulse(attacker, character_data, weapon_manager)
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades and randf() < upgrades.multishot_chance:
		_pulse(attacker, character_data, weapon_manager)

func _pulse(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> MeleeHit:
	var radius := _get_effective_radius(character_data, weapon_manager)
	var active_seconds: float = character_data.attack_pattern_params.get("hitbox_active_seconds", 0.09)
	var knockback: float = character_data.attack_pattern_params.get("knockback_distance", 7.0)
	if character_data.id == "knight_templar" and ability_level >= 4:
		knockback += LV4_KNOCKBACK_BONUS
	return spawn_arc_hit(attacker, radius, attacker.get_facing_direction(), 180.0, active_seconds, knockback, character_data, weapon_manager)

func _get_effective_radius(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var radius: float = character_data.attack_pattern_params.get("radius", DEFAULT_RADIUS)
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades:
		radius *= weapon_manager.get_melee_range_multiplier()
		radius *= 1.0 + upgrades.homing_strength * HOMING_TO_RADIUS_BONUS_FACTOR
	else:
		radius *= weapon_manager.get_melee_range_multiplier()
	if character_data.id == "knight_templar" and ability_level >= 2:
		radius *= 1.3
	elif character_data.id == "priest" and ability_level >= 4:
		radius *= 1.25
	return radius

## この攻撃パターンが命中時に付与する状態異常。聖なる波動が対象へ刻印を刻む。
func applied_status_id() -> String:
	return "marked"
