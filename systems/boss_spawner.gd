extends Node2D
class_name BossSpawner
## 一定間隔でボスを出現させる。ラン開始と同時に1体目を出現させ、以降は
## boss_interval_seconds(既定90秒=1分半)ごとに、data/bosses/からランダムに1体選んで
## プレイヤー付近に出現させる。ボスが生存している間は通常の雑魚湧き(WaveSpawner)を
## EventBus.boss_fight_started/endedを介して止め、HUDにボス専用のHP バーを表示する。
## 倒すと欠片+メタ通貨を報酬として渡し、既存の演出設備(VFXPoolManager/ScreenEffects)
## を使った派手な撃破演出を再生する。
##
## BossDataはEnemyDataを継承しているため、enemy_scene(EnemyBasic)へそのまま
## enemy_dataとして渡せる(既存のダメージ計算/移動/描画ロジックをそのまま再利用する。
## EnemyBasic側の変更は不要)。

@export var enemy_scene: PackedScene
## ボスの出現間隔(秒)。elapsed_secondsが「出現回数 * この値」以上になるたびに
## 1体出現させる(0秒・90秒・180秒…という固定スケジュール。ランダム幅は無し)。
## 1体目はラン開始直後ではなく、この時刻に出現する。
@export var first_boss_spawn_seconds: float = 60.0
## 2体目以降の出現間隔。game.tscnのInspectorからも調整可能。
@export var boss_spawn_interval_seconds: float = 60.0
@export var spawn_radius: float = 500.0 # プレイヤーから見た出現距離の目安
## 撃破時の確定欠片ドロップ数の範囲(仕様書7章: 「欠片1〜2個確定ドロップ」)。
@export var boss_meta_currency_reward: int = 150

## 通常Item報酬は既存3択を維持する。属性Build報酬はFragmentSelect側で常に4択。
@export var item_choice_count: int = 3

@export var screen_effects_path: NodePath
@export var vfx_pool_path: NodePath
@export var hud_path: NodePath
@export var item_select_path: NodePath
@export var fragment_select_path: NodePath

@onready var _screen_effects: ScreenEffects = get_node_or_null(screen_effects_path)
@onready var _vfx_pool: VFXPoolManager = get_node_or_null(vfx_pool_path)
@onready var _hud: HUD = get_node_or_null(hud_path)
@onready var _item_select: ItemSelect = get_node_or_null(item_select_path)
@onready var _fragment_select: FragmentSelect = get_node_or_null(fragment_select_path)

signal room_boss_started(room_number: int, boss_id: String, display_name: String)
signal room_boss_defeated(room_number: int, boss_id: String, death_position: Vector2)

## これまでに出現させたボスの体数。次の出現しきい値は
## _boss_spawn_count * boss_interval_seconds(0体目=0秒、1体目=90秒…)で毎フレーム
## 再計算するため、乱数のロールし忘れやタイミングのズレが起こらない。
var _boss_spawn_count: int = 0
var _current_boss: Node = null
## 同一ラン中に既に出現させたボスのidを記録し、未出現のボスから優先的に選ぶ
## (仕様書7章: 「同一ランでの重複出現なし」)。全10体を出現させ切った場合は
## リストをリセットし、以降は再び全ボスから選ばれるようにする(長時間プレイでも
## ボスの出現自体が止まらないようにするため)。
var _spawned_boss_ids: Array[String] = []
var _room_encounter_active: bool = false
var _room_encounter_number: int = 0
var _room_encounter_final: bool = false
var _prepared_room_boss: bool = false
var _encounter_epoch: int = 0

func _process(_delta: float) -> void:
	if GameManager.run_state != GameManager.RunState.PLAYING:
		return
	if _current_boss != null:
		return # ボス戦中は次の出現判定をしない
	var next_spawn_time := first_boss_spawn_seconds + _boss_spawn_count * boss_spawn_interval_seconds
	if GameManager.elapsed_seconds >= next_spawn_time:
		_spawn_boss()

func _spawn_boss() -> void:
	if enemy_scene == null:
		return
	var boss_ids: Array = DataLoader.bosses.keys()
	if boss_ids.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var next_boss_id := _pick_unspawned_boss_id(boss_ids)
	if next_boss_id == "":
		return
	_spawn_boss_by_id(next_boss_id)

