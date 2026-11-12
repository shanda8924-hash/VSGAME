extends Area2D
class_name MapLandmark
## MAP探索用の最小共通Interaction。属性祭壇・回復祭壇・Boss領域は同じE/X導線を使い、
## 報酬やBoss生成の責務はMapRunControllerへ返す。

const STAIRS_ART := preload("res://assets/tiles/landmarks/stairs_pixel_v3.png")


class DoorFrame extends Node2D:
	var door: MapLandmark
	func _draw() -> void:
		door.draw_door_reveal(self)

signal activated(kind: String, landmark: MapLandmark)
signal attempted_while_locked(kind: String)

var kind := "attribute"
var display_name := "祭壇"
var accent_color := Color("8edbff")
var available := true
var used := false
var _player: Player = null
var _label: Label = null
var _door_masonry: Texture2D
var _door_floor: Texture2D

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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	if kind == "boss_gate":
		# StageEnvironment supplies the architectural floor seal. Keep the prompt
		# below it instead of covering its centre with a procedural purple cage.
		_label.position = Vector2(-150, 116)
		_label.size = Vector2(300, 64)
		_label.add_theme_font_override("font", preload("res://assets/fonts/MPLUS1p-Medium.ttf"))
		_label.add_theme_font_size_override("font_size", 20)
		_label.add_theme_color_override("font_color", Color("f2e6cd"))
		_label.add_theme_constant_override("outline_size", 2)
	if kind == "room_exit":
		var theme := GameManager.current_map_index
		_door_masonry = load("res://assets/tiles/royal/wall_material.png" if theme == 1 else "res://assets/tiles/amethyst_depths/pixel_masonry_wall_v2.png" if theme == 2 else "res://assets/tiles/ruin_forge/pixel_materials_v2.png")
		_door_floor = load("res://assets/tiles/royal/dungeon_atlas.png" if theme == 1 else "res://assets/tiles/amethyst_depths/pixel_materials_v2.png" if theme == 2 else "res://assets/tiles/ruin_forge/pixel_materials_v2.png")
		z_index = -1
		_label.position.y = 24
		_label.add_theme_color_override("font_color", Color("c9c1ab"))
		_label.add_theme_font_size_override("font_size", 18)
		var frame := DoorFrame.new()
		frame.name = "DoorFrame"
		frame.door = self
		frame.z_index = 2
		add_child(frame)
	add_child(_label)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh_label()
	queue_redraw()

func set_available(value: bool) -> void:
	available = value
	var frame := get_node_or_null("DoorFrame")
	if frame: frame.queue_redraw()
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
	AudioManager.play_sfx("room_door" if kind == "room_exit" else "item_pickup")
	activated.emit(kind, self)
	return true

func _on_body_entered(body: Node2D) -> void:
	if used or not (body is Player):
		return
	_player = body as Player
	_player.register_interactable(self)
	_refresh_label()

func reset_interaction() -> void:
	used = false
	monitoring = true
	for body in get_overlapping_bodies():
		_on_body_entered(body)
	_refresh_label()
	queue_redraw()

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
	elif kind == "room_exit":
		_label.text = "【E / X】封鎖中" if not available else "【E / X】進む" if is_instance_valid(_player) else display_name
	elif is_instance_valid(_player):
		_label.text = "%s\n【E / X】%s" % [display_name, "侵入" if kind == "boss_gate" else "下りる" if kind == "descent_stairs" else "進む" if kind == "room_exit" else "調べる"]
	elif kind == "boss_gate" and not available:
		_label.text = "%s\n封印中" % display_name
	else:
		_label.text = display_name

func _draw() -> void:
	var color := accent_color if available and not used else accent_color.darkened(0.58)
	if kind == "boss_gate":
		return
	if kind == "room_exit":
		_draw_wall_door()
		return
	if kind == "descent_stairs":
		draw_texture_rect(STAIRS_ART, Rect2(-40, -24, 80, 56), false, Color.WHITE if available and not used else Color(0.65, 0.65, 0.65))
		return
	else:
		draw_rect(Rect2(-34, 18, 68, 18), Color(0.05, 0.04, 0.08, 0.92), true)
		draw_rect(Rect2(-34, 18, 68, 18), color, false, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-22, 18), Vector2(-10, -28), Vector2(10, -28), Vector2(22, 18)]), Color(color, 0.28))
		draw_polyline(PackedVector2Array([Vector2(-22, 18), Vector2(-10, -28), Vector2(10, -28), Vector2(22, 18)]), color, 3.0, false)
		draw_rect(Rect2(-5, -18, 10, 22), color.lightened(0.25), true)

