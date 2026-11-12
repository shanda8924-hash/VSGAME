extends Node

func _ready() -> void:
	var lab := (load("res://scenes/developer_test_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	await lab.lab_ready
	assert(lab.runtime_game != null and lab.player != null, "Lab still embeds production game")
	assert(SaveManager.is_ephemeral_session_active(), "Lab must not save test state")
	assert(not lab.runtime_game.has_node("RoomRunController") and not lab.runtime_game.has_node("RoomSelect"))
	for index in lab._tabs.get_tab_count():
		assert(lab._tabs.get_tab_title(index) != "ROOM", "Retired ROOM tab remained")
	assert(lab._tabs.get_tab_count() > 0, "Retain working developer tools")
	print("RETIRED_MODES_CHECK PASS: real game embedded, player loaded, save isolated, ROOM controls removed")
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0, "")
