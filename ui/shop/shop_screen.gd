extends CanvasLayer
class_name ShopScreen
## 各層のボス後に階段から開く4枠Shop。Stock・購入処理はShopSystemへ委譲する。

signal shop_closed

const CATEGORY_NAMES := {
	"weapon": "遺物武器",
	"generic": "汎用強化",
	"state": "状態異常強化",
	"recovery": "回復",
}
const CATEGORY_COLORS := {
	"weapon": Color("f2c14e"),
	"generic": Color("79d7e8"),
	"state": Color("c58cff"),
	"recovery": Color("72df8a"),
}

@export var shop_system_path: NodePath

@onready var shop_system: ShopSystem = get_node(shop_system_path)
@onready var title_label: Label = $CenterContainer/Panel/Margin/VBox/Title
@onready var gold_label: Label = $CenterContainer/Panel/Margin/VBox/TopRow/Gold
@onready var stock_grid: GridContainer = $CenterContainer/Panel/Margin/VBox/StockGrid
@onready var message_label: Label = $CenterContainer/Panel/Margin/VBox/Message
@onready var reroll_button: Button = $CenterContainer/Panel/Margin/VBox/BottomRow/RerollButton
@onready var leave_button: Button = $CenterContainer/Panel/Margin/VBox/BottomRow/LeaveButton

var _stock: Array[Dictionary] = []
var _focused_slot := 0
const CATEGORY_ICONS := {
	"weapon": preload("res://assets/ui/shop/weapon_icon.png"),
	"generic": preload("res://assets/ui/shop/upgrade_icon.png"),
	"state": preload("res://assets/ui/shop/status_icon.png"),
	"recovery": preload("res://assets/ui/shop/recovery_icon.png"),
}

func _ready() -> void:
	visible = false
	shop_system.stock_changed.connect(_on_stock_changed)
	shop_system.purchase_completed.connect(_on_purchase_completed)
	shop_system.purchase_failed.connect(_on_purchase_failed)
	EventBus.run_gold_changed.connect(_on_run_gold_changed)
	reroll_button.pressed.connect(_on_reroll_pressed)
	leave_button.pressed.connect(_close)
	leave_button.text = "探索を続ける"
	$CenterContainer/Panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	PixelUIStyle.apply_tree(self)
	PixelUIStyle.add_ornament($Background, "backdrop", PixelUIStyle.BORDER_HOVER)
	PixelUIStyle.apply_major_panel($CenterContainer/Panel, PixelUIStyle.BORDER_HOVER)
	PixelUIStyle.add_ornament($CenterContainer/Panel/Margin/VBox/Seal, "emblem")
	PixelUIStyle.apply_button(reroll_button, Color("79d7e8"))
	PixelUIStyle.apply_button(leave_button, Color("f2c14e"))

func show_shop(visit_index: int) -> void:
	GameManager.request_modal(func(): _open(visit_index))

func _open(visit_index: int) -> void:
	GameManager.open_modal()
	visible = true
	_focused_slot = 0
	message_label.text = "購入すると同じ枠へ別の商品が補充されます"
	title_label.text = "灯火の遺物商"
	$CenterContainer/Panel/Margin/VBox/Eyebrow.text = "5分サバイバル　・　戦闘へ戻る前の補給" if GameManager.survival_mode_active else "地下%d / 60層　・　探索の休息" % visit_index
	shop_system.begin_visit(visit_index)
	_refresh_gold()
	_focus_first_available.call_deferred()

func _close() -> void:
	if not visible:
		return
	AudioManager.play_sfx("ui_click")
	visible = false
	GameManager.close_modal()
	shop_closed.emit()

func _on_stock_changed(stock: Array[Dictionary], reroll_cost: int) -> void:
	_stock = stock
	for child in stock_grid.get_children():
		stock_grid.remove_child(child)
		child.queue_free()
	for product in _stock:
		var button := _build_product_button(product)
		stock_grid.add_child(button)
		button.focus_entered.connect(_on_product_focused.bind(stock_grid.get_child_count() - 1))
	reroll_button.text = "リロール　%d G" % reroll_cost
	_refresh_gold()
	_focus_first_available.call_deferred(true)

