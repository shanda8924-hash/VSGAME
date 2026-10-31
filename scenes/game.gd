extends Node2D
## Game.tscn のルートスクリプト(Controller層)。
## 各System/UIの初期化配線のみを担当し、ゲームロジック自体は持たない。
##
## StageEnvironment/PlayerのカメラはGameManager.dungeon_map(ダンジョン生成結果)に
## 依存するが、子ノードの_ready()は(GameManager.start_run()を呼ぶ)このノード自身の
## _ready()より先に実行されてしまうため、生成結果に依存する初期化はここで
## start_run()の直後に明示的に呼び出す。

@onready var player: Player = $Player
@onready var hud: HUD = $HUD
@onready var stage_environment: StageEnvironment = $StageEnvironment
@onready var elite_room_manager: EliteRoomManager = $EliteRoomManager
@onready var wave_spawner: WaveSpawner = $WaveSpawner
@onready var boss_spawner: BossSpawner = $BossSpawner
@onready var combo_system: ComboSystem = $ComboSystem
@onready var map_run_controller: MapRunController = $MapRunController
@onready var concept_system: ConceptSystem = $ConceptSystem
var mobile_controls: MobileControls

func _ready() -> void:
	mobile_controls = preload("res://ui/hud/mobile_controls.gd").new()
	add_child(mobile_controls)
	if "--survival-check" in OS.get_cmdline_user_args() or "--sector-mobile-check" in OS.get_cmdline_user_args(): SaveManager.begin_ephemeral_session()
	# 通常起動は大群・自動攻撃のMAP進行、埋め込みTest LabはSandbox。
	var map_runtime := get_tree().current_scene == self
	GameManager.start_run(map_runtime)
	if map_runtime:
		player.set_movement_locked(true)
		wave_spawner.set_spawning_paused(true)
		await stage_environment.build_dungeon_async(GameManager.dungeon_map, 5)
		player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
		player.setup_camera_limits(GameManager.dungeon_map)
		player.set_movement_locked(false)
	else:
		stage_environment.build_dungeon(GameManager.dungeon_map)
		player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
		player.setup_camera_limits(GameManager.dungeon_map)
	player.health_component.damaged.connect(_on_player_damaged)
	player.health_component.healed.connect(_on_player_healed)
	hud.set_health(player.health_component.current_hp, player.health_component.max_hp)
	player.experience_component.exp_changed.connect(_on_player_exp_changed)
	player.experience_component.leveled_up.connect(_on_player_leveled_up)
	hud.set_experience(player.experience_component.current_exp, player.experience_component.exp_to_next_level, player.experience_component.level)
	combo_system.combo_changed.connect(hud.set_combo)
	combo_system.combo_reset.connect(hud.reset_combo_display)
	concept_system.completed_skill_changed.connect(func(skill_id, level): hud.set_completed_skill(skill_id, concept_system.get_completed_skill_display_name(skill_id), level))
	if map_runtime:
		map_run_controller.begin_run()
		if OS.is_debug_build() and "--sector-mobile-check" in OS.get_cmdline_user_args():
			add_child(preload("res://tests/five_minute_survival_check.gd").new())
		elif OS.is_debug_build() and "--survival-check" in OS.get_cmdline_user_args():
			add_child(preload("res://tests/five_minute_survival_check.gd").new())
		elif OS.is_debug_build() and "--map-terrain-rhythm-check" in OS.get_cmdline_user_args():
			var terrain_rhythm_check := preload("res://tests/map_terrain_rhythm_check.gd").new()
			add_child(terrain_rhythm_check)
		elif OS.is_debug_build() and ("--map-performance-check" in OS.get_cmdline_user_args() or "--map-performance-feature-check" in OS.get_cmdline_user_args() or "--map-mass-density-check" in OS.get_cmdline_user_args()):
			var performance_check := preload("res://tests/map_performance_accumulation_check.gd").new()
			add_child(performance_check)
		elif OS.is_debug_build() and "--run-economy-balance-check" in OS.get_cmdline_user_args():
			var economy_balance_check := preload("res://tests/run_economy_balance_check.gd").new()
			add_child(economy_balance_check)
		elif OS.is_debug_build() and "--imported-assets-map-check" in OS.get_cmdline_user_args():
			add_child(preload("res://tests/imported_assets_map_check.gd").new())
		elif OS.is_debug_build() and ("--shop-runtime-check" in OS.get_cmdline_user_args() or "--shop-gui-capture" in OS.get_cmdline_user_args()):
			var shop_runtime_check := preload("res://tests/shop_runtime_check.gd").new()
			add_child(shop_runtime_check)
		elif OS.is_debug_build() and ("--map-runtime-check" in OS.get_cmdline_user_args() or "--map-combat-check" in OS.get_cmdline_user_args() or "--map-soak-check" in OS.get_cmdline_user_args() or "--map-gui-capture" in OS.get_cmdline_user_args() or "--map-phase2-check" in OS.get_cmdline_user_args()):
			var runtime_check := preload("res://tests/map_exploration_runtime_check.gd").new()
			add_child(runtime_check)
	else:
		combo_system.set_active(false)
		concept_system.set_active(false)
		elite_room_manager.setup(GameManager.dungeon_map)

func _exit_tree() -> void:
	# Restart・Title遷移・テスト終了のいずれでも、Game Sceneが消える前に
	# AudioServerのPlaybackを解放する。次のrun_startedでBGMは改めて再生される。
	AudioManager.stop_all()
	Engine.time_scale = 1.0

func _on_player_damaged(_amount: float, current_hp: float, max_hp: float) -> void:
	hud.set_health(current_hp, max_hp)

func _on_player_healed(_amount: float, current_hp: float, max_hp: float) -> void:
	hud.set_health(current_hp, max_hp)

func _on_player_exp_changed(current_exp: int, exp_to_next_level: int) -> void:
	hud.set_experience(current_exp, exp_to_next_level, player.experience_component.level)

func _on_player_leveled_up(new_level: int) -> void:
	hud.set_experience(player.experience_component.current_exp, player.experience_component.exp_to_next_level, new_level)
