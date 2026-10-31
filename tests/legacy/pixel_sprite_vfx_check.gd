extends Node2D
## Generated sheets + real public VFX entry points. No damage/balance or save writes.
const ACTIVE_STYLES := ["burst", "charge", "aura", "shield", "sanctuary", "time", "summon", "chains", "holy_burst", "execution", "impact", "rain"]
const CONCEPT_KINDS := ["thunder_strike", "fire_burst", "ice_nova", "wind_blade", "light_burst", "dark_rift"]
const SIGNATURES := ["thunderlord_descent", "inferno_pillar", "glacial_spear_rain", "radiant_blade_array", "void_severance"]
const THEMES := ["fire", "ice", "lightning", "light", "dark"]
var failures: Array[String] = []
var _bucket: Node2D

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PIXEL_SPRITE_VFX_CHECK: " + message)

func _run() -> void:
	await _check_assets_and_gallery()
	await _check_active_and_concept_routes()
	await _check_theme_routes()
	await _check_budget_and_pool()
	print("PIXEL_SPRITE_VFX_CHECK failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _new_bucket() -> void:
	if is_instance_valid(_bucket):
		_bucket.queue_free()
		await get_tree().process_frame
	_bucket = Node2D.new()
	add_child(_bucket)

func _all_ids() -> Array[String]:
	var result: Array[String] = []
	for value: String in ACTIVE_STYLES:
		result.append("active_" + value)
	for value: String in CONCEPT_KINDS:
		result.append("concept_" + value)
	for value: String in SIGNATURES:
		result.append("signature_" + value)
	for value: String in THEMES:
		result.append("hit_" + value)
	result.append_array(["beam", "chain", "mass_kill", "loot_awaken", "forge_awaken", "poison"])
	return result

func _check_assets_and_gallery() -> void:
	await _new_bucket()
	var ids := _all_ids()
	for index in ids.size():
		var id := ids[index]
		var frames := PixelSpriteVFX.frames_for(id)
		_check(frames != null, id + " has a generated runtime PNG")
		if frames == null:
			continue
		_check(frames.get_frame_count("play") == 6, id + " has six frames")
		_check(PixelSpriteVFX.frames_for(id) == frames, id + " reuses cached SpriteFrames")
		var position := Vector2(108 + (index % 8) * 196, 74 + (index / 8) * 170)
		var effect := PixelSpriteVFX.spawn(_bucket, position, id, Vector2(112, 112), 1.0)
		_check(effect != null, id + " connected to Sprite")
		if effect:
			effect.set_process(false)
			effect.frame = 2
			var label := Label.new()
			label.text = id.replace("signature_", "sig_").replace("concept_", "")
			label.position = position + Vector2(-92, 64)
			label.size = Vector2(184, 30)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 16)
			_bucket.add_child(label)
		if index % 8 == 7:
			await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
		get_viewport().get_texture().get_image().save_png("res://artifacts/generated_pixel_vfx_gallery.png")
	await _new_bucket()