func _build_product_button(product: Dictionary) -> Button:
	var view := shop_system.describe_product(product)
	var category := String(product.get("category", ""))
	var price := int(product.get("price", 0))
	var icon: Texture2D = CATEGORY_ICONS.get(category)
	if category == "weapon":
		var weapon: WeaponData = DataLoader.weapons.get(String(product.get("ref_id", "")))
		if weapon and weapon.icon: icon = weapon.icon
	elif String(product.get("item_kind", "")) == "upgrade":
		var upgrade: UpgradeData = DataLoader.upgrades.get(String(product.get("ref_id", "")))
		if upgrade and upgrade.icon_path != "" and ResourceLoader.exists(upgrade.icon_path):
			var upgrade_icon := load(upgrade.icon_path) as Texture2D
			if upgrade_icon: icon = upgrade_icon
	var button := PixelUIStyle.choice_card(String(CATEGORY_NAMES.get(category, category)), String(view.get("display_name", "")), String(view.get("description", "")), icon, "%d G" % price, CATEGORY_COLORS.get(category, PixelUIStyle.BORDER_HOVER))
	button.set_meta("product_id", String(product.get("id", "")))
	button.pressed.connect(_on_product_pressed.bind(String(product.get("id", ""))))
	return button

func _on_product_focused(slot: int) -> void:
	_focused_slot = slot
	if slot >= _stock.size(): return
	var price := int(_stock[slot].get("price", 0))
	message_label.text = "購入後  %d G  ・  購入枠は同カテゴリで補充" % (GameManager.run_gold - price) if GameManager.can_afford_run_gold(price) else "あと %d G 必要です  ・  他の商品も比較できます" % (price - GameManager.run_gold)

func _on_product_pressed(product_id: String) -> void:
	AudioManager.play_sfx("ui_click")
	shop_system.buy_product(product_id)

func _on_purchase_completed(product: Dictionary) -> void:
	var view := shop_system.describe_product(product)
	message_label.text = "%sを購入しました" % String(view.get("display_name", product.get("id", "")))
	AudioManager.play_sfx("level_up")

func _on_purchase_failed(reason: String) -> void:
	message_label.text = reason

func _on_reroll_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	if shop_system.reroll():
		message_label.text = "商品を入れ替えました"

func _on_run_gold_changed(_current_gold: int, _delta: int, _source: String) -> void:
	if visible:
		_refresh_gold()

func _refresh_gold() -> void:
	if gold_label == null:
		return
	gold_label.text = "所持金　%d G" % GameManager.run_gold
	if reroll_button:
		reroll_button.disabled = not GameManager.can_afford_run_gold(shop_system.get_reroll_cost())
	for child in stock_grid.get_children():
		var button := child as Button
		if button == null:
			continue
		var product_id := String(button.get_meta("product_id", ""))
		for product in _stock:
			if String(product.get("id", "")) == product_id:
				var price := int(product.get("price", 0))
				var affordable := GameManager.can_afford_run_gold(price)
				var footer := button.find_child("CardFooter", true, false) as Label
				if footer:
					footer.text = "%d G" % price if affordable else "%d G  ・  %d G不足" % [price, price - GameManager.run_gold]
					footer.add_theme_color_override("font_color", PixelUIStyle.BORDER_HOVER if affordable else PixelUIStyle.TEXT_MUTED)
				break

func _focus_first_available(preserve_message: bool = false) -> void:
	var target: Button
	if stock_grid.get_child_count() > 0:
		target = stock_grid.get_child(clampi(_focused_slot, 0, stock_grid.get_child_count()-1)) as Button
	elif not reroll_button.disabled:
		target = reroll_button
	else:
		target = leave_button
	# Stock補充の自動focusだけは、直前の購入/リロール完了表示を保持する。
	# 手動で別商品へ移動した際のfocus_enteredは従来通り比較文を表示する。
	var previous_message := message_label.text
	target.grab_focus()
	if preserve_message:
		message_label.text = previous_message

func debug_close_shop() -> void:
	_close()
