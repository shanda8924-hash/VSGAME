extends Node
class_name PlayerUpgradesComponent
## レベルアップの「通常強化オプション」(data/upgrades/*.json)と、ボス撃破で得られる
## 「アイテム」(data/items/*.json)の両方の蓄積値をまとめて保持するコンポーネント。
## WeaponManagerComponent/Projectileが読み取って反映する値(damage_multiplier等)と、
## MovementComponent/HealthComponentへ都度同期する値(bonus_speed_multiplier等)の
## 2通りの適用方法が混在する(詳細は各applyメソッドのコメント参照)。
##
## 強化オプション(data/upgrades/)はBrotato的なトレードオフ(downside_type/
## downside_value)を持つ場合があり、内部的には「同じeffect_typeの語彙を
## マイナス方向に適用するだけ」で表現している(_apply_effect参照)。そのため
## アイテム(常にプラスのみ)と強化オプション(プラス+任意のマイナス)は同じ
## _apply_effect()ディスパッチャを共有できる。

const MULTISHOT_CHANCE_CAP := 0.5
const HOMING_STRENGTH_CAP := 1.0
const ATTACK_INTERVAL_BONUS_CAP := 0.8      # 攻撃間隔短縮の上限(0秒に近づきすぎないように)
const ATTACK_INTERVAL_PENALTY_FLOOR := -0.5 # トレードオフで遅くなる場合の下限(最大+50%長くなる程度に留める)
const DAMAGE_TAKEN_REDUCTION_CAP := 0.8     # 被ダメージ軽減の上限(実質無敵化を防ぐ)
const DAMAGE_TAKEN_PENALTY_FLOOR := -0.5    # トレードオフで被ダメージが増える場合の下限(最大+50%までに留める)
const MOVE_SPEED_PENALTY_FLOOR := -0.5      # 移動速度が下がりすぎて実質動けなくなるのを防ぐ
const ATTACK_RANGE_PENALTY_FLOOR := -0.6    # 射程が縮みすぎて武器が実質機能しなくなるのを防ぐ
const DAMAGE_MULTIPLIER_FLOOR := 0.3        # 攻撃力が0近くまで下がるのを防ぐ
const NON_NEGATIVE_FLOOR := 0.0             # 会心率/誘導性能等、マイナスに意味が無い値の下限
## 状態異常を参照する条件付き強化。効果はresolve_state_condition_damage()と
## 撃破時フックで実装されており、属性システム廃止後も有効に機能する。
## LevelUpSelectはこのリストに載っているものだけを候補にする。
const ACTIVE_STATE_UPGRADE_EFFECTS := [
	"burning_damage", "burning_kill_xp", "frozen_damage", "frozen_crit",
	"charged_damage", "marked_damage", "marked_kill_shield",
	"cursed_damage", "cursed_kill_spread",
]
## 状態異常 -> それを参照する強化カードのeffect_type。
## LevelUpSelectは「現在の職業が付与する状態」のカードだけを候補にする
## (付与しない状態のカードは効果が永久にゼロになるため、仕様書36.7)。
const UPGRADE_EFFECTS_BY_STATE := {
	"burning": ["burning_damage", "burning_kill_xp"],
	"frozen": ["frozen_damage", "frozen_crit"],
	"charged": ["charged_damage"],
	"marked": ["marked_damage", "marked_kill_shield"],
	"cursed": ["cursed_damage", "cursed_kill_spread"],
}
## 旧属性カードを状態異常／汎用効果へ再定義したショップ専用強化。
## LevelUpSelectへは戻さず、ShopSystemが現在職業の付与状態で絞り込む。
const SHOP_STATE_UPGRADE_EFFECTS := [
	"fire_heatwave", "fire_scorching", "fire_ashes",
	"ice_permafrost", "ice_absolute_zero", "ice_deep_freeze",
	"lightning_speed", "lightning_overload", "lightning_field",
	"light_rapid_holy", "light_judgment", "light_blessing",
	"dark_abyss", "dark_bind", "dark_corrosion",
	"charged_chain",
]
const SHOP_UPGRADE_EFFECTS_BY_STATE := {
	"burning": ["fire_heatwave", "fire_scorching", "fire_ashes"],
	"frozen": ["ice_permafrost", "ice_absolute_zero", "ice_deep_freeze"],
	"charged": ["lightning_speed", "lightning_overload", "lightning_field", "charged_chain"],
	"marked": ["light_rapid_holy", "light_judgment", "light_blessing"],
	"cursed": ["dark_abyss", "dark_bind", "dark_corrosion"],
}
const STATE_UPGRADE_EFFECTS := ACTIVE_STATE_UPGRADE_EFFECTS + SHOP_STATE_UPGRADE_EFFECTS

