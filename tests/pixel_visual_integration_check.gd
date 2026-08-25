extends Node

const TITLE_SCENE := preload("res://scenes/title.tscn")

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_project_filter()
	await _check_pixel_ui()
	await _check_wind_concept_vfx()
	await _check_equipment_drop_visual()
	_check_fusion_assets()
	print("PIXEL_VISUAL_INTEGRATION_CHECK failures=%d" % failures.size())
	for failure in failures:
		push_error("PIXEL_VISUAL_INTEGRATION_CHECK: %s" % failure)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_project_filter() -> void:
	_check(int(ProjectSettings.get_setting("rendering/textures/default_filters/use_nearest_mipmap_filter", 0)) == 0, "no forced nearest mipmap filter")
	_check(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)) == 0, "canvas texture filter is Nearest")


func _check_pixel_ui() -> void:
	var title := TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	var start := title.get_node("CenterContainer/VBoxContainer/StartButton") as Button
	var normal := start.get_theme_stylebox("normal") as StyleBoxFlat
	var pressed := start.get_theme_stylebox("pressed") as StyleBoxFlat
	_check(normal != null and normal.corner_radius_top_left == 0 and normal.border_width_left == 3, "button uses square 3px Pixel border")
	_check(pressed != null and pressed.shadow_size < normal.shadow_size, "pressed state has a harder inset response")
	_check(start.has_meta("pixel_ui"), "title button is connected to common Pixel UI style")
	title.queue_free()
	await get_tree().process_frame


func _check_wind_concept_vfx() -> void:
	var effect := ConceptSkillVFX.spawn(self, Vector2.ZERO, "wind_blade", 78.0, Color("8ff5c0"))
	await get_tree().process_frame
	var sprite := effect.get_node_or_null("WindBladePixelVFX") as AnimatedSprite2D
	_check(sprite != null, "Wind Concept uses the generated Pixel Sprite")
	if sprite:
		_check(sprite.sprite_frames.get_frame_count("wind_blade") == 6, "Wind Concept Sprite has six frames")
		_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Wind Concept Sprite uses Nearest")
	_check(String(effect.get_meta("pixel_vfx_texture", "")) == "res://assets/vfx/concepts/wind_blade_6f_v2.png", "Wind Concept records its connected project asset")
	effect.queue_free()
	await get_tree().process_frame


func _check_equipment_drop_visual() -> void:
	var data := EquipmentData.new()
	data.display_name = "監査用装備"
	data.slot = "weapon"
	data.rarity = "legendary"
	var ground := GroundEquipmentItem.new()
	ground.setup(data)
	add_child(ground)
	await get_tree().process_frame
	_check(ground.find_child("PixelLootPlate", true, false) != null, "equipment drop uses the compact Pixel plate")
	for removed_name in ["LootBeam", "LootBeamGlow", "LootSpawnBeam"]:
		_check(ground.find_child(removed_name, true, false) == null, "equipment drop removed %s" % removed_name)
	ground.queue_free()
	await get_tree().process_frame


func _check_fusion_assets() -> void:
	var expected := ["frostfire", "plasma", "solar", "inferno", "superconductor", "aurora", "void_frost", "judgment", "voidstorm", "eclipse"]
	for fusion_id in expected:
		var data := DataLoader.fusion_vfx_effects.get(fusion_id) as FusionVFXData
		_check(data != null, "Fusion VFX Resource exists: %s" % fusion_id)
		if data == null:
			continue
		for mode in ["attack", "trail", "hit", "burst", "intro"]:
			var texture := data.sprite_sheet_for_mode(mode)
			_check(texture != null and texture.get_width() == 384 and texture.get_height() == 64, "%s %s is a 6x64 Pixel sheet" % [fusion_id, mode])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
