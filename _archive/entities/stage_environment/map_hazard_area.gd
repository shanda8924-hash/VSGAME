extends Area2D
class_name MapHazardArea
## DungeonMapのhazard region 1区画を、1個のArea2Dで監視する。
## セルごとのNodeは作らず、TileMap描画と矩形Collisionを分離して性能を守る。

var region: Rect2i
var damage_per_tick := 6.0
var tick_interval := 1.0
var damage_tick_count := 0
var _player: Player = null
var _tick_remaining := 0.25
var _elapsed := 0.0

func configure(region_rect: Rect2i, damage: float, interval: float = 1.0) -> void:
	region = region_rect
	damage_per_tick = maxf(damage, 0.0)
	tick_interval = maxf(interval, 0.2)

func _ready() -> void:
	add_to_group("map_content")
	add_to_group("map_hazard")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	z_index = -70
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(region.size) * DungeonMap.CELL_WORLD_SIZE
	shape_node.shape = shape
	add_child(shape_node)
	global_position = Vector2(region.position * 2 + region.size - Vector2i.ONE) * (DungeonMap.CELL_WORLD_SIZE * 0.5)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	if _player == null or not is_instance_valid(_player):
		_player = null
		return
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	_tick_remaining = tick_interval
	var health := _player.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.current_hp > 0.0:
		var applied := health.apply_damage(damage_per_tick)
		if applied > 0.0:
			damage_tick_count += 1

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body as Player
		_tick_remaining = minf(_tick_remaining, 0.25)

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_tick_remaining = 0.25

func _draw() -> void:
	var size := Vector2(region.size) * DungeonMap.CELL_WORLD_SIZE
	var local_rect := Rect2(-size * 0.5, size)
	draw_rect(local_rect, Color(0.72, 0.08, 0.30, 0.07), true)
	draw_rect(local_rect, Color(1.0, 0.38, 0.26, 0.55), false, 2.0)
