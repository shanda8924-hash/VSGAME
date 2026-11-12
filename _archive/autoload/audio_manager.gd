extends Node
## BGM/SE/Voiceの再生を一元管理する。
## 呼び出し側は「ファイルパス」ではなく「サウンドID」を渡す設計にすることで、
## 後からサウンド素材(BGM/SE/Voice)を差し替えてもゲームロジック側の修正は不要にする。

const SE_DIR := "res://assets/audio/se/"
const BGM_DIR := "res://assets/audio/bgm/"

var sfx_table: Dictionary = {} # id: String -> AudioStream
var bgm_table: Dictionary = {} # id: String -> AudioStream

var _sfx_players: Array[AudioStreamPlayer] = []
var _bgm_player: AudioStreamPlayer
var _current_bgm_id: String = ""
var _last_combat_hit_ms := -1000

func _ready() -> void:
	# Test-only silence never changes the saved player volume.
	if "--mute-audio" in OS.get_cmdline_user_args():
		AudioServer.set_bus_mute(0, true)
		print("TEST_AUDIO_MUTED driver=%s" % AudioServer.get_driver_name())
	_load_sound_dir(SE_DIR, sfx_table)
	_load_sound_dir(BGM_DIR, bgm_table)

	_create_bgm_player()
	_create_sfx_players()

	_connect_event_bus()

## SceneTree終了時に再生中のPlaybackとStream参照を明示的に切る。
## 通常のScene切替ではAutoloadを維持するが、テスト/ゲーム終了時にAudioServer側へ
## AudioStreamPlaybackWAVを残さないためのプロセス終了専用Cleanup。
func _exit_tree() -> void:
	stop_all(false)
	_current_bgm_id = ""
	sfx_table.clear()
	bgm_table.clear()

## assets/audio/se・assets/audio/bgm配下の.wavを、ファイル名(拡張子なし)を
## IDとしてそのまま読み込む。新しい音声素材を置くだけでコード変更なしに
## 使えるようにするため(データ駆動方針、DataLoaderのフォルダ走査と同じ考え方)。
func _load_sound_dir(dir_path: String, table: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("AudioManager: フォルダが見つかりません -> %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".wav"):
			table[file_name.get_basename()] = load(dir_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func play_sfx(id: String) -> void:
	if not sfx_table.has(id):
		return
	if id == "combat_hit":
		var now := Time.get_ticks_msec()
		if now - _last_combat_hit_ms < 80:
			return
		_last_combat_hit_ms = now
	var player := _get_free_sfx_player()
	player.stream = sfx_table[id]
	player.play()

## 既に同じIDのBGMを再生中なら何もしない(呼び出し側は状態を気にせず
## 何度呼んでも、頭出しし直されて音が途切れることはない)。
func play_bgm(id: String) -> void:
	if not bgm_table.has(id) or _current_bgm_id == id:
		return
	_current_bgm_id = id
	_bgm_player.stream = bgm_table[id]
	_bgm_player.play()

func stop_bgm(recreate_player: bool = true) -> void:
	_current_bgm_id = ""
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()
		_bgm_player.stream = null
		# Dummy audio driverを使うHeadless実行では、stop()+stream=nullだけでは
		# 最後のAudioStreamPlaybackWAVがAudioServerに残ることがある。
		# 通常のScene切替でも停止済みPlayerを解放し、空のPlayerへ入れ替える。
		if recreate_player and is_inside_tree():
			_bgm_player.queue_free()
			_create_bgm_player()

func stop_all(recreate_players: bool = true) -> void:
	stop_bgm(recreate_players)
	var old_sfx_players := _sfx_players.duplicate()
	_sfx_players.clear()
	for player in old_sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			if recreate_players and is_inside_tree():
				player.queue_free()
	if recreate_players and is_inside_tree():
		_create_sfx_players()

## 素材(.wav)側のループ設定に依存せず、AudioManager側で明示的にループさせる。
func _on_bgm_finished() -> void:
	if _current_bgm_id != "" and is_instance_valid(_bgm_player):
		_bgm_player.play()

func _create_bgm_player() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Music"
	_bgm_player.finished.connect(_on_bgm_finished)
	add_child(_bgm_player)

func _create_sfx_players() -> void:
	for _index in 8:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0]

## EventBus経由で発火するゲームイベントへのSE/BGM紐付けをここに集約する
## (HUD/DamageNumberManager等、既存の他Systemと同じくEventBus購読で疎結合を保つ。
## attack_shoot/hit_impact/ui_click/home_themeのようにEventBus化されていない
## イベントは、それぞれの発生源のスクリプト側から直接play_sfx/play_bgmを呼ぶ)。
func _connect_event_bus() -> void:
	EventBus.enemy_died.connect(func(_enemy_data, _pos): play_sfx("enemy_death"))
	EventBus.player_damaged.connect(func(_amount, _cur, _max): play_sfx("player_hurt"))
	EventBus.player_leveled_up.connect(func(_level): play_sfx("level_up"))
	EventBus.item_acquired.connect(func(_id, _name): play_sfx("item_pickup"))
	EventBus.equipment_picked_up.connect(func(_equipment): play_sfx("equipment_pickup"))
	EventBus.boss_fight_started.connect(func(_name): _on_boss_fight_started())
	EventBus.boss_fight_ended.connect(_on_boss_fight_ended)
	EventBus.run_started.connect(_on_run_started)
	# GameManager.end_run()の内部で発火する(=プレイヤー死亡時のみ現状呼ばれる)。
	EventBus.run_ended.connect(_on_run_ended)

func _on_run_started() -> void:
	play_bgm("dungeon_explore")

func _on_boss_fight_started() -> void:
	play_sfx("boss_appear")
	play_bgm("boss_battle")

func _on_boss_fight_ended() -> void:
	play_bgm("dungeon_explore")

func _on_run_ended(_seconds: float, _kills: int) -> void:
	stop_bgm()
	play_sfx("player_death")

func set_bus_volume(bus_name: String, linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_warning("AudioManager: Audio Busが見つかりません -> %s" % bus_name)
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(linear_volume, 0.0, 1.0)))
	AudioServer.set_bus_mute(bus_index, linear_volume <= 0.001)

func get_bus_volume(bus_name: String) -> float:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0 or AudioServer.is_bus_mute(bus_index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(bus_index))