# --- レベルアップの通常強化オプション由来(data/upgrades/)+ボス撃破アイテム由来(data/items/) ---
# 両者は同じ蓄積値を共有する(damage_up等は同じeffect_typeを再利用しているため)。
var damage_multiplier: float = 1.0
var multishot_chance: float = 0.0
var crit_rate_bonus: float = 0.0
var homing_strength: float = 0.0
var move_speed_multiplier: float = 0.0      # 蓄積された移動速度上昇率(例: 0.15=+15%、トレードオフでマイナスにもなる)
var max_hp_bonus: float = 0.0               # 蓄積された最大HP加算値(表示・記録用の合計。実際の増加は都度HealthComponentへ加算)
var attack_interval_multiplier: float = 0.0 # 蓄積された攻撃間隔短縮率(例: 0.10=-10%、トレードオフでマイナスにもなる=遅くなる)
var damage_taken_multiplier: float = 0.0    # 蓄積された被ダメージ軽減率(例: 0.15=-15%、トレードオフでマイナスにもなる=被ダメージ増加)
var attack_range_multiplier: float = 0.0    # 蓄積された射程倍率補正(例: 0.20=+20%、トレードオフでマイナスにもなる)
var melee_damage_multiplier: float = 1.0
var melee_attack_speed_bonus: float = 0.0
var melee_range_bonus: float = 0.0
var melee_lifesteal_percent: float = 0.0
var melee_lifesteal_cap_per_hit: float = 0.0
var lifesteal_percent: float = 0.0
var exp_gain_multiplier: float = 1.0        # 職業パッシブ由来の獲得経験値倍率(ExperienceComponentが参照)
## 装備由来は交換時に再計算するため、既存の累積強化値と分離する。
var equipment_damage_multiplier: float = 1.0
var equipment_attack_flat: float = 0.0
var equipment_crit_rate_bonus: float = 0.0
var equipment_crit_damage_bonus: float = 0.0
var equipment_attack_speed_bonus: float = 0.0
var equipment_low_hp_threshold: float = 0.0
var equipment_low_hp_damage_bonus: float = 0.0
var state_upgrade_counts: Dictionary = {}
var survival_upgrade_counts: Dictionary = {}

func get_survival_rank(id: String) -> int:
	return int(survival_upgrade_counts.get(id, 0))

## 所持している秘技の数（レベルアップの枠判定に使う）。
func get_arcana_count() -> int:
	var count := 0
	for id in survival_upgrade_counts.keys():
		if String(id).begins_with("arcana_") and int(survival_upgrade_counts[id]) > 0:
			count += 1
	return count

func _ready() -> void:
	EventBus.enemy_damage_confirmed.connect(_on_enemy_damage_confirmed)

func get_state_upgrade_count(effect_type: String) -> int:
	return int(state_upgrade_counts.get(effect_type, 0))

func resolve_state_condition_damage(target: Node, amount: float, metadata: Dictionary) -> Dictionary:
	var result_metadata := metadata.duplicate(true)
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return {"amount": amount, "metadata": result_metadata}
	var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if status == null:
		return {"amount": amount, "metadata": result_metadata}
	var multiplier := 1.0
	if status.has_state("burning"):
		multiplier *= 1.0 + 0.25 * get_state_upgrade_count("burning_damage")
	if status.has_state("frozen"):
		multiplier *= 1.0 + 0.25 * get_state_upgrade_count("frozen_damage") + 0.20 * get_state_upgrade_count("ice_deep_freeze")
		var bonus_crit := 0.15 * get_state_upgrade_count("frozen_crit") + 0.10 * get_state_upgrade_count("ice_absolute_zero")
		if not bool(result_metadata.get("is_critical", false)) and bonus_crit > 0.0 and randf() < minf(bonus_crit, 0.75):
			multiplier *= 2.0
			result_metadata["is_critical"] = true
	if status.has_state("charged"):
		multiplier *= 1.0 + 0.25 * get_state_upgrade_count("charged_damage") + 0.20 * get_state_upgrade_count("lightning_overload")
	if status.has_state("marked"):
		multiplier *= 1.0 + 0.25 * get_state_upgrade_count("marked_damage") + 0.20 * get_state_upgrade_count("light_judgment")
		var marked_crit := 0.10 * get_state_upgrade_count("light_rapid_holy")
		if not bool(result_metadata.get("is_critical", false)) and marked_crit > 0.0 and randf() < minf(marked_crit, 0.60):
			multiplier *= 2.0
			result_metadata["is_critical"] = true
	if status.has_state("cursed"):
		multiplier *= 1.0 + 0.25 * get_state_upgrade_count("cursed_damage") + 0.20 * get_state_upgrade_count("dark_corrosion")
	return {"amount": amount * multiplier, "metadata": result_metadata}

