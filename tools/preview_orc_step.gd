extends Node2D
var caption: Label
var enemy: EnemyBasic
var target: CharacterBody2D
var out := "C:/Users/USER/Documents/Codex/2026-09-09/v/outputs/orc_step"

func _draw() -> void:
	draw_rect(Rect2(-200,-100,400,200), Color("15222b"))
	for x in range(-200,201,16): draw_line(Vector2(x,-100),Vector2(x,100),Color("20333e"),0.3)
	for y in range(-100,101,16): draw_line(Vector2(-200,y),Vector2(200,y),Color("20333e"),0.3)
	pass

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	get_window().size = Vector2i(960,540)
	get_tree().root.content_scale_size = Vector2i(960,540)
	DirAccess.make_dir_recursive_absolute(out)
	var camera := Camera2D.new()
	camera.zoom = Vector2(5,5)
	add_child(camera)
	target = CharacterBody2D.new()
	target.name = "Target"
	target.add_to_group("player")
	target.position = Vector2(34,0)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_hp = 1000
	target.add_child(health)
	var hurtbox := HurtboxComponent.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.health_component_path = NodePath("../HealthComponent")
	target.add_child(hurtbox)
	var portrait := AnimatedSprite2D.new()
	portrait.sprite_frames = SpriteSheetBuilder.build_sprite_frames("player/Swordsman")
	portrait.scale = Vector2(1.4,1.4)
	portrait.flip_h = true
	target.add_child(portrait)
	add_child(target)
	portrait.play("idle")
	enemy = load("res://entities/enemies/enemy_basic.tscn").instantiate()
	enemy.enemy_data = DataLoader.enemies["armored_orc"]
	enemy.position = Vector2(-36,0)
	add_child(enemy)
	enemy.set_physics_process(false)
	assert(enemy.strong_attack != null, "Normal EnemyData must connect the skill")
	var layer := CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(32,30)
	caption.add_theme_font_size_override("font_size",26)
	layer.add_child(caption)
	var footer := Label.new()
	footer.text = "重装オーク  |  踏み込み斬り  |  実ゲームの敵・素材・攻撃処理 / 等速"
	footer.position = Vector2(32,492)
	footer.add_theme_font_size_override("font_size",18)
	layer.add_child(footer)
	var start_hp := health.current_hp
	for i in 150:
		if i == 24: enemy.strong_attack.cooldown = 0.0
		if i >= 24 and i < 60: enemy.strong_attack.tick(1.0/30.0)
		if i == 39: assert(health.current_hp == start_hp, "No damage during windup")
		if i == 59: assert(is_equal_approx(start_hp - health.current_hp, enemy.contact_hitbox.damage * 1.35), "Exactly one slash hit")
		if i == 65:
			enemy.position = Vector2(-36,0)
			target.position = Vector2(34,0)
			start_hp = health.current_hp
		if i == 84: enemy.strong_attack.cooldown = 0.0
		if i == 94: target.position.y = 40
		if i >= 84 and i < 122: enemy.strong_attack.tick(1.0/30.0)
		if i == 122: assert(health.current_hp == start_hp, "Moving out of fixed aim must dodge")
		caption.text = "通常姿勢" if i < 24 else "赤い目 → 構え" if i < 40 else "素早い斬撃 → 振り終わり" if i < 60 else "次は横へ回避" if i < 84 else "構えで方向が決まる" if i < 104 else "横へ避ければ空振り"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out+"/%03d.png" % i)
		await get_tree().process_frame
	# Stun interrupts the move and clears the visual/control lock.
	enemy.position = Vector2(-36,0)
	target.position = Vector2(34,0)
	enemy.strong_attack.cooldown = 0.0
	enemy.strong_attack.tick(0.01)
	enemy.status_effect_component.apply_effect("stun",1.0)
	enemy.strong_attack.tick(0.01)
	assert(not enemy.strong_attack.active)
	assert(not enemy._movement_locked_by_attack)
	enemy.status_effect_component.remove_effect("stun")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8,100)
	shape.shape = rectangle
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy.strong_attack.cooldown = 0.0
	enemy.strong_attack.tick(0.1)
	assert(not enemy.strong_attack.active, "Wall must block skill initiation")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy.strong_attack.cooldown = 0.0
	enemy.strong_attack.tick(0.01)
	assert(enemy.strong_attack.active)
	enemy.health_component.current_hp = 1.0
	enemy.health_component.apply_damage(10.0)
	assert(not enemy.strong_attack.active, "Death must clear the skill")
	print("ORC_STEP_PASS: wall; death; one hit; connected; windup safe; directional hit; dodge; stun cleanup")
	get_tree().quit()
