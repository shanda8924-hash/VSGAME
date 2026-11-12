extends SelfPulseAttack
class_name HolyPulseHealAttack
## Priest(holy_pulse_heal): SelfPulseAttackと同じ周囲AoEに加え、発動のたびに
## 自分のHPを少量回復する(attack_pattern_paramsのheal_percentはmax_hpに対する割合)。
##
## 職業専用強化(ability_level、2026年8月追加、Priest固有)。
## Lv2 回復量+30% / Lv3 発動間隔-20%(親クラスSelfPulseAttack.get_interval()が処理)/
## Lv4 ダメージ範囲+25%(親クラスSelfPulseAttack._get_effective_radius()が処理)/
## Lv5 被弾させた敵に被ダメージ+10%の弱体(vulnerable)を一定時間付与する。

const DEFAULT_HEAL_PERCENT := 0.08
const LV2_HEAL_MULTIPLIER := 1.3
const LV5_VULNERABLE_MULTIPLIER := 1.1
const LV5_VULNERABLE_DURATION := 4.0

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	var hit := _pulse(attacker, character_data, weapon_manager)
	if ability_level >= 5 and hit:
		hit.landed.connect(_on_vulnerable_hit)
	var upgrades := weapon_manager.get_owner_upgrades()
	if upgrades and randf() < upgrades.multishot_chance:
		_pulse(attacker, character_data, weapon_manager)
	var health: HealthComponent = attacker.get_node_or_null("HealthComponent")
	if health == null:
		return
	var heal_percent: float = character_data.attack_pattern_params.get("heal_percent", DEFAULT_HEAL_PERCENT)
	if ability_level >= 2:
		heal_percent *= LV2_HEAL_MULTIPLIER
	health.heal(health.max_hp * heal_percent)

## 被ダメージ倍率を一時的に引き上げる(既存のHealthComponent.damage_taken_multiplierを
## 直接操作する。敵側はこの値を誰も同期していないため安全に流用できる、
## components/health_component.gd参照)。倍率で加算するため、期間が重なっても
## 掛けた分だけ確実に戻せる。
func _on_vulnerable_hit(hurtbox: HurtboxComponent) -> void:
	var entity: Node = hurtbox.get_owner_entity()
	if entity == null or not is_instance_valid(entity):
		return
	var health: HealthComponent = entity.get_node_or_null("HealthComponent")
	if health == null:
		return
	health.damage_taken_multiplier *= LV5_VULNERABLE_MULTIPLIER
	await entity.get_tree().create_timer(LV5_VULNERABLE_DURATION, false).timeout
	if is_instance_valid(health):
		health.damage_taken_multiplier /= LV5_VULNERABLE_MULTIPLIER

## この攻撃パターンが命中時に付与する状態異常。祈祷が対象へ刻印を刻む。
func applied_status_id() -> String:
	return "marked"
