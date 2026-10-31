extends Node2D
class_name FloatingWeapons

## Equipped art is a world sprite; the same muzzle is used for automatic projectiles.
const ICON_METRICS := preload("res://resources/equipment_icon_metrics.gd")
const WEAPON_AURA := preload("res://entities/player/weapon_aura.gdshader")
const EQUIPMENT_SIZE := 48.0
const IDLE_OFFSET := Vector2(38, -9)

var actor: Player
var _sprites: Dictionary = {}
var _phase := 0.0
var _attack_flash := 0.0
var _equipment_age := 1.0
var _equipment_kind := "slash"
var _equipment_direction := Vector2.RIGHT
var _equipment_radius := 104.0
var _strike_world := Vector2.ZERO
var _flight_from := Vector2.ZERO
var _rarity_color := Color.WHITE
var _rarity_rank := 0
var _trail: Array[Dictionary] = []
var _trail_timer := 0.0
var _effect: Sprite2D
const SLASH = preload("res://assets/vfx/equipment_comfy/slash_6f.png")
const THRUST = preload("res://assets/vfx/equipment_comfy/thrust_6f.png")
const SHOT = preload("res://assets/vfx/equipment_comfy/shot_6f.png")
const LIGHT = preload("res://assets/vfx/equipment_comfy/light_6f.png")
const HEAVY = preload("res://assets/vfx/equipment_comfy/heavy_6f.png")
const AXE = preload("res://assets/vfx/equipment_comfy/axe_6f.png")
const HAMMER = preload("res://assets/vfx/equipment_comfy/hammer_6f.png")
const SCYTHE = preload("res://assets/vfx/equipment_comfy/scythe_6f.png")

func bind_player(value: Player) -> void:
	actor = value
	_effect = Sprite2D.new()
	_effect.hframes = 6
	_effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_effect.z_index = 3
	_effect.visible = false
	add_child(_effect)
	actor.equipment_component.equipment_changed.connect(_on_equipment_changed)
	actor.weapon_manager.weapon_added.connect(func(_data: WeaponData): _refresh())
	actor.weapon_manager.weapon_fired.connect(func(): _attack_flash = 0.16)
	_refresh()

func _on_equipment_changed(slot: String, _item: EquipmentData) -> void:
	if slot == "weapon":
		cancel_equipment_motion()
		_refresh()

func _refresh() -> void:
	for sprite in _sprites.values():
		(sprite as Sprite2D).queue_free()
	_sprites.clear()
	if actor == null:
		return
	var equipment := actor.equipment_component.get_equipped("weapon")
	if equipment:
		_rarity_color = equipment.get_rarity_color()
		_rarity_rank = maxi(["uncommon", "rare", "epic", "legendary", "mythic"].find(equipment.rarity), 0)
		var path := "res://assets/visuals/ember_v5/equipment/%s.png" % equipment.template_id
		if not ResourceLoader.exists(path): path = equipment.icon_path
		if ResourceLoader.exists(path):
			_add_sprite("equipment", load(path) as Texture2D, _rarity_color)
	for instance in actor.weapon_manager.get_weapon_instances():
		if _sprites.size() >= 2:
			break
		if instance.data.icon:
			_add_sprite(instance.data.id, instance.data.icon, Color.WHITE)

func _add_sprite(key: String, art: Texture2D, tint: Color) -> void:
	if art == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = art
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bounds: Rect2i = ICON_METRICS.BOUNDS.get(art.resource_path, Rect2i(Vector2i.ZERO, art.get_size()))
	sprite.scale = Vector2.ONE * (EQUIPMENT_SIZE if key == "equipment" else 36.0) / maxf(bounds.size.x, bounds.size.y)
	sprite.offset = art.get_size() * 0.5 - Vector2(bounds.get_center())
	var aura := ShaderMaterial.new()
	aura.shader = WEAPON_AURA
	aura.set_shader_parameter("rarity_color", Color("ff4659") if key == "equipment" and _rarity_rank == 4 else tint)
	aura.set_shader_parameter("rarity_rank", float(_rarity_rank) if key == "equipment" else 0.0)
	aura.set_shader_parameter("aura_strength", 0.30 + _rarity_rank * 0.12 if key == "equipment" else 0.0)
	sprite.material = aura
	sprite.z_index = 2
	add_child(sprite)
	_sprites[key] = sprite

