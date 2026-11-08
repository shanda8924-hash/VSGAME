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
	var ring := warning.get_node("PixelRing") as PixelSpriteVFX
	_check(ring != null and ring.get_meta("pixel_vfx_id", "") == WarningCircle.RING_KEY and String(ring.get_meta("pixel_vfx_source", "")) == "arcane/rune-circle", "Boss warning uses the pixelfx rune circle")
	_check(ring != null and is_equal_approx(ring.scale.x * PixelSpriteVFX.frame_size_for(WarningCircle.RING_KEY).x, 220.0), "warning artwork width matches attack diameter")
	_check(ring != null and ring.modulate != Color.WHITE and is_equal_approx(ring.modulate.a, warning.border_color.a), "Nova/Summon warning color remains configurable")
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
	_check(telegraph.get_child_count() == 1 and telegraph.get_child(0) is PixelSpriteVFX and (telegraph.get_child(0) as PixelSpriteVFX).persistent, "essential telegraph is one uncapped pixelfx ring")
	telegraph.trigger_once()
	_check(is_equal_approx(health.current_hp, 88.0), "delayed elite attack still triggers original damage")
	telegraph.queue_free()
	var projectile := load("res://entities/projectiles/projectile.tscn").instantiate() as Projectile
	add_child(projectile)
	var glow := projectile.get_node("Glow") as Sprite2D
	_check(glow.texture is AtlasTexture and (glow.texture as AtlasTexture).atlas.resource_path == PixelSpriteVFX.ASSET_DIRECTORY + "projectile_core.png", "projectile glow is a pixelfx frame rather than GradientTexture")
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
