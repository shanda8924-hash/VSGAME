extends Node
## セーブデータの読み書きを抽象化するレイヤー。
## 将来クラウドセーブ(Google Play Games Services / Game Center)に
## 差し替える際は、このクラスの内部実装だけを差し替えれば良い設計にする。

const SAVE_PATH := "user://save_data.json"

const DEFAULT_DATA := {
	"meta_currency": 0,
	"unlocked_weapon_ids": [],
	"unlocked_character_ids": ["soldier"],
	"unlocked_survival_maps": [1],
	"best_survival_seconds": 0.0,
	"deepest_cleared_floor": 0,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	# Phase 4（育成）：装備の持ち越し、職業の熟練、深度の鎖。
	"persistent_equipment": {"equipped": {}, "inventory": []},
	"class_mastery": {},
	"class_memory": {},
	"survival_depth": 1,
	"deepest_survival_depth": 0,
}
## ホームに持ち越せる所持品の上限（装備6枠は別）。
const PERSISTENT_INVENTORY_CAP := 20
## 熟練の段階（累計ポイント）。1：職業技Lv2（剣士は流派）で開始、2：前回の最初の強化を持ち込み、3：最大HP+10%。
const MASTERY_TIERS := [3, 8, 15]

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
				var fallback = DEFAULT_DATA[key]
				parsed[key] = fallback.duplicate(true) if typeof(fallback) in [TYPE_DICTIONARY, TYPE_ARRAY] else fallback
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

## 5分サバイバルのステージ解放。MAP1は常に解放済み。
func is_map_unlocked(map_index: int) -> bool:
	if map_index <= 1:
		return true
	var unlocked: Array = data.get("unlocked_survival_maps", [1])
	return map_index in unlocked

## メタ通貨costを消費してステージを解放する。解放済みならtrue、不足ならfalse。
func unlock_map(map_index: int, cost: int) -> bool:
	if is_map_unlocked(map_index):
		return true
	if int(data.get("meta_currency", 0)) < cost:
		return false
	data["meta_currency"] = int(data.get("meta_currency", 0)) - cost
	var unlocked: Array = data.get("unlocked_survival_maps", [1]).duplicate()
	unlocked.append(map_index)
	data["unlocked_survival_maps"] = unlocked
	save_data()
	return true

# ============================================================
# Phase 4：装備の持ち越し・職業の熟練・深度
# ============================================================

func get_persistent_equipment() -> Dictionary:
	var payload: Dictionary = data.get("persistent_equipment", {})
	return {"equipped": Dictionary(payload.get("equipped", {})).duplicate(true), "inventory": Array(payload.get("inventory", [])).duplicate(true)}

## 装備6枠と所持品（上限PERSISTENT_INVENTORY_CAP）を保存する。所持品はロック→お気に入り→レア度の順に残す。
func store_persistent_equipment(equipped: Dictionary, inventory: Array) -> void:
	var kept: Array = inventory.duplicate()
	kept.sort_custom(func(a: Dictionary, b: Dictionary):
		if bool(a.get("is_locked", false)) != bool(b.get("is_locked", false)): return bool(a.get("is_locked", false))
		if bool(a.get("is_favorite", false)) != bool(b.get("is_favorite", false)): return bool(a.get("is_favorite", false))
		return EquipmentMergeSystem.RARITY_ORDER.find(String(a.get("rarity", ""))) > EquipmentMergeSystem.RARITY_ORDER.find(String(b.get("rarity", "")))
	)
	if kept.size() > PERSISTENT_INVENTORY_CAP:
		kept.resize(PERSISTENT_INVENTORY_CAP)
	data["persistent_equipment"] = {"equipped": equipped.duplicate(true), "inventory": kept}
	save_data()

func clear_persistent_equipment() -> void:
	data["persistent_equipment"] = {"equipped": {}, "inventory": []}
	save_data()

func get_class_mastery(character_id: String) -> int:
	return int(Dictionary(data.get("class_mastery", {})).get(character_id, 0))

func add_class_mastery(character_id: String, points: int) -> int:
	var mastery: Dictionary = Dictionary(data.get("class_mastery", {})).duplicate(true)
	mastery[character_id] = int(mastery.get(character_id, 0)) + maxi(points, 0)
	data["class_mastery"] = mastery
	save_data()
	return int(mastery[character_id])

func get_mastery_tier(character_id: String) -> int:
	var points := get_class_mastery(character_id)
	var tier := 0
	for threshold in MASTERY_TIERS:
		if points >= int(threshold): tier += 1
	return tier

## 前回のビルドの記憶（最初に取った戦闘強化・流派）。熟練2段階以上で持ち込む。
func remember_class_build(character_id: String, first_upgrade_id: String, school: String) -> void:
	var memory: Dictionary = Dictionary(data.get("class_memory", {})).duplicate(true)
	var entry: Dictionary = Dictionary(memory.get(character_id, {})).duplicate(true)
	if first_upgrade_id != "": entry["first_upgrade"] = first_upgrade_id
	if school != "" and school != "none": entry["school"] = school
	memory[character_id] = entry
	data["class_memory"] = memory
	save_data()

func get_class_memory(character_id: String) -> Dictionary:
	return Dictionary(Dictionary(data.get("class_memory", {})).get(character_id, {})).duplicate(true)

func get_survival_depth() -> int:
	return maxi(int(data.get("survival_depth", 1)), 1)

## ステージを攻略するたびに深度+1。敵の倍率と報酬のレア度が上がる（MapRunController参照）。
func advance_survival_depth() -> int:
	var next := get_survival_depth() + 1
	data["survival_depth"] = next
	data["deepest_survival_depth"] = maxi(int(data.get("deepest_survival_depth", 0)), next - 1)
	save_data()
	return next

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
