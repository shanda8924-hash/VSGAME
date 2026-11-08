extends Node
## 通常のgame.tscn/MAP Runtime上で攻撃・撃破・Drop・VFXを止めず、
## 論理25分のNode/Object/Frame timeを30秒刻みで採取するPhase 1専用Harness。
## 製品設定は変更せず、`-- --map-performance-check`でのみ動作する。

const LOGICAL_DURATION_SECONDS := 1500.0
const SAMPLE_INTERVAL_SECONDS := 30.0
const FORCED_KILL_INTERVAL_SECONDS := 1.25
const CONTROLLED_ELITE_INTERVAL_SECONDS := 30.0
const TIME_SCALE := 10.0

var controller: MapRunController
var player: Player
var equipment_drop_system: EquipmentDropSystem

var _started_at := 0.0
var _next_sample_at := 0.0
var _next_kill_at := 0.0
var _next_controlled_elite_at := 0.0
var _forced_kills := 0
var _controlled_elite_kills := 0
var _combat_target_id := 0
var _previous_frame_usec := 0
var _wall_frame_ms: Array[float] = []
var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _samples: Array[Dictionary] = []
var _initial_class_histogram: Dictionary = {}
var _initial_name_histogram: Dictionary = {}
var _failures: Array[String] = []
var _surge_frame_ms: Array[float] = []
var _surge_peak_enemies := 0
var _surge_peak_enemy_group_nodes := 0

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	process_mode = Node.PROCESS_MODE_ALWAYS
	controller = get_parent().get_node("MapRunController") as MapRunController
	player = get_parent().get_node("Player") as Player
	equipment_drop_system = get_parent().get_node("EquipmentDropSystem") as EquipmentDropSystem
	_previous_frame_usec = Time.get_ticks_usec()
	_run.call_deferred()

func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if _previous_frame_usec > 0:
		var frame_ms := float(now_usec - _previous_frame_usec) / 1000.0
		_wall_frame_ms.append(frame_ms)
		if controller != null and controller._surge_active:
			_surge_frame_ms.append(frame_ms)
			_surge_peak_enemies = maxi(_surge_peak_enemies, _count_living_enemies())
			_surge_peak_enemy_group_nodes = maxi(_surge_peak_enemy_group_nodes, get_tree().get_nodes_in_group("enemies").size())
	_process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	_physics_ms.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	_previous_frame_usec = now_usec

