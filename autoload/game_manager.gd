extends Node
## ラン全体の状態(Model)を保持するControllerハブ。
## Viewやサブシステムはここを直接いじらず、EventBus経由でのみ状態変化を知る。

enum RunState { NONE, PLAYING, PAUSED, RESULT }

const ELEMENT_NONE := "element_none"
const ACTIVE_ELEMENT_BY_FRAGMENT := {
	"fire": "element_fire",
	"ice": "element_ice",
	"lightning": "element_lightning",
	"light": "element_light",
	"dark": "element_dark",
}
const THEME_ID_BY_ACTIVE_ELEMENT := {
	"element_fire": "fire",
	"element_ice": "ice",
	"element_lightning": "lightning",
	"element_light": "light",
	"element_dark": "dark",
}
const ELEMENT_IDS: Array[String] = [
	"element_fire", "element_ice", "element_lightning", "element_light", "element_dark",
]
const FUSION_BY_PAIR := {
	"element_fire+element_ice": "frostfire",
	"element_fire+element_lightning": "plasma",
	"element_fire+element_light": "solar",
	"element_fire+element_dark": "inferno",
	"element_ice+element_lightning": "superconductor",
	"element_ice+element_light": "aurora",
	"element_ice+element_dark": "void_frost",
	"element_lightning+element_light": "judgment",
	"element_lightning+element_dark": "voidstorm",
	"element_light+element_dark": "eclipse",
}
const FUSION_DISPLAY_NAMES := {
	"frostfire": "THERMAL SHOCK / 熱衝撃",
	"plasma": "PLASMA / プラズマ",
	"solar": "SOLAR FLARE / 太陽炎",
	"inferno": "INFERNO / 煉獄",
	"superconductor": "SUPERCONDUCTOR / 超伝導",
	"aurora": "AURORA / 極光",
	"void_frost": "BLACK ICE / 黒氷",
	"judgment": "RADIANT ARC / 聖雷",
	"voidstorm": "VOIDSTORM / 虚雷",
	"eclipse": "ECLIPSE / 日蝕",
}
const MASTERY_RANK_CAP := 3

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
var held_fragment_ids: Array[String] = []
## 欠片所持・Fusion消費とは別に保持する、ラン中だけ有効な属性Loadout。
## active_element_idsは古い取得順、末尾が主属性。最大2属性、各Lv3まで。
var active_element_ids: Array[String] = []
var element_stacks: Dictionary = {
	"element_fire": 0,
	"element_ice": 0,
	"element_lightning": 0,
	"element_light": 0,
	"element_dark": 0,
}
## 既存呼び出し互換用。2属性保持中はactive_element_ids末尾（主属性）を示す。
var active_element_id: String = ELEMENT_NONE
## 両属性Lv3で成立する、元属性とは別Presentationを持つFusion属性。
var active_fusion_id: String = ""
var general_mastery_ranks: Dictionary = {
	"power": 0, "echo": 0, "haste": 0, "reach": 0,
}
var element_mastery_ranks: Dictionary = {}
var fusion_mastery_ranks: Dictionary = {
	"power": 0, "echo": 0, "haste": 0, "signature": 0,
}
## 通常Game Sceneを直接開始した時だけtrue。Test Labや既存単体Testがgame.tscnを
## 埋め込んだ場合はfalseのままにし、ROOM自動進行を混入させない。
var room_mode_active: bool = false
var _debug_room_mode_next_game: bool = false
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
	_register_equipment_actions()

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
	key_event.physical_keycode = KEY_SPACE
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

func start_run(enable_room_mode: bool = false) -> void:
	# Result/Hit Stop/選択UIの途中で前Sceneが破棄された場合も、新しいRunへ
	# グローバルな停止状態や解放済みUI Callableを持ち越さない。
	get_tree().paused = false
	Engine.time_scale = 1.0
	active_modal_count = 0
	_modal_queue.clear()
	run_state = RunState.PLAYING
	elapsed_seconds = 0.0
	kill_count = 0
	held_fragment_ids.clear()
	_reset_element_loadout(true)
	room_mode_active = enable_room_mode
	if room_mode_active:
		dungeon_map = RoomTemplateFactory.build_map("standard")
	else:
		var elite_room_count := randi_range(dungeon_elite_room_count_min, dungeon_elite_room_count_max)
		dungeon_map = DungeonGenerator.generate(DUNGEON_WIDTH, DUNGEON_HEIGHT, DUNGEON_ROOM_COUNT, elite_room_count)
	EventBus.run_started.emit()

func debug_request_room_mode_for_next_game() -> void:
	if OS.is_debug_build():
		_debug_room_mode_next_game = true

func consume_debug_room_mode_request() -> bool:
	if not OS.is_debug_build() or not _debug_room_mode_next_game:
		return false
	_debug_room_mode_next_game = false
	return true

func end_run() -> void:
	if run_state == RunState.RESULT:
		return
	run_state = RunState.RESULT
	_reset_element_loadout(true)
	EventBus.run_ended.emit(elapsed_seconds, kill_count)

