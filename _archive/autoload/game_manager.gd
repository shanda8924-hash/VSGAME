extends Node
## ラン全体の状態(Model)を保持するControllerハブ。
## Viewやサブシステムはここを直接いじらず、EventBus経由でのみ状態変化を知る。

enum RunState { NONE, PLAYING, PAUSED, RESULT }
const PLAYABLE_CHARACTER_IDS := ["soldier", "swordsman", "archer", "knight", "armored_axeman", "wizard"]

## ダンジョン生成パラメータ(@exportではなくconstだが、この値を変えるだけで調整できる)。
const DUNGEON_WIDTH := 100
const DUNGEON_HEIGHT := 100
const DUNGEON_ROOM_COUNT := 12
## 精鋭部屋(Elite Room)として指定する部屋数の範囲(仕様書5章: 「1〜2部屋」)。
## start_run()のたびにこの範囲でランダムに決める。スタート地点に近い部屋は
## DungeonGenerator側で自動的に除外される。
@export var dungeon_elite_room_count_min: int = 1
@export var dungeon_elite_room_count_max: int = 2

var run_state: RunState = RunState.NONE
var elapsed_seconds: float = 0.0
var kill_count: int = 0
## ラン中だけ有効なショップ通貨。SaveManagerのmeta_currencyとは完全に分離する。
var run_gold: int = 0
## 通常の製品Runは3MAP探索進行。埋め込みTest Labでは自動進行しない。
var map_mode_active: bool = false
var survival_mode_active := false
var survival_duration_seconds := 300.0
var survival_completed := false
var selected_survival_map := 1
var run_equipment_count := 0
var current_map_index: int = 0
var current_floor_index: int = 1
var current_depth: int = 1
var selected_character_id: String = "soldier" # ホーム画面で選んだ職業。Playerが起動時に参照する
var dungeon_map: DungeonMap # ラン開始時に1回だけ生成される、床/壁のグリッドデータ

## 現在開いている選択待ちモーダル(LevelUpSelect/ItemSelect等)の数。
## 複数のモーダルが個別にget_tree().paused=true/falseを直接操作すると、片方が
## 閉じた際にもう片方がまだ開いている状態を考慮せずポーズを解除してしまう事故が
## 起こる(例: ボス撃破のアイテム選択とレベルアップ選択がほぼ同時に発生した場合)。
## そのためポーズの一時停止/解除は必ずこのカウンタ経由でのみ行う。
var active_modal_count: int = 0
## 既に他のモーダルが開いている間に新しく開こうとしたモーダルの表示処理を
## 順番に待たせておくキュー。close_modal()でactive_modal_countが0に戻った
## 瞬間に先頭から1件だけ取り出して実行する(同時に複数表示させないため)。
var _modal_queue: Array[Callable] = []

func _ready() -> void:
	_extend_ui_actions_with_wasd()
	_register_active_skill_action()
	_register_interact_action()
	EventBus.equipment_picked_up.connect(func(_equipment):
		if survival_mode_active and run_state == RunState.PLAYING: run_equipment_count += 1)
	_register_equipment_actions()
	_register_key_and_button("talent_menu", KEY_T, JOY_BUTTON_BACK)

## 宝箱・装備・将来のNPC/扉などで共有するInteraction Action。
## 南ボタン(A)はactive_skillへ割り当て済みのため、ゲームパッドは競合しないXを使う。
func _register_interact_action() -> void:
	_register_key_and_button("interact", KEY_E, JOY_BUTTON_X)

func _register_equipment_actions() -> void:
	_register_key_and_button("character_screen", KEY_C, JOY_BUTTON_Y)
	# Iは旧装備画面からの移行用エイリアスとして残す。画面本体は同じで二重実装しない。
	_register_key_and_button("equipment_menu", KEY_I, JOY_BUTTON_Y)