func _run() -> void:
	await _wait_frames(12)
	player.health_component.max_hp = 1000000000.0
	player.health_component.current_hp = 1000000000.0
	if "--map-mass-density-check" in OS.get_cmdline_user_args():
		await _run_mass_density_probe()
		return
	if "--map-performance-feature-check" in OS.get_cmdline_user_args():
		await _run_ground_equipment_feature_probe()
		# 短縮経路はMark cleanupの成立確認が目的。敵密度の増加待ちは行わず、
		# 長時間経路側で12体への一括cleanupを別途確認する。
		await _wait_for_living_enemies(1, 30)
		_finish_from_failures("MAP_PERFORMANCE_FEATURE_CHECK")
		return
	_initial_class_histogram = _node_histogram(false)
	_initial_name_histogram = _node_histogram(true)
	Engine.time_scale = TIME_SCALE
	_started_at = GameManager.elapsed_seconds
	_next_sample_at = _started_at
	_next_kill_at = _started_at + FORCED_KILL_INTERVAL_SECONDS
	_next_controlled_elite_at = _started_at + CONTROLLED_ELITE_INTERVAL_SECONDS
	print("PERF_CHECK_BEGIN logical_duration=%.0f sample_interval=%.0f time_scale=%.1f weapon_process_mode=%d movement_locked=%s" % [
		LOGICAL_DURATION_SECONDS,
		SAMPLE_INTERVAL_SECONDS,
		TIME_SCALE,
		player.weapon_manager.process_mode,
		player._movement_locked_by_attack,
	])
	_sample(0.0)
	_next_sample_at += SAMPLE_INTERVAL_SECONDS
	while GameManager.elapsed_seconds - _started_at < LOGICAL_DURATION_SECONDS:
		await _close_visible_reward_modals()
		_drive_combat()
		var elapsed := GameManager.elapsed_seconds - _started_at
		if GameManager.elapsed_seconds >= _next_kill_at:
			_force_one_enemy_death(GameManager.elapsed_seconds >= _next_controlled_elite_at)
			_next_kill_at += FORCED_KILL_INTERVAL_SECONDS
			if GameManager.elapsed_seconds >= _next_controlled_elite_at:
				_next_controlled_elite_at += CONTROLLED_ELITE_INTERVAL_SECONDS
		if GameManager.elapsed_seconds >= _next_sample_at:
			_sample(elapsed)
			_next_sample_at += SAMPLE_INTERVAL_SECONDS
		await get_tree().process_frame
	_release_movement()
	_sample(GameManager.elapsed_seconds - _started_at)
	_print_growth_summary()
	_print_surge_peak_summary()
	await _run_ground_equipment_cleanup_probe()
	await _run_ground_equipment_feature_probe()
	Engine.time_scale = 1.0
	_finish_from_failures("MAP_PERFORMANCE_ACCUMULATION_CHECK logical_seconds=%.1f samples=%d forced_kills=%d controlled_elite_kills=%d" % [
		GameManager.elapsed_seconds - _started_at,
		_samples.size(),
		_forced_kills,
		_controlled_elite_kills,
	])

func _run_mass_density_probe() -> void:
	var wave_spawner := get_parent().get_node("WaveSpawner") as WaveSpawner
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	controller._start_map(3)
	await _wait_frames(4)
	GameManager.elapsed_seconds = wave_spawner._map_started_elapsed + 720.0
	var started_usec := Time.get_ticks_usec()
	for _iteration in 32:
		wave_spawner._timer = 0.0
		wave_spawner._process(1.0)
		await get_tree().process_frame
	var spawned := _count_living_enemies()
	var frame_times: Array[float] = []
	var previous_usec := Time.get_ticks_usec()
	for _frame in 180:
		await get_tree().process_frame
		var current_usec := Time.get_ticks_usec()
		frame_times.append(float(current_usec - previous_usec) / 1000.0)
		previous_usec = current_usec
	var settled := _count_living_enemies()
	var total_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	_expect(spawned >= 180, "MAP3終盤の大群が180体以上まで生成されません")
	_expect(spawned <= 192 and settled <= 192, "MAP3の生存敵上限192体を超えました")
	print("MAP_MASS_DENSITY spawned=%d settled=%d cap=192 frame_avg_ms=%.4f frame_p95_ms=%.4f frame_max_ms=%.4f total_ms=%.1f" % [
		spawned,
		settled,
		_average(frame_times),
		_percentile(frame_times, 0.95),
		_maximum(frame_times),
		total_ms,
	])
	_finish_from_failures("MAP_MASS_DENSITY_CHECK")

func _force_one_enemy_death(controlled_elite_drop: bool) -> void:
	var target := _nearest_living_enemy()
	if target == null:
		return
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.current_hp <= 0.0:
		return
	if controlled_elite_drop and not target.is_in_group("elite_enemies"):
		# Real EnemyBasic death -> EventBus.enemy_drop_requested pathを通しつつ、
		# 30秒に1回だけ確定Dropにして蓄積量を再現可能にする。
		target.add_to_group("elite_enemies")
		_controlled_elite_kills += 1
	health.current_hp = minf(health.current_hp, 1.0)
	health.apply_secondary_damage(99999999.0, CombatEventMeta.create_secondary("performance_soak_forced_death", [], false))
	_forced_kills += 1

