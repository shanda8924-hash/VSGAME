extends Node
## 実Game Scene・実職業攻撃で、VFX生成ごとのPlayer Sprite読み戻しCostを測る。
## 敵48体と攻撃頻度を固定し、修正前後/序盤Buildを同じNode構成で比較する。

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const GROUND_EQUIPMENT_SCENE := preload("res://entities/pickups/ground_equipment_item.tscn")
const ENEMY_COUNT := 48
const WARMUP_SECONDS := 5.0
const SAMPLE_SECONDS := 60.0
const OUTPUT_DIR := "res://artifacts/vfx_stall"

var _frame_ms: Array[float] = []
var _process_ms: Array[float] = []
var _node_counts: Array[int] = []
var _previous_frame_usec := 0
var _measuring := false
var _attack_effects := 0
var _element_effects := 0
var _fusion_effects := 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_frame_usec = Time.get_ticks_usec()
	_run.call_deferred()

func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if _measuring and _previous_frame_usec > 0:
		_frame_ms.append(float(now_usec - _previous_frame_usec) / 1000.0)
		_process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		_node_counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_previous_frame_usec = now_usec

func _run() -> void:
	var late_build := "--vfx-stall-early" not in OS.get_cmdline_user_args()
	var label := "late"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--vfx-stall-label="):
			label = argument.trim_prefix("--vfx-stall-label=")
	GameManager.selected_character_id = "knight_templar"
	var character_data := DataLoader.characters.get("knight_templar") as CharacterData
	var original_crit_chance := character_data.crit_chance if character_data != null else 0.0
	if character_data != null:
		character_data.crit_chance = 0.0
	var game := GAME_SCENE.instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	await _wait_frames(40)
	_disable_non_test_progression(game)
	var player := game.get_node("Player") as Player
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	_expect(player != null and manager != null, "実GameのPlayer/AttackVFXManagerを取得できません")
	if player == null or manager == null:
		_finish(character_data, original_crit_chance)
		return
	player.health_component.invincible = true
	var cached_height := manager._get_player_visual_height()
	var direct_height := manager._calculate_player_visual_height()
	print("VFX_HEIGHT_CHECK cached=%.3f direct=%.3f" % [cached_height, direct_height])
	_expect(is_equal_approx(cached_height, direct_height), "接続時Cache高が従来の直接計算値と一致しません")
	manager.debug_reset_spawn_cost_counters()
	manager._on_run_started()
	await _wait_frames(2)
	var invalidation_snapshot := manager.debug_get_spawn_cost_counters()
	print("VFX_HEIGHT_INVALIDATION image_reads=%d cached=%.3f" % [
		int(invalidation_snapshot.get("player_visual_height_image_reads", 0)),
		float(invalidation_snapshot.get("player_visual_height_cache", 0.0)),
	])
	_expect(int(invalidation_snapshot.get("player_visual_height_image_reads", 0)) == 1, "run_started再計算が1回に限定されていません")
	if "--vfx-stall-icon-probe" in OS.get_cmdline_user_args():
		await _run_icon_cache_probe(game, player, manager)
		_finish(character_data, original_crit_chance)
		return
	player.upgrades_component.attack_interval_multiplier = 0.75
	player.weapon_manager._class_attack_cooldown = 0.01
	manager.effect_spawned.connect(func(_id: String, _effect: AnimatedSprite2D): _attack_effects += 1)
	_spawn_fixed_enemies(game, player)
	await _wait_real(WARMUP_SECONDS)
	_expect(_living_enemy_count() == ENEMY_COUNT, "Warmup後の生存敵が48体ではありません")
	var start_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	manager.debug_reset_spawn_cost_counters()
	_attack_effects = 0
	_element_effects = 0
	_fusion_effects = 0
	_frame_ms.clear()
	_process_ms.clear()
	_node_counts.clear()
	_previous_frame_usec = Time.get_ticks_usec()
	_measuring = true
	await _wait_real(SAMPLE_SECONDS)
	_measuring = false
	var counters := manager.debug_get_spawn_cost_counters()
	var living := _living_enemy_count()
	var result := {
		"label": label,
		"build": "late_solar_lv3x2" if late_build else "early_no_element",
		"seconds": SAMPLE_SECONDS,
		"frames": _frame_ms.size(),
		"enemies": living,
		"start_nodes": start_nodes,
		"node_avg": _average_int(_node_counts),
		"node_min": _minimum_int(_node_counts),
		"node_max": _maximum_int(_node_counts),
		"time_process_avg_ms": _average(_process_ms),
		"time_process_p95_ms": _percentile(_process_ms, 0.95),
		"frame_avg_ms": _average(_frame_ms),
		"frame_p95_ms": _percentile(_frame_ms, 0.95),
		"frame_max_ms": _maximum(_frame_ms),
		"attack_vfx_per_second": float(_attack_effects) / SAMPLE_SECONDS,
		"element_vfx_per_second": float(_element_effects) / SAMPLE_SECONDS,
		"fusion_vfx_per_second": float(_fusion_effects) / SAMPLE_SECONDS,
		"total_vfx_per_second": float(_attack_effects + _element_effects + _fusion_effects) / SAMPLE_SECONDS,
		"element_sprite_calls_per_second": float(counters.get("element_sprite_calls", 0)) / SAMPLE_SECONDS,
		"height_calls": int(counters.get("player_visual_height_calls", 0)),
		"height_image_reads": int(counters.get("player_visual_height_image_reads", 0)),
		"player_visual_height": float(counters.get("player_visual_height_cache", 0.0)),
	}
	print("VFX_STALL_RESULT %s" % JSON.stringify(result))
	_expect(living == ENEMY_COUNT, "計測終了時の生存敵が48体ではありません")
	_expect(player.weapon_manager.process_mode != Node.PROCESS_MODE_DISABLED, "Player Weaponが計測中に無効です")
	_expect(_attack_effects + _element_effects + _fusion_effects > 0, "実攻撃からVFXが生成されていません")
	if DisplayServer.get_name() != "headless":
		await _capture(label)
	_finish(character_data, original_crit_chance)

