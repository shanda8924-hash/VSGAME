extends Node2D
class_name StatusApplySystem
## 状態異常(burning / frozen / charged / marked / cursed)の付与と、
## 燃焼の継続ダメージだけを担当する。
##
## 【経緯】旧ElementCombatSystemから「状態異常の付与処理」だけを救出したもの。
## 属性ダメージ計算・属性Lv/スロット・熟練度倍率・属性ID体系(element_fire等)は
## 引き継いでいない。状態異常はslow/stunと同列の通常の状態異常として扱う。
##
## 付与の呼び出し元はsystems/attack_patterns/のattack_pattern_base.gd。
## 付与する状態は各Strategyのapplied_status_id()で職業ごとに決まる(仕様書36.3)。
## TODO: 天賦図による付与状態の追加・変更は後日設計する。

## 旧属性システムはLv1〜3で数値が変動したが、進行度レイヤーを廃止したため固定値にする。
const BURN_TICK_INTERVAL := 0.5
const BURN_TICK_DAMAGE_RATIO := 0.05  # 与えたダメージに対する1tickの割合
const BURN_DURATION := 3.0
const FROZEN_SLOW_DURATION := 2.0
const FROZEN_SLOW_MULTIPLIER := 0.55
const CHARGED_DURATION := 3.0
const MARKED_DURATION := 3.5
const CURSED_DURATION := 3.5
const CURSED_BONUS_DAMAGE_TAKEN := 0.25

## instance_id -> {target, health, tick_timer, tick_damage}
var _burning_targets: Dictionary = {}

func _ready() -> void:
	add_to_group("status_apply_system")
	EventBus.run_started.connect(reset_runtime)
	EventBus.run_ended.connect(func(_seconds, _kills): reset_runtime())

func reset_runtime() -> void:
	_burning_targets.clear()

## 状態IDを指定して付与する共通入口。攻撃Strategyやテストからはこれを呼ぶ。
func apply_state(target: Node2D, state_id: String, source_damage: float = 0.0) -> void:
	match state_id:
		"burning": apply_burning(target, source_damage)
		"frozen": apply_frozen(target)
		"charged": apply_charged(target)
		"marked": apply_marked(target)
		"cursed": apply_cursed(target)

func apply_burning(target: Node2D, source_damage: float) -> void:
	var status := _status_of(target)
	if status == null:
		return
	var upgrades := _player_upgrades()
	var duration_multiplier := upgrades.get_burn_duration_multiplier() if upgrades else 1.0
	var damage_multiplier := upgrades.get_burn_damage_multiplier() if upgrades else 1.0
	status.apply_effect("burning", BURN_DURATION * duration_multiplier, 1.0)
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return
	_burning_targets[target.get_instance_id()] = {
		"target": target,
		"health": health,
		"tick_timer": BURN_TICK_INTERVAL,
		"tick_damage": maxf(source_damage, 1.0) * BURN_TICK_DAMAGE_RATIO * damage_multiplier,
	}

func apply_frozen(target: Node2D) -> void:
	var status := _status_of(target)
	if status:
		var upgrades := _player_upgrades()
		var duration_multiplier := upgrades.get_frozen_duration_multiplier() if upgrades else 1.0
		status.apply_effect("slow", FROZEN_SLOW_DURATION * duration_multiplier, FROZEN_SLOW_MULTIPLIER)

func apply_charged(target: Node2D) -> void:
	var status := _status_of(target)
	if status:
		status.apply_effect("charged", CHARGED_DURATION, 1.0)

func apply_marked(target: Node2D) -> void:
	var status := _status_of(target)
	if status:
		status.apply_effect("marked", MARKED_DURATION, 1.0)

func apply_cursed(target: Node2D) -> void:
	var health := target.get_node_or_null("HealthComponent") as HealthComponent if target and is_instance_valid(target) else null
	if health:
		var upgrades := _player_upgrades()
		var duration_multiplier := upgrades.get_cursed_duration_multiplier() if upgrades else 1.0
		var bonus_damage_taken := upgrades.get_cursed_bonus_damage_taken() if upgrades else CURSED_BONUS_DAMAGE_TAKEN
		# HealthComponent側がStatusEffectComponentへcursedを立て、
		# 被ダメージ倍率も同時に管理する。
		health.apply_curse(1.0 + bonus_damage_taken, CURSED_DURATION * duration_multiplier)

func is_target_burning(target: Node2D) -> bool:
	var status := _status_of(target)
	return status != null and status.has_state("burning")

func _status_of(target: Node2D) -> StatusEffectComponent:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent

func _player_upgrades() -> PlayerUpgradesComponent:
	var player := get_tree().get_first_node_in_group("player")
	return player.get_node_or_null("PlayerUpgradesComponent") as PlayerUpgradesComponent if player else null

## 燃焼の継続ダメージ。StatusEffectComponent側で残り時間が切れたら自動的に打ち切る。
func _process(delta: float) -> void:
	if _burning_targets.is_empty():
		return
	for id_variant in _burning_targets.keys():
		var id := int(id_variant)
		var entry: Dictionary = _burning_targets.get(id, {})
		if entry.is_empty():
			continue
		var health_ref: Variant = entry.get("health")
		var target_ref: Variant = entry.get("target")
		if health_ref == null or not is_instance_valid(health_ref) or target_ref == null or not is_instance_valid(target_ref):
			_burning_targets.erase(id)
			continue
		var health := health_ref as HealthComponent
		var target := target_ref as Node2D
		if health.current_hp <= 0.0 or not is_target_burning(target):
			_burning_targets.erase(id)
			continue
		entry["tick_timer"] = float(entry["tick_timer"]) - delta
		if float(entry["tick_timer"]) <= 0.0:
			entry["tick_timer"] = BURN_TICK_INTERVAL
			var meta := CombatEventMeta.create_secondary("status_burn", [], false)
			var actual := health.apply_secondary_damage(float(entry["tick_damage"]), meta)
			if actual > 0.0:
				EventBus.damage_dealt.emit(actual, target.global_position, false)
			if health.current_hp <= 0.0:
				_burning_targets.erase(id)
				continue
		if _burning_targets.has(id):
			_burning_targets[id] = entry