func _drive_combat() -> void:
	var nearest := _nearest_living_enemy()
	if nearest == null:
		_release_movement()
		return
	_combat_target_id = nearest.get_instance_id()
	var offset := nearest.global_position - player.global_position
	var direction := offset.normalized() if offset.length() > 42.0 else Vector2.ZERO
	_set_movement(direction)

func _nearest_living_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance := INF
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy_variant) or not (enemy_variant is Node2D):
			continue
		var enemy := enemy_variant as Node2D
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			continue
		var distance := player.global_position.distance_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest

func _set_movement(direction: Vector2) -> void:
	if direction.x < -0.18: Input.action_press("ui_left", -direction.x)
	else: Input.action_release("ui_left")
	if direction.x > 0.18: Input.action_press("ui_right", direction.x)
	else: Input.action_release("ui_right")
	if direction.y < -0.18: Input.action_press("ui_up", -direction.y)
	else: Input.action_release("ui_up")
	if direction.y > 0.18: Input.action_press("ui_down", direction.y)
	else: Input.action_release("ui_down")

func _release_movement() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)

func _sample(elapsed: float) -> void:
	var live_enemies := _count_living_enemies()
	var ground_items := get_tree().get_nodes_in_group("ground_equipment")
	var ground_rarity_counts := _ground_rarity_counts(ground_items)
	var ground_nodes := 0
	var ground_particles := 0
	for item_variant in ground_items:
		if not is_instance_valid(item_variant):
			continue
		ground_nodes += _count_subtree_nodes(item_variant as Node)
		ground_particles += _count_subtree_type(item_variant as Node, "CPUParticles2D")
	var sample := {
		"elapsed": elapsed,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"process_avg_ms": _average(_process_ms),
		"process_p95_ms": _percentile(_process_ms, 0.95),
		"physics_avg_ms": _average(_physics_ms),
		"physics_p95_ms": _percentile(_physics_ms, 0.95),
		"frame_avg_ms": _average(_wall_frame_ms),
		"frame_p95_ms": _percentile(_wall_frame_ms, 0.95),
		"frame_max_ms": _maximum(_wall_frame_ms),
		"enemies": live_enemies,
		"enemy_group": get_tree().get_nodes_in_group("enemies").size(),
		"ground": ground_items.size(),
		"ground_low": int(ground_rarity_counts["low"]),
		"ground_high": int(ground_rarity_counts["high"]),
		"ground_pending": int(ground_rarity_counts["pending"]),
		"ground_nodes": ground_nodes,
		"ground_particles": ground_particles,
		"cpu_particles": _count_tree_type("CPUParticles2D"),
		"emitting_cpu_particles": _count_emitting_tree_particles(),
		"projectiles": get_tree().get_nodes_in_group("projectiles").size(),
		"transient_vfx": get_tree().get_nodes_in_group("transient_vfx").size(),
		"kills": GameManager.kill_count,
		"forced_kills": _forced_kills,
		"controlled_elite_kills": _controlled_elite_kills,
	}
	_samples.append(sample)
	print("PERF_SAMPLE logical=%.1f nodes=%d objects=%d process_avg_ms=%.4f process_p95_ms=%.4f physics_avg_ms=%.4f physics_p95_ms=%.4f frame_avg_ms=%.4f frame_p95_ms=%.4f frame_max_ms=%.4f enemies=%d enemy_group=%d ground=%d ground_low=%d ground_high=%d ground_pending=%d ground_nodes=%d ground_particles=%d cpu_particles=%d emitting_cpu_particles=%d projectiles=%d transient_vfx=%d kills=%d forced_kills=%d controlled_elite_kills=%d" % [
		float(sample["elapsed"]), int(sample["nodes"]), int(sample["objects"]),
		float(sample["process_avg_ms"]), float(sample["process_p95_ms"]),
		float(sample["physics_avg_ms"]), float(sample["physics_p95_ms"]),
		float(sample["frame_avg_ms"]), float(sample["frame_p95_ms"]), float(sample["frame_max_ms"]),
		int(sample["enemies"]), int(sample["enemy_group"]), int(sample["ground"]),
		int(sample["ground_low"]), int(sample["ground_high"]), int(sample["ground_pending"]),
		int(sample["ground_nodes"]), int(sample["ground_particles"]), int(sample["cpu_particles"]), int(sample["emitting_cpu_particles"]),
		int(sample["projectiles"]), int(sample["transient_vfx"]), int(sample["kills"]),
		int(sample["forced_kills"]), int(sample["controlled_elite_kills"]),
	])
	_wall_frame_ms.clear()
	_process_ms.clear()
	_physics_ms.clear()

