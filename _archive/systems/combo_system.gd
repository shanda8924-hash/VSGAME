extends Node
class_name ComboSystem

signal combo_changed(value: int, milestone: bool)
signal combo_reset()
signal combo_advanced(value: int, target: Node, metadata: Dictionary)

@export var timeout_seconds: float = 2.5
@export var triggered_chain_cap: int = 12

var combo: int = 0
var _remaining: float = 0.0
var _active: bool = false
var _triggered_chain_counts: Dictionary = {}

func _ready() -> void:
	EventBus.enemy_damage_confirmed.connect(_on_enemy_damage_confirmed)

func _process(delta: float) -> void:
	if not _active or combo <= 0 or get_tree().paused:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		reset_combo()

func set_active(active: bool) -> void:
	_active = active
	if not active:
		reset_combo()

func configure_timeout(seconds: float) -> void:
	timeout_seconds = maxf(seconds, 0.1)

func configure_triggered_chain_cap(value: int) -> void:
	triggered_chain_cap = maxi(value, 1)

func reset_combo() -> void:
	var had_combo := combo > 0
	combo = 0
	_remaining = 0.0
	_triggered_chain_counts.clear()
	if had_combo:
		combo_reset.emit()

func _on_enemy_damage_confirmed(target: Node, amount: float, _critical: bool, metadata: Dictionary) -> void:
	if not _active or GameManager.run_state != GameManager.RunState.PLAYING or amount <= 0.0 or not bool(metadata.get("combo_eligible", true)):
		return
	var is_triggered := bool(metadata.get("is_triggered", false))
	if is_triggered:
		var chain_id := int(metadata.get("chain_id", 0))
		var contributed := int(_triggered_chain_counts.get(chain_id, 0))
		if contributed >= triggered_chain_cap:
			return
		_triggered_chain_counts[chain_id] = contributed + 1
	combo += 1
	# Direct/Attribute/Fusion Hitだけが猶予を更新する。Triggered Hitは数字へ加算するが、
	# 本体攻撃を止めてもComboを維持できる状態にはしない。
	if not is_triggered:
		_remaining = timeout_seconds
	combo_changed.emit(combo, combo in [10, 30, 50, 100] or combo > 100 and combo % 50 == 0)
	combo_advanced.emit(combo, target, metadata.duplicate(true))
