extends Node
class_name MassKillTracker
## SNS拡散最優先演出:「短時間での大量撃破」を検出し、一掃演出(VFX/シェイク/ヒットストップ)を発火する。

@export var window_seconds: float = 1.0
@export var trigger_threshold: int = 5
@export var screen_effects_path: NodePath
@export var vfx_pool_path: NodePath

@onready var _screen_effects: ScreenEffects = get_node(screen_effects_path)
@onready var _vfx_pool: VFXPoolManager = get_node(vfx_pool_path)

var _recent_kill_times: Array[float] = []
var _recent_positions: Array[Vector2] = []

func _ready() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)

func _on_enemy_died(_enemy_data: Resource, death_position: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_recent_kill_times.append(now)
	_recent_positions.append(death_position)
	var filtered_times: Array[float] = []
	var filtered_positions: Array[Vector2] = []
	for i in _recent_kill_times.size():
		if now - _recent_kill_times[i] <= window_seconds:
			filtered_times.append(_recent_kill_times[i])
			filtered_positions.append(_recent_positions[i])
	_recent_kill_times = filtered_times
	_recent_positions = filtered_positions
	if _recent_kill_times.size() >= trigger_threshold:
		_trigger_mass_kill()

func _trigger_mass_kill() -> void:
	var avg_position := Vector2.ZERO
	for pos in _recent_positions:
		avg_position += pos
	avg_position /= _recent_positions.size()
	EventBus.mass_kill_triggered.emit(_recent_kill_times.size(), avg_position)
	_vfx_pool.play_mass_kill_burst(avg_position)
	_screen_effects.shake(8.0, 0.3)
	_screen_effects.hit_stop(0.08)
	_recent_kill_times.clear()
	_recent_positions.clear()