func _print_growth_summary() -> void:
	if _samples.size() < 2:
		return
	var first: Dictionary = _samples.front()
	var last: Dictionary = _samples.back()
	print("PERF_SUMMARY node_delta=%d object_delta=%d enemy_delta=%d ground_delta=%d ground_node_delta=%d ground_particle_delta=%d cpu_particle_delta=%d process_avg_delta_ms=%.4f physics_avg_delta_ms=%.4f frame_avg_delta_ms=%.4f corr_ground_nodes=%.4f corr_ground_process=%.4f corr_ground_physics=%.4f corr_ground_frame=%.4f" % [
		int(last["nodes"]) - int(first["nodes"]),
		int(last["objects"]) - int(first["objects"]),
		int(last["enemies"]) - int(first["enemies"]),
		int(last["ground"]) - int(first["ground"]),
		int(last["ground_nodes"]) - int(first["ground_nodes"]),
		int(last["ground_particles"]) - int(first["ground_particles"]),
		int(last["cpu_particles"]) - int(first["cpu_particles"]),
		float(last["process_avg_ms"]) - float(first["process_avg_ms"]),
		float(last["physics_avg_ms"]) - float(first["physics_avg_ms"]),
		float(last["frame_avg_ms"]) - float(first["frame_avg_ms"]),
		_correlation("ground", "nodes"),
		_correlation("ground", "process_avg_ms"),
		_correlation("ground", "physics_avg_ms"),
		_correlation("ground", "frame_avg_ms"),
	])
	var steady_samples := _samples.filter(func(sample: Dictionary): return float(sample["elapsed"]) >= 300.0)
	if steady_samples.size() >= 2:
		var steady_first: Dictionary = steady_samples.front()
		var steady_last: Dictionary = steady_samples.back()
		print("PERF_STEADY_SUMMARY start_logical=%.1f end_logical=%.1f node_delta=%d enemy_delta=%d ground_delta=%d ground_low_start=%d ground_low_end=%d ground_high_start=%d ground_high_end=%d ground_pending_end=%d ground_node_delta=%d cpu_particle_delta=%d corr_ground_nodes=%.4f corr_ground_process=%.4f corr_ground_physics=%.4f corr_ground_frame_avg=%.4f corr_ground_frame_p95=%.4f" % [
			float(steady_first["elapsed"]), float(steady_last["elapsed"]),
			int(steady_last["nodes"]) - int(steady_first["nodes"]),
			int(steady_last["enemies"]) - int(steady_first["enemies"]),
			int(steady_last["ground"]) - int(steady_first["ground"]),
			int(steady_first["ground_low"]), int(steady_last["ground_low"]),
			int(steady_first["ground_high"]), int(steady_last["ground_high"]),
			int(steady_last["ground_pending"]),
			int(steady_last["ground_nodes"]) - int(steady_first["ground_nodes"]),
			int(steady_last["cpu_particles"]) - int(steady_first["cpu_particles"]),
			_correlation("ground", "nodes", 300.0),
			_correlation("ground", "process_avg_ms", 300.0),
			_correlation("ground", "physics_avg_ms", 300.0),
			_correlation("ground", "frame_avg_ms", 300.0),
			_correlation("ground", "frame_p95_ms", 300.0),
		])
	print("PERF_WINDOW_COMPARE early_frame_avg_ms=%.4f late_frame_avg_ms=%.4f early_frame_p95_ms=%.4f late_frame_p95_ms=%.4f early_process_avg_ms=%.4f late_process_avg_ms=%.4f early_physics_avg_ms=%.4f late_physics_avg_ms=%.4f" % [
		_window_average("frame_avg_ms", 300.0, 600.0), _window_average("frame_avg_ms", 1200.0, 1501.0),
		_window_average("frame_p95_ms", 300.0, 600.0), _window_average("frame_p95_ms", 1200.0, 1501.0),
		_window_average("process_avg_ms", 300.0, 600.0), _window_average("process_avg_ms", 1200.0, 1501.0),
		_window_average("physics_avg_ms", 300.0, 600.0), _window_average("physics_avg_ms", 1200.0, 1501.0),
	])
	_print_histogram_growth("class", _initial_class_histogram, _node_histogram(false))
	_print_histogram_growth("name", _initial_name_histogram, _node_histogram(true))

