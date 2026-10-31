extends CanvasLayer
class_name ItemSelect
## ボス撃破時の戦利品選択UI(level_up_select.gdと似た構成・スタイル)。
## BossSpawnerがshow_choices()を呼ぶことで、3つのアイテム候補から1つをタップで
## 選ぶまでゲームを一時停止する。選んだ効果はこれまで通りPlayerUpgradesComponentへ
## 適用し、EventBus.item_acquiredを発火する(HUDのポップアップ/一覧表示はそのまま動く)。
## 表示/非表示のタイミングはGameManager.request_modal()/open_modal()/close_modal()を
## 経由する(LevelUpSelectとほぼ同時に開こうとした場合でも、必ずどちらか一方だけが
## 表示され、両方閉じるまでゲームの一時停止が解除されないようにするため)。

signal item_chosen(item_id: String)

const BORDER_COLOR := Color("d99565") # 戦利品は髑髏と赤銅のアクセント。
const NAME_FONT_SIZE := 24
const DESC_FONT_SIZE := 20
const DESC_COLOR := Color(0.88, 0.88, 0.93, 1.0)
const ICON_SIZE := Vector2(72, 72)

@onready var title_label: Label = $CenterContainer/VBoxContainer/StepTitle
@onready var grid_container: GridContainer = $CenterContainer/VBoxContainer/GridContainer

func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)
	PixelUIStyle.add_ornament($Background, "backdrop", BORDER_COLOR)
	PixelUIStyle.apply_major_panel($AltarPanel, BORDER_COLOR)
	var heading := $CenterContainer/VBoxContainer/StepTitle as Label
	heading.custom_minimum_size = Vector2(680, 68)
	heading.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	PixelUIStyle.FrameArt.plaque(heading)
	PixelUIStyle.FrameArt.emblem($CenterContainer/VBoxContainer/Seal, true)

## BossSpawnerがボス撃破時に呼び出す。candidatesは通常1〜3件を想定。
## 他のモーダル(LevelUpSelect等)が既に開いている場合は、GameManagerのキューに
## 積まれてそちらが閉じた後に自動的に表示される。
func show_choices(candidates: Array[ItemData], title: String = "ボス撃破　戦利品を選ぶ") -> void:
	if candidates.is_empty():
		return
	GameManager.request_modal(func(): _open(candidates, title))

func _open(candidates: Array[ItemData], title: String) -> void:
	GameManager.open_modal()
	visible = true
	title_label.text = title
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()

	for item in candidates:
		grid_container.add_child(_build_choice_button(item))
	if grid_container.get_child_count() > 0:
		(grid_container.get_child(0) as Button).grab_focus.call_deferred()

## アイテム名を上段(やや大きめ)、効果説明を下段(小さめ・薄い色)に分けた
## 2行表示のボタンを作る。Buttonの.textは使わず、子にVBoxContainer+2つのLabelを
## 重ねることで2行レイアウトを実現する(子Controlのmouse_filterをIGNOREにして
## クリックがボタン自体に通るようにしている)。
func _build_choice_button(item: ItemData) -> Button:
	var icon_texture := _load_icon(item.icon_path)
	var button := PixelUIStyle.choice_card("王家の戦利品", item.display_name, _resolve_description(item), icon_texture, "受け取る", BORDER_COLOR)
	button.custom_minimum_size = Vector2(360, 320)
	button.set_meta("item_id", item.id)
	button.pressed.connect(_on_choice_pressed.bind(item))
	return button

func _load_icon(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## data/items/のJSONにdescriptionが用意されていればそれをそのまま使う。
## 無い場合(将来descriptionを書き忘れたアイテムが追加された場合も含む)は
## effect_type/valueから簡単な説明文を自動生成して補う。
func _resolve_description(item: ItemData) -> String:
	if item.description != "":
		return item.description
	var percent := int(round(item.value * 100.0))
	match item.effect_type:
		"damage_up":
			return "攻撃力が%d%%上昇する" % percent
		"crit_rate_up":
			return "会心率が%d%%上昇する" % percent
		"max_hp_bonus":
			return "最大HPが%d上昇する" % int(item.value)
		"move_speed_multiplier":
			return "移動速度が%d%%上昇する" % percent
		"attack_interval_multiplier":
			return "攻撃間隔が%d%%短縮する" % percent
		"attack_range_multiplier":
			return "攻撃範囲が%d%%上昇する" % percent
		"lifesteal":
			return "与えたダメージの%d%%を回復する" % percent
		"damage_taken_multiplier":
			return "被ダメージが%d%%軽減される" % percent
		_:
			return ""

func _apply_choice_style(button: Button) -> void:
	PixelUIStyle.apply_button(button, BORDER_COLOR)

func _on_choice_pressed(item: ItemData) -> void:
	if not visible: return
	AudioManager.play_sfx("ui_click")
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var upgrades_component: PlayerUpgradesComponent = player.get_node_or_null("PlayerUpgradesComponent")
		if upgrades_component:
			upgrades_component.apply_item(item)
	EventBus.item_acquired.emit(item.id, item.display_name)
	item_chosen.emit(item.id)
	visible = false
	GameManager.close_modal()
