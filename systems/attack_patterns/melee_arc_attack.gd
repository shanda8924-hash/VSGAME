extends AttackPatternBase
class_name MeleeArcAttack
## Soldier / Swordsman / Armored Axeman用の前方扇形通常攻撃。
## WeaponManagerがモーション開始と踏み込みを担当し、命中フレームでexecute()を呼ぶ。
##
## 職業専用強化(ability_level、2026年8月追加): Soldier/Swordsman/Armored Axemanは
## 3職業ともこのクラスを共有しているため、character_data.idで分岐して職業ごとに
## 異なるLv2〜5の効果を適用する(data/upgrades/の職業専用強化・game_specification.md
## 19.8参照)。
##   Soldier: Lv2 2連続ヒット / Lv3 攻撃間隔-15% / Lv4 間合い+15%(貫通1段分の踏み込み)/
##            Lv5 20%で3連続ヒット
##   Armored Axeman: Lv2 なぎ払い角度+20度 / Lv3 ダメージ+25% / Lv4 クールダウン-20% /
##                   Lv5 返し斬り追加(逆方向にもう一振り)
##
## Swordsmanは19.9(2026年8月、試験実装)で「流派分岐」システムに切り替わった。
## school(基底クラス、"none"/"rengeki"/"issen")がLv1→2の強化選択時に確定し、
## 以降Lv3〜5は選んだ流派の強化だけが出現する(もう一方は二度と出現しない)。
##   乱撃派(rengeki): Lv2連続斬り数2 / Lv3で3 / Lv4攻撃間隔-20% /
##                     Lv5で4連続+最後の一撃は確定クリティカル
##   一閃派(issen): Lv2単発ダメージ+40% / Lv3間合い+30% / Lv4クリティカル率+25% /
##                  Lv5でHP30%以下の敵に約5倍ダメージ(完全な即死ではない)

const DEFAULT_ARC_HALF_ANGLE_DEGREES := 55.0
const HOMING_TO_RANGE_BONUS_FACTOR := 0.5
## Swordsman「一閃派」Lv5: 対象のHP割合がこの値以下なら大ダメージを追加で与える。
const ISSEN_EXECUTE_HP_THRESHOLD := 0.3
## 通常の1撃(roll_damage())に加えて、これだけ追加で乗せる(合計で概ね5倍相当になる)。
const ISSEN_EXECUTE_BONUS_MULTIPLIER := 4.0
const ISSEN_LV4_BONUS_CRIT_CHANCE := 0.25

