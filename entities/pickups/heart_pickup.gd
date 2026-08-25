extends Area2D
class_name HeartPickup

const HEAL_VFX_SCRIPT := preload("res://effects/active_skill_vfx.gd")

var heal_ratio: float = 0.15
var lifetime_seconds: float = 25.0
var _elapsed: float = 0.0
var _collected := false

func _ready() -> void:
	add_to_group("room_transient")
	body_entered.connect(_on_body_entered)
	var tween := create_tween().set_loops()
	tween.tween_property(self, "modulate", Color(1.15, 0.72, 0.78, 1.0), 0.7)
	tween.tween_property(self, "modulate", Color.WHITE, 0.7)

func setup(configured_heal_ratio: float, configured_lifetime: float) -> void:
	heal_ratio = configured_heal_ratio
	lifetime_seconds = configured_lifetime

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= lifetime_seconds:
		queue_free()

func _draw() -> void:
	var float_offset := Vector2(0.0, sin(_elapsed * 3.0) * 3.0)
	draw_circle(float_offset, 18.0, Color(0.9, 0.08, 0.2, 0.12))
	draw_circle(float_offset + Vector2(-6, -4), 8.0, Color(1.0, 0.18, 0.3, 1.0))
	draw_circle(float_offset + Vector2(6, -4), 8.0, Color(1.0, 0.18, 0.3, 1.0))
	draw_colored_polygon(PackedVector2Array([
		float_offset + Vector2(-13, -2),
		float_offset + Vector2(13, -2),
		float_offset + Vector2(0, 15)
	]), Color(1.0, 0.18, 0.3, 1.0))
	draw_circle(float_offset + Vector2(-5, -6), 2.0, Color(1.0, 0.72, 0.78, 0.9))

func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	var health: HealthComponent = body.get_node_or_null("HealthComponent")
	if health == null or health.current_hp >= health.max_hp:
		return
	_collected = true
	var before := health.current_hp
	health.heal(health.max_hp * heal_ratio)
	var recovered := health.current_hp - before
	EventBus.healing_received.emit(recovered, global_position)
	var vfx := HEAL_VFX_SCRIPT.new() as ActiveSkillVFX
	vfx.setup(32.0, Color(0.3, 1.0, 0.5, 0.85), Vector2.UP, 180.0, "aura")
	GameManager.get_runtime_world(self).add_child(vfx)
	vfx.global_position = global_position
	AudioManager.play_sfx("item_pickup")
	queue_free()