func complete_room_run(room_count: int) -> void:
	if run_state == RunState.RESULT:
		return
	run_state = RunState.RESULT
	EventBus.run_cleared.emit(room_count, elapsed_seconds, kill_count)

func register_kill() -> void:
	kill_count += 1

func _process(delta: float) -> void:
	if run_state == RunState.PLAYING:
		elapsed_seconds += delta

func add_fragment(fragment_id: String) -> void:
	var fragment: WeaponFragmentData = DataLoader.fragments.get(fragment_id)
	if fragment and ACTIVE_ELEMENT_BY_FRAGMENT.has(fragment.element):
		if not _acquire_element(String(ACTIVE_ELEMENT_BY_FRAGMENT[fragment.element])):
			return
	held_fragment_ids.append(fragment_id)
	EventBus.fragment_collected.emit(fragment_id)

func get_active_element_theme_id() -> String:
	return String(THEME_ID_BY_ACTIVE_ELEMENT.get(active_element_id, ""))

func get_active_element_ids() -> Array[String]:
	return active_element_ids.duplicate()

func get_element_stack(element_id: String) -> int:
	return int(element_stacks.get(element_id, 0))

func get_primary_element_id() -> String:
	return active_element_id

func get_fusion_display_name(fusion_id: String = active_fusion_id) -> String:
	return String(FUSION_DISPLAY_NAMES.get(fusion_id, fusion_id.to_upper()))

func get_fusion_for_elements(first: String, second: String) -> String:
	return String(FUSION_BY_PAIR.get(_fusion_pair_key(first, second), ""))

func get_general_mastery_rank(mastery_id: String) -> int:
	return int(general_mastery_ranks.get(mastery_id, 0))

func get_element_mastery_rank(element_id: String, mastery_id: String) -> int:
	var ranks: Dictionary = element_mastery_ranks.get(element_id, {})
	return int(ranks.get(mastery_id, 0))

func get_fusion_mastery_rank(mastery_id: String) -> int:
	return int(fusion_mastery_ranks.get(mastery_id, 0))

func add_general_mastery(mastery_id: String) -> bool:
	if not general_mastery_ranks.has(mastery_id):
		return false
	var rank := get_general_mastery_rank(mastery_id)
	if rank >= MASTERY_RANK_CAP:
		return false
	general_mastery_ranks[mastery_id] = rank + 1
	EventBus.element_mastery_changed.emit("general", mastery_id, rank + 1)
	return true

func add_element_mastery(element_id: String, mastery_id: String) -> bool:
	if element_id not in active_element_ids or get_element_stack(element_id) < 3:
		return false
	if not element_mastery_ranks.has(element_id):
		element_mastery_ranks[element_id] = {"power": 0, "echo": 0, "reach": 0, "signature": 0}
	var ranks: Dictionary = element_mastery_ranks[element_id]
	var rank := int(ranks.get(mastery_id, 0))
	if not ranks.has(mastery_id) or rank >= MASTERY_RANK_CAP:
		return false
	ranks[mastery_id] = rank + 1
	element_mastery_ranks[element_id] = ranks
	EventBus.element_mastery_changed.emit(element_id, mastery_id, rank + 1)
	return true

func add_fusion_mastery(mastery_id: String) -> bool:
	if active_fusion_id == "" or not fusion_mastery_ranks.has(mastery_id):
		return false
	var rank := get_fusion_mastery_rank(mastery_id)
	if rank >= MASTERY_RANK_CAP:
		return false
	fusion_mastery_ranks[mastery_id] = rank + 1
	EventBus.element_mastery_changed.emit(active_fusion_id, mastery_id, rank + 1)
	return true

func get_element_damage_multiplier(element_id: String) -> float:
	return 1.0 + get_general_mastery_rank("power") * 0.15 + get_element_mastery_rank(element_id, "power") * 0.25

func get_element_echo_chance(element_id: String) -> float:
	return minf(0.45, get_general_mastery_rank("echo") * 0.15 + get_element_mastery_rank(element_id, "echo") * 0.15)

func get_element_reach_multiplier(element_id: String) -> float:
	return 1.0 + get_general_mastery_rank("reach") * 0.12 + get_element_mastery_rank(element_id, "reach") * 0.20

func get_element_haste_multiplier() -> float:
	return maxf(0.70, 1.0 - get_general_mastery_rank("haste") * 0.10)

func get_fusion_damage_multiplier() -> float:
	return 1.0 + get_fusion_mastery_rank("power") * 0.25

func get_fusion_echo_chance() -> float:
	return minf(0.45, get_fusion_mastery_rank("echo") * 0.15)

func get_fusion_haste_multiplier() -> float:
	return maxf(0.64, 1.0 - get_fusion_mastery_rank("haste") * 0.12)

## Spawn先をSceneTree.current_sceneへ固定せず、呼び出し元が属する実Game Worldを返す。
## 通常Gameでは従来と同じGame root、Developer Test LabのSubViewport内でも同じ
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

