extends Node2D
const IDS := ["armored_orc","armored_skeleton","greatsword_skeleton","blood_monster_b","elite_orc","werebear"]
const NAMES := ["重装オーク｜踏み込み斬り","重装スケルトン｜迎撃突き","大剣スケルトン｜大薙ぎ払い","ブラッドモンスターB｜血槍","エリートオーク｜二連斬り","ワーベア｜跳びかかり叩きつけ"]
var target: CharacterBody2D
var health: HealthComponent
var caption: Label
var title: Label
var failures: Array[String] = []
var output := "C:/Users/USER/Documents/Codex/2026-09-09/v/outputs/strong_roster"

func _draw() -> void:
	draw_rect(Rect2(-200,-120,400,240),Color("15222b"))
	for x in range(-200,201,16): draw_line(Vector2(x,-120),Vector2(x,120),Color("20333e"),0.3)
	for y in range(-120,121,16): draw_line(Vector2(-200,y),Vector2(200,y),Color("20333e"),0.3)

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func spawn(id: String) -> EnemyBasic:
	var e := load("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	e.enemy_data = DataLoader.enemies[id]
	e.position = Vector2(-30,0)
	add_child(e)
	e.set_physics_process(false)
	return e

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	get_window().size = Vector2i(800,600)
	get_tree().root.content_scale_size = Vector2i(800,600)
	var camera := Camera2D.new()
	camera.zoom = Vector2(4,4)
	add_child(camera)
	target = CharacterBody2D.new()
	target.add_to_group("player")
	target.position = Vector2(30,0)
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_hp = 1000
	target.add_child(health)
	var hurtbox := HurtboxComponent.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.health_component_path = NodePath("../HealthComponent")
	target.add_child(hurtbox)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = SpriteSheetBuilder.build_sprite_frames("player/Swordsman")
	sprite.scale = Vector2(1.4,1.4)
	sprite.flip_h = true
	target.add_child(sprite)
	add_child(target)
	sprite.play("idle")
	var layer := CanvasLayer.new()
	add_child(layer)
	title = Label.new()
	title.position = Vector2(24,25)
	title.add_theme_font_size_override("font_size",25)
	layer.add_child(title)
	caption = Label.new()
	caption.position = Vector2(24,65)
	caption.add_theme_font_size_override("font_size",21)
	layer.add_child(caption)
	var footer := Label.new()
	footer.text = "実ゲームの敵・素材・攻撃処理／拡大・等速"
	footer.position = Vector2(24,552)
	footer.add_theme_font_size_override("font_size",18)
	layer.add_child(footer)
	for index in IDS.size():
		var id: String = IDS[index]
		DirAccess.make_dir_recursive_absolute(output+"/"+id)
		target.position = Vector2(30,0)
		health.current_hp = 1000
		var e := spawn(id)
		if e.strong_attack == null:
			failures.append(id+": skill disconnected")
			e.queue_free()
			continue
		title.text = NAMES[index]
		var dodge_hp := 0.0
		for i in 180:
			if i == 18 or i == 105: e.strong_attack.cooldown = 0.0
			if (i >= 18 and i < 80) or (i >= 105 and i < 172): e.strong_attack.tick(1.0/30.0)
			if i == 29: check(health.current_hp == 1000,id+": windup damage")
			if i == 80:
				var multiplier: float = 1.35 if id == "armored_orc" else float(e.strong_attack.move.damage)*e.strong_attack.move.hits.size()
				check(is_equal_approx(1000-health.current_hp,e.contact_hitbox.damage*multiplier),id+": wrong number of hits")
				e.position = Vector2(-30,0)
				e._normal_attack_state = EnemyBasic.NormalAttackState.READY
				dodge_hp = health.current_hp
			if i == 115: target.position.y = 65
			if i == 174: check(is_equal_approx(health.current_hp,dodge_hp),id+": dodge failed")
			caption.text = "赤い目の合図 → 構え → 固有技" if i < 80 else "次は予兆を見て横へ避ける → 空振り"
			await RenderingServer.frame_post_draw
			if "--logic-only" not in OS.get_cmdline_user_args():
				get_viewport().get_texture().get_image().save_png(output+"/"+id+"/%03d.png" % i)
			await get_tree().process_frame
		# Interrupt every species, including the bear in midair.
		e.position = Vector2(-30,0)
		target.position = Vector2(30,0)
		e._normal_attack_state = EnemyBasic.NormalAttackState.READY
		e.strong_attack.cooldown = 0.0
		e.strong_attack.tick(0.60)
		e.status_effect_component.apply_effect("stun",1.0)
		e.strong_attack.tick(0.01)
		check(not e.strong_attack.active and not e._movement_locked_by_attack,id+": stun lock")
		check(e.animated_sprite.position == Vector2.ZERO,id+": airborne pose left behind")
		e.status_effect_component.remove_effect("stun")
		e.strong_attack.cooldown = 0.0
		e.strong_attack.tick(0.01)
		e.set_room_activation_locked(true)
		check(not e.strong_attack.active,id+": room transition did not cancel")
		e.queue_free()
		await get_tree().process_frame
	# Nearby attack slots include the original orc and all five new species.
	var cohort: Array[EnemyBasic] = []
	for id in ["armored_orc","armored_skeleton","greatsword_skeleton"]:
		var e := spawn(id)
		e.strong_attack.cooldown = 0.0
		e.strong_attack.tick(0.01)
		cohort.append(e)
	check(cohort[0].strong_attack.active and cohort[1].strong_attack.active and not cohort[2].strong_attack.active,"nearby attack limit")
	for e in cohort: e.queue_free()
	await get_tree().process_frame
	for id in IDS:
		target.position = Vector2(30,0)
		var e := spawn(id)
		e.strong_attack.cooldown = 0.0
		e.set_physics_process(true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(e.strong_attack.active,id+": real physics entry")
		e.set_physics_process(false)
		e.strong_attack.cancel()
		target.position = e.position+Vector2(1,0)
		e._normal_attack_state = EnemyBasic.NormalAttackState.READY
		e.strong_attack.cooldown = 0.0
		e.strong_attack.tick(0.01)
		check(e.strong_attack.active,id+": point blank skill unavailable")
		e.health_component.current_hp = 1.0
		e.health_component.apply_damage(10.0)
		check(not e.strong_attack.active,id+": death cleanup")
		e.queue_free()
		await get_tree().process_frame
	if failures.is_empty(): print("STRONG_ROSTER_PASS: actual physics; point blank; death; six data connections; exact hits; windups; dodges; stun; room cancel; 2-slot limit")
	else: print("STRONG_ROSTER_FAIL: ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
