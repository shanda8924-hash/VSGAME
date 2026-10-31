extends Node2D
## Pixel replacement may change art, never warning radius, damage, or ownership.

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveManager.begin_ephemeral_session()
	var player := Node2D.new()
	player.add_to_group("player")
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	player.add_child(health)
	add_child(player)
	var warning := WarningCircle.new()
	warning.radius = 110.0
	warning.border_color = Color(0.8, 0.4, 1.0, 0.95)
	add_child(warning)
	var ring := warning.get_node("PixelRing") as Sprite2D
	_check(ring.texture.resource_path == "res://assets/vfx/pixel/warning_ring.png", "Boss warning uses generated PNG")
	_check_warning_image_radius()
	_check(is_equal_approx(ring.scale.x * WarningCircle.RING_PIXEL_RADIUS, 110.0), "warning artwork boundary matches attack radius")
	_check(ring.modulate == warning.border_color, "Nova/Summon warning color remains configurable")
	_check(ring.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "warning uses crisp nearest filtering")
	warning.queue_free()
	player.position = Vector2(61, 0)
	var poison := EliteHazard.new()
	poison.radius = 60.0
	poison.duration = 0.95
	poison.tick_interval = 0.1
	poison.damage = 5.0
	add_child(poison)
	var animated_poison := poison.get_child(1) as PixelSpriteVFX
	_check(animated_poison != null, "poison uses animated pixel sheet")
	if animated_poison:
		_check(animated_poison.sprite_frames.get_frame_count("play") == 6, "poison has six generated animation frames")
	await get_tree().create_timer(0.13).timeout
	_check(is_equal_approx(health.current_hp, 100.0), "outside original radius does not take poison damage")
	_check(animated_poison != null and animated_poison.frame > 0, "poison visibly advances frames")
	player.position = Vector2(60, 0)
	await get_tree().create_timer(0.14).timeout
	_check(is_equal_approx(health.current_hp, 95.0), "original inclusive radius and 5 damage remain intact")
	player.position = Vector2(61, 0)
	await get_tree().create_timer(0.44).timeout
	_check(is_instance_valid(animated_poison), "poison animation loops beyond its 0.6 second cycle")
	await get_tree().create_timer(0.3).timeout
	_check(not is_instance_valid(poison) and not is_instance_valid(animated_poison), "poison ends with owning hazard, without orphaned VFX")
	var telegraph := EliteHazard.new()
	telegraph.warning_only = true
	telegraph.duration = 0.5
	telegraph.radius = 60.0
	telegraph.damage = 7.0
	player.position = Vector2.ZERO
	add_child(telegraph)
	health._iframe_remaining = 0.0
	await get_tree().create_timer(0.1).timeout
	_check(is_equal_approx(health.current_hp, 95.0), "warning-only hazard still waits for explicit attack")
	_check(telegraph.get_child_count() == 1 and telegraph.get_child(0) is Sprite2D, "essential telegraph is one uncapped static pixel sprite")
	telegraph.trigger_once()
	_check(is_equal_approx(health.current_hp, 88.0), "delayed elite attack still triggers original damage")
	telegraph.queue_free()
	var projectile := load("res://entities/projectiles/projectile.tscn").instantiate() as Projectile
	add_child(projectile)
	var glow := projectile.get_node("Glow") as Sprite2D
	_check(glow.texture.resource_path == "res://assets/vfx/pixel/projectile_core.png", "projectile uses PNG rather than GradientTexture")
	_check(glow.texture.get_size() == Vector2(24, 24), "projectile core keeps 24px footprint")
	_check(is_equal_approx((projectile.get_node("CollisionShape2D").shape as CircleShape2D).radius, 6.0), "projectile attack collision is unchanged")
	_check((projectile.get_node("Visual") as Sprite2D).texture.resource_path.ends_with("Arrow01(32x32).png"), "actual arrow weapon remains unchanged")
	projectile.queue_free()
	player.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error("PIXEL_HAZARD_CHECK: " + failure)
	print("PIXEL_HAZARD_CHECK failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _check_warning_image_radius() -> void:
	# Readback is test-only. Ignore the four cardinal ticks, not the actual circle.
	var image := WarningCircle.RING_TEXTURE.get_image()
	_check(image.get_size() == Vector2i(64, 64), "warning PNG dimensions")
	var minimum := Vector2i(64, 64)
	var maximum := Vector2i.ZERO
	for y in 64:
		for x in 64:
			if absf(float(x) - 31.5) <= 2.0 or absf(float(y) - 31.5) <= 2.0:
				continue
			if image.get_pixel(x, y).a > 0.0:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	var body_extent := maximum + Vector2i.ONE - minimum
	var measured_radius := float(maxi(body_extent.x, body_extent.y)) * 0.5
	print("PIXEL_HAZARD warning ring body radius=%.1f px, full tick bounds=%s" % [measured_radius, image.get_used_rect()])
	_check(is_equal_approx(measured_radius, WarningCircle.RING_PIXEL_RADIUS), "warning scale uses measured circle body rather than compass ticks")
