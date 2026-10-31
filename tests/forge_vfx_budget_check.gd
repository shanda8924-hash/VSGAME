extends Node
## The paused combat VFX budget must never swallow the one-slot forge animation.

const GAME_SCENE := preload("res://scenes/game.tscn")
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "soldier"
	var game := GAME_SCENE.instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await get_tree().process_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager", "MapRunController"]:
		game.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var component := player.equipment_component
	var drop_system := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	var materials: Array[EquipmentData] = []
	for template in drop_system.debug_get_templates():
		if String(template.get("rarity", "")) == "uncommon":
			var item := drop_system.debug_generate_equipment(String(template.get("id", "")), "uncommon")
			component.add_item(item)
			materials.append(item)
		if materials.size() == 3:
			break
	screen._open()
	for item in materials:
		screen._toggle_merge_material(item)
	_check(get_tree().paused, "equipment screen pauses combat")
	var paused_world := Node2D.new()
	paused_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(paused_world)
	for _batch in 6:
		for _index in PixelSpriteVFX.MAX_SPAWNS_PER_FRAME:
			if PixelSpriteVFX._live_count >= PixelSpriteVFX.MAX_LIVE:
				break
			PixelSpriteVFX.spawn(paused_world, Vector2.ZERO, "hit_fire", Vector2(36, 36), 0.26)
		await get_tree().process_frame
	var live_at_cap := PixelSpriteVFX._live_count
	_check(live_at_cap == PixelSpriteVFX.MAX_LIVE, "real paused VFX instances saturate the combat budget")
	var rejected := PixelSpriteVFX.spawn(paused_world, Vector2.ZERO, "hit_fire", Vector2(36, 36))
	_check(rejected == null, "combat spawn remains capped")
	var inventory_before := component.inventory.size()
	screen._merge_selected()
	screen._merge_selected()
	_check(screen._merge_in_progress and component.inventory.size() == inventory_before - 2, "one atomic merge starts despite saturated VFX")
	await get_tree().create_timer(0.82, true, false, true).timeout
	var awakening := screen.merge_animation_layer.get_node_or_null("ForgeAwakening") as PixelSpriteVFX
	_check(awakening != null and awakening.active and awakening.is_visible_in_tree(), "reserved forge sprite appears while combat remains paused at cap")
	if awakening:
		_check(awakening.frame > 0, "forge frames progress during pause")
		_check(minf(awakening.modulate.r, minf(awakening.modulate.g, awakening.modulate.b)) >= 0.75, "authored gold highlights are not darkened into muddy rarity tint")
		var target := awakening.global_position
		screen._spawn_merge_impact(target, Color.WHITE, 2)
		screen._spawn_merge_impact(target, Color.WHITE, 2)
	var forge_count := 0
	for child in screen.merge_animation_layer.get_children():
		if child is PixelSpriteVFX:
			forge_count += 1
	_check(forge_count == 1, "repeated callback cannot create a second forge sprite")
	_check((paused_world.get_child(0) as PixelSpriteVFX).frame == 0, "paused combat lifetime really remains frozen")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/forge_pixel_awakening.png")
	await get_tree().create_timer(1.0, true, false, true).timeout
	_check(not screen._merge_in_progress and screen._merge_result != null, "forge transaction finishes normally")
	_check(not is_instance_valid(awakening), "reserved forge sprite is released by completion")
	_check(PixelSpriteVFX._live_count == live_at_cap, "combat budget returns to original cap after forge cleanup")
	_check(component.inventory.size() == inventory_before - 2, "callbacks and completion do not duplicate rewards")
	screen._close()
	await get_tree().create_timer(0.4, true, false, true).timeout
	_check(paused_world.get_child_count() == 0, "combat VFX expire normally after resuming")
	paused_world.queue_free()
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for failure in failures:
		push_error("FORGE_VFX_BUDGET_CHECK: " + failure)
	print("FORGE_VFX_BUDGET_CHECK failures=%d" % failures.size())
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