func get_interval(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var interval := super.get_interval(character_data, weapon_manager)
	match character_data.id:
		"soldier":
			if ability_level >= 3:
				interval *= 0.85
		"armored_axeman":
			if ability_level >= 4:
				interval *= 0.8
		"swordsman":
			if school == "rengeki" and ability_level >= 4:
				interval *= 0.8
	return interval

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	if character_data.id == "swordsman":
		_execute_swordsman(attacker, character_data, weapon_manager)
		return

	_swing(attacker, character_data, weapon_manager)
	var extra_swings := _bonus_swing_count(character_data)
	for i in extra_swings:
		_swing(attacker, character_data, weapon_manager)
	if character_data.id == "armored_axeman" and ability_level >= 5:
		# 返し斬り: 逆方向へもう一振り(なぎ払いの折り返し)。
		_swing(attacker, character_data, weapon_manager, -attacker.get_facing_direction())
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades and randf() < upgrades.multishot_chance:
		_swing(attacker, character_data, weapon_manager)

## 乱撃派: 連続斬り数がLv2で2、Lv3で3、Lv5で4に増える。最後の一撃はLv5で確定クリティカル。
## 一閃派: 単発(常に1回)だが、_swing()側でダメージ/クリティカル率/間合いが伸びる。
## Lv5到達時はHP30%以下の敵へ追加の大ダメージ判定を行う。
func _execute_swordsman(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	var swing_count := 1
	if school == "rengeki":
		if ability_level >= 5:
			swing_count = 4
		elif ability_level >= 3:
			swing_count = 3
		elif ability_level >= 2:
			swing_count = 2
	var force_crit_last_swing := school == "rengeki" and ability_level >= 5
	for i in swing_count:
		var is_last_swing := i == swing_count - 1
		_swing(attacker, character_data, weapon_manager, Vector2.ZERO, force_crit_last_swing and is_last_swing)

	if school == "issen" and ability_level >= 5:
		_apply_issen_execute_bonus(attacker, character_data, weapon_manager)

	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades and randf() < upgrades.multishot_chance:
		_swing(attacker, character_data, weapon_manager)

## Lv2以上で確定の追加スイング数(2連続化)+SoldierのLv5だけ20%で更にもう1回。
## (Swordsmanは_execute_swordsman()側で独自に連続斬り数を管理するためここは通らない)
func _bonus_swing_count(character_data: CharacterData) -> int:
	if ability_level < 2:
		return 0
	var count := 1
	if character_data.id == "soldier" and ability_level >= 5 and randf() < 0.2:
		count += 1
	return count

func _swing(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent, facing_override: Vector2 = Vector2.ZERO, force_critical: bool = false) -> MeleeHit:
	var radius := _get_effective_radius(character_data, weapon_manager)
	var half_angle: float = character_data.attack_pattern_params.get("arc_half_angle_degrees", DEFAULT_ARC_HALF_ANGLE_DEGREES)
	if character_data.id == "armored_axeman" and ability_level >= 2:
		half_angle += 20.0
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades:
		half_angle *= 1.0 + upgrades.melee_range_bonus
	var active_seconds: float = character_data.attack_pattern_params.get("hitbox_active_seconds", 0.08)
	var knockback: float = character_data.attack_pattern_params.get("knockback_distance", 8.0)
	var facing := facing_override if facing_override != Vector2.ZERO else attacker.get_facing_direction()
	var damage_multiplier := 1.0
	var bonus_crit_chance := 0.0
	if character_data.id == "armored_axeman" and ability_level >= 3:
		damage_multiplier *= 1.25
	if character_data.id == "swordsman" and school == "issen":
		if ability_level >= 2:
			damage_multiplier *= 1.4
		if ability_level >= 4:
			bonus_crit_chance = ISSEN_LV4_BONUS_CRIT_CHANCE
	return spawn_arc_hit(attacker, radius, facing, half_angle, active_seconds, knockback, character_data, weapon_manager, damage_multiplier, bonus_crit_chance, force_critical)

## 一閃派Lv5: 通常のなぎ払い範囲内にいる、HP30%以下の敵へ追加の大ダメージを与える
## (通常の1撃と合わせて概ね5倍相当。完全な即死にはせず「大ダメージ」として実装)。
func _apply_issen_execute_bonus(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	var radius := _get_effective_radius(character_data, weapon_manager)
	var half_angle: float = character_data.attack_pattern_params.get("arc_half_angle_degrees", DEFAULT_ARC_HALF_ANGLE_DEGREES)
	var facing := attacker.get_facing_direction()
	var character_level := weapon_manager.get_owner_character_level()
	for hurtbox in query_enemy_hurtboxes(attacker.get_world_2d(), attacker.global_position, radius):
		var entity: Node2D = hurtbox.get_owner_entity() as Node2D
		if entity == null or not is_instance_valid(entity):
			continue
		if not is_within_arc(attacker.global_position, entity.global_position, facing, half_angle):
			continue
		var health: HealthComponent = entity.get_node_or_null("HealthComponent")
		if health == null or health.max_hp <= 0.0:
			continue
		if health.current_hp / health.max_hp > ISSEN_EXECUTE_HP_THRESHOLD:
			continue
		var roll := roll_damage(character_data, weapon_manager)
		apply_direct_damage(hurtbox, roll["damage"] * ISSEN_EXECUTE_BONUS_MULTIPLIER, roll["is_critical"], character_data, character_level, attacker.global_position)

func _get_effective_radius(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var radius := character_data.attack_range * weapon_manager.get_melee_range_multiplier()
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades:
		radius *= 1.0 + upgrades.homing_strength * HOMING_TO_RANGE_BONUS_FACTOR
	match character_data.id:
		"soldier":
			if ability_level >= 4:
				radius *= 1.15
		"swordsman":
			if school == "issen" and ability_level >= 3:
				radius *= 1.3
	return radius
