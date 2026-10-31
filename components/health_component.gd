extends Node
class_name HealthComponent
## HP管理のみを責務とするコンポーネント(単一責任の原則)。
## 描画やUI更新は一切行わず、Signalで通知するだけに徹する。

signal damaged(amount: float, current_hp: float, max_hp: float)
signal healed(amount: float, current_hp: float, max_hp: float)
signal died()
signal shield_changed(current_shield: float, max_shield: float)

## 1回の被弾(同一物理フレーム内の合算を含む)で最大HPのこの割合を超える
## ダメージを与えない安全策。弾幕系のボス攻撃(nova等)が同時に複数命中して
## 合算即死する事故を防ぐための保険的措置。
const MAX_DAMAGE_PER_HIT_RATIO := 0.4
## 上記キャップに最低保証する実ダメージ量。max_hpが低い雑魚敵(例: スライムの
## HP10)にそのまま割合キャップだけを適用すると、本来なら一撃で倒せるはずの
## 攻撃まで小刻みに軽減されてしまい、「大量の敵を薙ぎ払う」爽快感を損なう。
## この下限より小さい実ダメージは割合キャップの対象にせずそのまま通す。
const MIN_DAMAGE_CAP_FLOOR := 30.0

@export var max_hp: float = 100.0
## 被ダメージ倍率(sturdy_shieldのようなアイテムで蓄積した軽減率を
## PlayerUpgradesComponentがここへ同期する)。1.0=軽減なし、0.85=ダメージ15%軽減。
## Enemy側は誰も同期しないため既定の1.0のまま(軽減の影響を受けない)。
var damage_taken_multiplier: float = 1.0
## Spaceスキルによる一時防御倍率。恒常強化値と分離し、終了時に強化値を巻き戻さない。
var active_skill_damage_multiplier: float = 1.0
## trueの間はapply_damage()が何もしない(charge_dash等、突進中無敵になる
## 攻撃パターンが一時的に立てる)。ONにした側が必ずOFFへ戻す責任を持つ。
var invincible: bool = false
var dodge_iframe_remaining := 0.0
var current_hp: float
var shield_amount: float = 0.0
var shield_max: float = 0.0
var equipment_negate_chance: float = 0.0
## 装備防御力は固定値。受けた生ダメージから先に差し引き、その後に既存の
## 割合軽減(damage_taken_multiplier/active_skill_damage_multiplier)を適用する。
var equipment_defense_flat: float = 0.0

## 被弾後、この秒数の間は再び被弾してもダメージを受けない無敵時間(iframe)。
## 敵の接触ダメージ判定が(攻撃モーション中のみとはいえ)複数の敵に同時に
## 囲まれた際に連続ヒットしてしまう事故を防ぐための安全策。Player/Enemy
## 共通のHealthComponentに実装するため、敵側が被弾した際にも同様に適用される
## (短時間での連続被弾を避けるという趣旨自体はどちらにも当てはまるため)。
const IFRAME_DURATION := 0.5
var _iframe_remaining: float = 0.0

## 同一物理フレーム内での被弾合算キャップ用の内部状態。
var _damage_taken_this_frame: float = 0.0
var _last_damage_physics_frame: int = -1

var _curse_multiplier: float = 1.0
var _player_upgrades_cache: PlayerUpgradesComponent = null

func _ready() -> void:
	current_hp = max_hp
	var status := get_parent().get_node_or_null("StatusEffectComponent") as StatusEffectComponent if get_parent() else null
	if status:
		status.states_changed.connect(_on_states_changed)
	if get_parent() and get_parent().is_in_group("enemies"):
		var player := get_tree().get_first_node_in_group("player")
		_player_upgrades_cache = player.get_node_or_null("PlayerUpgradesComponent") as PlayerUpgradesComponent if player else null

func _process(delta: float) -> void:
	dodge_iframe_remaining = maxf(0.0, dodge_iframe_remaining - delta)
	if _iframe_remaining > 0.0:
		_iframe_remaining -= delta

func apply_damage(amount: float, combat_metadata: Dictionary = {}) -> float:
	return _apply_damage_internal(amount, false, true, combat_metadata)

## 同じ攻撃のベースHit直後に発生する属性追加ダメージ用。既に開始したiframeだけを
## 無視し、新たなiframeは開始しない。防御・Shield・1Hit上限・死亡判定は通常と共通。
func apply_secondary_damage(amount: float, combat_metadata: Dictionary = {}) -> float:
	return _apply_damage_internal(amount, true, false, combat_metadata)

