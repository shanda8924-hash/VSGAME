extends Node
## 「数値バランス=JSON、演出/参照=Resource」のハイブリッド方針を実現するローダー。
## data/ 以下にJSONファイルを追加するだけで、コードを一切書き換えずに
## 新しい武器・敵・欠片を追加できる(データ駆動設計/開放閉鎖原則)。

const ENEMY_DIR := "res://data/enemies/"
const WEAPON_DIR := "res://data/weapons/"
const FRAGMENT_DIR := "res://data/fragments/"
const EFFECT_THEME_DIR := "res://effects/themes/"
const ATTACK_VFX_DIR := "res://effects/attack_vfx/"
const DIFFICULTY_DIR := "res://data/difficulty/"
const CHARACTER_DIR := "res://data/characters/"
const UPGRADE_DIR := "res://data/upgrades/"
const BOSS_DIR := "res://data/bosses/"
const ITEM_DIR := "res://data/items/"
const CONCEPT_DIR := "res://data/concepts/"
const BOSS_SCALING_PATH := "res://data/balance/boss_scaling.json"
const DEFAULT_PROJECTILE_SCENE := "res://entities/projectiles/projectile.tscn"

var enemies: Dictionary = {}          # id: String -> EnemyData
var weapons: Dictionary = {}          # id: String -> WeaponData
var fragments: Dictionary = {}        # id: String -> WeaponFragmentData
var effect_themes: Dictionary = {}    # id: String -> EffectThemeData
var attack_vfx_effects: Dictionary = {} # id: String -> AttackVFXData
var difficulty_curves: Dictionary = {} # id: String -> Array[Dictionary] ({time_seconds, spawn_interval, spawn_batch?}を時間昇順で保持)
var characters: Dictionary = {}        # id: String -> CharacterData
var upgrades: Dictionary = {}          # id: String -> UpgradeData
var bosses: Dictionary = {}            # id: String -> BossData
var items: Dictionary = {}             # id: String -> ItemData
var concepts: Dictionary = {}          # id: String -> ConceptData

func _ready() -> void:
	_load_enemies()
	_load_weapons()
	_load_fragments()
	_load_effect_themes()
	_load_attack_vfx_effects()
	_load_difficulty_curves()
	_load_characters()
	_load_upgrades()
	_load_bosses()
	_load_items()
	_load_concepts()

