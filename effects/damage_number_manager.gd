extends Node
class_name DamageNumberManager
## ダメージ数値ポップアップのオブジェクトプール管理(VFXPoolManagerと同じ方針)。
## EventBus.damage_dealtを購読し、都度instantiateせずプールから使い回す。
## 設定画面のダメージ表示トグル(ScreenEffects.quality_settings)がOFFの場合は
## 何も生成しない。

@export var damage_number_scene: PackedScene
@export var pool_size: int = 36

@onready var _screen_effects: ScreenEffects = get_tree().get_first_node_in_group("screen_effects")

var _pool: Array[DamageNumber] = []

func _ready() -> void:
	if damage_number_scene == null:
		return
	for i in pool_size:
		var n: DamageNumber = damage_number_scene.instantiate()
		n.visible = false
		add_child(n)
		_pool.append(n)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.healing_received.connect(_on_healing_received)

func _on_damage_dealt(amount: float, position: Vector2, is_critical: bool) -> void:
	if _screen_effects and not _screen_effects.quality_settings.get("damage_numbers_enabled", true):
		return
	for n in _pool:
		if not n.visible:
			n.play(amount, position, is_critical)
			return

func _on_healing_received(amount: float, position: Vector2) -> void:
	if _screen_effects and not _screen_effects.quality_settings.get("damage_numbers_enabled", true):
		return
	for n in _pool:
		if not n.visible:
			n.play_heal(amount, position)
			return

