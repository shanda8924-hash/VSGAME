extends Node
class_name StatusEffectComponent
## 状態異常(burning / frozen / charged / marked / cursed および slow / stun)を管理する。
## 付与はStatusApplySystemとEliteAffixComponent等が行い、ここは保持と時間経過だけを担当する。
## frozenはslow/stunの両方から立つ(仕様書36.2)。

signal states_changed(states: Array[String])

const STATE_BY_EFFECT := {
	"burning": "burning",
	"slow": "frozen",
	"stun": "frozen",
	"charged": "charged",
	"marked": "marked",
	"cursed": "cursed",
}
const STATE_ORDER: Array[String] = ["burning", "frozen", "charged", "marked", "cursed"]

var _active_effects: Dictionary = {} # effect_name: String -> remaining_seconds: float
var _last_states: Array[String] = []
var slow_multiplier: float = 1.0
## 1.0で通常時間。BossSpawnerがROOMボスだけ0.25〜0.45へ設定し、
## Freeze/Stun/Slowを完全無効にせず拘束時間だけ短縮する。
var duration_multiplier: float = 1.0

func apply_effect(effect_name: String, duration: float, magnitude: float = 0.5) -> void:
	# Developer Dummyだけが使用する明示的な免疫Flag。通常Enemyにはmetaが無く、
	# 本編Status経路と数値には一切影響しない。
	if get_parent() and bool(get_parent().get_meta("status_immune", false)):
		return
	var adjusted_duration := maxf(duration * maxf(duration_multiplier, 0.0), 0.01)
	# 再付与で既に残っている長い効果を短くしない。
	_active_effects[effect_name] = maxf(float(_active_effects.get(effect_name, 0.0)), adjusted_duration)
	if effect_name == "slow":
		slow_multiplier = magnitude
	elif effect_name == "stun":
		# 気絶: 移動速度を完全に0にする(slowと同じspeed_multiplier経由の仕組みを流用)。
		slow_multiplier = 0.0
	_emit_element_states_if_changed()

func has_effect(effect_name: String) -> bool:
	return _active_effects.has(effect_name)

func has_state(state_id: String) -> bool:
	return state_id in get_states()

func get_states() -> Array[String]:
	var states: Array[String] = []
	for state_id in STATE_ORDER:
		for effect_name in STATE_BY_EFFECT:
			if String(STATE_BY_EFFECT[effect_name]) == state_id and _active_effects.has(effect_name):
				states.append(state_id)
				break
	return states

func remove_effect(effect_name: String) -> void:
	if not _active_effects.erase(effect_name):
		return
	if effect_name == "slow" or effect_name == "stun":
		slow_multiplier = 0.0 if _active_effects.has("stun") else 0.5 if _active_effects.has("slow") else 1.0
	_emit_element_states_if_changed()

func _process(delta: float) -> void:
	if _active_effects.is_empty():
		return
	var element_state_expired := false
	for effect_name in _active_effects.keys().duplicate():
		_active_effects[effect_name] -= delta
		if _active_effects[effect_name] <= 0.0:
			_active_effects.erase(effect_name)
			element_state_expired = element_state_expired or STATE_BY_EFFECT.has(effect_name)
			if effect_name == "slow" or effect_name == "stun":
				slow_multiplier = 0.0 if _active_effects.has("stun") else 0.5 if _active_effects.has("slow") else 1.0
	if element_state_expired:
		_emit_element_states_if_changed()

func _emit_element_states_if_changed() -> void:
	var current := get_states()
	if current == _last_states:
		return
	_last_states = current
	states_changed.emit(current.duplicate())