func _print_surge_peak_summary() -> void:
	print("PERF_SURGE_PEAK samples=%d peak_living_enemies=%d peak_enemy_group_nodes=%d frame_avg_ms=%.4f frame_p95_ms=%.4f frame_max_ms=%.4f" % [
		_surge_frame_ms.size(),
		_surge_peak_enemies,
		_surge_peak_enemy_group_nodes,
		_average(_surge_frame_ms),
		_percentile(_surge_frame_ms, 0.95),
		_maximum(_surge_frame_ms),
	])


func _run_ground_equipment_cleanup_probe() -> void:
	var items := get_tree().get_nodes_in_group("ground_equipment")
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var particles_before := _count_tree_type("CPUParticles2D")
	var last_sample: Dictionary = _samples.back()
	for item_variant in items:
		if is_instance_valid(item_variant):
			(item_variant as Node).queue_free()
	await _wait_frames(5)
	_wall_frame_ms.clear()
	_process_ms.clear()
	_physics_ms.clear()
	var probe_started := GameManager.elapsed_seconds
	while GameManager.elapsed_seconds - probe_started < SAMPLE_INTERVAL_SECONDS:
		await _close_visible_reward_modals()
		await get_tree().process_frame
	print("PERF_GROUND_CLEANUP_PROBE ground_before=%d ground_after=%d nodes_before=%d nodes_after=%d cpu_particles_before=%d cpu_particles_after=%d frame_avg_before_ms=%.4f frame_avg_after_ms=%.4f frame_p95_before_ms=%.4f frame_p95_after_ms=%.4f process_avg_after_ms=%.4f physics_avg_after_ms=%.4f" % [
		items.size(), get_tree().get_nodes_in_group("ground_equipment").size(),
		nodes_before, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		particles_before, _count_tree_type("CPUParticles2D"),
		float(last_sample["frame_avg_ms"]), _average(_wall_frame_ms),
		float(last_sample["frame_p95_ms"]), _percentile(_wall_frame_ms, 0.95),
		_average(_process_ms), _average(_physics_ms),
	])

