extends Node
var fired := 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await get_tree().process_frame
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.weapon_fired.connect(func(): fired += 1)
	await get_tree().create_timer(1.0).timeout
	assert(fired == 0, "Idle must not attack")
	Input.action_press("primary_attack")
	await get_tree().create_timer(0.20).timeout
	Input.action_release("primary_attack")
	assert(fired == 1, "J must swing even without a target")
	while player.weapon_manager._class_attack_in_progress:
		await get_tree().process_frame
	player.face_direction(Vector2.RIGHT)
	assert(player.try_dodge())
	assert(not player.try_dodge(), "Dodge cooldown")
	var before := player.global_position
	var hp := player.health_component.current_hp
	player.health_component.apply_damage(10)
	assert(player.health_component.current_hp == hp, "Early dodge iframe")
	GameManager.open_modal()
	var remaining := player.dodge_remaining
	await get_tree().create_timer(0.25, true).timeout
	assert(player.dodge_remaining == remaining and player.global_position == before)
	GameManager.close_modal()
	await get_tree().create_timer(0.25, true).timeout
	assert(player.dodge_remaining == 0.0)
	assert(player.global_position.distance_to(before) <= 81.0)
	assert(player.health_component.dodge_iframe_remaining == 0.0)
	player.health_component.apply_damage(10)
	assert(player.health_component.current_hp < hp, "Dodge must expire")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_L
	assert(InputMap.action_has_event("active_skill", event))
	print("MANUAL_COMBAT PASS: idle, J swing, dodge cooldown/iframe/expiry, menu pause, L mapping")
	get_tree().quit()
