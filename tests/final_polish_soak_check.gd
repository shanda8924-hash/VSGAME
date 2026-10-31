extends Node
## 実Game Sceneを用いた完成前の耐久・ゲームループ回帰テスト。
## 600秒時点のSpawn条件で大量生成/死亡を圧縮反復し、終了待ち後の残留も検査する。

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const PROJECTILE_SCENE := preload("res://entities/projectiles/projectile.tscn")

const EQUIVALENT_PLAY_SECONDS := 600.0
const ENEMY_BATCHES := 40
const ENEMIES_PER_BATCH := 12
const PROJECTILE_STRESS_COUNT := 240
const IAI_REPETITIONS := 10

var failures: Array[String] = []
var metrics: Dictionary = {}
var _focus_checked: Dictionary = {}
var _capture_flags: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var started_ms := Time.get_ticks_msec()
	await _run_soak_and_game_loop()
	metrics["wall_seconds"] = (Time.get_ticks_msec() - started_ms) / 1000.0
	for failure in failures:
		push_error(failure)
	print("FINAL_POLISH_SOAK_CHECK failures=%d metrics=%s" % [failures.size(), metrics])
	get_tree().paused = false
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_soak_and_game_loop() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := await _instantiate_game()
	var player := game.get_node("Player") as Player
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	var boss_spawner := game.get_node("BossSpawner") as BossSpawner
	var attack_vfx := game.get_node("AttackVFXManager") as AttackVFXManager
	var effect_vfx := game.get_node("EffectThemeManager") as EffectThemeManager

	_disable_automatic_managers(game)
	player.health_component.invincible = true
	GameManager.elapsed_seconds = EQUIVALENT_PLAY_SECONDS
	metrics["baseline_nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	metrics["baseline_resources"] = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	metrics["baseline_memory"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	metrics["baseline_orphans"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var baseline_signal_connections := _event_connection_snapshot()
	metrics["baseline_signal_connections"] = baseline_signal_connections

	await get_tree().process_frame
	_check(not player.weapon_manager.has_weapon("steam_burst_weapon"), "new Fusion state does not also create the legacy Fusion weapon")

	# 600秒時点の候補・Spawn位置選択を使い、480体を生成して本番死亡経路へ通す。
	var kills_before := GameManager.kill_count
	for batch in ENEMY_BATCHES:
		for _spawn_index in ENEMIES_PER_BATCH:
			wave._spawn_enemy()
		await get_tree().physics_frame
		if batch == 0:
			await _capture_if_gui("mass_combat")
		var living := _living_non_boss_enemies()
		for enemy in living:
			enemy.health_component.current_hp = 1.0
			enemy.health_component.apply_damage(10.0)
		await get_tree().process_frame
		await _drain_modals(game)
		if batch == 9:
			await _wait_real(1.0)
			metrics["warm_nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			metrics["warm_resources"] = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
			metrics["warm_memory"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	metrics["enemy_kills"] = GameManager.kill_count - kills_before
	_check(int(metrics["enemy_kills"]) >= ENEMY_BATCHES * ENEMIES_PER_BATCH, "all stress enemies reach the normal death pipeline")
	_check(player.experience_component.level > 1, "enemy deaths grant EXP and consecutive level ups")
	_check(GameManager.active_modal_count == 0 and not get_tree().paused, "consecutive level-up choices fully drain and resume play")

	await _wait_real(1.2)
	metrics["post_kill_nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	metrics["post_kill_resources"] = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	metrics["post_kill_memory"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_check(int(metrics["post_kill_nodes"]) <= int(metrics["warm_nodes"]) + 100, "node count does not grow unbounded after repeated spawn/death")
	_check(int(metrics["post_kill_resources"]) <= int(metrics["warm_resources"]) + 40, "resource count stabilizes after enemy assets are warmed")
	_check(int(metrics["post_kill_memory"]) <= int(metrics["warm_memory"]) + 24 * 1024 * 1024, "static memory remains within the soak tolerance")

	# 燃焼を生存・即queue_free・死亡の混在対象へ付与し、追跡解放を待つ。
	# 旧ElementCombatSystemのFire Lv3付与から、StatusApplySystemの付与へ移植したもの。
	# StatusApplySystem._burning_targetsが解放漏れを起こさないことがこの検証の目的。
	var status_apply := game.get_node("StatusApplySystem") as StatusApplySystem
	var burn_targets: Array[EnemyBasic] = []
	for index in 30:
		var target := _spawn_tank_enemy(game, player.global_position + Vector2(80.0 + index * 4.0, 24.0))
		burn_targets.append(target)
		status_apply.apply_state(target, "burning", 100.0)
	for index in burn_targets.size():
		if index % 2 == 0:
			burn_targets[index].queue_free()
		else:
			burn_targets[index].health_component.current_hp = 1.0
			burn_targets[index].health_component.apply_damage(10.0)
	await _wait_real(4.6)
	await _drain_modals(game)
	_check(status_apply._burning_targets.is_empty(), "Burn tracking releases freed and dead targets after its maximum duration")

	# 死亡アニメ中でNodeが残っていても、自動攻撃/Homingは次の生存敵を選ぶ。
	var dead_probe := _spawn_tank_enemy(game, player.global_position + Vector2(24.0, 0.0), 20.0)
	var living_probe := _spawn_tank_enemy(game, player.global_position + Vector2(120.0, 0.0), 1000.0)
	dead_probe.health_component.current_hp = 1.0
	dead_probe.health_component.apply_damage(10.0)
	var selected_target := player.weapon_manager.find_nearest_enemy(player.global_position)
	_check(selected_target == living_probe, "automatic targeting skips an HP-zero enemy during its death animation")
	var homing_probe := PROJECTILE_SCENE.instantiate() as Projectile
	game.add_child(homing_probe)
	homing_probe.global_position = player.global_position
	_check(homing_probe._find_nearest_enemy() == living_probe, "homing projectile skips an HP-zero enemy")
	homing_probe.queue_free()
	living_probe.queue_free()
	await get_tree().process_frame

	# 大量Projectileを実Sceneへ積み、3秒Lifetime後に全て消えることを確認する。
	var projectile_data := WeaponData.new()
	projectile_data.id = "soak_projectile"
	projectile_data.base_damage = 1.0
	projectile_data.crit_chance = 0.0
	projectile_data.crit_multiplier = 1.0
	projectile_data.projectile_scene = PROJECTILE_SCENE
	for index in PROJECTILE_STRESS_COUNT:
		var projectile := PROJECTILE_SCENE.instantiate() as Projectile
		projectile.name = "SoakProjectile_%03d" % index
		game.add_child(projectile)
		projectile.global_position = player.global_position
		var angle := TAU * float(index) / float(PROJECTILE_STRESS_COUNT)
		projectile.launch(player.global_position + Vector2(cos(angle), sin(angle)) * 500.0, projectile_data)
	metrics["projectile_peak"] = _count_nodes_of_type(game, "Projectile")
	_check(int(metrics["projectile_peak"]) >= PROJECTILE_STRESS_COUNT, "projectile stress batch is present in the runtime scene")
	await _wait_real(3.4)
	metrics["remaining_soak_projectiles"] = _count_named_prefix(game, "SoakProjectile_")
	_check(int(metrics["remaining_soak_projectiles"]) == 0, "offscreen and non-hit projectiles expire by lifetime")

	# Pixel/Theme VFXを多数生成し、Animation/Tween/Timer完了後の残留を検査する。
	# ここまでで通常/Fusion自動攻撃は十分通したため、Cleanup計測中の新規生成だけ止める。
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for index in 120:
		var pos := player.global_position + Vector2((index % 12) * 8.0, (index / 12) * 6.0)
		attack_vfx.play_hit(pos, "fire", index % 7 == 0)
		effect_vfx.play_weapon_hit("fire", pos, 3)
	await _wait_real(1.8)
	await get_tree().process_frame
	await get_tree().process_frame
	var remaining_vfx := _transient_vfx_names(game)
	metrics["remaining_transient_vfx"] = remaining_vfx
	_check(remaining_vfx.is_empty(), "hit VFX, particles, lines and damage visuals expire after stress playback")

	# 居合を繰り返し実行し、終了後の操作・無敵・キュー状態を検査する。
	player.health_component.invincible = false
	player.face_direction(Vector2.RIGHT)
	var iai_kills_before := GameManager.kill_count
	for _index in IAI_REPETITIONS:
		var target := _spawn_tank_enemy(game, player.global_position + Vector2(70.0, 0.0), 20.0)
		player.active_skill_component.cooldown_remaining = 0.0
		_check(player.active_skill_component.try_activate(), "Iai accepts input when ready")
		await _wait_real(0.55)
		if is_instance_valid(target) and target.health_component.current_hp > 0.0:
			target.health_component.apply_damage(5000.0)
		await _drain_modals(game)
	metrics["iai_kills"] = GameManager.kill_count - iai_kills_before
	_check(not player._movement_locked_by_attack, "Iai returns normal movement control")
	_check(not player.health_component.invincible, "Iai clears invincibility after completion")
	_check(not player.active_skill_component._swordsman_iai_running and player.active_skill_component._swordsman_iai_pending == 0, "Iai async queue fully drains")
	await _run_boss_attack_probes(game, player)

	# BossのSpawn→Damage→死亡→Item/Fragmentの直列Modal→HUD解除を実経路で確認。
	boss_spawner._spawn_boss()
	await _wait_real(0.4)
	var boss := boss_spawner._current_boss as EnemyBasic
	_check(is_instance_valid(boss), "boss spawns in the long-run game scene")
	if is_instance_valid(boss):
		boss.health_component.current_hp = 1.0
		boss.health_component.apply_damage(10.0)
	await get_tree().process_frame
	await _drain_modals(game)
	await _wait_real(1.0)
	_check(boss_spawner._current_boss == null, "boss spawner clears its dead boss reference")
	_check(GameManager.active_modal_count == 0 and not get_tree().paused, "boss item and fragment reward modals drain in order")
	_check(not (game.get_node("HUD") as HUD).boss_health_container.visible, "boss HP UI hides after death")

	# PauseもGameManagerのModal経路で開閉し、キーボード操作の起点へFocusを置く。
	var pause_menu := game.get_node("PauseMenu") as PauseMenu
	pause_menu._open()
	await get_tree().process_frame
	_check(pause_menu.visible and get_tree().paused, "Pause menu opens through the shared modal pause path")
	_check(get_viewport().gui_get_focus_owner() == pause_menu.weapon_tab_button, "Pause menu gives keyboard focus to its active tab")
	await _capture_if_gui("pause_menu")
	pause_menu._close()
	_check(not pause_menu.visible and not get_tree().paused, "Pause menu closes and resumes play")

	# 死亡→Result。Game Over中のBGM停止と状態表示を確認する。
	player.health_component.invincible = false
	player.health_component.current_hp = 1.0
	player.health_component.apply_damage(5000.0)
	var result := game.get_node("ResultScreen") as ResultScreen
	for _frame in 180:
		if result.visible:
			break
		await get_tree().process_frame
	_check(result.visible and get_tree().paused, "player death opens the paused Result screen")
	_check(GameManager.run_state == GameManager.RunState.RESULT, "player death moves GameManager to RESULT")
	_check(AudioManager._current_bgm_id == "", "Game Over stops dungeon or boss BGM")
	await get_tree().process_frame
	_check(get_viewport().gui_get_focus_owner() == result.retry_button, "Result screen gives keyboard focus to Retry")
	await _capture_if_gui("result_screen")

	# ResultのRetry Button実経路を1回、その後手動再生成を2回行う。
	Engine.time_scale = 0.2
	var old_game_id := game.get_instance_id()
	result.retry_button.pressed.emit()
	for _frame in 10:
		await get_tree().process_frame
		if get_tree().current_scene and get_tree().current_scene.get_instance_id() != old_game_id:
			break
	var button_restarted := get_tree().current_scene
	_check(button_restarted != null and button_restarted.get_instance_id() != old_game_id, "Result Retry reloads the Game scene")
	if button_restarted != null and button_restarted.get_instance_id() != old_game_id:
		_disable_automatic_managers(button_restarted)
		_check_restart_state(button_restarted, 1, baseline_signal_connections)
		get_tree().current_scene = self
		button_restarted.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		get_tree().paused = false
		get_tree().current_scene = self
		if is_instance_valid(game):
			game.queue_free()
		await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("enemies").is_empty(), "old run leaves no enemy nodes after Retry removal")

	for restart_number in range(2, 4):
		var restarted := await _instantiate_game()
		_disable_automatic_managers(restarted)
		_check_restart_state(restarted, restart_number, baseline_signal_connections)
		get_tree().current_scene = self
		restarted.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	metrics["final_nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	metrics["final_resources"] = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	metrics["final_memory"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	metrics["final_orphans"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(int(metrics["final_orphans"]) <= int(metrics["baseline_orphans"]), "soak/restart creates no persistent orphan nodes")

func _check_restart_state(restarted: Node, restart_number: int, baseline_signal_connections: Dictionary) -> void:
	var restarted_player := restarted.get_node("Player") as Player
	_check(GameManager.run_state == GameManager.RunState.PLAYING, "restart %d enters PLAYING" % restart_number)
	_check(GameManager.kill_count == 0 and GameManager.elapsed_seconds < 0.25, "restart %d resets time and kills" % restart_number)
	_check(restarted_player.experience_component.level == 1 and restarted_player.experience_component.current_exp == 0, "restart %d resets EXP and level" % restart_number)
	_check(GameManager.active_modal_count == 0 and not get_tree().paused, "restart %d has no stale modal or pause" % restart_number)
	_check(is_equal_approx(Engine.time_scale, 1.0), "restart %d restores normal time scale" % restart_number)
	_check(_event_connection_snapshot() == baseline_signal_connections, "restart %d does not accumulate EventBus connections" % restart_number)

func _instantiate_game() -> Node:
	var game := GAME_SCENE.instantiate()
	# 初回はこのTest Scene自身の_ready中なので、SceneTree rootの子構築完了を待つ。
	await get_tree().process_frame
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	await get_tree().process_frame
	await get_tree().physics_frame
	return game

func _disable_automatic_managers(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _living_non_boss_enemies() -> Array[EnemyBasic]:
	var result: Array[EnemyBasic] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBasic and not (node.enemy_data is BossData) and node.health_component.current_hp > 0.0:
			result.append(node)
	return result

func _spawn_tank_enemy(game: Node, position: Vector2, hp: float = 5000.0) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "soak_target"
	data.display_name = "Soak Target"
	data.max_hp = hp
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.exp_value = 1
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	return enemy

func _spawn_probe_boss(game: Node, boss_id: String, position: Vector2) -> EnemyBasic:
	var boss := ENEMY_SCENE.instantiate() as EnemyBasic
	boss.enemy_data = DataLoader.bosses.get(boss_id)
	boss.visual_scale_multiplier = 1.0
	game.add_child(boss)
	boss.global_position = position
	if boss.boss_attack_component:
		boss.boss_attack_component.process_mode = Node.PROCESS_MODE_DISABLED
	return boss

func _run_boss_attack_probes(game: Node, player: Player) -> void:
	# Exercise every current Boss strategy with compressed telegraphs/recovery.
	player.health_component.invincible = true
	var charge_boss := _spawn_probe_boss(game, "black_knight_a", player.global_position + Vector2(210.0, 0.0))
	var charge := charge_boss.boss_attack_component.attack_strategy as ChargeAttackStrategy
	charge.telegraph_duration = 0.05
	charge.dash_duration = 0.12
	charge.recovery_duration = 0.05
	var charge_start := charge_boss.global_position
	var charge_damage := charge_boss.contact_hitbox.damage
	await charge.execute(charge_boss, player)
	_check(charge_boss.global_position.distance_to(charge_start) > 1.0, "Boss charge strategy moves through its runtime physics path")
	_check(not charge_boss._movement_locked_by_attack and is_equal_approx(charge_boss.contact_hitbox.damage, charge_damage), "Boss charge restores movement and contact damage")
	charge_boss.queue_free()
	await get_tree().process_frame

	var slam_boss := _spawn_probe_boss(game, "black_knight_b", player.global_position + Vector2(180.0, 0.0))
	var slam := slam_boss.boss_attack_component.attack_strategy as SlamStrategy
	slam.telegraph_duration = 0.05
	slam.recovery_duration = 0.05
	player.health_component.invincible = false
	player.health_component.current_hp = player.health_component.max_hp
	player.health_component._iframe_remaining = 0.0
	var slam_hp := player.health_component.current_hp
	await slam.execute(slam_boss, player)
	_check(player.health_component.current_hp < slam_hp, "Boss slam telegraph resolves into player damage")
	slam_boss.queue_free()
	await get_tree().process_frame

	var before_summon_ids: Dictionary = {}
	for enemy in _living_non_boss_enemies():
		before_summon_ids[enemy.get_instance_id()] = true
	var summon_boss := _spawn_probe_boss(game, "demon_a", player.global_position + Vector2(220.0, 0.0))
	var summon := summon_boss.boss_attack_component.attack_strategy as SummonStrategy
	summon.telegraph_duration = 0.05
	summon.recovery_duration = 0.05
	summon.summon_count_min = 2
	summon.summon_count_max = 2
	player.health_component.invincible = true
	await summon.execute(summon_boss, player)
	var summoned: Array[EnemyBasic] = []
	for enemy in _living_non_boss_enemies():
		if not before_summon_ids.has(enemy.get_instance_id()):
			summoned.append(enemy)
	_check(summoned.size() == 2, "Boss summon strategy creates its configured enemy count")
	for enemy in summoned:
		enemy.queue_free()
	summon_boss.queue_free()
	await get_tree().process_frame

	# Player has Fire Lv3 here. Enemy Nova must remain an enemy-colored Arrow and must
	# not inherit the Player's Fire projectile replacement.
	var nova_boss := _spawn_probe_boss(game, "black_knight_c", player.global_position + Vector2(130.0, 0.0))
	var nova := nova_boss.boss_attack_component.attack_strategy as NovaStrategy
	nova.telegraph_duration = 0.05
	nova.recovery_duration = 0.05
	nova.bullet_count = 8
	player.health_component.invincible = false
	player.health_component.current_hp = player.health_component.max_hp
	player.health_component._iframe_remaining = 0.0
	var nova_hp := player.health_component.current_hp
	await nova.execute(nova_boss, player)
	var bullets := _nodes_named_prefix(game, "BossNovaProjectile_")
	_check(bullets.size() == 8, "Boss nova creates the configured projectile count")
	for node in bullets:
		var bullet := node as Projectile
		_check(not bullet.uses_player_element_vfx and not bullet.is_player_attack, "Boss nova projectile keeps enemy team/element settings")
		_check(bullet.get_node("Visual").visible and bullet.get_node_or_null("ElementProjectile_vfx_fire_projectile") == null, "Boss nova projectile does not inherit Fire replacement VFX")
	await _wait_real(0.15)
	await _capture_if_gui("boss_nova")
	nova_boss.queue_free()
	await _wait_real(0.65)
	_check(player.health_component.current_hp < nova_hp, "Boss nova collision damages the player")
	await _wait_real(2.6)
	_check(_count_named_prefix(game, "BossNovaProjectile_") == 0, "Boss nova projectiles expire by lifetime")
	player.health_component.invincible = false

func _drain_modals(game: Node) -> void:
	var level_up := game.get_node("LevelUpSelect") as LevelUpSelect
	var item_select := game.get_node("ItemSelect") as ItemSelect
	for _guard in 160:
		await get_tree().process_frame
		if GameManager.active_modal_count == 0 and GameManager._modal_queue.is_empty():
			return
		var grid: GridContainer = null
		if level_up.visible:
			grid = level_up.grid_container
		elif item_select.visible:
			grid = item_select.grid_container
		if grid and grid.get_child_count() > 0:
			var button := grid.get_child(0) as Button
			var modal_id := "level_up" if level_up.visible else "item_select"
			if modal_id == "item_select" and not _capture_flags.has("boss_flash_expired"):
				await _wait_real(0.55)
				var screen_effects := game.get_node("ScreenEffects") as ScreenEffects
				var overlay_layers := screen_effects.get_children().filter(func(child): return child is CanvasLayer)
				_check(overlay_layers.is_empty(), "Boss flash expires while its reward modal keeps the tree paused")
				_capture_flags["boss_flash_expired"] = true
			if not _focus_checked.has(modal_id):
				_check(get_viewport().gui_get_focus_owner() == button, "%s gives keyboard focus to its first choice" % modal_id)
				_focus_checked[modal_id] = true
			await _capture_if_gui(modal_id)
			button.pressed.emit()
			await get_tree().process_frame
	_failures_append_once("modal queue did not drain within the guard limit")

func _wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _event_connection_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for signal_name in [
		"damage_dealt", "run_started", "run_ended", "elite_room_entered",
		"elite_room_cleared", "boss_fight_started", "boss_fight_ended",
		"boss_health_changed", "item_acquired"
	]:
		snapshot[signal_name] = EventBus.get_signal_connection_list(StringName(signal_name)).size()
	return snapshot

func _capture_if_gui(label: String) -> void:
	if DisplayServer.get_name() == "headless" or _capture_flags.has(label):
		return
	_capture_flags[label] = true
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://artifacts/final_polish")
	DirAccess.make_dir_recursive_absolute(directory)
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(directory.path_join("%s.png" % label))
	_check(error == OK, "GUI screenshot saves: %s" % label)

func _count_nodes_of_type(root: Node, type_name: String) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_class(type_name) or (type_name == "Projectile" and node is Projectile):
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count

func _count_named_prefix(root: Node, prefix: String) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if String(node.name).begins_with(prefix):
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count

func _nodes_named_prefix(root: Node, prefix: String) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if String(node.name).begins_with(prefix):
			result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result

func _transient_vfx_names(root: Node) -> Array[String]:
	var names: Array[String] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.name.to_lower().contains("vfx") or node is GPUParticles2D or node is Line2D or node is CharacterAfterimage:
			# 常設Manager/Poolは残留扱いにしない。
			if not node is AttackVFXManager and not node is EffectThemeManager and not node is VFXPoolManager and not node.get_parent() is VFXPoolManager:
				# 床に落ちている装備の見た目(PixelLootPlate/PixelLootOutline等)は
				# その装備が生きている間は残るのが正しい。床装備自体の寿命は
				# 上限・期限切れの検証が別途担当するため、ここでは残留扱いにしない。
				if not _is_ground_loot_visual(node):
					names.append("%s:%s" % [node.get_class(), node.name])
		for child in node.get_children():
			pending.append(child)
	return names

func _is_ground_loot_visual(node: Node) -> bool:
	var cursor := node
	while cursor != null:
		if cursor is GroundEquipmentItem:
			return true
		cursor = cursor.get_parent()
	return false

func _failures_append_once(label: String) -> void:
	if label not in failures:
		failures.append(label)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
