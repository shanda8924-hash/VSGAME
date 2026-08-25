extends Node
class_name HeartDropSystem

const HEART_SCENE := preload("res://entities/pickups/heart_pickup.tscn")
const CONFIG_PATH := "res://data/pickups/heart.json"

var heart_drop_chance: float = 0.05
var elite_heart_drop_chance: float = 0.10
var heal_ratio: float = 0.15
var lifetime_seconds: float = 25.0

func _ready() -> void:
	_load_config()
	EventBus.enemy_drop_requested.connect(_on_enemy_drop_requested)

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("HeartDropSystem: 設定ファイルを読み込めません -> %s" % CONFIG_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("HeartDropSystem: Heart設定JSONが不正です")
		return
	heart_drop_chance = clampf(float(parsed.get("heart_drop_chance", heart_drop_chance)), 0.0, 1.0)
	elite_heart_drop_chance = clampf(float(parsed.get("elite_heart_drop_chance", elite_heart_drop_chance)), 0.0, 1.0)
	heal_ratio = maxf(float(parsed.get("heal_ratio", heal_ratio)), 0.0)
	lifetime_seconds = maxf(float(parsed.get("lifetime_seconds", lifetime_seconds)), 1.0)

func _on_enemy_drop_requested(position: Vector2, is_elite: bool, is_boss: bool) -> void:
	if is_boss:
		return
	var chance := elite_heart_drop_chance if is_elite else heart_drop_chance
	if randf() >= chance:
		return
	var heart := HEART_SCENE.instantiate() as HeartPickup
	heart.setup(heal_ratio, lifetime_seconds)
	var runtime_world := GameManager.get_runtime_world(self)
	_add_heart_deferred.call_deferred(runtime_world, heart, position)


func _add_heart_deferred(runtime_world: Node, heart: HeartPickup, position: Vector2) -> void:
	if not is_instance_valid(runtime_world) or not is_instance_valid(heart):
		return
	runtime_world.add_child(heart)
	heart.global_position = position

func spawn_recovery_drop(position: Vector2, configured_heal_ratio: float = 0.30, configured_lifetime: float = 60.0) -> HeartPickup:
	var runtime_world := GameManager.get_runtime_world(self)
	if runtime_world == null:
		return null
	var heart := HEART_SCENE.instantiate() as HeartPickup
	heart.setup(configured_heal_ratio, configured_lifetime)
	runtime_world.add_child(heart)
	heart.global_position = position
	return heart
