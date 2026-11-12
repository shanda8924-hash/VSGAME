extends Node
## 土台の検査：10職すべてについて、キャラクターのシーンが生成でき、職業の見た目(idle/walk)と
## 基本ステータス(HP・移動速度)が反映され、待機アニメーションが実際に進むことを確かめる。
## Godot --headless --path . res://tests/character_base_check.tscn
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var characters: Dictionary = DataLoader.characters
	check(characters.size() == 10, "expected 10 characters, got %d" % characters.size())
	var scene := load("res://entities/player/player.tscn") as PackedScene
	for id in characters.keys():
		var data: CharacterData = characters[id]
		GameManager.selected_character_id = id
		var player := scene.instantiate() as Player
		add_child(player)
		await get_tree().process_frame
		var sprite := player.animated_sprite
		check(player.character_data == data, "%s: character data not applied" % id)
		check(is_equal_approx(player.health_component.max_hp, data.max_hp) and is_equal_approx(player.health_component.current_hp, data.max_hp), "%s: HP not applied" % id)
		check(is_equal_approx(player.movement_component.base_speed, data.move_speed), "%s: move speed not applied" % id)
		check(sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idle") and sprite.sprite_frames.has_animation("walk"), "%s: idle/walk animations missing" % id)
		check(sprite.animation == &"idle" and sprite.is_playing(), "%s: not playing idle" % id)
		var seen := {}
		for i in 40:
			await get_tree().process_frame
			seen[sprite.frame] = true
		check(seen.size() >= 2, "%s: idle animation does not advance" % id)
		check(player.velocity == Vector2.ZERO, "%s: moves without any input" % id)
		check(data.icon_name != "" and ResourceLoader.exists(data.icon_path) and load(data.icon_path) is Texture2D, "%s: class icon missing" % id)
		player.queue_free()
		await get_tree().process_frame
	GameManager.selected_character_id = "no_such_class"
	check(GameManager.get_selected_character() != null and GameManager.selected_character_id == "soldier", "invalid class id does not fall back")
	print("CHARACTER_BASE_CHECK characters=%d failures=%d" % [characters.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
