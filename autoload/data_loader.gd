extends Node
## JSONデータの読み込み。現在は職業(キャラクター)だけを読む。
## 新しい種類のデータを足すときは、ここに読み込み関数を1つ足す。

const CHARACTER_DIR := "res://data/characters/"

var characters: Dictionary = {} # id: String -> CharacterData

func _ready() -> void:
	_load_characters()

func _read_json_dir(dir_path: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("DataLoader: フォルダが見つかりません -> %s" % dir_path)
		return results
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir_path + file_name))
		if typeof(parsed) == TYPE_DICTIONARY:
			results.append(parsed)
		else:
			push_warning("DataLoader: JSON解析失敗 -> %s" % file_name)
	return results

func _load_characters() -> void:
	for entry in _read_json_dir(CHARACTER_DIR):
		var data := CharacterData.new()
		data.id = String(entry.get("id", ""))
		data.display_name = String(entry.get("display_name", ""))
		data.sprite_folder = String(entry.get("sprite_folder", ""))
		data.max_hp = float(entry.get("max_hp", 100.0))
		data.move_speed = float(entry.get("move_speed", 140.0))
		if data.id != "":
			characters[data.id] = data

func get_all_characters() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for value in characters.values():
		result.append(value)
	return result