func get_equipment_conditional_damage_multiplier() -> float:
	if equipment_low_hp_damage_bonus <= 0.0 or equipment_low_hp_threshold <= 0.0:
		return 1.0
	var health := _get_sibling("HealthComponent") as HealthComponent
	if health and health.max_hp > 0.0 and health.current_hp / health.max_hp <= equipment_low_hp_threshold:
		return 1.0 + equipment_low_hp_damage_bonus
	return 1.0

## 職業選択(CharacterData)由来の恒常パッシブを、既存の強化オプション/アイテムと
## 同じ蓄積値(damage_multiplier/crit_rate_bonus/damage_taken_multiplier)へ
## 「初期値」として合成する。こうすることで、後から選ぶ強化オプションの加算・減算
## ロジック(_apply_effect)を一切変更せずに、職業パッシブと強化オプションが
## 自然に重ね合わさる(例: Necromancerの本体攻撃力-10%は基準値0.9からdamage_up分だけ
## さらに増えていく)。Player._apply_character_data()の直後、HealthComponentの
## max_hpが確定した後に1回だけ呼ぶ想定。
func apply_character_passives(character_data: CharacterData) -> void:
	damage_multiplier = character_data.self_damage_multiplier
	crit_rate_bonus = character_data.crit_rate_bonus
	damage_taken_multiplier = character_data.damage_reduction
	exp_gain_multiplier = character_data.exp_gain_multiplier
	_sync_health_component()

## LevelUpSelectがUpgradeDataを1つ選んだ際に呼び出す。主効果(effect_type/value)を
## 適用した後、downside_typeが設定されていればその代償を「マイナス方向」に適用する。
## 流派選択(class_school_select、2026年8月試験実装)はfloatのvalueではなく
## class_school(文字列)を渡す必要があるため、通常のeffect_type/valueディスパッチャ
## (_apply_effect())を経由せずここで直接処理する(代償も持たないため早期returnでよい)。
func apply_upgrade(upgrade: UpgradeData) -> void:
	if upgrade.category == "reward":
		# 強化を取り尽くした後の報酬。段階を持たず、何度でも即時に効く。
		match upgrade.effect_type:
			"reward_gold": GameManager.add_run_gold(int(upgrade.value), "level_up_reward")
			"reward_heal":
				var health := _get_sibling("HealthComponent") as HealthComponent
				if health: health.heal(health.max_hp * upgrade.value)
		return
	if upgrade.category == "arcana":
		# 秘技（自動発動の大技）。段階はsurvival_upgrade_countsで数え、実体はConceptSystemが持つ。
		var arcana_rank := get_survival_rank(upgrade.id)
		if arcana_rank >= int(upgrade.effect_params.get("max_rank", 5)): return
		survival_upgrade_counts[upgrade.id] = arcana_rank + 1
		var world := GameManager.get_runtime_world(self)
		var concept := world.get_node_or_null("ConceptSystem") as ConceptSystem if world else null
		if concept: concept.acquire_completed_skill(String(upgrade.effect_params.get("skill_id", "")))
		var arcana_manager := _get_sibling("WeaponManagerComponent") as WeaponManagerComponent
		if arcana_manager: arcana_manager.sector_style_changed.emit()
		return
	if upgrade.category == "survival":
		var rank := get_survival_rank(upgrade.id)
		var maximum := int(upgrade.effect_params.get("max_rank", 0))
		if maximum > 0 and rank >= maximum: return
		survival_upgrade_counts[upgrade.id] = rank + 1
		var manager := _get_sibling("WeaponManagerComponent") as WeaponManagerComponent
		match upgrade.effect_type:
			"survival_area":
				_apply_effect("attack_range_multiplier", upgrade.value)
				if manager: manager.sector_arc_width_level = mini(manager.sector_arc_width_level + 1, 3)
			"survival_haste": _apply_effect("attack_interval_multiplier", upgrade.value)
			"survival_power": _apply_effect("damage_up", upgrade.value)
			"survival_pierce":
				if manager: manager.sector_pierce_level = mini(manager.sector_pierce_level + 1, 2)
		if manager: manager.sector_style_changed.emit()
		return
	if upgrade.effect_type == "class_school_select":
		var weapon_manager := _get_sibling("WeaponManagerComponent") as WeaponManagerComponent
		if weapon_manager:
			weapon_manager.select_class_school(upgrade.class_school)
		return
	if upgrade.effect_type in STATE_UPGRADE_EFFECTS:
		state_upgrade_counts[upgrade.effect_type] = get_state_upgrade_count(upgrade.effect_type) + 1
		# 3枚は旧範囲／連鎖語彙を安全な常時Statへ再定義する。状態対応職だけが
		# Shopで取得できるため、状態カードとしてのBuild識別は維持される。
		match upgrade.effect_type:
			"fire_heatwave", "lightning_field":
				_apply_effect("attack_range_multiplier", upgrade.value)
			"lightning_speed":
				_apply_effect("attack_interval_multiplier", upgrade.value)
		return
	_apply_effect(upgrade.effect_type, upgrade.value)
	if upgrade.effect_type == "melee_lifesteal":
		melee_lifesteal_cap_per_hit = maxf(melee_lifesteal_cap_per_hit, float(upgrade.effect_params.get("max_heal_per_hit", 3.0)))
	if upgrade.downside_type != "":
		_apply_effect(upgrade.downside_type, -upgrade.downside_value)

