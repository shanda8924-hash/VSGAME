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
@onready var room_run_controller: RoomRunController = $RoomRunController
@onready var concept_system: ConceptSystem = $ConceptSystem

func _ready() -> void:
	# game.tscnがMain Sceneとして直接起動した時だけROOM進行を有効化する。
	# Test Scene / Developer Test Lab内へ埋め込まれた実Gameは従来の手動検証経路を維持する。
	var main_game_runtime := get_tree().current_scene == self or GameManager.consume_debug_room_mode_request()
	GameManager.start_run(main_game_runtime)
	# ROOM RunはRoomRunControllerが非同期敷設する。ここでも同期buildするとRun開始時に
	# 同じROOMを2回構築してしまうため、従来Map/Test経路だけを即時構築する。
	if not main_game_runtime:
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
	if main_game_runtime:
		room_run_controller.begin_run()
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
