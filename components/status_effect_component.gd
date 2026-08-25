extends Node
class_name StatusEffectComponent
## 毒/氷結(スロウ)等の状態異常を管理するコンポーネント。
## プロトタイプ段階では「スロウ」のみ実装し、将来のDoT系(毒/燃焼)も
## 同じ辞書構造で追加できるようにしてある。

var _active_effects: Dictionary = {} # effect_name: String -> remaining_seconds: float
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

func has_effect(effect_name: String) -> bool:
	return _active_effects.has(effect_name)

func remove_effect(effect_name: String) -> void:
	if not _active_effects.erase(effect_name):
		return
	if effect_name == "slow" or effect_name == "stun":
		slow_multiplier = 0.0 if _active_effects.has("stun") else 0.5 if _active_effects.has("slow") else 1.0

func _process(delta: float) -> void:
	if _active_effects.is_empty():
		return
	for effect_name in _active_effects.keys().duplicate():
		_active_effects[effect_name] -= delta
		if _active_effects[effect_name] <= 0.0:
			_active_effects.erase(effect_name)
			if effect_name == "slow" or effect_name == "stun":
				slow_multiplier = 1.0