func _spawn_boss_by_id(boss_id: String, position_override: Vector2 = Vector2.INF, tuning: Dictionary = {}, defer_activation: bool = false) -> Node:
	if _current_boss != null or not DataLoader.bosses.has(boss_id):
		return null
	var player := get_tree().get_first_node_in_group("player")
	var runtime_world := GameManager.get_runtime_world(self)
	if player == null or enemy_scene == null or runtime_world == null:
		return null
	var boss_data: BossData = DataLoader.bosses[boss_id]
	var boss := enemy_scene.instantiate()
	boss.enemy_data = boss_data
	boss.visual_scale_multiplier = boss_data.visual_scale
	boss.room_hp_multiplier = float(tuning.get("hp_multiplier", 1.0))
	boss.room_damage_multiplier = float(tuning.get("damage_multiplier", 1.0))
	boss.room_attack_interval_multiplier = float(tuning.get("attack_interval_multiplier", 1.0))
	boss.boss_special_interval_multiplier = float(tuning.get("special_interval_multiplier", 1.0))
	boss.boss_status_duration_multiplier = float(tuning.get("status_duration_multiplier", 1.0))
	boss.set_meta("summon_hp_multiplier", float(tuning.get("summon_hp_multiplier", 1.0)))
	boss.set_meta("summon_damage_multiplier", float(tuning.get("summon_damage_multiplier", 1.0)))
	_encounter_epoch += 1
	var epoch := _encounter_epoch
	runtime_world.add_child(boss)
	boss.global_position = _pick_spawn_position(player.global_position) if position_override == Vector2.INF else position_override
	boss.health_component.damaged.connect(_on_boss_damaged.bind(boss, epoch))
	boss.health_component.died.connect(_on_boss_died.bind(boss, epoch), CONNECT_ONE_SHOT)

	_current_boss = boss
	_boss_spawn_count += 1
	_spawned_boss_ids.append(boss_data.id)
	if defer_activation:
		boss.visible = false
		boss.process_mode = Node.PROCESS_MODE_DISABLED
		_prepared_room_boss = true
		return boss
	_announce_current_boss()
	return boss

func _announce_current_boss() -> void:
	if not is_instance_valid(_current_boss):
		return
	var boss := _current_boss as EnemyBasic
	var boss_data := boss.enemy_data as BossData
	var hud_name := _format_boss_hud_name(boss_data.display_name)
	EventBus.boss_fight_started.emit(hud_name)
	EventBus.boss_health_changed.emit(boss.health_component.current_hp, boss.health_component.max_hp)
	if _hud:
		_hud.show_boss_health(hud_name, boss.health_component.current_hp, boss.health_component.max_hp)
		if _room_encounter_active:
			_hud.show_boss_intro(boss_data.display_name, _room_encounter_final)
	_play_spawn_impact()
	if _room_encounter_active:
		room_boss_started.emit(_room_encounter_number, boss_data.id, boss_data.display_name)

## ROOM 4/8/12専用の明示的Encounter入口。_processの時間判定は使わず、候補・
## 倍率・報酬責務をROOM側から渡す。旧報酬処理はこの経路では実行しない。
func start_room_boss(room_number: int, encounter: Dictionary, position_override: Vector2 = Vector2.INF, defer_activation: bool = false) -> Node:
	if _current_boss != null:
		return null
	_room_encounter_active = true
	_room_encounter_number = room_number
	_room_encounter_final = bool(encounter.get("is_final", false))
	var candidates: Array = encounter.get("candidates", [])
	var valid: Array = candidates.filter(func(id): return DataLoader.bosses.has(String(id)))
	if valid.is_empty():
		valid = DataLoader.bosses.keys()
	var boss_id := _pick_unspawned_boss_id(valid)
	if boss_id == "":
		return null
	return _spawn_boss_by_id(boss_id, position_override, encounter, defer_activation)

func activate_prepared_room_boss() -> Node:
	if not _prepared_room_boss or not is_instance_valid(_current_boss):
		return null
	_prepared_room_boss = false
	_current_boss.visible = true
	_current_boss.process_mode = Node.PROCESS_MODE_INHERIT
	_announce_current_boss()
	return _current_boss

func prepare_room_run() -> void:
	clear_room_boss()
	_spawned_boss_ids.clear()
	_boss_spawn_count = 0
	process_mode = Node.PROCESS_MODE_DISABLED

