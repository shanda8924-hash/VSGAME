extends Node
class_name RunEconomySystem
## MAP探索のラン専用ゴールド獲得を集約する。所持・消費の正本はGameManager。

const CONFIG_PATH := "res://data/maps/exploration_run.json"

var _economy: Dictionary = {}
var _ordinary_kills := 0

func _ready() -> void:
	_economy = Dictionary(_read_json(CONFIG_PATH).get("economy", {})).duplicate(true)
	EventBus.enemy_drop_requested.connect(_on_enemy_drop_requested)
	EventBus.map_started.connect(func(_depth, _total, _name): _ordinary_kills = 0)
	EventBus.elite_room_cleared.connect(_on_elite_room_cleared)
	EventBus.map_surge_ended.connect(_on_map_surge_ended)
	EventBus.map_completed.connect(_on_map_completed)

func _on_enemy_drop_requested(_position: Vector2, is_elite: bool, is_boss: bool) -> void:
	if not _accepts_map_reward():
		return
	var base_gold := int(_economy.get("enemy_kill_gold", 1))
	if is_boss:
		var boss_bonus := int(_economy.get("boss_clear_gold_by_map", {}).get(str(GameManager.current_map_index), 0)) if GameManager.survival_mode_active else 0
		GameManager.add_run_gold(base_gold + boss_bonus, "boss_kill")
		return
	if is_elite:
		GameManager.add_run_gold(base_gold + int(_economy.get("elite_kill_bonus", 10)), "elite_kill")
		return
	_ordinary_kills += 1
	if _ordinary_kills % maxi(int(_economy.get("kills_per_gold", 4)), 1) == 0:
		GameManager.add_run_gold(base_gold, "enemy_kill")

func _on_elite_room_cleared(_room_index: int) -> void:
	if _accepts_map_reward():
		GameManager.add_run_gold(int(_economy.get("elite_room_clear_bonus", 50)), "elite_room_clear")

func _on_map_surge_ended(_map_index: int, _surge_index: int, _reward_type: String, _reward_position: Vector2) -> void:
	if _accepts_map_reward():
		GameManager.add_run_gold(int(_economy.get("surge_clear_bonus", 20)), "surge_clear")

func _on_map_completed(map_index: int, _elapsed_seconds: float, _kill_count: int) -> void:
	if not _accepts_map_reward():
		return
	var rewards: Dictionary = _economy.get("boss_clear_gold_by_map", {})
	GameManager.add_run_gold(int(rewards.get(str(map_index), 0)) + (GameManager.current_floor_index - 1) * 2, "boss_clear")

func _accepts_map_reward() -> bool:
	return GameManager.map_mode_active and GameManager.run_state == GameManager.RunState.PLAYING

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RunEconomySystem: 設定を読み込めません -> %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("RunEconomySystem: 設定形式が不正です -> %s" % path)
		return {}
	return parsed
