extends Node
## Verify the imported shield guard reaches the finite encounter path in a real MAP1 run.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	var wave_spawner := get_parent().get_node("WaveSpawner") as WaveSpawner
	var deadline := Time.get_ticks_msec() + 30000
	while not wave_spawner.encounters_ready and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not wave_spawner.encounters_ready:
		push_error("IMPORTED_ASSETS_MAP_CHECK: MAP1 encounters did not finish")
		get_tree().quit(1)
		return
	var guards := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBasic
		if enemy and enemy.enemy_data and enemy.enemy_data.id == "shield_guard":
			guards += 1
	if guards == 0:
		push_error("IMPORTED_ASSETS_MAP_CHECK: shield guard is missing from MAP1")
		get_tree().quit(1)
		return
	print("IMPORTED_ASSETS_MAP_CHECK PASS: MAP1 shield guards=", guards)
	get_tree().quit(0)