func _check_active_and_concept_routes() -> void:
	for style: String in ACTIVE_STYLES:
		var effect := ActiveSkillVFX.new()
		effect.setup(80.0, Color.YELLOW, Vector2.RIGHT, 60.0, style)
		_bucket.add_child(effect)
		effect.position = Vector2(120, 120)
		var sprite := effect.get_child(0) as PixelSpriteVFX if effect.get_child_count() else null
		_check(sprite != null and String(sprite.get_meta("pixel_vfx_id", "")) == "active_" + style, "Space route " + style)
		if sprite:
			_check(maxf(sprite.scale.x, sprite.scale.y) * PixelSpriteVFX.FRAME_SIZE <= ActiveSkillVFX.MAX_VISUAL_SIDE, style + " respects visual footprint budget")
			var position := sprite.global_position
			sprite._process(0.19)
			_check(sprite.frame >= 3, style + " changes actual sprite frames")
			_check(sprite.global_position == position and sprite.modulate.a == 1.0, style + " stays stationary and opaque")
		effect.queue_free()
		await get_tree().process_frame
	for kind: String in CONCEPT_KINDS:
		var effect := ConceptSkillVFX.spawn(_bucket, Vector2(300, 200), kind, 80, Color.WHITE)
		_check(effect._pixel_sprite is PixelSpriteVFX, "Concept route " + kind)
		_check(String(effect.get_meta("pixel_vfx_texture", "")) == PixelSpriteVFX.ASSET_DIRECTORY + "concept_" + kind + ".png", "Concept asset " + kind)
		effect.queue_free()
		await get_tree().process_frame
	for profile: String in SIGNATURES:
		var effect := ConceptSkillVFX.spawn(_bucket, Vector2.ZERO, "fire_burst", 80, Color.WHITE, 3, profile)
		_check(effect._pixel_sprite is PixelSpriteVFX, "Signature route " + profile)
		_check(String(effect.get_meta("signature_vfx_profile", "")) == profile, "Signature metadata " + profile)
		effect.queue_free()
		await get_tree().process_frame
	await _new_bucket()

func _check_theme_routes() -> void:
	var manager := EffectThemeManager.new()
	_bucket.add_child(manager)
	for id: String in THEMES:
		manager.play_weapon_hit(id, Vector2(80, 80), 1)
		_check(_find_id(manager, "hit_" + id) != null, "Weapon theme sprite " + id)
		await get_tree().process_frame
	var enemies: Array[Node2D] = []
	for index in 3:
		var enemy := Node2D.new()
		enemy.position = Vector2(100 + index * 70, 200)
		enemy.add_to_group("enemies")
		var health := HealthComponent.new()
		health.name = "HealthComponent"
		enemy.add_child(health)
		_bucket.add_child(enemy)
		enemies.append(enemy)
	manager.play_weapon_hit("light", Vector2(280, 200), 3, null, Vector2(80, 200))
	_check(_find_id(manager, "beam") != null, "Beam path uses image")
	manager.play_weapon_hit("lightning", Vector2(30, 200), 3)
	_check(_find_id(manager, "chain") != null, "Chain path uses image")
	for enemy in enemies:
		enemy.queue_free()
	# Absorb's delayed callback no longer retains any enemy; death must not invalidate a VFX ID.
	manager.play_weapon_hit("dark", Vector2(280, 200), 3, null, Vector2(80, 200))
	await get_tree().create_timer(0.65).timeout
	_check(manager.get_child_count() == 0, "Theme/beam/chain/delayed absorb all release")
	await _new_bucket()

func _find_id(parent: Node, id: String) -> PixelSpriteVFX:
	for child in parent.get_children():
		if child is PixelSpriteVFX and String(child.get_meta("pixel_vfx_id", "")) == id:
			return child as PixelSpriteVFX
	return null

func _check_budget_and_pool() -> void:
	for _wave in 4:
		for _index in 50:
			PixelSpriteVFX.spawn(_bucket, Vector2.ZERO, "hit_fire", Vector2(32, 32), 1.0)
		await get_tree().process_frame
	_check(_bucket.get_child_count() <= PixelSpriteVFX.MAX_LIVE, "Repeated hits stay within live budget")
	_check(_bucket.get_child_count() > 0, "Budget still allows visible effects")
	await _new_bucket()
	var pool := VFXPoolManager.new()
	_bucket.add_child(pool)
	_check(pool._pool.size() == 6, "Mass-kill keeps six pooled sprites")
	for _index in 20:
		pool.play_mass_kill_burst(Vector2.ZERO)
	_check(pool.get_child_count() == 6, "Burst spam creates no extra pool nodes")
	await get_tree().create_timer(0.7).timeout
	for sprite in pool._pool:
		_check(not sprite.active and not sprite.visible, "Pool sprite returns idle without deletion")
	pool.play_mass_kill_burst(Vector2(80, 80))
	_check(pool._pool.size() == 6 and pool._pool[0].active, "Idle sprite is reused")
	await _new_bucket()
