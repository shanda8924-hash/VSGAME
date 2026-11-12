extends Control
## 3つ揃えて消すパズルの試作。戦闘は無い。
## 職業のマスを揃えるとその職業が右の部屋に召喚され、強化のマスを揃えるとその強化が1段上がる（効果はまだ無い）。
## 4つ以上の並びは1つ多いごとに報酬が1増える。連鎖は続けて数える。
## 部屋のキャラクターをタップすると右のパネルにステータスが出る。同じ職業が揃っていれば「融合して転職」できる。

const UNIT_SCENE := preload("res://entities/player/player.tscn")
const UNIT_COLUMNS := 5
const UNIT_ORIGIN := Vector2(48, 58)
const UNIT_SPACING := Vector2(76, 80)
const UNIT_SCALE := Vector2(1.6, 1.6)
const PICK_RADIUS := 42.0

@onready var board_view: MatchBoardView = %BoardView
@onready var units_root: Node2D = %Units
@onready var room_panel: Control = %RoomPanel
@onready var status_panel: VBoxContainer = %StatusPanel
@onready var summon_label: Label = %SummonLabel
@onready var upgrade_label: Label = %UpgradeLabel
@onready var message_label: Label = %MessageLabel
@onready var move_label: Label = %MoveLabel
@onready var restart_button: Button = %RestartButton

var model: MatchBoard
var army: Army
var moves := 0
var best_chain := 0
## 職業ID → これまでに召喚した数。強化ID → 段階。
var summoned := {}
var upgrades := {}
## 部屋に立っているキャラクター（army.units と同じ並び）と、通し番号 → ノード。
var units: Array[Player] = []
var _unit_nodes := {}
var selected_uid := -1
var fusions := 0

# ステータスパネルの部品
var status_icon: TextureRect
var status_name: Label
var status_tier: Label
var status_stats: Label
var status_promotion: Label
var fuse_button: Button
var _ring: SelectionRing

func _ready() -> void:
	_build_status_panel()
	_ring = SelectionRing.new()
	_ring.visible = false
	room_panel.add_child(_ring)
	room_panel.move_child(_ring, 0)
	room_panel.gui_input.connect(_on_room_input)
	board_view.groups_cleared.connect(_on_groups_cleared)
	board_view.resolved.connect(_on_resolved)
	board_view.swap_rejected.connect(func(_a: int, _b: int): message_label.text = "そこは揃わない")
	board_view.reshuffled.connect(func(): message_label.text = "動かせる手が無いので並べ直した")
	restart_button.pressed.connect(func(): start())
	fuse_button.pressed.connect(fuse_selected)
	start()

func start(seed_value: int = -1) -> void:
	model = MatchBoard.new(seed_value)
	army = Army.new(int(model.config.get("max_army", 20)))
	moves = 0
	best_chain = 0
	fusions = 0
	summoned.clear()
	upgrades.clear()
	selected_uid = -1
	_sync_units()
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
			var joined := 0
			for index in amount:
				if add_unit(character.id) >= 0:
					joined += 1
			if joined == amount:
				parts.append("%sが揃った！ %sを%d体 召喚" % [character.icon_name, character.display_name, amount])
			else:
				parts.append("%sが揃ったが、軍がいっぱい（融合で空きを作る）" % character.icon_name)
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

## 軍に1体加えて部屋に立たせる。満員なら -1。
func add_unit(character_id: String) -> int:
	var uid := army.add(character_id)
	if uid >= 0:
		_sync_units()
		_refresh()
	return uid