func _process(delta: float) -> void:
	if actor == null:
		return
	_phase += delta
	_attack_flash = maxf(_attack_flash - delta, 0.0)
	_equipment_age += delta
	var direction := actor.get_facing_direction()
	var side := 1.0 if direction.x >= 0.0 else -1.0
	var index := 0
	var profile: Dictionary = actor.weapon_manager.equipment_attack.PROFILES[_equipment_kind]
	var motion_time := float(profile.flight + profile.swing + profile["return"])
	for key in _sprites:
		var sprite := _sprites[key] as Sprite2D
		if key == "equipment" and _equipment_age < motion_time:
			_update_equipment_pose(sprite)
			_trail_timer -= delta
			if _trail_timer <= 0.0:
				_trail_timer = 0.025
				_trail.append({"position": sprite.global_position, "rotation": sprite.rotation})
				while _trail.size() > _rarity_rank + 1:
					_trail.pop_front()
			index += 1
			continue
		var target := Vector2(side * (IDLE_OFFSET.x + index * 16.0), IDLE_OFFSET.y - index * 14.0 + sin(_phase * 4.0 + index) * 2.0)
		(sprite as Sprite2D).position = (sprite as Sprite2D).position.lerp(target, minf(delta * 14.0, 1.0))
		(sprite as Sprite2D).rotation = sin(_phase * 3.0 + index) * 0.08 * side + (sin((_attack_flash / 0.16) * PI) * 0.5 * side if key != "equipment" else 0.0)
		index += 1
	var effect_age := _equipment_age - float(profile.flight)
	_effect.visible = effect_age >= 0.0 and effect_age < float(profile.swing) and _sprites.has("equipment")
	if _effect.visible:
		_effect.frame = mini(int(effect_age / float(profile.swing) * 6.0), 5)
		if _equipment_kind not in ["bow", "magic"]:
			_effect.position = to_local(_strike_world) - _equipment_direction * float(profile.cut) * 0.45
	if _equipment_age >= motion_time:
		_trail.clear()
	queue_redraw()

func start_equipment_motion(kind: String, direction: Vector2, radius: float, target_position: Vector2, item: EquipmentData) -> void:
	if not _sprites.has("equipment"):
		return
	_equipment_age = 0.0
	_equipment_kind = kind
	_equipment_direction = direction
	_equipment_radius = radius
	_strike_world = target_position
	_flight_from = (_sprites["equipment"] as Sprite2D).global_position
	_rarity_color = item.get_rarity_color()
	_rarity_rank = maxi(["uncommon", "rare", "epic", "legendary", "mythic"].find(item.rarity), 0)
	_trail.clear()
	_effect.texture = {"light":LIGHT, "heavy":HEAVY, "thrust":THRUST, "axe":AXE, "hammer":HAMMER, "scythe":SCYTHE, "bow":SHOT, "magic":SHOT}.get(kind, SLASH)
	_effect.rotation = direction.angle()
	_effect.position = direction * 35.0 if kind in ["bow", "magic"] else Vector2.ZERO
	var profile: Dictionary = actor.weapon_manager.equipment_attack.PROFILES[kind]
	# 表示サイズ：射撃は約42px、近接は64*cut/26px。シートはその約1/2の寸法で描いてある。
	var display_side := 41.6 if kind in ["bow", "magic"] else 64.0 * float(profile.cut) / 26.0 * actor.weapon_manager.get_melee_range_multiplier()
	_effect.scale = Vector2.ONE * display_side / float(_effect.texture.get_height())
	_effect.modulate = Color.WHITE.lerp(_rarity_color, 0.48 + _rarity_rank * 0.09)
	_update_equipment_pose(_sprites["equipment"])

func track_equipment_target(position_in_world: Vector2) -> void:
	_strike_world = position_in_world

func cancel_equipment_motion() -> void:
	_equipment_age = 1.0
	_trail.clear()
	if _effect:
		_effect.visible = false

