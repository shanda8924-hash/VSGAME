extends SceneTree
## エフェクトの全面置き換え（pixelfx）の検査。
## Godot --headless --path . --script res://tests/pixelfx_vfx_check.gd
## 1) 対応表 data/vfx/pixelfx_effects.json の全キーがシートとメタを持ち、SpriteFramesになる。
## 2) ゲームが要求するキー（命中・技・秘技・概念・浮遊武器・柱など）が漏れていない。
## 3) 旧エフェクト（assets/vfx/pixel 等、tools/vfx_unified）が残っていない。
## 4) 再生器の置き方：pivot・整数倍・横伸ばし・左向きの反転・一発物の終了。
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx/pixelfx_effects.json"))
	var effects: Dictionary = manifest.get("effects", {})
	check(effects.size() >= 60, "manifest lost entries (%d)" % effects.size())
	var total_bytes := 0
	for key in effects.keys():
		var meta := PixelSpriteVFX.meta_for(key)
		check(not meta.is_empty(), "missing json: " + key)
		check(String(meta.get("fx", "")) == String(effects[key].get("fx", "")), "sheet is stale for %s (re-run tools/pixelfx_import/build.mjs)" % key)
		var frames := PixelSpriteVFX.frames_for(key)
		check(frames != null and frames.get_frame_count("play") == int(meta.get("count", -1)), "frames do not build: " + key)
		var texture := load(PixelSpriteVFX.ASSET_DIRECTORY + key + ".png") as Texture2D
		if texture:
			total_bytes += texture.get_width() * texture.get_height() * 4
	var required: Array[String] = ["hit_normal", "hit_critical", "attack_pulse", "attack_projectile", "beam", "chain", "contact_mark",
		"echo_slash", "power_spark", "guard_shield", "iai_trail", "iai_glint", "dodge_burst", "chest_burst", "mass_kill", "poison",
		"warning_ring", "loot_awaken", "loot_seal", "forge_awaken", "wizard_bolt", "equip_magic", "projectile_core", "enemy_shot"]
	for element in ["fire", "ice", "lightning", "dark", "light"]:
		required.append("hit_" + element)
	for style in ["aura", "burst", "chains", "charge", "execution", "holy_burst", "impact", "rain", "sanctuary", "shield", "summon", "time"]:
		required.append("active_" + style)
	for kind in ["dark_rift", "fire_burst", "ice_nova", "light_burst", "thunder_strike", "wind_blade"]:
		required.append("concept_" + kind)
	for profile in ["thunderlord_descent", "inferno_pillar", "glacial_spear_rain", "radiant_blade_array", "void_severance"]:
		required.append("signature_" + profile)
	for rarity in ["uncommon", "rare", "epic", "legendary", "mythic"]:
		required.append("loot_beam_" + rarity)
	for key in FloatingWeaponsKeys.all():
		required.append(key)
	for key in required:
		check(PixelSpriteVFX.has_effect(key), "game requests a key with no pixelfx sheet: " + key)
	for upgrade_id in ["arcana_thunderlord_descent", "arcana_inferno_pillar", "arcana_glacial_spear_rain", "arcana_radiant_blade_array", "arcana_void_severance"]:
		var upgrade: UpgradeData = (get_root().get_node("DataLoader").get("upgrades") as Dictionary).get(upgrade_id)
		check(upgrade != null and PixelSpriteVFX.has_effect(String(upgrade.effect_params.get("vfx_key", ""))), "arcana preview key missing: " + upgrade_id)
	for old in ["res://assets/vfx/pixel", "res://assets/vfx/attack", "res://assets/vfx/dodge", "res://assets/vfx/equipment_comfy", "res://assets/vfx/imported", "res://effects/particles", "res://tools/vfx_unified"]:
		check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(old)), "old effect folder still present: " + old)
	check(FileAccess.file_exists(PixelSpriteVFX.ASSET_DIRECTORY + "LICENSE_pixelfx.txt"), "pixelfx MIT license not shipped next to the sheets")
	# 再生器
	var root_node := Node2D.new()
	get_root().add_child(root_node)
	await process_frame
	var hit := PixelSpriteVFX.spawn(root_node, Vector2(100, 100), "hit_fire")
	check(hit != null and hit.offset == -PixelSpriteVFX.pivot_for("hit_fire") and hit.scale == Vector2.ONE, "fixed effect is not placed on its pivot at its integer scale")
	var nova := PixelSpriteVFX.spawn(root_node, Vector2.ZERO, "concept_ice_nova", Vector2.ONE * 520.0)
	check(nova != null and nova.scale.x == roundf(nova.scale.x) and nova.scale.x >= 2.0, "fit:size does not pick an integer scale near the requested size (%s)" % (nova.scale if nova else Vector2.ZERO))
	var bolt := PixelSpriteVFX.spawn(root_node, Vector2.ZERO, "chain", Vector2(300, 0), 0.0, PI)
	check(bolt != null and is_equal_approx(absf(bolt.scale.x) * PixelSpriteVFX.frame_size_for("chain").x, 300.0) and bolt.scale.x < 0.0 and is_zero_approx(bolt.rotation), "stretched bolt does not span its segment / mirror when pointing left")
	var slash := PixelSpriteVFX.spawn(root_node, Vector2.ZERO, "echo_slash", Vector2.ZERO, 0.0, deg_to_rad(150.0))
	check(slash != null and slash.scale.x < 0.0 and absf(slash.rotation) < PI * 0.5, "left-facing slash is drawn upside down instead of mirrored")
	var length := hit.get_length() if hit else 1.0
	for i in int(length * 60.0) + 12:
		await process_frame
	check(not is_instance_valid(hit), "one-shot effect never ends")
	var persistent := PixelSpriteVFX.make_persistent("loot_beam_rare", Vector2.ZERO, true)
	root_node.add_child(persistent)
	await process_frame
	check(not persistent.is_in_group("transient_vfx"), "persistent effect joins the transient cleanup group")
	root_node.queue_free()
	await process_frame
	print("PIXELFX_VFX keys=%d required=%d sheets=%.1fMB failures=%d" % [effects.size(), required.size(), total_bytes / 1048576.0, failures.size()])
	for failure in failures:
		print("  - " + failure)
	quit(0 if failures.is_empty() else 1)

class FloatingWeaponsKeys:
	static func all() -> Array:
		var script := load("res://entities/player/floating_weapons.gd") as GDScript
		var keys: Array = (script.get_script_constant_map().get("EFFECT_KEYS", {}) as Dictionary).values()
		keys.append("equip_slash")
		return keys