func _read_json_dir(dir_path: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("DataLoader: フォルダが見つかりません -> %s" % dir_path)
		return results
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var file := FileAccess.open(dir_path + file_name, FileAccess.READ)
			if file:
				var parsed = JSON.parse_string(file.get_as_text())
				if typeof(parsed) == TYPE_DICTIONARY:
					results.append(parsed)
				else:
					push_warning("DataLoader: JSON解析失敗 -> %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results

func _load_enemies() -> void:
	for entry in _read_json_dir(ENEMY_DIR):
		var data := EnemyData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.sprite_folder = entry.get("sprite_folder", "")
		data.max_hp = float(entry.get("max_hp", 20.0))
		data.move_speed = float(entry.get("move_speed", 60.0))
		data.contact_damage = float(entry.get("contact_damage", 5.0))
		data.exp_value = int(entry.get("exp_value", 1))
		data.min_elapsed_seconds = float(entry.get("min_elapsed_seconds", 0.0))
		data.special_attack_id = String(entry.get("special_attack_id", ""))
		data.attack_interval = float(entry.get("attack_interval", 1.0))
		data.attack_range = float(entry.get("attack_range", 52.0))
		data.attack_windup = float(entry.get("attack_windup", 0.45))
		enemies[data.id] = data

func _load_weapons() -> void:
	for entry in _read_json_dir(WEAPON_DIR):
		var data := WeaponData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.description = entry.get("description", "")
		data.base_damage = float(entry.get("base_damage", 10.0))
		data.attack_interval = float(entry.get("attack_interval", 1.0))
		data.attack_range = float(entry.get("attack_range", 150.0))
		var required: Array[String] = []
		for f in entry.get("required_fragment_ids", []):
			required.append(String(f))
		data.required_fragment_ids = required
		data.is_relic = bool(entry.get("is_relic", false))
		data.vfx_theme_id = entry.get("vfx_theme_id", "default")
		data.crit_chance = float(entry.get("crit_chance", 0.15))
		data.crit_multiplier = float(entry.get("crit_multiplier", 2.0))
		data.projectile_scene = load(DEFAULT_PROJECTILE_SCENE)
		weapons[data.id] = data

func _load_fragments() -> void:
	for entry in _read_json_dir(FRAGMENT_DIR):
		var data := WeaponFragmentData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.element = entry.get("element", "")
		fragments[data.id] = data

func _load_effect_themes() -> void:
	# .tres は演出テーマの「参照系」を持つため(2.2のハイブリッド方針)、
	# JSONではなくResourceとしてそのままフォルダから読み込む。
	var dir := DirAccess.open(EFFECT_THEME_DIR)
	if dir == null:
		push_warning("DataLoader: フォルダが見つかりません -> %s" % EFFECT_THEME_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var theme: EffectThemeData = load(EFFECT_THEME_DIR + file_name)
			if theme and theme.id != "":
				effect_themes[theme.id] = theme
			else:
				push_warning("DataLoader: 演出テーマ読込失敗 -> %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _load_attack_vfx_effects() -> void:
	var dir := DirAccess.open(ATTACK_VFX_DIR)
	if dir == null:
		push_warning("DataLoader: Attack VFXフォルダが見つかりません -> %s" % ATTACK_VFX_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var data: AttackVFXData = load(ATTACK_VFX_DIR + file_name)
			if data and data.id != "" and data.sprite_sheet:
				attack_vfx_effects[data.id] = data
			else:
				push_warning("DataLoader: Attack VFX読込失敗 -> %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()




func _load_difficulty_curves() -> void:
	# 難易度カーブのJSONは(欠片/武器/敵と違い)1ファイル=1個のオブジェクトではなく
	# breakpointの配列そのものなので、_read_json_dirは使わず専用に読み込む。
	# idは「将来ステージごとに違うカーブを使う」ことを見据え、ファイル名をそのままキーにする
	# (例: data/difficulty/hard.jsonを追加するだけでカーブid "hard" が増える)。
	var dir := DirAccess.open(DIFFICULTY_DIR)
	if dir == null:
		push_warning("DataLoader: フォルダが見つかりません -> %s" % DIFFICULTY_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var file := FileAccess.open(DIFFICULTY_DIR + file_name, FileAccess.READ)
			if file:
				var parsed = JSON.parse_string(file.get_as_text())
				if typeof(parsed) == TYPE_ARRAY:
					var breakpoints: Array = parsed
					breakpoints.sort_custom(
						func(a, b): return float(a.get("time_seconds", 0)) < float(b.get("time_seconds", 0))
					)
					difficulty_curves[file_name.get_basename()] = breakpoints
				else:
					push_warning("DataLoader: JSON解析失敗(difficulty) -> %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _load_characters() -> void:
	for entry in _read_json_dir(CHARACTER_DIR):
		var data := CharacterData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.sprite_folder = entry.get("sprite_folder", "")
		data.max_hp = float(entry.get("max_hp", 100.0))
		data.move_speed = float(entry.get("move_speed", 140.0))
		data.unlock_cost = int(entry.get("unlock_cost", 0))
		data.preferred_element = entry.get("preferred_element", "")
		data.attack_pattern_id = entry.get("attack_pattern_id", "single_shot")
		data.base_damage = float(entry.get("base_damage", 10.0))
		data.attack_interval = float(entry.get("attack_interval", 1.0))
		data.attack_range = float(entry.get("attack_range", 200.0))
		data.vfx_theme_id = entry.get("vfx_theme_id", "default")
		data.crit_chance = float(entry.get("crit_chance", 0.15))
		data.crit_multiplier = float(entry.get("crit_multiplier", 2.0))
		data.attack_pattern_params = entry.get("attack_pattern_params", {})
		data.active_skill_id = entry.get("active_skill_id", "")
		data.active_skill_name = entry.get("active_skill_name", "")
		data.active_skill_icon = entry.get("active_skill_icon", "SK")
		data.active_skill_cooldown = float(entry.get("active_skill_cooldown", 10.0))
		data.active_skill_params = entry.get("active_skill_params", {})
		data.damage_reduction = float(entry.get("damage_reduction", 0.0))
		data.exp_gain_multiplier = float(entry.get("exp_gain_multiplier", 1.0))
		data.pickup_range_multiplier = float(entry.get("pickup_range_multiplier", 1.0))
		data.crit_rate_bonus = float(entry.get("crit_rate_bonus", 0.0))
		data.melee_lifesteal_percent = float(entry.get("melee_lifesteal_percent", 0.0))
		data.melee_lifesteal_cap_per_hit = float(entry.get("melee_lifesteal_cap_per_hit", 0.0))
		data.minion_stat_multiplier = float(entry.get("minion_stat_multiplier", 1.0))
		data.self_damage_multiplier = float(entry.get("self_damage_multiplier", 1.0))
		data.dash_invincible = bool(entry.get("dash_invincible", false))
		characters[data.id] = data

func _load_upgrades() -> void:
	for entry in _read_json_dir(UPGRADE_DIR):
		var data := UpgradeData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.effect_type = entry.get("effect_type", "")
		data.value = float(entry.get("value", 0.0))
		data.description = entry.get("description", "")
		data.icon_path = entry.get("icon_path", "")
		data.category = entry.get("category", "common")
		data.effect_params = entry.get("effect_params", {})
		data.downside_type = entry.get("downside_type", "")
		data.downside_value = float(entry.get("downside_value", 0.0))
		data.class_character_id = entry.get("class_character_id", "")
		data.class_ability_level = int(entry.get("class_ability_level", 0))
		data.class_school = entry.get("class_school", "")
		upgrades[data.id] = data

func get_all_upgrades() -> Array[UpgradeData]:
	var arr: Array[UpgradeData] = []
	for v in upgrades.values():
		arr.append(v)
	return arr

func _load_bosses() -> void:
	var scaling := _read_json_file(BOSS_SCALING_PATH)
	var hp_multiplier := float(scaling.get("hp_multiplier", 1.0))
	var damage_multiplier := float(scaling.get("damage_multiplier", 1.0))
	var speed_multiplier := float(scaling.get("move_speed_multiplier", 1.0))
	for entry in _read_json_dir(BOSS_DIR):
		var data := BossData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.sprite_folder = entry.get("sprite_folder", "")
		data.max_hp = float(entry.get("max_hp", 300.0)) * hp_multiplier
		data.move_speed = float(entry.get("move_speed", 50.0)) * speed_multiplier
		data.contact_damage = float(entry.get("contact_damage", 40.0)) * damage_multiplier
		data.exp_value = int(entry.get("exp_value", 20))
		data.attack_interval = float(entry.get("attack_interval", 1.0))
		data.attack_range = float(entry.get("attack_range", 64.0))
		data.attack_windup = float(entry.get("attack_windup", 0.55))
		data.visual_scale = float(entry.get("visual_scale", 2.2))
		data.attack_pattern_id = entry.get("attack_pattern_id", "")
		data.special_attack_id = entry.get("special_attack_id", "")
		bosses[data.id] = data

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("DataLoader: 設定ファイルが見つかりません -> %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func get_all_bosses() -> Array[BossData]:
	var arr: Array[BossData] = []
	for v in bosses.values():
		arr.append(v)
	return arr

func _load_items() -> void:
	for entry in _read_json_dir(ITEM_DIR):
		var data := ItemData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.effect_type = entry.get("effect_type", "")
		data.value = float(entry.get("value", 0.0))
		data.icon_path = entry.get("icon_path", "")
		data.is_special = bool(entry.get("is_special", false))
		data.description = entry.get("description", "")
		items[data.id] = data

func get_all_items() -> Array[ItemData]:
	var arr: Array[ItemData] = []
	for v in items.values():
		arr.append(v)
	return arr

func _load_concepts() -> void:
	for entry in _read_json_dir(CONCEPT_DIR):
		var data := ConceptData.new()
		data.id = entry.get("id", "")
		data.display_name = entry.get("display_name", "")
		data.concept_type = entry.get("concept_type", "trigger")
		data.description = entry.get("description", "")
		var tags: Array[String] = []
		for tag in entry.get("element_tags", []):
			tags.append(String(tag))
		data.element_tags = tags
		data.params = entry.get("params", {})
		if data.id != "":
			concepts[data.id] = data

func get_all_concepts() -> Array[ConceptData]:
	var arr: Array[ConceptData] = []
	for value in concepts.values():
		arr.append(value)
	return arr

func get_concept(concept_id: String) -> ConceptData:
	return concepts.get(concept_id)

func get_all_characters() -> Array[CharacterData]:
	var arr: Array[CharacterData] = []
	for v in characters.values():
		arr.append(v)
	return arr

func get_all_enemies() -> Array[EnemyData]:
	var arr: Array[EnemyData] = []
	for v in enemies.values():
		arr.append(v)
	return arr

func get_all_weapons() -> Array[WeaponData]:
	var arr: Array[WeaponData] = []
	for v in weapons.values():
		arr.append(v)
	return arr