func _run_ground_equipment_feature_probe() -> void:
	for item_variant in get_tree().get_nodes_in_group("ground_equipment"):
		if is_instance_valid(item_variant):
			(item_variant as Node).queue_free()
	await _wait_frames(3)
	var runtime_world := GameManager.get_runtime_world(self)
	var ground_scene := load("res://entities/pickups/ground_equipment_item.tscn") as PackedScene
	var visibility_item := ground_scene.instantiate() as GroundEquipmentItem
	visibility_item.setup(_make_probe_equipment("uncommon", "visibility_probe", 0.0))
	runtime_world.add_child(visibility_item)
	var camera := get_viewport().get_camera_2d()
	var screen_center := camera.get_screen_center_position() if camera != null else player.global_position
	visibility_item.global_position = screen_center + Vector2(5000.0, 5000.0)
	await _wait_render_frames(4)
	var seal := visibility_item.get_node_or_null("Visual/RoyalLootSeal") as PixelSpriteVFX
	_expect(visibility_item.get_node_or_null("Visual/ItemLabel") == null and visibility_item.get_node_or_null("Visual/Prompt") == null, "範囲外の床装備がLabelを先行生成しています")
	_expect(seal != null and seal.get_meta("pixel_vfx_id", "") == "loot_seal" and not seal.is_processing(), "画面外の床装備の紋が静止1コマになっていません")
	_expect(visibility_item.get_node_or_null("Visual/LootAmbientParticles") == null and visibility_item.get_node_or_null("Visual/ParticleVisibilityNotifier") == null, "撤去した常駐Emitter/Notifierが残っています")
	visibility_item.global_position = screen_center
	await _wait_render_frames(4)
	_expect(seal != null and seal.is_visible_in_tree() and not seal.is_processing(), "画面内へ戻った静止紋章が表示されないか常時処理されています")
	visibility_item._on_body_entered(player)
	_expect(visibility_item.get_node_or_null("Visual/ItemLabel") is Label and visibility_item.get_node_or_null("Visual/Prompt") is Label, "初回接近時にLabelが遅延生成されません")
	visibility_item._on_body_exited(player)
	visibility_item.global_position = screen_center + Vector2(5000.0, 5000.0)
	await _wait_render_frames(4)
	_expect(seal != null and not seal.is_processing() and visibility_item.get_node_or_null("Visual/LootAmbientParticles") == null, "再度画面外へ出た床装備が常駐Particleを生成しました")
	visibility_item.queue_free()
	await _wait_frames(2)

	var cap := int(equipment_drop_system._drop_table.get("ground_item_low_rarity_cap", 24))
	var warning_seconds := float(equipment_drop_system._drop_table.get("ground_item_expiration_warning_seconds", 1.2))
	var legendary := equipment_drop_system.debug_drop_equipment(_make_probe_equipment("legendary", "legendary_probe", 0.0), player.global_position)
	var mythic := equipment_drop_system.debug_drop_equipment(_make_probe_equipment("mythic", "mythic_probe", 0.0), player.global_position)
	var collectible := equipment_drop_system.debug_drop_equipment(_make_probe_equipment("uncommon", "cap_collectible", 12.0), player.global_position)
	await _wait_frames(1)
	for index in cap:
		equipment_drop_system.debug_drop_equipment(_make_probe_equipment("uncommon", "cap_probe_%d" % index, 0.0), player.global_position)
	await _wait_frames(2)
	var pending_items := _low_rarity_ground_items().filter(func(item: GroundEquipmentItem): return item.cap_expiration_pending)
	_expect(not pending_items.is_empty(), "上限超過した低Rarity装備が削除予約されません")
	_expect(collectible != null and collectible.cap_expiration_pending, "最古の低Rarity装備が削除対象になっていません")
	var inventory_before := player.equipment_component.get_all_inventory().size()
	var collectible_ref: WeakRef = weakref(collectible)
	var collected_data := collectible.equipment
	_expect(collectible.collect(player), "点滅中の床装備を取得できません")
	await _wait_frames(3)
	_expect(collectible_ref.get_ref() == null, "点滅中取得後に床装備Nodeが残っています")
	_expect(player.equipment_component.get_all_inventory().size() == inventory_before + 1, "点滅中取得がInventoryへ反映されません")
	_expect(player.equipment_component.equip(collected_data), "点滅中取得した装備を装着できません")
	_expect(is_equal_approx(player.upgrades_component.equipment_attack_flat, 12.0), "取得・装着した装備AttackがStatusへ反映されません")
	var treasure_item := equipment_drop_system.spawn_treasure_drop(player.global_position, "uncommon")
	await get_tree().create_timer(warning_seconds + 0.25).timeout
	await _wait_frames(3)
	var cap_settled := await _wait_for_low_ground_at_most(cap, 3000)
	var low_after := _low_rarity_ground_items()
	var pending_after := low_after.filter(func(item: GroundEquipmentItem): return item.cap_expiration_pending)
	_expect(cap_settled and low_after.size() <= cap, "低Rarity床装備が点滅削除後も上限を超えています: %d/%d (pending=%d)" % [low_after.size(), cap, pending_after.size()])
	_expect(is_instance_valid(legendary) and is_instance_valid(mythic), "Legendary/Mythicが自動削除されました")
	_expect(is_instance_valid(treasure_item), "最新の宝箱Dropが上限処理で誤削除されました")
	print("PERF_GROUND_FEATURE_PROBE cap=%d low_after=%d pending_after=%d pending_before_collect=%d cap_settled=%s legendary_alive=%s mythic_alive=%s treasure_alive=%s inventory_delta=%d attack_flat=%.1f" % [
		cap, low_after.size(), pending_after.size(), pending_items.size(), cap_settled, is_instance_valid(legendary), is_instance_valid(mythic), is_instance_valid(treasure_item),
		player.equipment_component.get_all_inventory().size() - inventory_before, player.upgrades_component.equipment_attack_flat,
	])
	for item_variant in get_tree().get_nodes_in_group("ground_equipment"):
		if is_instance_valid(item_variant):
			(item_variant as Node).queue_free()
	await _wait_frames(3)

