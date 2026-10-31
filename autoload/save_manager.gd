extends Node
## セーブデータの読み書きを抽象化するレイヤー。
## 将来クラウドセーブ(Google Play Games Services / Game Center)に
## 差し替える際は、このクラスの内部実装だけを差し替えれば良い設計にする。

const SAVE_PATH := "user://save_data.json"

const DEFAULT_DATA := {
	"meta_currency": 0,
	"unlocked_weapon_ids": [],
	"unlocked_character_ids": ["soldier"],
	"best_survival_seconds": 0.0,
	"deepest_cleared_floor": 0,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
}

var data: Dictionary = DEFAULT_DATA.duplicate(true)
var _ephemeral_session_depth: int = 0
var _ephemeral_snapshot: Dictionary = {}

func _ready() -> void:
	load_data()
	_apply_audio_settings()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		# 過去のセーブデータに新しいキー(unlocked_character_ids等)が
		# 存在しない場合に備えて、無ければ既定値で補完しておく。
		for key in DEFAULT_DATA.keys():
			if not parsed.has(key):
				parsed[key] = DEFAULT_DATA[key]
		data = parsed

func save_data() -> void:
	# Developer Test Lab中はBoss/Elite/Result経路まで実物を試せるが、
	# その結果を通常セーブへ書き込まない。
	if _ephemeral_session_depth > 0:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func add_meta_currency(amount: int) -> void:
	data["meta_currency"] = int(data.get("meta_currency", 0)) + amount
	save_data()

func update_best_survival(seconds: float) -> void:
	if seconds > float(data.get("best_survival_seconds", 0.0)):
		data["best_survival_seconds"] = seconds
		save_data()

func record_cleared_floor(depth: int) -> void:
	if depth > int(data.get("deepest_cleared_floor", 0)):
		data["deepest_cleared_floor"] = depth
		save_data()

func begin_ephemeral_session() -> void:
	if _ephemeral_session_depth == 0:
		_ephemeral_snapshot = data.duplicate(true)
	_ephemeral_session_depth += 1

func end_ephemeral_session() -> void:
	if _ephemeral_session_depth <= 0:
		return
	_ephemeral_session_depth -= 1
	if _ephemeral_session_depth == 0:
		data = _ephemeral_snapshot.duplicate(true)
		_ephemeral_snapshot.clear()

func is_ephemeral_session_active() -> bool:
	return _ephemeral_session_depth > 0

func is_character_unlocked(character_id: String) -> bool:
	var unlocked: Array = data.get("unlocked_character_ids", ["soldier"])
	return character_id in unlocked

## メタ通貨costを消費してcharacter_idを解放する。既に解放済みならtrueを返すだけ。
## コストが足りない場合は何もせずfalseを返す。
func unlock_character(character_id: String, cost: int) -> bool:
	if is_character_unlocked(character_id):
		return true
	if int(data.get("meta_currency", 0)) < cost:
		return false
	data["meta_currency"] = int(data.get("meta_currency", 0)) - cost
	var unlocked: Array = data.get("unlocked_character_ids", ["soldier"]).duplicate()
	unlocked.append(character_id)
	data["unlocked_character_ids"] = unlocked
	save_data()
	return true

func set_audio_volume(bus_name: String, linear_volume: float) -> void:
	var key := "music_volume" if bus_name == "Music" else "sfx_volume"
	data[key] = clampf(linear_volume, 0.0, 1.0)
	AudioManager.set_bus_volume(bus_name, float(data[key]))
	save_data()

func get_audio_volume(bus_name: String) -> float:
	var key := "music_volume" if bus_name == "Music" else "sfx_volume"
	return float(data.get(key, DEFAULT_DATA[key]))

func _apply_audio_settings() -> void:
	AudioManager.set_bus_volume("Music", get_audio_volume("Music"))
	AudioManager.set_bus_volume("SFX", get_audio_volume("SFX"))
