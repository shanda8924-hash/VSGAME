extends Control
class_name HomeScreen
## ホーム画面: title.tscn → home.tscn → game.tscn の中継地点。
## 10職業を5列×2行のグリッドに並べ、各セルへポートレート(1コマ切り出し)・
## 職業名・(未解放の場合)鍵アイコンと解放コストを表示する
## (ドラゴンクエストの記念画像のような「複数キャラクターのポートレートを
## グリッドに整列させる」レイアウトを参考にした構成。特定作品のデザインの
## 模倣ではなく、レイアウトの考え方のみを踏襲している)。
## 解放済みのセルを選ぶとGameManager.selected_character_idに記録してgame.tscnへ、
## 未解放のセルはタップで解放を試みる(コスト不足なら何もしない)。

@onready var currency_label: Label = $MarginContainer/VBoxContainer/CurrencyLabel
@onready var character_grid: GridContainer = $MarginContainer/VBoxContainer/CenterContainer/CharacterGrid

## 1600x900基準: 5列+横間隔の合計を1520px、2段+縦間隔を698pxに収める。
## 1920x1080などではCenterContainerにより同じグリッドを中央配置する。
const CELL_SIZE := Vector2(288, 340)
## カード内の配置枠(CenterContainer)のサイズ。カードのレイアウト・名前ラベル
## との間隔はこの値を基準に決まるため、ポートレートの表示スケールを変えても
## 動かさない。
const PORTRAIT_FRAME_SIZE := Vector2(230, 230)
## ポートレート原寸(_Idle.pngの1コマ)は100x100だが、実際に描かれた絵は
## そのごく一部(SpriteSheetBuilder.build_portrait_texture()が不透明ピクセルの
## 外接矩形へ切り詰め済み)。TextureRect側は正方形の表示サイズだけを持ち、
## STRETCH_KEEP_ASPECT_CENTEREDでこのサイズいっぱいまでアスペクト比を保って
## 拡大する(project.godotのdefault_texture_filter=0(Nearest)により、拡大
## してもドット絵の輪郭はにじまない)。
## ドット絵の粗さが目立ちすぎないよう、配置枠に対して2/3のサイズで表示する
## (配置枠はPORTRAIT_FRAME_SIZEのままなのでCenterContainerが自動的に中央配置する)。
const PORTRAIT_DISPLAY_SCALE := 200.0 / 230.0
const PORTRAIT_SIZE := PORTRAIT_FRAME_SIZE * PORTRAIT_DISPLAY_SCALE
const LOCK_ICON_FONT_SIZE := 120
const NAME_FONT_SIZE := 28
const SUB_FONT_SIZE := 20
## 未解放セルのポートレートに掛けるmodulate(彩度を落としたグレースケール調)。
const LOCKED_PORTRAIT_MODULATE := Color(0.45, 0.45, 0.45, 1.0)
const UNLOCKED_PORTRAIT_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const NORMAL_BORDER_COLOR := Color(0.35, 0.35, 0.42, 1.0)
const HOVER_BORDER_COLOR := Color(0.9, 0.85, 0.4, 1.0)
const SUBTEXT_COLOR := Color(0.75, 0.75, 0.8, 1.0)

func _ready() -> void:
	_refresh()
	PixelUIStyle.apply_tree(self)
	AudioManager.play_bgm("home_theme")

func _refresh() -> void:
	currency_label.text = "所持メタ通貨: %d" % int(SaveManager.data.get("meta_currency", 0))

	for child in character_grid.get_children():
		child.queue_free()

	var characters := DataLoader.get_all_characters()
	characters.sort_custom(func(a, b): return a.unlock_cost < b.unlock_cost)
	for character_data in characters:
		character_grid.add_child(_build_character_cell(character_data))
	if character_grid.get_child_count() > 0:
		(character_grid.get_child(0) as Button).grab_focus.call_deferred()

## ポートレート+職業名+(未解放時)鍵アイコン・解放コストの1セルを組み立てる。
## Buttonの.textは使わず、子にVBoxContainerを重ねる(item_select.gd等と同じ、
## クリックがボタン自体に通るよう子のmouse_filterをIGNOREにする構成)。
func _build_character_cell(character_data: CharacterData) -> Button:
	var unlocked := SaveManager.is_character_unlocked(character_data.id)

	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.text = ""
	button.focus_mode = Control.FOCUS_ALL
	_apply_cell_style(button)
	button.pressed.connect(_on_character_pressed.bind(character_data))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
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

	if not unlocked:
		var lock_label := Label.new()
		lock_label.text = "🔒"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_label.add_theme_font_size_override("font_size", LOCK_ICON_FONT_SIZE)
		lock_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_wrap.add_child(lock_label)

	var name_label := Label.new()
	name_label.text = character_data.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	vbox.add_child(name_label)

	var sub_label := Label.new()
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", SUB_FONT_SIZE)
	sub_label.add_theme_color_override("font_color", SUBTEXT_COLOR)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_label.text = "選択してスタート" if unlocked else "解放コスト: %d" % character_data.unlock_cost
	vbox.add_child(sub_label)

	return button

## 通常/ホバー/選択中(フォーカス)で枠線の色を変える(ホバー・選択中セルの
## ハイライト表示)。
func _apply_cell_style(button: Button) -> void:
	PixelUIStyle.apply_button(button, NORMAL_BORDER_COLOR)

func _on_character_pressed(character_data: CharacterData) -> void:
	AudioManager.play_sfx("ui_click")
	if SaveManager.is_character_unlocked(character_data.id):
		GameManager.selected_character_id = character_data.id
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		return
	# 解放を試みる。コスト不足ならSaveManager側で何もせずfalseを返すだけ。
	if SaveManager.unlock_character(character_data.id, character_data.unlock_cost):
		_refresh()