func _make_probe_equipment(rarity: String, id: String, attack_power: float) -> EquipmentData:
	var item := EquipmentData.new()
	item.instance_id = id
	item.template_id = "performance_probe"
	item.display_name = "Performance Probe"
	item.slot = "weapon"
	item.rarity = rarity
	item.icon_path = "res://assets/items/weapons/weapon_sword_uncommon_001.png"
	if attack_power > 0.0:
		item.stats = {"attack_power": attack_power}
	return item

func _low_rarity_ground_items() -> Array[GroundEquipmentItem]:
	var result: Array[GroundEquipmentItem] = []
	for item_variant in get_tree().get_nodes_in_group("ground_equipment"):
		var item := item_variant as GroundEquipmentItem
		if item != null and is_instance_valid(item) and item.equipment != null and item.equipment.rarity in ["uncommon", "rare", "epic"]:
			result.append(item)
	return result

func _ground_rarity_counts(items: Array) -> Dictionary:
	var counts := {"low": 0, "high": 0, "pending": 0}
	for item_variant in items:
		var item := item_variant as GroundEquipmentItem
		if item == null or not is_instance_valid(item) or item.equipment == null:
			continue
		if item.equipment.rarity in ["uncommon", "rare", "epic"]:
			counts["low"] = int(counts["low"]) + 1
			if item.cap_expiration_pending:
				counts["pending"] = int(counts["pending"]) + 1
		elif item.equipment.rarity in ["legendary", "mythic"]:
			counts["high"] = int(counts["high"]) + 1
	return counts

func _wait_for_low_ground_at_most(maximum: int, timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if _low_rarity_ground_items().size() <= maximum:
			return true
		await get_tree().process_frame
	return _low_rarity_ground_items().size() <= maximum

func _wait_for_living_enemies(minimum: int, maximum_frames: int) -> void:
	for _frame in maximum_frames:
		if _count_living_enemies() >= minimum:
			return
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish_from_failures(label: String) -> void:
	Engine.time_scale = 1.0
	if _failures.is_empty():
		_finish(0, "%s: PASS" % label)
	else:
		for failure in _failures:
			push_error("%s: %s" % [label, failure])
		_finish(1, "")


func _count_living_enemies() -> int:
	var count := 0
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy_variant):
			continue
		var health := (enemy_variant as Node).get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.current_hp > 0.0:
			count += 1
	return count

func _count_tree_type(type_name: String) -> int:
	return _count_subtree_type(get_tree().root, type_name)

