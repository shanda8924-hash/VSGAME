extends Node2D

const STAGE_SCENE := preload("res://entities/stage_environment/stage_environment.tscn")
const OUTPUT := "res://artifacts/map_themes"
const CONFIGS := {
	1: Vector4i(78, 78, 10, 1),
	2: Vector4i(86, 86, 11, 2),
	3: Vector4i(94, 94, 12, 2),
}
const NAMES := {1: "忘却の地下回廊", 2: "紫晶の深層", 3: "終焉の炉心"}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var stage := STAGE_SCENE.instantiate() as StageEnvironment
	add_child(stage)
	await get_tree().process_frame
	var label := Label.new()
	label.position = Vector2(38, 28)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color("f4e6c7"))
	label.add_theme_color_override("font_outline_color", Color("090b12"))
	label.add_theme_constant_override("outline_size", 8)
	label.z_index = 100
	add_child(label)
	for map_index in [2, 3]:
		var captured := {}
		for sample in 10:
			var config: Vector4i = CONFIGS[map_index]
			var rng := RandomNumberGenerator.new()
			rng.seed = 91820 + map_index + sample * 100
			var map := DungeonGenerator.generate(config.x, config.y, config.z, config.w, rng)
			GameManager.current_map_index = map_index
			seed(72100 + map_index)
			stage.build_dungeon(map)
			var entries: Array = map.get_meta("scenic_landmarks", [])
			for entry: Dictionary in entries:
				if captured.has(entry.kind):
					continue
				captured[entry.kind] = true
				var base: Rect2i = entry.footprint
				var focus_cell := base.position + Vector2i(3, 1)
				stage.position = get_viewport_rect().size * 0.5 - map.grid_to_world(focus_cell)
				label.text = "MAP %d  %s — %s" % [map_index, NAMES[map_index], entry.name]
				await _frames(5)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OUTPUT + "/landmark%d.png" % int(entry.kind))
				print("LANDMARK_CAPTURE ", entry.name)
			if captured.size() == 2:
				break
	get_tree().quit(0)

func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
