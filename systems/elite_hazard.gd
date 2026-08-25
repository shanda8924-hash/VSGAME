extends Node2D
class_name EliteHazard
## 雷撃予兆または持続毒床。局所描画のみで全画面フラッシュは使わない。

var radius: float = 64.0
var color: Color = Color.GREEN
var damage: float = 5.0
var duration: float = 4.0
var tick_interval: float = 1.0
var warning_only: bool = false
var _elapsed := 0.0
var _tick := 0.0

func _ready() -> void:
	add_to_group("room_transient")
	z_index = 5
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	_tick -= delta
	if not warning_only and _tick <= 0.0:
		_tick = tick_interval
		_damage_player_in_radius()
	if _elapsed >= duration:
		queue_free()
	queue_redraw()

func trigger_once() -> void:
	_damage_player_in_radius()

func _damage_player_in_radius() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or global_position.distance_to(player.global_position) > radius:
		return
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.apply_damage(damage)

func _draw() -> void:
	var pulse := 0.65 + sin(_elapsed * 8.0) * 0.15
	draw_circle(Vector2.ZERO, radius, Color(color, 0.10 * pulse))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(color, 0.75 * pulse), 3.0)
