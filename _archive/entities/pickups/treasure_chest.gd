extends Area2D
class_name TreasureChest

signal opened(rarity: String)

const CHEST_SHEET = preload("res://assets/sprites/props/treasure_chests_new.png")

var rarity: String = "normal"
var accent_color: Color = Color(0.85, 0.85, 0.9, 1.0)
var is_opened: bool = false
var available := true
var name_override := ""
var locked_reason := "周囲の敵を倒す"
var is_boss_chest: bool = false
var _player_in_range: Player = null

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("map_content")
	var solid := StaticBody2D.new()
	solid.name = "ChestBody"
	solid.collision_layer = 1
	solid.collision_mask = 0
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(28, 12)
	collider.shape = shape
	collider.position = Vector2(0, -6)
	solid.add_child(collider)
	add_child(solid)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_label()
	queue_redraw()

func configure(chest_rarity: String, color: Color, boss_chest: bool = false) -> void:
	rarity = chest_rarity
	accent_color = color
	is_boss_chest = boss_chest
	if is_node_ready():
		_update_label()
		queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if is_opened or not body.is_in_group("player") or not (body is Player):
		return
	_player_in_range = body as Player
	_player_in_range.register_interactable(self)
	_update_label()

func _on_body_exited(body: Node2D) -> void:
	if body != _player_in_range:
		return
	_player_in_range.unregister_interactable(self)
	_player_in_range = null
	_update_label()

func can_interact(actor: Node) -> bool:
	return not is_opened and actor == _player_in_range

func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	if not available:
		_update_label()
		return true
	is_opened = true
	if is_instance_valid(_player_in_range):
		_player_in_range.unregister_interactable(self)
	_player_in_range = null
	set_deferred("monitoring", false)
	_update_label()
	AudioManager.play_sfx("chest_open")
	if is_boss_chest:
		ImportedBurstVFX.spawn(get_parent() as Node2D, global_position + Vector2(0, -24), "chest")
	queue_redraw()
	opened.emit(rarity)
	return true

func _update_label() -> void:
	if label == null:
		return
	if is_opened:
		label.text = "開封済み"
	elif not available:
		label.text = "%s\n%s" % [_display_name(), locked_reason]
	elif is_instance_valid(_player_in_range):
		label.text = "%s\n【E】宝箱を開く" % _display_name()
	else:
		label.text = _display_name()

func _display_name() -> String:
	if not name_override.is_empty(): return name_override
	if is_boss_chest:
		return {"normal": "ボス宝箱", "rare": "希少なボス宝箱", "legendary": "伝説のボス宝箱"}.get(rarity, "ボス宝箱")
	return {"normal": "宝箱", "rare": "希少な宝箱", "legendary": "伝説の宝箱"}.get(rarity, "宝箱")

func _draw() -> void:
	var source := _source_region()
	var width := 48.0 if is_boss_chest else 32.0
	var height := width * source.size.y / source.size.x
	draw_texture_rect_region(CHEST_SHEET, Rect2(-width / 2.0, -height, width, height), source)

func _source_region() -> Rect2:
	# The source sheet has five palettes across and three closed/open pairs down.
	# Crop transparent padding so the chest keeps its in-world size.
	var column: int = {"normal": 0, "rare": 2, "legendary": 3}.get(rarity, 0)
	var row := (4 if is_boss_chest else 0) + (1 if is_opened else 0)
	return Rect2(column * 32 + 6, row * 32 + (4 if is_opened else 9), 20, 24 if is_opened else 19)

func set_available(value: bool) -> void:
	available = value
	if is_node_ready(): _update_label()