func clear_room_boss() -> void:
	_encounter_epoch += 1
	var had_boss := is_instance_valid(_current_boss)
	if had_boss:
		_current_boss.queue_free()
	_current_boss = null
	_room_encounter_active = false
	_room_encounter_number = 0
	_room_encounter_final = false
	_prepared_room_boss = false
	_cleanup_boss_attack_nodes()
	if had_boss:
		EventBus.boss_fight_ended.emit()
	if _hud:
		_hud.hide_boss_health()
	if _screen_effects:
		_screen_effects.restore_runtime_state()

func debug_spawn_boss(boss_id: String, position_override: Vector2 = Vector2.INF) -> Node:
	if not OS.is_debug_build():
		return null
	return _spawn_boss_by_id(boss_id, position_override)

func debug_get_current_boss() -> Node:
	return _current_boss if OS.is_debug_build() else null

func debug_clear_boss() -> void:
	if not OS.is_debug_build() or _current_boss == null:
		return
	clear_room_boss()

func debug_defeat_current_boss() -> void:
	if not OS.is_debug_build() or not is_instance_valid(_current_boss):
		return
	_current_boss.health_component.current_hp = minf(_current_boss.health_component.current_hp, 1.0)
	_current_boss.health_component.apply_secondary_damage(99999999.0, CombatEventMeta.create_secondary("debug_boss_clear", [], false))

## 未出現のボスidだけを対象にランダムに1つ選ぶ。全ボスを出現させ切っていた場合は
## 記録をリセットしてから全ボスを対象に選び直す(重複出現なしの制約を保ちつつ、
## 出現自体は止めない)。
func _pick_unspawned_boss_id(boss_ids: Array) -> String:
	var unspawned: Array = boss_ids.filter(func(id): return not _spawned_boss_ids.has(id))
	if unspawned.is_empty():
		return ""
	return unspawned[randi() % unspawned.size()]

## ボス出現の瞬間、「何か大きなことが起きた」感を出すため、不穏な暗い赤の
## フラッシュ(撃破時の明るい赤フラッシュとは色を分けている)と軽いヒットストップを
## 重ねる。ScreenEffects.hit_stop()は実時間ベースのタイマーで待つため、
## time_scaleが下がっていてもduration分だけきちんと止まって見える。
func _play_spawn_impact() -> void:
	if _screen_effects == null:
		return
	_screen_effects.flash(Color(0.55, 0.05, 0.05, 1.0), 0.35)
	_screen_effects.hit_stop(0.3)

func _on_boss_damaged(_amount: float, current_hp: float, max_hp: float, boss: Node, epoch: int) -> void:
	if epoch != _encounter_epoch or boss != _current_boss:
		return
	EventBus.boss_health_changed.emit(current_hp, max_hp)
	if _hud:
		_hud.update_boss_health(current_hp, max_hp)

func _on_boss_died(boss: Node, epoch: int) -> void:
	if epoch != _encounter_epoch or boss != _current_boss:
		return
	var death_position: Vector2 = boss.global_position if is_instance_valid(boss) else Vector2.ZERO
	var defeated_id := String((boss.enemy_data as BossData).id) if is_instance_valid(boss) and boss.enemy_data is BossData else ""
	var defeated_room := _room_encounter_number
	var was_room_encounter := _room_encounter_active
	_current_boss = null
	_room_encounter_active = false
	_room_encounter_number = 0
	EventBus.boss_fight_ended.emit()
	if _hud:
		_hud.hide_boss_health()
	_cleanup_boss_attack_nodes()
	if _screen_effects:
		_screen_effects.restore_runtime_state()
	_play_defeat_impact(death_position)
	if was_room_encounter:
		room_boss_defeated.emit(defeated_room, defeated_id, death_position)
	else:
		_grant_rewards(death_position)