func _register_key_and_button(action: String, keycode: Key, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	if not InputMap.action_has_event(action, key_event):
		InputMap.action_add_event(action, key_event)
	var joy_event := InputEventJoypadButton.new()
	joy_event.button_index = button
	if not InputMap.action_has_event(action, joy_event):
		InputMap.action_add_event(action, joy_event)

## 職業固有アクティブスキル発動アクション。キーボードはSpace、ゲームパッドは
## 南ボタン(Xbox配置でいうAボタン、JOY_BUTTON_A)を両方このアクションへ束ねる
## (2026年8月、能動発動スキルシステム試験実装にあわせてゲームパッド割り当てを追加。
## 新規アクションは作らず、既存の"active_skill"をそのまま拡張する方針)。
func _register_active_skill_action() -> void:
	const ACTION := "active_skill"
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_L
	if not InputMap.action_has_event(ACTION, key_event):
		InputMap.action_add_event(ACTION, key_event)
	var joy_event := InputEventJoypadButton.new()
	joy_event.button_index = JOY_BUTTON_A
	if not InputMap.action_has_event(ACTION, joy_event):
		InputMap.action_add_event(ACTION, joy_event)

## Godot既定のui_left/right/up/downは矢印キーとゲームパッド(十字キー/左スティック)
## のみが登録されており、WASDは含まれない。project.godotの[input]セクションを
## 手書きで編集するとInputEventのResourceシリアライズ形式を誤りやすいため、
## 起動時にコードから安全にWASDキーを追加登録する(Player.gdはui_*アクションの
## Input.get_vector()だけを見ればよく、キー種別を意識しなくてよい)。
func _extend_ui_actions_with_wasd() -> void:
	var bindings := {
		"ui_left": KEY_A,
		"ui_right": KEY_D,
		"ui_up": KEY_W,
		"ui_down": KEY_S,
	}
	for action in bindings.keys():
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)

func start_run(enable_map_mode: bool = false) -> void:
	if selected_character_id not in PLAYABLE_CHARACTER_IDS:
		selected_character_id = "soldier"
	# Result/Hit Stop/選択UIの途中で前Sceneが破棄された場合も、新しいRunへ
	# グローバルな停止状態や解放済みUI Callableを持ち越さない。
	get_tree().paused = false
	Engine.time_scale = 1.0
	active_modal_count = 0
	_modal_queue.clear()
	run_state = RunState.PLAYING
	elapsed_seconds = 0.0
	kill_count = 0
	map_mode_active = enable_map_mode
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/exploration_run.json"))
	survival_mode_active = map_mode_active and float(config.get("survival_duration_seconds", 0)) > 0
	survival_duration_seconds = maxf(float(config.get("survival_duration_seconds", 300)), 1.0)
	survival_completed = false
	run_equipment_count = 0
	if not SaveManager.is_map_unlocked(selected_survival_map):
		selected_survival_map = 1
	selected_survival_map = clampi(selected_survival_map, 1, 3)
	current_map_index = selected_survival_map if survival_mode_active else (1 if map_mode_active else 0)
	current_floor_index = 1
	# 深度（Phase 4）：ステージを攻略するたびに+1。サバイバルだけが使う。
	current_depth = SaveManager.get_survival_depth() if survival_mode_active else 1
	reset_run_gold()
	generate_exploration_map(current_map_index)
	EventBus.run_started.emit()