## BossSpawnerがボス撃破時にItemDataを1つ選んだ際に呼び出す。同じアイテムを複数回
## 獲得した場合はそのまま重ね掛け(再度加算)される。アイテムのeffect_typeは
## data/upgrades/と同じ語彙を再利用しており、同じ蓄積値に合算される。
func apply_item(item: ItemData) -> void:
	_apply_effect(item.effect_type, item.value)

## 強化オプション・アイテム・トレードオフの代償のすべてがここを通る共通の適用処理。
## valueが負の場合は「その分だけ減らす」ことになるため、トレードオフの代償
## (downside)もこの1箇所だけで安全に(上限/下限つきで)処理できる。
func _apply_effect(effect_type: String, value: float) -> void:
	match effect_type:
		"damage_up":
			damage_multiplier = maxf(damage_multiplier + value, DAMAGE_MULTIPLIER_FLOOR)
		"multishot_chance_up":
			multishot_chance = clampf(multishot_chance + value, NON_NEGATIVE_FLOOR, MULTISHOT_CHANCE_CAP)
		"crit_rate_up":
			crit_rate_bonus = maxf(crit_rate_bonus + value, NON_NEGATIVE_FLOOR)
		"homing_upgrade":
			homing_strength = clampf(homing_strength + value, NON_NEGATIVE_FLOOR, HOMING_STRENGTH_CAP)
		"max_hp_bonus":
			max_hp_bonus += value
			_apply_max_hp_bonus_delta(value)
		"move_speed_multiplier":
			move_speed_multiplier = maxf(move_speed_multiplier + value, MOVE_SPEED_PENALTY_FLOOR)
			_sync_movement_component()
		"attack_interval_multiplier":
			attack_interval_multiplier = clampf(attack_interval_multiplier + value, ATTACK_INTERVAL_PENALTY_FLOOR, ATTACK_INTERVAL_BONUS_CAP)
		"attack_range_multiplier":
			attack_range_multiplier = maxf(attack_range_multiplier + value, ATTACK_RANGE_PENALTY_FLOOR)
		"damage_taken_multiplier":
			damage_taken_multiplier = clampf(damage_taken_multiplier + value, DAMAGE_TAKEN_PENALTY_FLOOR, DAMAGE_TAKEN_REDUCTION_CAP)
			_sync_health_component()
		"melee_damage_up":
			melee_damage_multiplier = maxf(melee_damage_multiplier + value, DAMAGE_MULTIPLIER_FLOOR)
		"melee_attack_speed_up":
			melee_attack_speed_bonus = clampf(melee_attack_speed_bonus + value, 0.0, ATTACK_INTERVAL_BONUS_CAP)
		"melee_range_up":
			melee_range_bonus = maxf(melee_range_bonus + value, 0.0)
		"melee_lifesteal":
			melee_lifesteal_percent = clampf(melee_lifesteal_percent + value, 0.0, 0.12)
		"lifesteal":
			lifesteal_percent = clampf(lifesteal_percent + value, 0.0, 0.08)
		"class_ability_level_up":
			var weapon_manager := _get_sibling("WeaponManagerComponent") as WeaponManagerComponent
			if weapon_manager:
				weapon_manager.increase_class_ability_level()