## Developer Test Lab専用のForce State入口。通常Gameplayは必ずadd_fragment()を使う。
## Release Exportから呼ばれても状態を書き換えないようDebug Buildでのみ許可する。
func debug_force_element_state(forced_stacks: Dictionary, forced_fusion_id: String = "") -> bool:
	if not OS.is_debug_build():
		return false
	var forced_ids: Array[String] = []
	var sanitized := {}
	for element_id in ELEMENT_IDS:
		var level := clampi(int(forced_stacks.get(element_id, 0)), 0, 3)
		sanitized[element_id] = level
		if level > 0:
			forced_ids.append(element_id)
	if forced_ids.size() > 2:
		return false
	if forced_fusion_id != "":
		if forced_ids.size() != 2 or sanitized[forced_ids[0]] < 3 or sanitized[forced_ids[1]] < 3:
			return false
		if get_fusion_for_elements(forced_ids[0], forced_ids[1]) != forced_fusion_id:
			return false
	active_element_ids = forced_ids
	for element_id in ELEMENT_IDS:
		element_stacks[element_id] = int(sanitized[element_id])
	active_element_id = active_element_ids.back() if not active_element_ids.is_empty() else ELEMENT_NONE
	active_fusion_id = forced_fusion_id
	element_mastery_ranks.clear()
	fusion_mastery_ranks = {"power": 0, "echo": 0, "haste": 0, "signature": 0}
	_emit_element_loadout()
	return true

func set_active_element(element_id: String) -> bool:
	if element_id != ELEMENT_NONE and not DataLoader.element_vfx_effects.has(element_id):
		push_warning("GameManager: 未登録の現在属性です -> %s" % element_id)
		return false
	if element_id == ELEMENT_NONE:
		_reset_element_loadout()
	else:
		active_fusion_id = ""
		active_element_ids = [element_id]
		for id in element_stacks.keys():
			element_stacks[id] = 1 if id == element_id else 0
		active_element_id = element_id
		_emit_element_loadout()
	return true

func _acquire_element(element_id: String) -> bool:
	var max_stack := maxi(int(DataLoader.element_combat_config.get("max_stack", 3)), 1)
	var max_active := maxi(int(DataLoader.element_combat_config.get("max_active_elements", 2)), 1)
	if element_id in active_element_ids:
		if get_element_stack(element_id) >= max_stack:
			return false
		element_stacks[element_id] = get_element_stack(element_id) + 1
		# 同属性を再取得した場合も主属性へ移し、2属性時の居合Trailを明示的に切り替える。
		active_element_ids.erase(element_id)
		active_element_ids.append(element_id)
	else:
		if active_element_ids.size() >= max_active:
			# 2属性確定後はRun中のBuildをLockし、未取得属性で置換しない。
			return false
		else:
			active_element_ids.append(element_id)
			element_stacks[element_id] = 1
	active_element_id = active_element_ids.back() if not active_element_ids.is_empty() else ELEMENT_NONE
	_check_fusion_ready()
	_emit_element_loadout()
	return true

func _reset_element_loadout(force_emit: bool = false) -> void:
	var had_element := not active_element_ids.is_empty() or active_element_id != ELEMENT_NONE or active_fusion_id != ""
	active_element_ids.clear()
	for id in element_stacks.keys():
		element_stacks[id] = 0
	active_element_id = ELEMENT_NONE
	active_fusion_id = ""
	general_mastery_ranks = {"power": 0, "echo": 0, "haste": 0, "reach": 0}
	element_mastery_ranks.clear()
	fusion_mastery_ranks = {"power": 0, "echo": 0, "haste": 0, "signature": 0}
	if force_emit or had_element:
		_emit_element_loadout()

func _emit_element_loadout() -> void:
	EventBus.active_element_changed.emit(active_element_id)
	EventBus.element_loadout_changed.emit(active_element_ids.duplicate(), element_stacks.duplicate(true))

func _check_fusion_ready() -> void:
	if active_fusion_id != "" or active_element_ids.size() != 2:
		return
	if get_element_stack(active_element_ids[0]) < 3 or get_element_stack(active_element_ids[1]) < 3:
		return
	active_fusion_id = get_fusion_for_elements(active_element_ids[0], active_element_ids[1])
	if active_fusion_id == "":
		return
	EventBus.element_fusion_formed.emit(active_fusion_id, get_fusion_display_name(), active_element_ids.duplicate())

func _fusion_pair_key(first: String, second: String) -> String:
	var order := {"element_fire": 0, "element_ice": 1, "element_lightning": 2, "element_light": 3, "element_dark": 4}
	return "%s+%s" % [first, second] if int(order.get(first, 99)) <= int(order.get(second, 99)) else "%s+%s" % [second, first]

## LevelUpSelect/ItemSelect等の選択待ちUIが、今すぐ表示してよいか(他に何も
## 開いていないか)を問い合わせるための入り口。既に何か開いている場合は
## show_callableをキューへ積むだけにし、即座には呼ばない(＝2つのモーダルが
## 同時に表示されることは無い)。呼び出し側は「表示してよい」と判断された
## 瞬間(この関数内、またはキュー経由で後から)にshow_callableの中でopen_modal()
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
