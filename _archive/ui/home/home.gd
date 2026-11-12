extends Control
class_name HomeScreen
## ホーム画面: title.tscn → home.tscn → game.tscn の中継地点。
## 上段に5分サバイバルの出撃先（3ステージ、ボス候補の肖像付き）、下段に正式6職業を
## 3列×2行のグリッドで並べる。どちらも継承の欠片で解放する。
## 解放済みの職業を選ぶとGameManager.selected_character_idに記録してgame.tscnへ、
## 未解放のセル／カードはタップで解放を試みる(コスト不足なら何もしない)。

@onready var currency_label: Label = $MarginContainer/VBoxContainer/CurrencyLabel
@onready var stage_row: HBoxContainer = $MarginContainer/VBoxContainer/StageRow
@onready var character_grid: GridContainer = $MarginContainer/VBoxContainer/CenterContainer/CharacterGrid

## 1600x900基準: ステージ3枚＋職業6枚を1画面へ収める。
const CELL_SIZE := Vector2(350, 225)
const STAGE_CARD_SIZE := Vector2(470, 112)
const STAGE_PORTRAIT_SIZE := Vector2(68, 68)
## カード内の配置枠(CenterContainer)のサイズ。
const PORTRAIT_FRAME_SIZE := Vector2(230, 92)
## ポートレート原寸(_Idle.pngの1コマ)は100x100だが、実際に描かれた絵はその一部
## (SpriteSheetBuilder.build_portrait_texture()が不透明ピクセルの外接矩形へ切り詰め済み)。
## 整数倍に近い拡大で粗さが目立ちすぎない大きさにする。
const PORTRAIT_SIZE := Vector2(92, 92)
const NAME_FONT_SIZE := 28
const SUB_FONT_SIZE := 20
## 未解放セルのポートレートに掛けるmodulate(彩度を落としたグレースケール調)。
const LOCKED_PORTRAIT_MODULATE := Color(0.45, 0.45, 0.45, 1.0)
const UNLOCKED_PORTRAIT_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const SUBTEXT_COLOR := Color(0.75, 0.75, 0.8, 1.0)
const STAGE_NAME_COLOR := Color(0.98, 0.87, 0.59, 1.0)

var _maps: Array = []
## Phase 4：拠点の装備・鍛造。持ち越し装備を載せた隠しPlayer（LoadoutPlayer）に
## ラン中と同じEquipmentScreenを被せる。閉じたらSaveManagerへ書き戻す。
var _loadout_player: Player
var _equipment_screen: EquipmentScreen
var _meta_label: Label
var _forge_button: Button

func _ready() -> void:
	PixelUIStyle.apply_tree(self)
	PixelUIStyle.add_ornament($MarginContainer/VBoxContainer/HeaderCrest, "emblem")
	var heading := $MarginContainer/VBoxContainer/TitleLabel as Label
	heading.custom_minimum_size = Vector2(520, 50)
	heading.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	PixelUIStyle.FrameArt.plaque(heading)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/exploration_run.json"))
	_maps = config.get("maps", [])
	if not SaveManager.is_map_unlocked(GameManager.selected_survival_map):
		GameManager.selected_survival_map = 1
	_setup_loadout()
	_refresh()
	AudioManager.play_bgm("home_theme")

func _setup_loadout() -> void:
	# 1行に収める（ホームは1画面固定）：左に深度・次の目標、右に装備・鍛造ボタン。
	var column := $MarginContainer/VBoxContainer as VBoxContainer
	var row := HBoxContainer.new()
	row.name = "LoadoutRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	column.move_child(row, currency_label.get_index() + 1)
	_meta_label = Label.new()
	_meta_label.name = "MetaLabel"
	_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_meta_label.add_theme_font_size_override("font_size", 19)
	_meta_label.add_theme_color_override("font_color", STAGE_NAME_COLOR)
	row.add_child(_meta_label)
	_forge_button = Button.new()
	_forge_button.name = "ForgeButton"
	_forge_button.custom_minimum_size = Vector2(380, 38)
	_forge_button.add_theme_font_size_override("font_size", 18)
	PixelUIStyle.apply_button(_forge_button, Color("d48742"))
	_forge_button.pressed.connect(_on_forge_pressed)
	row.add_child(_forge_button)
	# 隠しPlayer：EquipmentScreenは"player"グループの最初のノードからEquipmentComponentを取る。
	_loadout_player = preload("res://entities/player/player.tscn").instantiate() as Player
	_loadout_player.name = "LoadoutPlayer"
	_loadout_player.visible = false
	_loadout_player.position = Vector2(-4000, -4000)
	_loadout_player.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := _loadout_player.get_node_or_null("Camera2D") as Camera2D
	if camera: camera.enabled = false
	add_child(_loadout_player)
	_loadout_player.equipment_component.restore_from_save()
	_equipment_screen = preload("res://ui/equipment/equipment_screen.tscn").instantiate() as EquipmentScreen
	_equipment_screen.name = "HomeEquipmentScreen"
	add_child(_equipment_screen)
	_equipment_screen.closed.connect(_on_forge_closed)

