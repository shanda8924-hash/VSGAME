extends RefCounted
class_name UiText

const JAPANESE_PATH := "res://data/localization/ui_ja.json"
static var _japanese: Dictionary = {}

static func get_text(key: String, fallback: String = "") -> String:
	if _japanese.is_empty():
		_load_japanese()
	return String(_japanese.get(key, fallback if fallback != "" else key))

static func _load_japanese() -> void:
	var file := FileAccess.open(JAPANESE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	_japanese = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
