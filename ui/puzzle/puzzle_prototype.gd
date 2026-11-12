extends Control
## 3つ揃えて消すパズルの試作。戦闘は無い。
## 職業のマスを揃えるとその職業が右の部屋に召喚され、強化のマスを揃えるとその強化が1段上がる（効果はまだ無い）。
## 4つ以上の並びは1つ多いごとに報酬が1増える。連鎖は続けて数える。

const UNIT_SCENE := preload("res://entities/player/player.tscn")
const UNIT_COLUMNS := 8
const UNIT_SPACING := Vector2(76, 82)
const UNIT_SCALE := Vector2(1.6, 1.6)

@onready var board_view: MatchBoardView = %BoardView
@onready var units_root: Node2D = %Units
@onready var room_panel: Control = %RoomPanel
@onready var summon_label: Label = %SummonLabel
@onready var upgrade_label: Label = %UpgradeLabel
@onready var message_label: Label = %MessageLabel
@onready var move_label: Label = %MoveLabel
@onready var restart_button: Button = %RestartButton

var model: MatchBoard
var moves := 0
var best_chain := 0
## 職業ID → 召喚した数。強化ID → 段階。
var summoned := {}
var upgrades := {}
var units: Array[Player] = []

func _ready() -> void:
	board_view.groups_cleared.connect(_on_groups_cleared)
	board_view.resolved.connect(_on_resolved)
	board_view.swap_rejected.connect(func(_a: int, _b: int): message_label.text = "そこは揃わない")
	board_view.reshuffled.connect(func(): message_label.text = "動かせる手が無いので並べ直した")
	restart_button.pressed.connect(func(): start())
	start()

func start(seed_value: int = -1) -> void:
	model = MatchBoard.new(seed_value)
	moves = 0
	best_chain = 0
	summoned.clear()
	upgrades.clear()
	for unit in units:
		unit.queue_free()
	units.clear()
	board_view.bind(model)
	message_label.text = "隣のマスと入れ替えて、同じ絵を3つ並べる"
	_refresh()

func _on_groups_cleared(groups: Array, chain: int) -> void:
	var parts: Array[String] = []
	for group in groups:
		var data := model.kind_data(int(group.kind))
		var amount := model.reward_for(group)
		if String(data.get("type", "")) == "unit":
			var character: CharacterData = DataLoader.characters.get(String(data.get("character", "")))
			if character == null:
				continue
			summoned[character.id] = int(summoned.get(character.id, 0)) + amount
			for index in amount:
				_spawn_unit(character)
			parts.append("%sが揃った！ %sを%d体 召喚" % [character.icon_name, character.display_name, amount])
		else:
			var id := String(data.get("id", ""))
			upgrades[id] = int(upgrades.get(id, 0)) + amount
			parts.append("%s +%d" % [String(data.get("name", id)), amount])
	message_label.text = ("%d連鎖！　" % chain if chain >= 2 else "") + "、".join(parts)
	_refresh()

func _on_resolved(chain: int) -> void:
	moves += 1
	best_chain = maxi(best_chain, chain)
	_refresh()

## 召喚した職業を部屋に立たせる（待機アニメ）。表示の上限を超えた分は数だけ増える。
func _spawn_unit(character: CharacterData) -> void:
	if units.size() >= int(model.config.get("max_units_shown", 32)):
		return
	var unit := UNIT_SCENE.instantiate() as Player
	units_root.add_child(unit)
	unit.apply_character(character)
	var slot := units.size()
	unit.position = Vector2(54 + (slot % UNIT_COLUMNS) * UNIT_SPACING.x, 56 + (slot / UNIT_COLUMNS) * UNIT_SPACING.y)
	unit.scale = Vector2.ZERO
	unit.create_tween().tween_property(unit, "scale", UNIT_SCALE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	units.append(unit)

func _refresh() -> void:
	var unit_parts: Array[String] = []
	var upgrade_parts: Array[String] = []
	for kind in model.kinds.size():
		var data := model.kind_data(kind)
		if String(data.get("type", "")) == "unit":
			var character: CharacterData = DataLoader.characters.get(String(data.get("character", "")))
			if character:
				unit_parts.append("%s ×%d" % [character.display_name, int(summoned.get(character.id, 0))])
		else:
			upgrade_parts.append("%s Lv.%d" % [String(data.get("name", "")), int(upgrades.get(String(data.get("id", "")), 0))])
	summon_label.text = "召喚　" + "　".join(unit_parts)
	upgrade_label.text = "強化　" + "　".join(upgrade_parts)
	move_label.text = "手数 %d　・　最大 %d連鎖" % [moves, best_chain]
