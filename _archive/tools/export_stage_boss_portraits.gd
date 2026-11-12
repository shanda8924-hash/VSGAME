extends Node
const IDS := ["armored_skeleton", "greatsword_skeleton", "blood_monster_b", "werebear", "armored_orc", "elite_orc"]

class Frame extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0,0,256,256), Color("10161d"))
		for i in range(0,256,16):
			draw_line(Vector2(0,i),Vector2(256,i),Color("52616e"))
			for j in range(0,256,32): draw_line(Vector2(j+(16 if i%32 else 0),i),Vector2(j+(16 if i%32 else 0),i+16),Color("52616e"))
		for inset in [8,12,16]: draw_rect(Rect2(inset,inset,256-inset*2,256-inset*2),Color("a36a56"),false,1)
		draw_polyline(PackedVector2Array([Vector2(128,24),Vector2(140,36),Vector2(128,48),Vector2(116,36),Vector2(128,24)]),Color("d57460"),1)
		draw_set_transform(Vector2(128,214),0,Vector2(1,.18))
		draw_circle(Vector2.ZERO,72,Color("482d22"))
		draw_circle(Vector2.ZERO,62,Color("d76b56"))

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(256,256)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.transparent_bg = false
	add_child(view)
	view.add_child(Frame.new())
	var sprite := Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.add_child(sprite)
	for id: String in IDS:
		var data: BossData = DataLoader.bosses[id]
		sprite.texture = SpriteSheetBuilder.build_portrait_texture(data.sprite_folder)
		var factor := floorf(minf(160.0/sprite.texture.get_width(),144.0/sprite.texture.get_height()))
		sprite.scale = Vector2.ONE * maxf(factor,1.0)
		sprite.position = Vector2(128,214-sprite.texture.get_height()*sprite.scale.y/2)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://dashboard/dist/assets/portraits/bosses/"+id+".png"
		assert(view.get_texture().get_image().save_png(path)==OK)
	view.queue_free()
	await get_tree().process_frame
	print("STAGE_BOSS_PORTRAITS PASS: six original sprite portraits at 256px")
	get_tree().quit()