func _apply_damage_internal(amount: float, ignore_iframe: bool, start_iframe: bool, combat_metadata: Dictionary) -> float:
	if current_hp <= 0.0 or invincible or dodge_iframe_remaining > 0.0 or (not ignore_iframe and _iframe_remaining > 0.0):
		return 0.0
	if equipment_negate_chance > 0.0 and randf() < equipment_negate_chance:
		return 0.0
	var metadata := CombatEventMeta.normalize(combat_metadata)
	var resolved_amount := amount
	var owner_entity := get_parent()
	if owner_entity and owner_entity.is_in_group("enemies") and _is_player_origin_damage(metadata):
		if _player_upgrades_cache == null:
			var player := get_tree().get_first_node_in_group("player")
			_player_upgrades_cache = player.get_node_or_null("PlayerUpgradesComponent") as PlayerUpgradesComponent if player else null
		if _player_upgrades_cache:
			var resolved := _player_upgrades_cache.resolve_state_condition_damage(owner_entity, amount, metadata)
			resolved_amount = float(resolved.get("amount", amount))
			metadata = resolved.get("metadata", metadata)
	# Equipment armor alone cannot erase contact damage, even with six high-tier pieces.
	var after_flat_defense := maxf(resolved_amount - equipment_defense_flat, maxf(1.0, resolved_amount * 0.4)) if resolved_amount > 0.0 else 0.0
	var reduced_amount := after_flat_defense * damage_taken_multiplier * active_skill_damage_multiplier
	if shield_amount > 0.0:
		var absorbed := minf(shield_amount, reduced_amount)
		shield_amount -= absorbed
		reduced_amount -= absorbed
		shield_changed.emit(shield_amount, shield_max)
	reduced_amount = _apply_per_hit_cap(reduced_amount)
	if reduced_amount <= 0.0:
		return 0.0
	current_hp = max(current_hp - reduced_amount, 0.0)
	if start_iframe:
		_iframe_remaining = 0.08 if get_parent() and get_parent().is_in_group("enemies") else IFRAME_DURATION
	damaged.emit(reduced_amount, current_hp, max_hp)
	if current_hp > 0.0 and _is_player_origin_damage(metadata) and owner_entity.has_method("receive_hit_impact"):
		owner_entity.receive_hit_impact(metadata)
	if owner_entity and owner_entity.is_in_group("enemies"):
		metadata["killed"] = current_hp <= 0.0
		if owner_entity is Node2D:
			metadata["impact_position"] = (owner_entity as Node2D).global_position
		EventBus.enemy_damage_confirmed.emit(owner_entity, reduced_amount, bool(metadata.get("is_critical", false)), metadata)
	if current_hp <= 0.0:
		died.emit()
	return reduced_amount

## 同一物理フレーム内(Engine.get_physics_frames()が変わるまで)に受けた
## ダメージを合算管理し、その合計がmax_hp * MAX_DAMAGE_PER_HIT_RATIOを
## 超えないようその場で切り詰める(MIN_DAMAGE_CAP_FLOOR未満の実ダメージは
## そのまま通す)。複数の弾が同一フレームで命中しても、合算で即死しないように
## するための処理。
func _apply_per_hit_cap(amount: float) -> float:
	var current_frame := Engine.get_physics_frames()
	if current_frame != _last_damage_physics_frame:
		_last_damage_physics_frame = current_frame
		_damage_taken_this_frame = 0.0
	var cap := maxf(max_hp * MAX_DAMAGE_PER_HIT_RATIO, MIN_DAMAGE_CAP_FLOOR)
	var remaining_budget := maxf(cap - _damage_taken_this_frame, 0.0)
	var capped_amount := minf(amount, remaining_budget)
	_damage_taken_this_frame += capped_amount
	return capped_amount

func heal(amount: float) -> void:
	# A defeated entity remains in the tree until its death animation finishes.
	# Late aura/affix healing must not revive it and allow a second died signal.
	if current_hp <= 0.0:
		return
	var before := current_hp
	current_hp = min(current_hp + amount, max_hp)
	var recovered := current_hp - before
	if recovered > 0.0:
		healed.emit(recovered, current_hp, max_hp)

func grant_temporary_shield(amount: float) -> void:
	shield_max = maxf(amount, 0.0)
	shield_amount = shield_max
	shield_changed.emit(shield_amount, shield_max)

func clear_shield() -> void:
	shield_amount = 0.0
	shield_max = 0.0
	shield_changed.emit(0.0, 0.0)

## 闇属性の呪い。被ダメージ倍率をmultiplier(1.0より大きい値)へ引き上げ、
## duration秒後に自動で1.0へ戻す。再付与時は残り時間・倍率のどちらも大きい方を採用する
## (連続Hitで途切れず、弱いLvの呪いが強いLvの呪いを上書きしないように)。
func apply_curse(multiplier: float, duration: float) -> void:
	_curse_multiplier = maxf(_curse_multiplier, multiplier)
	damage_taken_multiplier = maxf(damage_taken_multiplier, _curse_multiplier)
	var status := get_parent().get_node_or_null("StatusEffectComponent") as StatusEffectComponent if get_parent() else null
	if status:
		status.apply_effect("cursed", duration, multiplier)

func _on_states_changed(states: Array[String]) -> void:
	if "cursed" in states:
		return
	_curse_multiplier = 1.0
	# Enemyの恒常軽減は現状無く、PlayerのStatusEffectにはCurseを付けない。
	if get_parent() and get_parent().is_in_group("enemies"):
		damage_taken_multiplier = 1.0

func _is_player_origin_damage(metadata: Dictionary) -> bool:
	var source := String(metadata.get("source_kind", ""))
	return source.begins_with("player_") or source.begins_with("element_") or source.begins_with("fusion_") or source.begins_with("concept:") or source.begins_with("completed_skill")

## Authored melee strokes have their own per-target deduplication. Enemy iframe must
## not swallow the next visible stroke; player dodge/invulnerability stays intact.
func apply_animation_strike_damage(amount: float, metadata: Dictionary = {}) -> float:
	if not get_parent().is_in_group("enemies"):
		return apply_damage(amount, metadata)
	return _apply_damage_internal(amount, true, false, metadata)