# The wall itself supplies the masonry. Only its recessed opening and hinges
# are drawn here, so no unrelated stone slab covers the existing courses.
func _door_base_y() -> float:
	return 0.0 if GameManager.current_map_index == 1 else 16.0

func _door_outline() -> PackedVector2Array:
	var y := _door_base_y()
	return PackedVector2Array([Vector2(-20,y),Vector2(-20,y-40),Vector2(-16,y-48),Vector2(-8,y-54),Vector2(8,y-54),Vector2(16,y-48),Vector2(20,y-40),Vector2(20,y)])

func _door_stone_color() -> Color:
	match GameManager.current_map_index:
		2: return Color("504956")
		3: return Color("514333")
		_: return Color("344453")

func _draw_wall_door() -> void:
	var y := _door_base_y()
	var stone := _door_stone_color()
	draw_colored_polygon(_door_outline(), Color("07090c"))
	# Low light on the tunnel floor shows depth instead of a luminous portal.
	var floor_points := PackedVector2Array([Vector2(-18,y),Vector2(-10,y-16),Vector2(10,y-16),Vector2(18,y)])
	var floor_region := Rect2(144,160,16,8) if GameManager.current_map_index == 1 else Rect2(4,4,16,8)
	_draw_door_stone(self, floor_points, _door_floor, floor_region, Color(0.30,0.30,0.30))
	for depth in [4,10]:
		draw_line(Vector2(-16,y-depth),Vector2(16,y-depth),stone.darkened(0.68),2.0)
	if not available:
		var metal := stone.darkened(0.22)
		for x in range(-16,17,6):
			var top := y-48 if absi(x)<=8 else y-42
			draw_rect(Rect2(x,top,2,y-top-2),metal)
			draw_rect(Rect2(x,top,1,y-top-2),metal.lightened(0.10))
		for height in [14,34]:
			draw_rect(Rect2(-18,y-height,36,4),metal.darkened(0.25))
			for x in [-14,14]: draw_rect(Rect2(x,y-height+1,2,2),metal.lightened(0.2))
		draw_rect(Rect2(-3,y-27,6,8),metal.lightened(0.16))
		draw_rect(Rect2(-1,y-24,2,3),Color("111216"))

func draw_door_reveal(canvas: Node2D) -> void:
	var y := _door_base_y()
	var stone := _door_stone_color()
	# A narrow bevel cut into the original wall; no rectangular outer backing.
	var outline := _door_outline()
	var outer := PackedVector2Array([Vector2(-24,y),Vector2(-24,y-42),Vector2(-18,y-52),Vector2(-8,y-58),Vector2(8,y-58),Vector2(18,y-52),Vector2(24,y-42),Vector2(24,y)])
	var region := Rect2(4,160,16,32) if GameManager.current_map_index == 1 else Rect2(4,4,16,32) if GameManager.current_map_index == 2 else Rect2(140,4,16,32)
	var shade := Color(0.72,0.72,0.72) if GameManager.current_map_index == 1 else Color(0.80,0.80,0.88) if GameManager.current_map_index == 2 else Color(0.85,0.78,0.68)
	for i in 7:
		var block := PackedVector2Array([outer[i],outer[i+1],outline[i+1],outline[i]])
		var block_region := Rect2(region.position + Vector2(i * 2,0),Vector2(2,maxf(2,ceilf(outer[i].distance_to(outer[i+1])*0.5))))
		_draw_door_stone(canvas,block,_door_masonry,block_region,shade)
		if i in [1,2,4,5]:
			canvas.draw_line(outer[i],outline[i],stone.darkened(0.45),1.0,false)
	canvas.draw_polyline(outline.slice(0,7),Color(0,0,0,0.5),2.0,false)
	canvas.draw_line(Vector2(-22,y-38),Vector2(-22,y),stone.lightened(0.06),2.0)
	canvas.draw_line(Vector2(22,y-38),Vector2(22,y),stone.darkened(0.4),2.0)
	for side in [-1,1]:
		for height in [8,26]:
			canvas.draw_rect(Rect2(side*18-1,y-height,2,5),stone.darkened(0.1))
	# Threshold is the same stone, flush with the floor, rather than a plinth.
	canvas.draw_line(Vector2(-21,y),Vector2(21,y),stone.darkened(0.1),2.0)

func _draw_door_stone(canvas: Node2D, points: PackedVector2Array, texture: Texture2D, region: Rect2, shade: Color) -> void:
	var lo := region.position / texture.get_size()
	var hi := region.end / texture.get_size()
	canvas.draw_polygon(points,PackedColorArray([shade]),PackedVector2Array([lo,Vector2(lo.x,hi.y),hi,Vector2(hi.x,lo.y)]),texture)
