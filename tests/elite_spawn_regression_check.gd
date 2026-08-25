extends Node
## 実際のGame sceneで精鋭部屋への物理入室を再現する回帰テスト。

var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var manager := game.get_node("EliteRoomManager") as EliteRoomManager
	# Embedded Game/Test Lab経路では旧自動進行Systemを停止している。物理入室を
	# 検証するこのテストだけ監視を有効化し、本番ROOM進行の設定は変えない。
	manager.process_mode = Node.PROCESS_MODE_ALWAYS
	var player := game.get_node("Player") as Player
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	wave._spawn_enemy()
	await get_tree().process_frame
	var normal_before_elite := get_tree().get_nodes_in_group("enemies").filter(func(enemy): return not enemy.is_in_group("elite_enemies") and not (enemy.enemy_data is BossData)).size()
	_check(normal_before_elite >= 1, "normal enemy spawn")
	_check(not GameManager.dungeon_map.elite_room_indices.is_empty(), "elite room assignment")
	_check(manager.get_child_count() == GameManager.dungeon_map.elite_room_indices.size(), "elite trigger creation")
	var elite_count_before_roaming := get_tree().get_nodes_in_group("elite_enemies").size()
	manager._spawn_roaming_elite()
	await get_tree().process_frame
	var roaming_candidates := get_tree().get_nodes_in_group("elite_enemies")
	_check(roaming_candidates.size() == elite_count_before_roaming + 1, "roaming elite runtime spawn")
	var roaming: EnemyBasic = null
	if roaming_candidates.size() > elite_count_before_roaming:
		roaming = roaming_candidates.back() as EnemyBasic
		var has_roaming_affix := false
		for child in roaming.get_children():
			if child is EliteAffixComponent:
				has_roaming_affix = not child.affix_ids.is_empty()
		_check(has_roaming_affix, "roaming elite affix attachment")
	manager.elite_min_count = 2
	manager.elite_max_count = 2
	var room_index: int = GameManager.dungeon_map.elite_room_indices[0]
	var room: Rect2i = GameManager.dungeon_map.rooms[room_index]
	player.global_position = GameManager.dungeon_map.grid_to_world(room.position + room.size / 2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	# EliteRoomManagerはPhysicsServer flush回避のため生成をdeferredしている。
	await get_tree().process_frame
	var elites := get_tree().get_nodes_in_group("elite_enemies")
	var room_elites: Array = manager._elite_enemies_alive.get(room_index, [])
	_check(room_elites.size() == 2, "elite physical-entry spawn for target room (expected 2, got %d; global=%d)" % [room_elites.size(), elites.size()])
	if not room_elites.is_empty():
		var affix_count := 0
		for child in room_elites[0].get_children():
			if child is EliteAffixComponent:
				affix_count = child.affix_ids.size()
		_check(affix_count >= 1, "elite affix attachment")
	if room_elites.size() == 2 and is_instance_valid(roaming):
		var equipment_drop := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
		equipment_drop._drop_table["strong_enemy_drop_chance"] = 1.0
		# 本物のroaming 1体＋精鋭部屋2体を撃破し、本番のEnemyBasic.died
		# -> enemy_drop_requested -> EquipmentDropSystem経路を確定率で確認する。
		# Managerの生存配列は死亡時にその場で縮むため、撃破前に2体の参照を固定する。
		var first := room_elites[0] as EnemyBasic
		var second := room_elites[1] as EnemyBasic
		var drops_before_three_kills := get_tree().get_nodes_in_group("ground_equipment").size()
		roaming.health_component.current_hp = 1.0
		roaming.health_component.apply_damage(10.0)
		await get_tree().process_frame
		await get_tree().process_frame
		first.health_component.current_hp = 1.0
		first.health_component.apply_damage(10.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(manager._elite_enemies_alive.get(room_index, []).size() == 1, "elite death tracking")
		second.health_component.current_hp = 1.0
		second.health_component.apply_damage(10.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var drops_after_three_kills := get_tree().get_nodes_in_group("ground_equipment").size()
		_check(drops_after_three_kills - drops_before_three_kills == 3, "three actual strong-enemy kills create three drops when chance is forced to 100%% (before=%d after=%d)" % [drops_before_three_kills, drops_after_three_kills])
		_check(manager._elite_enemies_alive.get(room_index, []).is_empty(), "elite room death tracking completes")
	var temporary_walls := 0
	for child in manager.get_children():
		if child is StaticBody2D:
			temporary_walls += 1
	_check(temporary_walls == 0, "no invisible walls")
	player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	await get_tree().physics_frame
	_check(player.global_position.distance_to(GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)) < 1.0, "player can leave elite room")
	var boss_spawner := game.get_node("BossSpawner") as BossSpawner
	boss_spawner._spawn_boss()
	await get_tree().process_frame
	var boss_spawned := is_instance_valid(boss_spawner._current_boss)
	_check(boss_spawned, "boss spawn remains functional")
	# BossSpawnerの既存hit-stop用実時間Timerを完了させてからテストsceneを破棄する。
	await get_tree().create_timer(0.5, true, false, true).timeout
	for failure in failures:
		push_error(failure)
	print("ELITE_SPAWN_REGRESSION_CHECK failures=%d normal_enemies=%d elites=%d boss=%s" % [failures.size(), normal_before_elite, elites.size(), boss_spawned])
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