func _run_icon_cache_probe(game: Node, player: Player, manager: AttackVFXManager) -> void:
	GroundEquipmentItem.debug_reset_icon_read_cache()
	manager.debug_reset_spawn_cost_counters()
	for index in 8:
		var equipment := EquipmentData.new()
		equipment.instance_id = "vfx_icon_cache_%d" % index
		equipment.display_name = "ICON CACHE PROBE"
		equipment.slot = "weapon"
		equipment.rarity = "uncommon"
		equipment.icon_path = "res://assets/items/weapons/weapon_sword_uncommon_001.png"
		var ground := GROUND_EQUIPMENT_SCENE.instantiate() as GroundEquipmentItem
		ground.setup(equipment)
		game.add_child(ground)
		ground.global_position = player.global_position + Vector2(index * 6.0, 90.0)
	await _wait_frames(3)
	var icon_snapshot := GroundEquipmentItem.debug_get_icon_read_snapshot()
	var vfx_snapshot := manager.debug_get_spawn_cost_counters()
	print("VFX_ICON_CACHE_RESULT icons=8 cached_paths=%d icon_image_reads=%d player_height_calls=%d player_height_image_reads=%d" % [
		int(icon_snapshot.get("cached_paths", 0)), int(icon_snapshot.get("image_reads", 0)),
		int(vfx_snapshot.get("player_visual_height_calls", 0)), int(vfx_snapshot.get("player_visual_height_image_reads", 0)),
	])
	_expect(int(icon_snapshot.get("cached_paths", 0)) == 1, "同一icon_pathが1件に集約されていません")
	_expect(int(icon_snapshot.get("image_reads", -1)) == 0, "装備Dropは事前計算Boundsを使い、get_image()を実行してはいけません")
	_expect(int(vfx_snapshot.get("player_visual_height_image_reads", -1)) == 0, "Drop生成からPlayer Sprite読み戻しが発生しました")

func _disable_non_test_progression(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager", "MapRunController"]:
		var node := game.get_node_or_null(node_name)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()

func _spawn_fixed_enemies(game: Node, player: Player) -> void:
	var data := EnemyData.new()
	data.id = "vfx_stall_target"
	data.display_name = "VFX STALL TARGET"
	data.max_hp = 1000000000000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 9999.0
	data.attack_windup = 9999.0
	data.exp_value = 0
	data.sprite_folder = "enemies/Orc"
	for index in ENEMY_COUNT:
		var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
		enemy.enemy_data = data
		enemy.visual_scale_multiplier = 0.7
		game.add_child(enemy)
		var ring := 0 if index < 16 else 1
		var ring_index := index if ring == 0 else index - 16
		var ring_count := 16 if ring == 0 else 32
		var radius := 38.0 if ring == 0 else 58.0
		var angle := TAU * float(ring_index) / float(ring_count)
		enemy.global_position = player.global_position + Vector2.RIGHT.rotated(angle) * radius

func _living_enemy_count() -> int:
	var count := 0
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy_variant):
			continue
		var health := (enemy_variant as Node).get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.current_hp > 0.0:
			count += 1
	return count

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUTPUT_DIR, label]))
	_expect(error == OK, "Vulkan画面Captureを保存できません")

func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * ratio) - 1, 0, sorted.size() - 1)]

func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result

func _average_int(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += value
	return float(total) / float(values.size())

func _minimum_int(values: Array[int]) -> int:
	var result := values[0] if not values.is_empty() else 0
	for value in values:
		result = mini(result, value)
	return result

func _maximum_int(values: Array[int]) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish(character_data: CharacterData, original_crit_chance: float) -> void:
	if character_data != null:
		character_data.crit_chance = original_crit_chance
	for failure in _failures:
		push_error("VFX_STALL_CHECK: %s" % failure)
	AudioManager.stop_all()
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)