func _cleanup_boss_attack_nodes() -> void:
	for group_name in ["boss_projectiles", "boss_attack_transient", "boss_summons"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.queue_free()

func _format_boss_hud_name(display_name: String) -> String:
	if not _room_encounter_active:
		return display_name
	return "%s　%s" % ["最終ボス" if _room_encounter_final else "ボス", display_name]

func _play_defeat_impact(at_position: Vector2) -> void:
	if _vfx_pool:
		_vfx_pool.play_mass_kill_burst(at_position)
	if _screen_effects:
		_screen_effects.shake(14.0, 0.5)
		_screen_effects.flash(Color(1.0, 0.3, 0.3, 1.0), 0.4)

## 撃破報酬は精鋭部屋(EliteRoomManager)と同じ形(欠片+メタ通貨)を確定付与し、
## それに加えてdata/items/からの戦利品はItemSelectの3択UIで選ばせる(ゲームは
## 選び終えるまで一時停止のまま)。演出は赤みがかったフラッシュにして精鋭部屋の
## 金色フラッシュと区別している。
func _grant_rewards(at_position: Vector2) -> void:
	SaveManager.add_meta_currency(boss_meta_currency_reward)
	_offer_item_choice()
	if _fragment_select:
		# ItemSelectが先にopen_modal()するため、こちらは既存キューへ入り、
		# アイテム選択終了後にだけ順番に表示される。
		_fragment_select.show_choices("ボス報酬：属性ビルドを1つ選択")

## data/items/からitem_choice_count件(既定3)の候補を組み立て、ItemSelectへ渡して
## プレイヤーに選ばせる。選択後の適用(PlayerUpgradesComponent.apply_item)と
## EventBus.item_acquiredの発火はItemSelect側の責務。
func _offer_item_choice() -> void:
	if _item_select == null:
		return
	var candidates := _build_item_candidates(item_choice_count)
	if candidates.is_empty():
		return
	_item_select.show_choices(candidates)

## is_special(特別アイテム)を優先的に候補へ入れ、残り枠を通常アイテムから
## ランダムに埋める。現状の6種はすべてis_special=falseのため、実質は
## 「ランダムにcount件選ぶ」のと同じ結果になるが、将来is_special=trueの
## アイテムを追加した際にそのままこの優先ロジックが機能する。
func _build_item_candidates(count: int) -> Array[ItemData]:
	var special_items: Array[ItemData] = []
	var normal_items: Array[ItemData] = []
	for item in DataLoader.get_all_items():
		if item.is_special:
			special_items.append(item)
		else:
			normal_items.append(item)
	special_items.shuffle()
	normal_items.shuffle()

	var result: Array[ItemData] = []
	for item in special_items:
		if result.size() >= count:
			break
		result.append(item)
	for item in normal_items:
		if result.size() >= count:
			break
		result.append(item)
	return result

## WaveSpawner._pick_spawn_positionと同じ考え方(DungeonMapの床マスから選ぶ)を
## 踏襲し、壁の中に出現しないようにする。ボスは雑魚と違って近すぎる距離を除外する
## 必要が薄いため、プレイヤーの周辺で床マスをspawn_radius以内から探すだけの
## 単純な実装にしてある。
func _pick_spawn_position(near_world_pos: Vector2) -> Vector2:
	var map: DungeonMap = GameManager.dungeon_map
	if map == null:
		return _fallback_ring_position(near_world_pos)

	var floor_cells := map.get_floor_cells()
	if floor_cells.is_empty():
		return _fallback_ring_position(near_world_pos)

	var near_grid := map.world_to_grid(near_world_pos)
	# ROOM Bossは極端な至近/遠距離Spawnで撃破時間がぶれないよう、視認して
	# 接近できる180〜320px帯へ限定する。旧明示Spawnは従来の半径を維持する。
	var maximum_radius := minf(spawn_radius, 320.0) if _room_encounter_active else spawn_radius
	var minimum_radius := 180.0 if _room_encounter_active else 0.0
	var max_radius_cells := maximum_radius / DungeonMap.CELL_WORLD_SIZE
	var min_radius_cells := minimum_radius / DungeonMap.CELL_WORLD_SIZE

	var candidates: Array[Vector2i] = []
	for cell in floor_cells:
		var distance := Vector2(cell - near_grid).length()
		if distance >= min_radius_cells and distance <= max_radius_cells:
			candidates.append(cell)
	if candidates.is_empty():
		return _fallback_ring_position(near_world_pos)

	var chosen: Vector2i = candidates[randi() % candidates.size()]
	return map.grid_to_world(chosen)

func _fallback_ring_position(near_world_pos: Vector2) -> Vector2:
	var angle := randf() * TAU
	return near_world_pos + Vector2(cos(angle), sin(angle)) * spawn_radius
