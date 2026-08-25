extends Area2D
class_name TreasureChest

signal opened(rarity: String)

var rarity: String = "normal"
var accent_color: Color = Color(0.85, 0.85, 0.9, 1.0)
var is_opened: bool = false
var is_boss_chest: bool = false
var _player_in_range: Player = null

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("map_content")
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
	is_opened = true
	if is_instance_valid(_player_in_range):
		_player_in_range.unregister_interactable(self)
	_player_in_range = null
	set_deferred("monitoring", false)
	_update_label()
	AudioManager.play_sfx("item_pickup")
	queue_redraw()
	opened.emit(rarity)
	return true

func _update_label() -> void:
	if label == null:
		return
	if is_opened:
		label.text = "%s\n開封済み" % _display_name()
	elif is_instance_valid(_player_in_range):
		label.text = "%s\n【E】宝箱を開く" % _display_name()
	else:
		label.text = _display_name()

func _display_name() -> String:
	if is_boss_chest:
		return {"normal": "ボス宝箱", "rare": "希少なボス宝箱", "legendary": "伝説のボス宝箱"}.get(rarity, "ボス宝箱")
	return {"normal": "宝箱", "rare": "希少な宝箱", "legendary": "伝説の宝箱"}.get(rarity, "宝箱")

func _draw() -> void:
	var lid_y := -30.0 if is_opened else -18.0
	# 角の欠けた硬いShadow/OutlineでWorld Spriteと同じPixel密度に揃える。
	draw_rect(Rect2(-38, 7, 84, 44), Color(0.035, 0.025, 0.02, 0.72), true)
	draw_rect(Rect2(-42, 0, 84, 44), Color(0.24, 0.11, 0.04, 1.0), true)
	draw_rect(Rect2(-42, 0, 84, 44), accent_color, false, 4.0)
	draw_rect(Rect2(-46, lid_y, 92, 22), Color(0.38, 0.18, 0.06, 1.0), true)
	draw_rect(Rect2(-46, lid_y, 92, 22), accent_color, false, 4.0)
	draw_rect(Rect2(-34, lid_y + 6, 68, 4), Color(accent_color, 0.72), true)
	draw_rect(Rect2(-8, 5, 16, 22), accent_color, true)
	draw_rect(Rect2(-4, 9, 8, 10), Color(0.05, 0.04, 0.03, 1.0), true)
	if rarity in ["rare", "legendary"]:
		for side in [-1, 1]:
			var x := float(side) * 30.0
			draw_rect(Rect2(x - 2, lid_y - 7, 4, 4), accent_color, true)
			if rarity == "legendary":
				draw_rect(Rect2(x - 1, lid_y - 13, 2, 4), accent_color.lightened(0.25), true)
	if is_boss_chest:
		draw_rect(Rect2(-50, 14, 8, 12), accent_color.darkened(0.2), true)
		draw_rect(Rect2(42, 14, 8, 12), accent_color.darkened(0.2), true)