## 最大HPの増加分を即座にHealthComponent.max_hp/current_hpへ加算する(増加した分だけ
## その場で回復もする、よくあるローグライク仕様)。HealthComponentは「基礎値+ボーナス」を
## 別々に持つ設計になっていないため、絶対値の再計算ではなく差分加算にして二重加算を防ぐ。
func _apply_max_hp_bonus_delta(delta: float) -> void:
	var health := _get_sibling("HealthComponent") as HealthComponent
	if health:
		health.max_hp += delta
		health.current_hp += delta

## bonus_speed_multiplierは「今の蓄積合計」を都度セットする(増分を掛け続けるのではない)
## ため、何度呼んでも安全(べき等)。
func _sync_movement_component() -> void:
	var movement := _get_sibling("MovementComponent") as MovementComponent
	if movement:
		movement.bonus_speed_multiplier = 1.0 + move_speed_multiplier

func _sync_health_component() -> void:
	var health := _get_sibling("HealthComponent") as HealthComponent
	if health:
		health.damage_taken_multiplier = maxf(0.2, 1.0 - damage_taken_multiplier)

func _get_sibling(node_name: String) -> Node:
	var parent := get_parent()
	return parent.get_node_or_null(node_name) if parent else null

func _on_enemy_damage_confirmed(target: Node, _amount: float, _is_critical: bool, metadata: Dictionary) -> void:
	if not bool(metadata.get("killed", false)) or target == null or not is_instance_valid(target):
		return
	var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if status == null:
		return
	if status.has_state("burning"):
		var bonus_xp := get_state_upgrade_count("burning_kill_xp")
		var experience := _get_sibling("ExperienceComponent") as ExperienceComponent
		if bonus_xp > 0 and experience:
			experience.add_exp(bonus_xp)
	if status.has_state("marked"):
		var shield_stacks := get_state_upgrade_count("marked_kill_shield")
		var blessing_stacks := get_state_upgrade_count("light_blessing")
		var player_health := _get_sibling("HealthComponent") as HealthComponent
		if (shield_stacks > 0 or blessing_stacks > 0) and player_health:
			player_health.grant_temporary_shield(player_health.max_hp * (0.08 * shield_stacks + 0.06 * blessing_stacks))
	if status.has_state("charged") and get_state_upgrade_count("charged_chain") > 0:
		_spread_charged_from(target as Node2D, get_state_upgrade_count("charged_chain"))
	if status.has_state("cursed") and get_state_upgrade_count("cursed_kill_spread") > 0:
		_spread_curse_from(target as Node2D)

func _spread_curse_from(source: Node2D) -> void:
	if source == null:
		return
	# 数値はStatusApplySystemの呪い付与と揃える(属性Lvによる変動は廃止済み)。
	var duration := StatusApplySystem.CURSED_DURATION
	var ratio := StatusApplySystem.CURSED_BONUS_DAMAGE_TAKEN
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy := enemy_variant as Node2D
		if enemy == null or enemy == source or not is_instance_valid(enemy) or enemy.global_position.distance_to(source.global_position) > 150.0:
			continue
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health and health.current_hp > 0.0:
			health.apply_curse(1.0 + ratio, duration)

func _spread_charged_from(source: Node2D, target_count: int) -> void:
	if source == null or target_count <= 0:
		return
	var candidates: Array[Node2D] = []
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy := enemy_variant as Node2D
		if enemy == null or enemy == source or not is_instance_valid(enemy) or enemy.global_position.distance_to(source.global_position) > 160.0:
			continue
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health and health.current_hp > 0.0:
			candidates.append(enemy)
	candidates.sort_custom(func(a: Node2D, b: Node2D): return a.global_position.distance_squared_to(source.global_position) < b.global_position.distance_squared_to(source.global_position))
	var status_system := get_tree().get_first_node_in_group("status_apply_system") as StatusApplySystem
	if status_system == null:
		return
	for index in mini(target_count, candidates.size()):
		status_system.apply_charged(candidates[index])

func get_burn_duration_multiplier() -> float:
	return 1.0 + 0.50 * get_state_upgrade_count("fire_ashes")

func get_burn_damage_multiplier() -> float:
	return 1.0 + 0.40 * get_state_upgrade_count("fire_scorching")

func get_frozen_duration_multiplier() -> float:
	return 1.0 + 0.40 * get_state_upgrade_count("ice_permafrost")

func get_cursed_duration_multiplier() -> float:
	return 1.0 + 0.60 * get_state_upgrade_count("dark_bind")

func get_cursed_bonus_damage_taken() -> float:
	return StatusApplySystem.CURSED_BONUS_DAMAGE_TAKEN + 0.12 * get_state_upgrade_count("dark_abyss")