func _update_equipment_pose(sprite: Sprite2D) -> void:
	if _equipment_kind in ["bow", "magic"]:
		var t := clampf(_equipment_age / 0.30, 0.0, 1.0)
		sprite.position = _equipment_direction * (30.0 - sin(t * PI) * 5.0)
		sprite.rotation = _equipment_direction.angle() + PI / 4.0
		return
	var profile: Dictionary = actor.weapon_manager.equipment_attack.PROFILES[_equipment_kind]
	var tangent := _equipment_direction.orthogonal()
	var arc := float(profile.cut) * 0.45
	var swing_t := clampf((_equipment_age - float(profile.flight)) / float(profile.swing), 0.0, 1.0)
	var cut_position := _strike_world + tangent * lerpf(-arc, arc, swing_t)
	if _equipment_kind == "thrust":
		cut_position = _strike_world + _equipment_direction * lerpf(-26.0, 12.0, swing_t)
	elif _equipment_kind == "hammer":
		cut_position = _strike_world + Vector2(0, lerpf(-22.0, 5.0, minf(swing_t * 3.0, 1.0)))
	elif _equipment_kind == "axe":
		cut_position = _strike_world + tangent * lerpf(-arc, arc, swing_t) - _equipment_direction * sin(swing_t * PI) * 5.0
	if _equipment_age < float(profile.flight):
		sprite.global_position = _flight_from.lerp(cut_position, _equipment_age / float(profile.flight))
	elif _equipment_age < float(profile.flight + profile.swing):
		sprite.global_position = cut_position
	else:
		var t := clampf((_equipment_age - float(profile.flight + profile.swing)) / float(profile["return"]), 0.0, 1.0)
		sprite.global_position = cut_position.lerp(actor.global_position + Vector2(IDLE_OFFSET.x * (1.0 if actor.get_facing_direction().x >= 0.0 else -1.0), IDLE_OFFSET.y), t)
	var offset := sprite.global_position - actor.global_position
	if offset.length() > _equipment_radius:
		sprite.global_position = actor.global_position + offset.limit_length(_equipment_radius)
	sprite.rotation = _equipment_direction.angle() + PI / 4.0 + (0.0 if _equipment_kind == "thrust" else lerpf(-1.0, 1.0, swing_t))
	if _equipment_kind == "hammer":
		sprite.rotation = _equipment_direction.angle() + PI / 4.0 + lerpf(-0.6, 0.2, minf(swing_t * 3.0, 1.0))
	elif _equipment_kind == "axe":
		sprite.rotation = _equipment_direction.angle() + PI / 4.0 + lerpf(-1.4, 0.8, swing_t)

func _draw() -> void:
	if actor == null or actor._is_dead or not _sprites.has("equipment"):
		return
	var radius: float = actor.weapon_manager.equipment_attack.get_range(actor.weapon_manager)
	# A quiet dotted boundary, always centred on the player rather than the orbiting art.
	for segment in 48:
		var angle := TAU * segment / 48.0
		draw_arc(Vector2.ZERO, radius, angle, angle + TAU / 72.0, 3, Color(0.64, 0.82, 0.85, 0.30), 1.0, false)
	var sprite := _sprites["equipment"] as Sprite2D
	for index in _trail.size():
		var pose: Dictionary = _trail[index]
		draw_set_transform(to_local(pose.position), float(pose.rotation), sprite.scale)
		draw_texture(sprite.texture, -sprite.texture.get_size() * 0.5 + sprite.offset, Color(_rarity_color, 0.06 + 0.04 * index))
	draw_set_transform(Vector2.ZERO)
	if _effect.visible and _rarity_rank > 0 and _equipment_kind not in ["bow", "magic"]:
		for index in _rarity_rank:
			var offset := Vector2.from_angle(index * 2.4 + 0.6) * (15.0 + _rarity_rank * 2.0)
			var point := to_local(_strike_world) + offset
			draw_texture_rect_region(SHOT, Rect2(point - Vector2(12,12), Vector2(24,24)), Rect2(_effect.frame * SHOT.get_height(), 0, SHOT.get_height(), SHOT.get_height()), Color(_rarity_color, 0.65))

func get_muzzle(weapon_id: String) -> Vector2:
	if _sprites.has(weapon_id):
		return (_sprites[weapon_id] as Sprite2D).global_position
	return actor.global_position if actor else global_position
