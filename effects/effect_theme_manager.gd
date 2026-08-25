extends Node
class_name EffectThemeManager
## 武器属性ごとのVFXテーマ実行役(設計提案書 7.2「武器属性別テーマ例」に対応)。
## WeaponData.vfx_theme_id からEffectThemeData(res://effects/themes/*.tres)を引き当て、
## 通常ヒット/強化(レベル依存)の見た目をここに集約する。
## 新しい属性テーマはeffects/themes/にResourceを追加するだけで良く、
## Projectile側やこのスクリプト自体の変更は不要(開放閉鎖の原則)。

const ENHANCED_CHARACTER_LEVEL := 3
const CHAIN_BASE_COUNT := 1
const CHAIN_COUNT_PER_LEVEL := 1
const CHAIN_MAX_COUNT := 5

func _ready() -> void:
	add_to_group("effect_theme_manager")

## theme_id: WeaponData.vfx_theme_id。character_level: プレイヤーのExperienceComponent.level。
## origin_position: 攻撃の発射位置(光属性のビーム描画・闇属性の吸収演出に使用)。
func play_weapon_hit(theme_id: String, position: Vector2, character_level: int, hit_hurtbox: HurtboxComponent = null, origin_position: Vector2 = Vector2.ZERO, is_critical: bool = false, suppress_class_yellow_hit: bool = false) -> void:
	# 属性Themeが無いstarter_swordでも、実命中を伝えるPixel Hit VFXは必ず要求する。
	var attack_vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
	if attack_vfx and not suppress_class_yellow_hit:
		attack_vfx.play_hit(position, theme_id, is_critical)
	var theme: EffectThemeData = DataLoader.effect_themes.get(theme_id)
	if theme == null:
		return
	for element_id in theme.get_component_ids():
		_play_element(element_id, position, character_level, hit_hurtbox, origin_position, suppress_class_yellow_hit)

func _play_element(element_id: String, position: Vector2, character_level: int, hit_hurtbox: HurtboxComponent, origin_position: Vector2, suppress_class_yellow_hit: bool = false) -> void:
	var theme: EffectThemeData = DataLoader.effect_themes.get(element_id)
	if theme == null:
		return

	var enhanced := character_level >= ENHANCED_CHARACTER_LEVEL
	if enhanced and theme.enhanced_requires_status != "":
		enhanced = _target_has_status(hit_hurtbox, theme.enhanced_requires_status)

	var suppress_base_particle := suppress_class_yellow_hit and element_id == "lightning"
	var pixel_data := DataLoader.element_vfx_effects.get("element_%s" % element_id) as ElementVFXData
	var attack_vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
	if attack_vfx and pixel_data and not suppress_base_particle:
		# 旧GPUParticlesと新Pixel Spriteを二重表示しない。属性Hitは一つの
		# 6-frame Shape形成→Fragmentだけへ統一する。
		attack_vfx.play_element_hit(position, pixel_data, 3 if enhanced else 1)
	else:
		var scene: PackedScene = theme.enhanced_particle_scene if enhanced and theme.enhanced_particle_scene else theme.hit_particle_scene
		if not suppress_base_particle:
			_spawn_particle(scene, position)

	if theme.status_effect != "":
		_apply_status(hit_hurtbox, theme.status_effect, theme.status_duration)

	if theme.is_beam:
		var from := origin_position if origin_position != Vector2.ZERO else position
		var width := 6.0 if enhanced else 3.0
		var color := theme.enhanced_color if enhanced else theme.hit_color
		_spawn_line(from, position, color, width, 0.2)
		# 以前は強化時にscreen_effects.flash()で画面全体をフラッシュさせていたが、
		# 攻撃速度上昇で点滅頻度が上がり不快感・光過敏性リスクにつながるため廃止。
		# 着弾位置周辺の局所的なビーム線(上記_spawn_line)のみに留める。

	# 現在属性の雷連鎖はElementCombatSystemが実ダメージと同じ対象へ描画する。
	# 旧Themeだけの見かけ上のChainは、雷Shard未所持のFusion演出に限定する。
	if theme.is_chain and enhanced and GameManager.get_element_stack("element_lightning") <= 0:
		var count: int = clamp(CHAIN_BASE_COUNT + (character_level - ENHANCED_CHARACTER_LEVEL) * CHAIN_COUNT_PER_LEVEL, CHAIN_BASE_COUNT, CHAIN_MAX_COUNT)
		_spawn_chain(position, theme.enhanced_color, count)

	if theme.is_absorb and enhanced and origin_position != Vector2.ZERO:
		await get_tree().create_timer(0.15).timeout
		_spawn_particle(theme.enhanced_particle_scene, origin_position)

func _spawn_particle(scene: PackedScene, position: Vector2) -> void:
	if scene == null:
		return
	var p: Node = scene.instantiate()
	add_child(p)
	if p is Node2D:
		p.global_position = position
	if p is GPUParticles2D:
		var particles := p as GPUParticles2D
		particles.emitting = true
		get_tree().create_timer(particles.lifetime + 0.3).timeout.connect(particles.queue_free)
	else:
		p.queue_free()

func _apply_status(hurtbox: HurtboxComponent, effect_name: String, duration: float) -> void:
	var status := _get_status_component(hurtbox)
	if status:
		status.apply_effect(effect_name, duration)

func _target_has_status(hurtbox: HurtboxComponent, effect_name: String) -> bool:
	var status := _get_status_component(hurtbox)
	return status.has_effect(effect_name) if status else false

func _get_status_component(hurtbox: HurtboxComponent) -> StatusEffectComponent:
	if hurtbox == null:
		return null
	var entity := hurtbox.get_owner_entity()
	if entity == null:
		return null
	return entity.get_node_or_null("StatusEffectComponent")

func _spawn_line(from: Vector2, to: Vector2, color: Color, width: float, fade_duration: float) -> void:
	if from.distance_squared_to(to) <= 1.0:
		return
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.antialiased = false
	var segment := to - from
	var normal := segment.normalized().orthogonal()
	var steps := clampi(int(segment.length() / 18.0), 3, 14)
	for index in steps + 1:
		var ratio := float(index) / float(steps)
		var stair_offset := normal * float((index % 3) - 1) * 2.0
		line.add_point((from + segment * ratio + stair_offset).round())
	add_child(line)
	# 全体Fadeではなく、数Frameだけ濃く表示して即解放する。
	get_tree().create_timer(minf(fade_duration, 0.16)).timeout.connect(line.queue_free)

func _spawn_chain(origin: Vector2, color: Color, count: int) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	enemies.sort_custom(func(a, b): return origin.distance_to(a.global_position) < origin.distance_to(b.global_position))
	var previous := origin
	var made := 0
	for e in enemies:
		if made >= count:
			break
		var health: HealthComponent = e.get_node_or_null("HealthComponent")
		if health == null or health.current_hp <= 0.0:
			continue
		_spawn_line(previous, e.global_position, color, 3.0, 0.25)
		previous = e.global_position
		made += 1