func _count_emitting_tree_particles() -> int:
	var count := 0
	for node in get_tree().root.find_children("*", "CPUParticles2D", true, false):
		if (node as CPUParticles2D).emitting:
			count += 1
	return count

func _count_subtree_type(root: Node, type_name: String) -> int:
	var count := 1 if root.is_class(type_name) else 0
	for child in root.get_children():
		count += _count_subtree_type(child, type_name)
	return count

func _count_subtree_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_subtree_nodes(child)
	return count

func _node_histogram(by_name: bool) -> Dictionary:
	var histogram := {}
	_accumulate_histogram(get_tree().root, histogram, by_name)
	return histogram

func _accumulate_histogram(node: Node, histogram: Dictionary, by_name: bool) -> void:
	var key := String(node.name) if by_name else node.get_class()
	histogram[key] = int(histogram.get(key, 0)) + 1
	for child in node.get_children():
		_accumulate_histogram(child, histogram, by_name)

func _print_histogram_growth(kind: String, before: Dictionary, after: Dictionary) -> void:
	var growth: Array[Dictionary] = []
	for key_variant in after.keys():
		var key := String(key_variant)
		var delta := int(after[key]) - int(before.get(key, 0))
		if delta > 0:
			growth.append({"key": key, "delta": delta})
	growth.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["delta"]) > int(b["delta"]))
	for index in mini(15, growth.size()):
		print("PERF_HISTOGRAM_GROWTH kind=%s key=%s delta=%d" % [kind, String(growth[index]["key"]), int(growth[index]["delta"])])

func _correlation(x_key: String, y_key: String, minimum_elapsed: float = 0.0) -> float:
	var selected := _samples.filter(func(sample: Dictionary): return float(sample["elapsed"]) >= minimum_elapsed)
	if selected.size() < 2:
		return 0.0
	var x_mean := 0.0
	var y_mean := 0.0
	for sample in selected:
		x_mean += float(sample[x_key])
		y_mean += float(sample[y_key])
	x_mean /= selected.size()
	y_mean /= selected.size()
	var numerator := 0.0
	var x_variance := 0.0
	var y_variance := 0.0
	for sample in selected:
		var x_delta := float(sample[x_key]) - x_mean
		var y_delta := float(sample[y_key]) - y_mean
		numerator += x_delta * y_delta
		x_variance += x_delta * x_delta
		y_variance += y_delta * y_delta
	var denominator := sqrt(x_variance * y_variance)
	return numerator / denominator if denominator > 0.000001 else 0.0

func _window_average(key: String, minimum_elapsed: float, maximum_elapsed: float) -> float:
	var values: Array[float] = []
	for sample in _samples:
		var elapsed := float(sample["elapsed"])
		if elapsed >= minimum_elapsed and elapsed <= maximum_elapsed:
			values.append(float(sample[key]))
	return _average(values)

func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()

func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result

func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil((sorted.size() - 1) * ratio)), 0, sorted.size() - 1)]

func _close_visible_reward_modals() -> void:
	for _attempt in 12:
		var pressed := false
		for ui_name in ["ConceptSelect", "LevelUpSelect", "ItemSelect"]:
			var ui := get_parent().get_node_or_null(ui_name) as CanvasLayer
			if ui and ui.visible:
				pressed = _press_first_enabled_button(ui) or pressed
		if not pressed:
			return
		await _wait_frames(2)

func _press_first_enabled_button(root: Node) -> bool:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.visible and not button.disabled:
			button.pressed.emit()
			if root is LevelUpSelect: root.confirm_selection()
			return true
	return false

func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _wait_render_frames(count: int) -> void:
	for _index in count:
		# Dummy rendererのheadlessでは描画完了Signalが発火しない。
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		await get_tree().process_frame

func _finish(exit_code: int, message: String) -> void:
	_release_movement()
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(exit_code, message)
