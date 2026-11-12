extends Control
## 盤面だけの試作（ロードマップ案Aの1段目）。戦闘は無い。
## 1回回す＝1部屋ぶん。spins_per_run 回で1プレイが終わり、揃ったラインの合計を出す。
## 操作：マスをタップ＝ホールド、「回す」ボタンかSpace/Enter＝回す。

@onready var board_view: BoardView = %BoardView
@onready var spin_button: Button = %SpinButton
@onready var round_label: Label = %RoundLabel
@onready var hold_label: Label = %HoldLabel
@onready var result_label: Label = %ResultLabel
@onready var total_label: Label = %TotalLabel
@onready var hint_label: Label = %HintLabel

var model: BoardModel
var spins_done := 0
var spins_per_run := 8
var total_lines := 0
var best_lines := 0
var run_finished := false

func _ready() -> void:
	spin_button.pressed.connect(_on_spin_pressed)
	board_view.hold_toggled.connect(_on_hold_toggled)
	board_view.spin_finished.connect(_on_spin_finished)
	start_run()

func start_run(seed_value: int = -1) -> void:
	model = BoardModel.new(seed_value)
	spins_per_run = int(model.config.get("spins_per_run", 8))
	spins_done = 0
	total_lines = 0
	best_lines = 0
	run_finished = false
	board_view.bind(model)
	result_label.text = "残したいマスをタップして、回す"
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_spin_pressed()
		get_viewport().set_input_as_handled()

func _on_spin_pressed() -> void:
	if board_view.spinning:
		return
	if run_finished:
		start_run()
		return
	if board_view.spin():
		spins_done += 1
		result_label.text = "…"
		_refresh()

func _on_hold_toggled(_index: int, accepted: bool) -> void:
	if not accepted:
		result_label.text = "ホールドは %d マスまで" % model.max_holds
	_refresh()

func _on_spin_finished(lines: Array) -> void:
	var count := lines.size()
	total_lines += count
	best_lines = maxi(best_lines, count)
	if count == 0:
		result_label.text = "揃わず"
	elif count >= 8:
		result_label.text = "全ライン！　8本"
	else:
		result_label.text = "%d本 揃った！" % count
	if spins_done >= spins_per_run:
		run_finished = true
		result_label.text += "　　おしまい：合計 %d 本（最高 %d 本）" % [total_lines, best_lines]
	_refresh()

func _refresh() -> void:
	round_label.text = "回した回数　%d / %d" % [spins_done, spins_per_run]
	hold_label.text = "ホールド　%d / %d" % [model.held_count(), model.max_holds]
	total_label.text = "揃ったライン 合計　%d 本" % total_lines
	spin_button.text = "もう一度" if run_finished else "回す"
	spin_button.disabled = board_view.spinning
	hint_label.text = "マスをタップ：ホールド\n回す：ボタン・Space・Enter"
