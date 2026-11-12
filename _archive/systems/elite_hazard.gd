extends Node2D
class_name EliteHazard
## 精鋭能力の床予兆と発動を一体で管理する。ダメージは予兆終了後だけ発生する。

var radius: float = 64.0
var color: Color = Color.GREEN
var damage: float = 5.0
var duration: float = 4.0
var tick_interval: float = 1.0
var warning_only: bool = false
var effect_id: String = "fire"
var warning_duration: float = 0.65
var source: EnemyBasic
var _elapsed := 0.0
var _tick := 0.0
var _activated := false
var _ring: PixelSpriteVFX

func _ready() -> void:
	add_to_group("room_transient")
	z_index = 5
	_ring = WarningCircle.make_ring(radius, Color(color, 0.9))
	if _ring:
		add_child(_ring)
		_ring.play_once(global_position)
		_ring.position = Vector2.ZERO

func _process(delta: float) -> void:
	if source != null and (not is_instance_valid(source) or source._is_dead or (source.exploration_guard and (not source.exploration_alert or source._returning_home))):
		queue_free()
		return
	_elapsed += delta
	if not _activated:
		var warning_progress := clampf(_elapsed / maxf(warning_duration, 0.01), 0.0, 1.0)
		if _ring:
			_ring.modulate.a = 0.75 + warning_progress * 0.25
		queue_redraw()
		if _elapsed >= warning_duration:
			_activate()
		return
	_tick -= delta
	if not warning_only and _tick <= 0.0:
		_tick = tick_interval
		_damage_player_in_radius()
	if _elapsed >= warning_duration + duration:
		queue_free()

func _activate() -> void:
	_activated = true
	queue_redraw()
	if _ring:
		_ring.set_tint(Color(color, 0.95))
	var vfx_id := "concept_fire_burst"
	if effect_id == "lightning":
		vfx_id = "concept_thunder_strike"
	elif effect_id == "poison":
		vfx_id = "poison"
	var effect := PixelSpriteVFX.spawn(self, global_position, vfx_id, Vector2.ONE * radius * 2.1, duration if effect_id == "poison" else 0.45, 0.0, Color.WHITE, effect_id == "poison")
	if effect:
		effect.z_index = -1 if effect_id == "poison" else 2
	if warning_only:
		_damage_player_in_radius()
	else:
		_tick = tick_interval
		_damage_player_in_radius()

func trigger_once() -> void:
	# 旧呼び出しとの互換。予兆を飛ばす明示呼び出しだけ即時発動する。
	if not _activated:
		_elapsed = warning_duration
		_activate()

func _damage_player_in_radius() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or global_position.distance_to(player.global_position) > radius:
		return
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.apply_damage(damage)

func _draw() -> void:
	if _activated: return
	var progress := clampf(_elapsed/maxf(warning_duration,0.01),0.0,1.0)
	draw_circle(Vector2.ZERO,radius,Color(color,0.06+progress*0.13))
	draw_arc(Vector2.ZERO,radius,-PI/2,-PI/2+TAU*progress,48,Color(1.0,0.85,0.6,0.9),2.0,false)