func _carried_summary() -> Dictionary:
	var payload := SaveManager.get_persistent_equipment()
	return {"equipped": Dictionary(payload.get("equipped", {})).size(), "inventory": Array(payload.get("inventory", [])).size()}

## 深度・次の目標・持ち越し装備の1行（何を目指すかの可視化）。
func _refresh_meta() -> void:
	if _meta_label == null:
		return
	var depth := SaveManager.get_survival_depth()
	var target := GameManager.selected_survival_map
	var entry: Dictionary = {}
	for candidate in _maps:
		if int(candidate.get("index", 0)) == target: entry = candidate
	var objective := "MAP%d %s を攻略して深度%dへ" % [target, String(entry.get("display_name", "")), depth + 1]
	var next_locked := -1
	for candidate in _maps:
		var index := int(candidate.get("index", 0))
		if not SaveManager.is_map_unlocked(index) and next_locked < 0: next_locked = index
	if next_locked > 0 and depth >= next_locked:
		objective += "　／　封印解除 MAP%d（◆%d）" % [next_locked, int(_maps[next_locked - 1].get("unlock_cost", 0))]
	var carried := _carried_summary()
	_meta_label.text = "深度 %d　・　次の目標：%s" % [depth, objective]
	if _forge_button:
		_forge_button.text = "装備・鍛造　持ち越し %d点（装備中 %d）" % [int(carried.inventory) + int(carried.equipped), int(carried.equipped)]

func _on_forge_pressed() -> void:
	if _equipment_screen == null or _equipment_screen.is_open():
		return
	AudioManager.play_sfx("ui_click")
	_equipment_screen._open()

func _on_forge_closed() -> void:
	if _loadout_player:
		_loadout_player.equipment_component.store_for_next_run(true)
	_refresh_meta()

func _refresh() -> void:
	currency_label.text = "継承の欠片　◆ %d" % int(SaveManager.data.get("meta_currency", 0))
	_refresh_meta()

	for child in stage_row.get_children():
		child.queue_free()
	for entry in _maps:
		stage_row.add_child(_build_stage_card(entry))

	for child in character_grid.get_children():
		child.queue_free()
	var characters := DataLoader.get_all_characters().filter(func(data): return data.id in GameManager.PLAYABLE_CHARACTER_IDS)
	characters.sort_custom(func(a, b): return a.unlock_cost < b.unlock_cost)
	for character_data in characters:
		character_grid.add_child(_build_character_cell(character_data))
	if character_grid.get_child_count() > 0:
		(character_grid.get_child(0) as Button).grab_focus.call_deferred()

# ============================================================
# 出撃先（ステージ）カード
# ============================================================