## MAP Controllerからのみ呼ぶ生成入口。進行度は敵DataやPlayer Buildを参照せず、
## MAP番号に固定した寸法・部屋数・Elite数だけで決まる。
func generate_exploration_map(map_index: int, width: int = DUNGEON_WIDTH, height: int = DUNGEON_HEIGHT, room_count: int = DUNGEON_ROOM_COUNT, elite_count: int = -1) -> DungeonMap:
	current_map_index = maxi(map_index, 0)
	var resolved_elites := elite_count
	var isolated_rooms := false
	if resolved_elites < 0:
		resolved_elites = randi_range(dungeon_elite_room_count_min, dungeon_elite_room_count_max)
	if map_index > 0:
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/exploration_run.json"))
		var theme: Dictionary = config.maps[clampi(map_index-1, 0, 2)]
		width = int(theme.width)
		height = int(theme.height)
		room_count = int(theme.room_count)
		resolved_elites = 0 # Elite enemies join the horde; no room event pauses the wave.
		isolated_rooms = bool(theme.get("isolated_rooms", false))
	if survival_mode_active and map_index > 0:
		dungeon_map = preload("res://systems/room_layout.gd").generate(1, randi_range(1, 3), randi(), true)
	elif isolated_rooms:
		dungeon_map = preload("res://systems/room_layout.gd").generate(current_depth, 0, randi())
	else:
		dungeon_map = DungeonGenerator.generate(width, height, room_count, resolved_elites, null, map_index > 0)
	dungeon_map.set_meta("global_depth", current_depth)
	return dungeon_map

func end_run() -> void:
	if run_state == RunState.RESULT:
		return
	run_state = RunState.RESULT
	EventBus.run_ended.emit(elapsed_seconds, kill_count)
	reset_run_gold()

func complete_map_run(map_count: int) -> void:
	if run_state == RunState.RESULT:
		return
	run_state = RunState.RESULT
	EventBus.run_cleared.emit(map_count, elapsed_seconds, kill_count)
	reset_run_gold()

func register_kill() -> void:
	kill_count += 1

## 加算・消費はこのAPIだけを通し、UIや各報酬Systemが値を直接変更しない。
func add_run_gold(amount: int, source: String = "") -> int:
	if amount <= 0 or run_state != RunState.PLAYING:
		return run_gold
	run_gold += amount
	EventBus.run_gold_changed.emit(run_gold, amount, source)
	return run_gold

func can_afford_run_gold(amount: int) -> bool:
	return amount >= 0 and run_gold >= amount

func try_spend_run_gold(amount: int, source: String = "shop") -> bool:
	if amount <= 0 or run_state != RunState.PLAYING or not can_afford_run_gold(amount):
		return false
	run_gold -= amount
	EventBus.run_gold_changed.emit(run_gold, -amount, source)
	return true

func reset_run_gold() -> void:
	var delta := -run_gold
	run_gold = 0
	EventBus.run_gold_changed.emit(run_gold, delta, "run_reset")

func _process(delta: float) -> void:
	if run_state == RunState.PLAYING and not survival_completed:
		elapsed_seconds += delta


## game.tscn rootを返す。祖先が見つからない既存Testだけcurrent_sceneへfallbackする。
func get_runtime_world(context: Node = null) -> Node:
	var cursor := context
	while cursor:
		if cursor.is_in_group("game_runtime_world"):
			return cursor
		cursor = cursor.get_parent()
	var worlds := get_tree().get_nodes_in_group("game_runtime_world")
	if not worlds.is_empty():
		return worlds[0]
	return get_tree().current_scene

## を呼び、実際に画面を表示すること。
func request_modal(show_callable: Callable) -> void:
	if active_modal_count > 0:
		_modal_queue.append(show_callable)
	else:
		show_callable.call()

## モーダルを実際に表示する際に呼ぶ。呼ぶたびにactive_modal_countを+1し、
## (1以上になった瞬間に)ゲームを一時停止する。
func open_modal() -> void:
	active_modal_count += 1
	get_tree().paused = true

## モーダルを閉じた(選択を完了した)際に呼ぶ。active_modal_countが0に戻った
## 場合のみ一時停止を解除し、キューに次の表示待ちモーダルがあれば1件取り出して
## 表示する(その中で再びopen_modal()が呼ばれ、一時停止は維持されたままになる)。
func close_modal() -> void:
	active_modal_count = maxi(0, active_modal_count - 1)
	if active_modal_count > 0:
		return
	get_tree().paused = false
	if not _modal_queue.is_empty():
		var next_show: Callable = _modal_queue.pop_front()
		next_show.call()
