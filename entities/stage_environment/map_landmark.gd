extends Area2D
class_name MapLandmark
## MAP探索用の最小共通Interaction。属性祭壇・回復祭壇・Boss領域は同じE/X導線を使い、
## 報酬やBoss生成の責務はMapRunControllerへ返す。

signal activated(kind: String, landmark: MapLandmark)
signal attempted_while_locked(kind: String)

var kind := "attribute"
var display_name := "祭壇"
var accent_color := Color("8edbff")
var available := true
var used := false
var _player: Player = null
var _label: Label = null

func configure(configured_kind: String, configured_name: String, color: Color, initially_available: bool = true) -> void:
	kind = configured_kind
	display_name = configured_name
	accent_color = color
	available = initially_available
	if is_node_ready():
		_refresh_label()
		queue_redraw()

func _ready() -> void:
	add_to_group("map_content")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 92.0 if kind == "boss_gate" else 76.0
	collision.shape = circle
	add_child(collision)
	_label = Label.new()
	_label.position = Vector2(-130, -82)
	_label.size = Vector2(260, 52)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", accent_color)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh_label()
	queue_redraw()

func set_available(value: bool) -> void:
	available = value
	_refresh_label()
	queue_redraw()

func can_interact(actor: Node) -> bool:
	return not used and actor == _player

func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	if not available:
		attempted_while_locked.emit(kind)
		return true
	if kind == "recovery":
		var health := actor.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp >= health.max_hp:
			return false
	used = true
	if is_instance_valid(_player):
		_player.unregister_interactable(self)
	_player = null
	set_deferred("monitoring", false)
	_refresh_label()
	queue_redraw()
	AudioManager.play_sfx("item_pickup")
	activated.emit(kind, self)
	return true

func _on_body_entered(body: Node2D) -> void:
	if used or not (body is Player):
		return
	_player = body as Player
	_player.register_interactable(self)
	_refresh_label()

func _on_body_exited(body: Node2D) -> void:
	if body != _player:
		return
	_player.unregister_interactable(self)
	_player = null
	_refresh_label()

func _refresh_label() -> void:
	if _label == null:
		return
	if used:
		_label.text = "%s\n使用済み" % display_name
	elif is_instance_valid(_player):
		_label.text = "%s\n【E / X】%s" % [display_name, "侵入" if kind == "boss_gate" else "調べる"]
	elif kind == "boss_gate" and not available:
		_label.text = "%s\n封印中" % display_name
	else:
		_label.text = display_name

func _draw() -> void:
	var color := accent_color if available and not used else accent_color.darkened(0.58)
	if kind == "boss_gate":
		draw_rect(Rect2(-58, -32, 116, 64), Color(color, 0.12), true)
		draw_rect(Rect2(-58, -32, 116, 64), color, false, 4.0)
		draw_rect(Rect2(-42, -20, 84, 40), Color(0.04, 0.025, 0.08, 0.82), true)
		for x in [-32.0, 0.0, 32.0]:
			draw_rect(Rect2(x - 3, -26, 6, 52), color, true)
	else:
		draw_rect(Rect2(-34, 18, 68, 18), Color(0.05, 0.04, 0.08, 0.92), true)
		draw_rect(Rect2(-34, 18, 68, 18), color, false, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-22, 18), Vector2(-10, -28), Vector2(10, -28), Vector2(22, 18)]), Color(color, 0.28))
		draw_polyline(PackedVector2Array([Vector2(-22, 18), Vector2(-10, -28), Vector2(10, -28), Vector2(22, 18)]), color, 3.0, false)
		draw_rect(Rect2(-5, -18, 10, 22), color.lightened(0.25), true)
