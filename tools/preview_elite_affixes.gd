extends Node2D

const IDS := ["fire", "lightning", "freeze", "poison", "vampiric", "fortified"]
const NAMES := ["火炎｜周囲爆発", "雷撃｜地点落雷", "氷結｜命中スロー", "毒｜持続する毒沼", "吸血｜命中回復", "堅牢｜再生シールド"]
const CAPTIONS := [
	"橙の紋章と床予兆 → 炎が一気に噴き上がる",
	"黄の紋章と照準 → 予兆地点へ落雷",
	"青の結晶紋章 → 命中時に氷片が弾ける",
	"緑の泡紋章と床予兆 → 毒沼がその場に残る",
	"紅の血滴紋章 → 命中時に生命を吸収",
	"銀の盾紋章 → シールド展開中は六角障壁を表示",
]

var enemy: EnemyBasic
var target: CharacterBody2D
var target_hurtbox: HurtboxComponent
var title: Label
var caption: Label
var settings: Dictionary
var output := "C:/Users/USER/Documents/Codex/2026-09-09/v/outputs/elite_affixes"
var failures: Array[String] = []

func _draw() -> void:
	draw_rect(Rect2(-200, -120, 400, 240), Color("101c26"))
	for x in range(-200, 201, 16):
		draw_line(Vector2(x, -120), Vector2(x, 120), Color("1c303c"), 0.3)
	for y in range(-120, 121, 16):
		draw_line(Vector2(-200, y), Vector2(200, y), Color("1c303c"), 0.3)

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	get_window().size = Vector2i(800, 600)
	get_tree().root.content_scale_size = Vector2i(800, 600)
	var camera := Camera2D.new()
	camera.zoom = Vector2(4, 4)
	add_child(camera)
	_build_target()
	_build_enemy()
	_build_caption()
	settings = _read_json("res://data/elite_affixes/default.json").get("affixes", {})
	for index in IDS.size():
		await _capture_affix(index)
	print("ELITE_AFFIX_VFX_PASS" if failures.is_empty() else "ELITE_AFFIX_VFX_FAIL: %s" % failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _build_target() -> void:
	target = CharacterBody2D.new()
	target.add_to_group("player")
	target.position = Vector2(38, 0)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_hp = 1000.0
	target.add_child(health)
	var status := StatusEffectComponent.new()
	status.name = "StatusEffectComponent"
	target.add_child(status)
	target_hurtbox = HurtboxComponent.new()
	target_hurtbox.name = "HurtboxComponent"
	target_hurtbox.health_component_path = NodePath("../HealthComponent")
	target.add_child(target_hurtbox)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = SpriteSheetBuilder.build_sprite_frames("player/Swordsman")
	sprite.scale = Vector2(1.4, 1.4)
	sprite.flip_h = true
	target.add_child(sprite)
	add_child(target)
	sprite.play("idle")

func _build_enemy() -> void:
	enemy = load("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	enemy.enemy_data = DataLoader.enemies["elite_orc"]
	enemy.elite_stat_multiplier = 2.0
	enemy.visual_scale_multiplier = 1.78
	enemy.position = Vector2(-24, 0)
	add_child(enemy)
	enemy.set_physics_process(false)

func _build_caption() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	title = Label.new()
	title.position = Vector2(24, 25)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("ffd37a"))
	layer.add_child(title)
	caption = Label.new()
	caption.position = Vector2(24, 64)
	caption.add_theme_font_size_override("font_size", 20)
	layer.add_child(caption)
	var footer := Label.new()
	footer.text = "実ゲーム内表示／拡大・等速"
	footer.position = Vector2(24, 552)
	footer.add_theme_font_size_override("font_size", 18)
	layer.add_child(footer)

func _capture_affix(index: int) -> void:
	var id: String = IDS[index]
	var target_health := target.get_node("HealthComponent") as HealthComponent
	target_health.current_hp = target_health.max_hp
	target_health._iframe_remaining = 0.0
	enemy.health_component.current_hp = enemy.health_component.max_hp * 0.5 if id == "vampiric" else enemy.health_component.max_hp
	var hp_before_activation := target_health.current_hp
	DirAccess.make_dir_recursive_absolute(output + "/" + id)
	title.text = "精鋭能力　" + NAMES[index]
	caption.text = CAPTIONS[index]
	var component := EliteAffixComponent.new()
	component.set_process(false)
	var ids: Array[String] = [id]
	component.configure(enemy, ids, settings)
	enemy.add_child(component)
	await get_tree().process_frame
	var config: Dictionary = settings[id]
	for frame_index in 150:
		if frame_index == 22:
			if id in ["fire", "lightning", "poison", "fortified"]:
				component._activate_periodic(id)
			else:
				component._visual.pulse_affix(id, 0.55)
		if frame_index == 42 and id in ["freeze", "vampiric"]:
			component._on_elite_attack_landed(target_hurtbox)
		if frame_index == 43 and id == "freeze" and not (target.get_node("StatusEffectComponent") as StatusEffectComponent).has_effect("slow"):
			failures.append("freeze: slow missing")
		if frame_index == 35 and id in ["fire", "lightning", "poison"] and target_health.current_hp != hp_before_activation:
			failures.append(id + ": damage during warning")
		if frame_index == 55 and id in ["fire", "lightning", "poison"] and target_health.current_hp >= hp_before_activation:
			failures.append(id + ": no damage after warning")
		await RenderingServer.frame_post_draw
		if "--logic-only" not in OS.get_cmdline_user_args():
			get_viewport().get_texture().get_image().save_png(output + "/" + id + "/%03d.png" % frame_index)
		await get_tree().process_frame
	if component._visual == null:
		failures.append(id + ": aura missing")
	if id == "vampiric" and enemy.health_component.current_hp <= enemy.health_component.max_hp * 0.5:
		failures.append("vampiric: heal missing")
	if id == "fortified" and enemy.health_component.shield_amount <= 0.0:
		failures.append("fortified: shield missing")
	component.queue_free()
	for hazard in get_tree().get_nodes_in_group("room_transient"):
		hazard.queue_free()
	await get_tree().process_frame
	enemy.health_component.clear_shield()

func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
