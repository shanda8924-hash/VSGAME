extends Node

var OUT := "res://artifacts/weapon_aura_walls"
const Layout := preload("res://systems/room_layout.gd")
const Aura := preload("res://entities/player/weapon_aura.gdshader")
var failures: Array[String] = []
var wall_cells := 0
var floor_cells := 0
var weapon_count := 0
var rarity_records: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--touch-preview" in OS.get_cmdline_user_args(): OUT+="/mobile"
	SaveManager.begin_ephemeral_session()
	get_tree().create_timer(80,true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_check(AudioServer.is_bus_mute(0) and AudioServer.get_driver_name()=="Dummy","Test must be silent")
	GameManager.selected_character_id="swordsman"
	var game := preload("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func(): get_tree().current_scene=game)
	get_tree().root.add_child(game)
	var controller := game.get_node("MapRunController") as MapRunController
	while not controller._active: await _frames(1)
	controller.set_process(false)
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	wave._sector_active=false
	wave.set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	var player := game.get_node("Player") as Player
	player.health_component.invincible=true
	player.set_physics_process(false)
	player.weapon_manager.set_process(false)
	var stage := game.get_node("StageEnvironment") as StageEnvironment
	var initial := GameManager.dungeon_map
	for theme in [1,2,3]:
		GameManager.current_map_index=theme
		for sample in 4:
			var map: DungeonMap
			if theme==1:
				map=Layout.generate(sample+1,1+sample%3,94000+sample)
			else:
				var rng:=RandomNumberGenerator.new()
				rng.seed=94000+theme*100+sample
				map=DungeonGenerator.generate(78,78,10,1,rng)
			GameManager.dungeon_map=map
			if sample%2==0: stage.build_dungeon(map)
			else: await stage.build_dungeon_async(map,5)
			await get_tree().physics_frame
			var surface=stage.get_node("PaintedSurfaces")
			var scenery: Dictionary=map.get_meta("scenic_landmark_cells",{})
			for cell in stage._tile_map_layer.get_used_cells():
				var data:=stage._tile_map_layer.get_cell_tile_data(cell)
				var solid:=data.get_collision_polygons_count(0)>0
				if solid and not scenery.has(cell):
					_check(not surface._walk_surface(cell),"Solid tile painted as empty floor: theme %d, cell %s"%[theme,cell])
					wall_cells+=1
				elif not solid:
					_check(surface._walk_surface(cell),"Walkable tile painted as wall")
					floor_cells+=1
			for cell in map.terrain_obstacle_cells:
				if scenery.has(cell): continue
				var point:=PhysicsPointQueryParameters2D.new()
				point.position=map.grid_to_world(cell)+Vector2(16,16)
				point.collision_mask=1
				_check(not stage.get_world_2d().direct_space_state.intersect_point(point).is_empty(),"Visible obstacle lost physical collision")
	_check(wall_cells>100 and floor_cells>100,"Terrain check did not exercise solid and walkable cells")
	GameManager.current_map_index=1
	GameManager.dungeon_map=initial
	stage.build_dungeon(initial)
	await get_tree().physics_frame
	player.global_position=Vector2.ZERO
	var drops:=game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var component:=player.equipment_component
	for template in drops.debug_get_templates():
		if template.slot!="weapon": continue
		var item:=drops.debug_generate_equipment(template.id,template.rarity)
		_check(component.add_item(item) and component.equip(item),"Equip failed: "+template.id)
		await _frames(1)
		var sprite:=player.floating_weapons._sprites["equipment"] as Sprite2D
		var bounds: Rect2i=player.floating_weapons.ICON_METRICS.BOUNDS[item.icon_path]
		_check(is_equal_approx(maxf(bounds.size.x,bounds.size.y)*sprite.scale.x,48.0),"Weapon art not normalized to 48px: "+template.id)
		_check(sprite.material is ShaderMaterial and sprite.material.shader==Aura,"World weapon lacks silhouette outline/aura")
		var image:=sprite.texture.get_image()
		for y in image.get_height():
			for x in image.get_width():
				var a:=image.get_pixel(x,y).a
				_check(a==0.0 or a==1.0,"Runtime weapon contains soft rectangular background: "+template.id)
		weapon_count+=1
		component.unequip("weapon")
		component.remove_item(item)
	_check(weapon_count==52,"Entire weapon catalog was not checked")
	for rarity in ["uncommon","rare","epic","legendary","mythic"]:
		var item:=drops.debug_generate_equipment("rune_greatsword",rarity)
		_check(component.add_item(item) and component.equip(item),"Rarity equip failed")
		await _frames(20)
		var sprite:=player.floating_weapons._sprites["equipment"] as Sprite2D
		var material:=sprite.material as ShaderMaterial
		var rank: int=["uncommon","rare","epic","legendary","mythic"].find(rarity)
		_check(is_equal_approx(material.get_shader_parameter("rarity_rank"),float(rank)),"Rarity not passed to flame shader")
		_check(material.get_shader_parameter("rarity_color")== (Color("ff4659") if rank==4 else item.get_rarity_color()),"Wrong outline color")
		rarity_records.append({"rarity":rarity,"rank":rank,"strength":material.get_shader_parameter("aura_strength")})
		if DisplayServer.get_name()!="headless":
			for frame in 16:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OUT+"/%s_%02d.png"%[rarity,frame])
				await _frames(2)
		component.unequip("weapon")
		component.remove_item(item)
	await _check_soft_background()
	var item:=drops.debug_generate_equipment("wanderer_iron_sword","mythic")
	component.add_item(item)
	component.equip(item)
	# Legacy saved/test icon paths resolve to the same approved cutout.
	item.icon_path="res://assets/items/weapons/weapon_sword_uncommon_001.png"
	player.floating_weapons._refresh()
	_check(player.floating_weapons._sprites["equipment"].texture.resource_path.ends_with("ember_v5/equipment/wanderer_iron_sword.png"),"Legacy icon bypassed canonical world art")
	var wall_map: DungeonMap=Layout.generate(1,2,94700)
	GameManager.dungeon_map=wall_map
	stage.build_dungeon(wall_map)
	player.setup_camera_limits(wall_map)
	await _frames(8)
	_check(not player.test_move(Transform2D(0,Vector2.ZERO),Vector2(8,0)),"Empty central floor blocks movement")
	for cell in wall_map.terrain_obstacle_cells:
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if wall_map.is_floor(cell-direction):
				var center:=wall_map.grid_to_world(cell)+Vector2(16,16)
				_check(player.test_move(Transform2D(0,center-Vector2(direction)*48),Vector2(direction)*48),"Visible wall does not stop the real player")
				break
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT+"/visible_walls.png")
	var report:={"failures":failures,"solidVisibleCells":wall_cells,"walkableCells":floor_cells,"rooms":12,"weapons":weapon_count,"rarities":rarity_records,"legacyArtResolved":true,"muted":AudioServer.is_bus_mute(0),"audioDriver":AudioServer.get_driver_name()}
	FileAccess.open(OUT+"/check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var cleanup:=preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1,"WEAPON_AURA_WALLS failures=%d walls=%d weapons=%d muted=true"%[failures.size(),wall_cells,weapon_count])

func _check_soft_background() -> void:
	if DisplayServer.get_name()=="headless": return
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(256,256)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var image:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.05,0.05,0.05,0.08))
	image.fill_rect(Rect2i(13,3,6,26),Color.WHITE)
	var sprite:=Sprite2D.new()
	sprite.texture=ImageTexture.create_from_image(image)
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position=Vector2(128,128)
	sprite.scale=Vector2.ONE*3
	var material:=ShaderMaterial.new()
	material.shader=Aura
	material.set_shader_parameter("aura_strength",0.0)
	sprite.material=material
	viewport.add_child(sprite)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var result:=viewport.get_texture().get_image()
	_check(result.get_pixel(90,90).a==0 and result.get_pixel(165,165).a==0,"Shader leaves a faint square behind the blade")
	_check(result.get_pixel(128,128).a>0.99,"Alpha cutoff erased the weapon")
	material.set_shader_parameter("aura_strength",0.8)
	material.set_shader_parameter("rarity_rank",4.0)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var before:=viewport.get_texture().get_image()
	await _frames(12)
	await RenderingServer.frame_post_draw
	var after:=viewport.get_texture().get_image()
	_check(after.get_pixel(128,128).r>0.95,"Shader darkens the original weapon art")
	var aura_pixels:=0
	for y in after.get_height():
		for x in after.get_width():
			var a:=after.get_pixel(x,y).a
			if a>0.20 and a<0.99: aura_pixels+=1
	_check(aura_pixels>20,"Flames vanish outside the original weapon alpha")
	_check(before.get_data()!=after.get_data(),"Weapon flames do not animate")
	_check(after.get_pixel(60,60).a==0 and after.get_pixel(195,195).a==0,"Aura illuminates a rectangular backdrop")
	after.save_png(OUT+"/alpha_shader_check.png")
	viewport.queue_free()