## ボス候補2体の肖像、ステージ名、特徴、解放状態／補給の時刻を1枚に収める。
func _build_stage_card(entry: Dictionary) -> Button:
	var index := int(entry.get("index", 1))
	var unlocked := SaveManager.is_map_unlocked(index)
	var selected := unlocked and GameManager.selected_survival_map == index
	var cost := int(entry.get("unlock_cost", 0))
	var affordable := int(SaveManager.data.get("meta_currency", 0)) >= cost

	var button := Button.new()
	button.name = "Stage%d" % index
	button.custom_minimum_size = STAGE_CARD_SIZE
	button.text = ""
	button.focus_mode = Control.FOCUS_ALL
	var accent: Color = PixelUIStyle.JEWEL if selected else (PixelUIStyle.BORDER_HOVER if unlocked else PixelUIStyle.STONE)
	_apply_cell_style(button, accent)
	if selected:
		button.add_theme_stylebox_override("normal", PixelUIStyle.FrameArt.box(true, 14, Color(0.85, 1.15, 1.1)))
	button.tooltip_text = String(entry.get("stage_note", ""))
	button.pressed.connect(_on_stage_pressed.bind(entry))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.offset_top = 10
	row.offset_bottom = -10
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var portraits := HBoxContainer.new()
	portraits.add_theme_constant_override("separation", 4)
	portraits.alignment = BoxContainer.ALIGNMENT_CENTER
	portraits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portraits)
	for boss_id in entry.get("boss_candidates", []):
		var enemy: EnemyData = DataLoader.enemies.get(boss_id)
		if enemy == null:
			continue
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = STAGE_PORTRAIT_SIZE
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.texture = SpriteSheetBuilder.build_portrait_texture(enemy.sprite_folder)
		portrait.modulate = UNLOCKED_PORTRAIT_MODULATE if unlocked else LOCKED_PORTRAIT_MODULATE
		portrait.tooltip_text = "終盤ボス候補　%s" % enemy.display_name
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portraits.add_child(portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var name_label := Label.new()
	name_label.text = ("▶ " if selected else "") + "%d　%s" % [index, String(entry.get("display_name", ""))]
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", STAGE_NAME_COLOR if unlocked else PixelUIStyle.DISABLED)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var tagline := Label.new()
	tagline.text = String(entry.get("tagline", ""))
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", SUBTEXT_COLOR)
	tagline.clip_text = true
	tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tagline)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 18)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unlocked:
		var supplies: Array = entry.get("survival_supply_seconds", [])
		var marks: Array[String] = []
		for seconds in supplies:
			marks.append("%d:%02d" % [int(seconds) / 60, int(seconds) % 60])
		status.text = ("出撃先　" if selected else "") + "補給 " + " / ".join(marks)
		status.add_theme_color_override("font_color", PixelUIStyle.JEWEL if selected else SUBTEXT_COLOR)
		if not selected:
			button.tooltip_text = "決定でこのステージを出撃先にする
" + button.tooltip_text
	else:
		status.text = "封印解除　◆ %d" % cost + ("　決定で解放" if affordable else "　欠片が足りない")
		status.add_theme_color_override("font_color", PixelUIStyle.JEWEL if affordable else PixelUIStyle.DISABLED)
	column.add_child(status)
	return button

func _on_stage_pressed(entry: Dictionary) -> void:
	var index := int(entry.get("index", 1))
	if SaveManager.is_map_unlocked(index):
		AudioManager.play_sfx("ui_click")
		GameManager.selected_survival_map = index
		_refresh()
		_focus_stage(index)
		return
	if SaveManager.unlock_map(index, int(entry.get("unlock_cost", 0))):
		AudioManager.play_sfx("ui_click")
		GameManager.selected_survival_map = index
		_refresh()
		_focus_stage(index)

func _focus_stage(index: int) -> void:
	var card := stage_row.get_node_or_null("Stage%d" % index) as Button
	if card:
		card.grab_focus.call_deferred()

# ============================================================
# 職業カード
# ============================================================

