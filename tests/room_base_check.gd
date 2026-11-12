extends Node
## 最小の土台の検査：起動シーン（何もない1部屋）に選んだ職業が1人だけ立ち、待機アニメが進み、
## 部屋の中から動かず、敵・UI・攻撃のノードが無いことを確かめる。
## Godot --headless --path . res://tests/room_base_check.tscn
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "main scene is not the room")
	for id in ["soldier", "wizard", "knight_templar"]:
		GameManager.selected_character_id = id
		var room := (load("res://scenes/main.tscn") as PackedScene).instantiate()
		add_child(room)
		await get_tree().process_frame
		var players := get_tree().get_nodes_in_group("player")
		check(players.size() == 1, "%s: expected exactly one character, got %d" % [id, players.size()])
		var player := players[0] as Player
		check(player.character_data != null and player.character_data.id == id, "%s: selected class is not the one standing in the room" % id)
		var start := player.global_position
		var frames_seen := {}
		for i in 60:
			await get_tree().process_frame
			frames_seen[player.animated_sprite.frame] = true
		check(player.animated_sprite.animation == &"idle" and frames_seen.size() >= 2, "%s: idle animation is not running" % id)
		check(player.global_position == start and (room.call("get_room_rect") as Rect2).has_point(player.global_position), "%s: character moved or is outside the room" % id)
		check(room.get_node_or_null("Camera2D") is Camera2D, "%s: room has no camera" % id)
		var extra: Array[String] = []
		for child in room.get_children():
			if child != player and not child is Camera2D:
				extra.append(child.name)
		check(extra.is_empty(), "%s: room contains more than the character and camera: %s" % [id, extra])
		check(room.find_children("*", "CanvasLayer", true, false).is_empty() and room.find_children("*", "Control", true, false).is_empty(), "%s: room has UI" % id)
		room.queue_free()
		await get_tree().process_frame
	print("ROOM_BASE_CHECK failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