## 選択中のキャラクターを、同じ職業の仲間と融合して転職させる。
func fuse_selected() -> bool:
	var before := army.character_of(selected_uid)
	var new_uid := army.fuse(selected_uid)
	if new_uid < 0:
		return false
	fusions += 1
	selected_uid = new_uid
	_sync_units()
	var after := army.character_of(new_uid)
	message_label.text = "%s %d体が融合 → %sに転職！" % [before.display_name, before.fusion_count, after.display_name]
	var node: Player = _unit_nodes.get(new_uid)
	if node:
		node.scale = UNIT_SCALE * 1.6
		node.create_tween().tween_property(node, "scale", UNIT_SCALE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh()
	return true

func select_unit(uid: int) -> void:
	selected_uid = uid if army.index_of(uid) >= 0 else -1
	_refresh()

## army.units に合わせて部屋のノードを作り直す（残っている通し番号のノードは使い回す）。
func _sync_units() -> void:
	var alive := {}
	for unit in army.units:
		alive[int(unit.uid)] = true
	for uid in _unit_nodes.keys():
		if not alive.has(uid):
			(_unit_nodes[uid] as Node).queue_free()
			units_root.remove_child(_unit_nodes[uid])
			_unit_nodes.erase(uid)
	units.clear()
	for index in army.units.size():
		var uid := int(army.units[index].uid)
		var node: Player = _unit_nodes.get(uid)
		if node == null:
			node = UNIT_SCENE.instantiate() as Player
			units_root.add_child(node)
			node.apply_character(DataLoader.characters[String(army.units[index].id)])
			# 部屋に並べて見せるだけなので、互いに押し合わないよう当たり判定と物理処理を切る。
			node.collision_layer = 0
			node.collision_mask = 0
			node.set_physics_process(false)
			node.scale = Vector2.ZERO
			node.create_tween().tween_property(node, "scale", UNIT_SCALE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_unit_nodes[uid] = node
		node.position = slot_position(index)
		units.append(node)
	if army.index_of(selected_uid) < 0:
		selected_uid = -1

func slot_position(index: int) -> Vector2:
	return UNIT_ORIGIN + Vector2(index % UNIT_COLUMNS, index / UNIT_COLUMNS) * UNIT_SPACING

func _on_room_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var best := -1
		var best_distance := PICK_RADIUS
		for index in army.units.size():
			var distance: float = slot_position(index).distance_to(event.position)
			if distance < best_distance:
				best_distance = distance
				best = int(army.units[index].uid)
		select_unit(best)
		room_panel.accept_event()

func _build_status_panel() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	status_panel.add_child(header)
	status_icon = TextureRect.new()
	status_icon.custom_minimum_size = Vector2(64, 64)
	status_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	header.add_child(status_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	status_name = Label.new()
	status_name.add_theme_font_size_override("font_size", 26)
	titles.add_child(status_name)
	status_tier = Label.new()
	status_tier.add_theme_font_size_override("font_size", 22)
	status_tier.add_theme_color_override("font_color", Color("f6d860"))
	titles.add_child(status_tier)
	status_stats = Label.new()
	status_stats.add_theme_font_size_override("font_size", 22)
	status_panel.add_child(status_stats)
	status_promotion = Label.new()
	status_promotion.add_theme_font_size_override("font_size", 20)
	status_promotion.add_theme_color_override("font_color", Color("b8e0a0"))
	status_promotion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_promotion.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_panel.add_child(status_promotion)
	fuse_button = Button.new()
	fuse_button.custom_minimum_size = Vector2(0, 52)
	fuse_button.add_theme_font_size_override("font_size", 22)
	fuse_button.text = "融合して転職"
	status_panel.add_child(fuse_button)

func _refresh_status() -> void:
	var character := army.character_of(selected_uid)
	_ring.visible = character != null
	if character == null:
		status_icon.texture = null
		status_name.text = "ステータス"
		status_tier.text = ""
		status_stats.text = ""
		status_promotion.text = "部屋のキャラクターをタップ"
		fuse_button.visible = false
		return
	_ring.position = slot_position(army.index_of(selected_uid)) + Vector2(0, 26)
	status_icon.texture = load(character.icon_path) as Texture2D if ResourceLoader.exists(character.icon_path) else null
	status_name.text = character.display_name
	status_tier.text = "★".repeat(character.tier) + "☆".repeat(maxi(3 - character.tier, 0))
	status_stats.text = "HP　%d\n移動速度　%d" % [roundi(character.max_hp), roundi(character.move_speed)]
	var target := army.promotion_of(selected_uid)
	fuse_button.visible = target != null
	if target == null:
		status_promotion.text = "最上位（これ以上の転職なし）"
	else:
		var have := army.count_of(character.id)
		status_promotion.text = "転職先　%s\n%s %d / %d\n%s" % [target.display_name, character.display_name, mini(have, character.fusion_count), character.fusion_count, "融合できる！" if army.can_fuse(selected_uid) else "あと%d体で融合" % (character.fusion_count - have)]
		fuse_button.disabled = not army.can_fuse(selected_uid)

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
	move_label.text = "手数 %d　・　最大 %d連鎖　・　軍 %d / %d　・　転職 %d回" % [moves, best_chain, army.units.size(), army.capacity, fusions]
	_refresh_status()

## 選択中のキャラクターの足元に出す輪。
class SelectionRing extends Node2D:
	func _draw() -> void:
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, Color("fff2b0"), 4.0)