## ポートレート+職業名+(未解放時)鍵アイコン・解放コストの1セルを組み立てる。
## Buttonの.textは使わず、子にVBoxContainerを重ねる(item_select.gd等と同じ、
## クリックがボタン自体に通るよう子のmouse_filterをIGNOREにする構成)。
func _build_character_cell(character_data: CharacterData) -> Button:
	var unlocked := SaveManager.is_character_unlocked(character_data.id)

	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.text = ""
	button.focus_mode = Control.FOCUS_ALL
	var accent: Color = PixelUIStyle.JEWEL if unlocked else PixelUIStyle.STONE
	_apply_cell_style(button, accent, true)
	button.pressed.connect(_on_character_pressed.bind(character_data))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	button.add_child(vbox)

	var portrait_wrap := CenterContainer.new()
	portrait_wrap.custom_minimum_size = PORTRAIT_FRAME_SIZE
	portrait_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(portrait_wrap)

	var portrait := HoverAttackPortrait.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# expand_mode既定(EXPAND_KEEP_SIZE)だとテクスチャ本来のサイズ(1コマ=100x100)を
	# 最小サイズとして扱ってしまい、custom_minimum_size/stretch_modeで意図した
	# 拡大表示が反映されないため、テクスチャ本来のサイズを無視させる。
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.modulate = UNLOCKED_PORTRAIT_MODULATE if unlocked else LOCKED_PORTRAIT_MODULATE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 多コマのスプライトシートをそのまま表示すると複数キャラクターが横に
	# 並んで見えてしまうため、SpriteSheetBuilderで1コマ目だけ切り出す(通常時の静止画)。
	var idle_texture := SpriteSheetBuilder.build_portrait_texture(character_data.sprite_folder)
	# 解放済みのカードだけ、カードにマウスカーソルが乗っている間
	# 攻撃アニメーションをループ再生する(未解放カードは鍵アイコン表示のまま
	# 対象外とする)。
	if unlocked:
		var hover_data := SpriteSheetBuilder.build_hover_attack_frames(character_data.sprite_folder)
		var attack_frames: Array[Texture2D] = []
		for frame in hover_data.get("attack_frames", []):
			attack_frames.append(frame)
		var fps: float = hover_data.get("fps", 10.0)
		portrait.configure(idle_texture, attack_frames, fps)
		button.mouse_entered.connect(portrait.start_attack)
		button.mouse_exited.connect(portrait.stop_attack)
	else:
		portrait.configure(idle_texture, [], 10.0)
	portrait_wrap.add_child(portrait)

	var name_label := Label.new()
	name_label.text = character_data.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	vbox.add_child(name_label)

	var sub_label := Label.new()
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", 18)
	sub_label.add_theme_color_override("font_color", SUBTEXT_COLOR)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_label.text = "固有技　%s" % PixelUIStyle.localized_name(character_data.active_skill_name) if unlocked else "封印解除　◆ %d" % character_data.unlock_cost
	vbox.add_child(sub_label)
	if unlocked:
		# 熟練（Phase 4）：累計ポイントと段階、持ち込みの内容。
		var mastery_label := Label.new()
		mastery_label.name = "Mastery"
		mastery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mastery_label.add_theme_font_size_override("font_size", 16)
		mastery_label.add_theme_color_override("font_color", PixelUIStyle.JEWEL)
		mastery_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mastery_label.text = _mastery_text(character_data.id)
		vbox.add_child(mastery_label)

	var action_label := Label.new()
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_label.add_theme_font_size_override("font_size", 18)
	action_label.add_theme_color_override("font_color", accent if unlocked else PixelUIStyle.DISABLED)
	action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_label.text = "決定で出撃" if unlocked else "欠片を捧げて解放"
	vbox.add_child(action_label)

	return button

func _mastery_text(character_id: String) -> String:
	var points := SaveManager.get_class_mastery(character_id)
	var tier := SaveManager.get_mastery_tier(character_id)
	var memory := SaveManager.get_class_memory(character_id)
	var perks: Array[String] = []
	if tier >= 1: perks.append("技Lv2開始")
	if tier >= 2:
		var upgrade: UpgradeData = DataLoader.upgrades.get(String(memory.get("first_upgrade", "")))
		perks.append("持込 " + (upgrade.display_name if upgrade else "強化"))
	if tier >= 3: perks.append("HP+10%")
	var next_threshold := int(SaveManager.MASTERY_TIERS[tier]) if tier < SaveManager.MASTERY_TIERS.size() else -1
	var progress := "次の段階まで %d" % (next_threshold - points) if next_threshold > 0 else "最大"
	return "熟練 %d（%s）%s" % [points, "・".join(perks) if not perks.is_empty() else progress, "　" + progress if not perks.is_empty() and next_threshold > 0 else ""]

## 通常/ホバー/選択中(フォーカス)で枠線の色を変える(ホバー・選択中セルの
## ハイライト表示)。
func _apply_cell_style(button: Button, accent: Color, major: bool = false) -> void:
	PixelUIStyle.apply_button(button, accent)
	button.add_theme_stylebox_override("normal", PixelUIStyle.FrameArt.box(not major, 20 if major else 14))
	button.add_theme_stylebox_override("hover", PixelUIStyle.FrameArt.box(not major, 20 if major else 14, Color(0.85, 1.15, 1.1)))

func _on_character_pressed(character_data: CharacterData) -> void:
	if character_data.id not in GameManager.PLAYABLE_CHARACTER_IDS:
		return
	AudioManager.play_sfx("ui_click")
	if SaveManager.is_character_unlocked(character_data.id):
		GameManager.selected_character_id = character_data.id
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		return
	# 解放を試みる。コスト不足ならSaveManager側で何もせずfalseを返すだけ。
	if SaveManager.unlock_character(character_data.id, character_data.unlock_cost):
		_refresh()
