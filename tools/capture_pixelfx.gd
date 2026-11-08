extends Node
## pixelfxへ置き換えたエフェクトの実画面。通常起動と同じ経路（game.tscn → start_run(true)）で、
## 自動戦闘・連鎖・残影・結界・秘技・床ドロップ・警告円・敵弾を順に出して撮る。
## xvfb-run … --rendering-driver opengl3 res://tools/capture_pixelfx.tscn → artifacts/pixelfx/*.png
const GAME_SCENE := preload("res://scenes/game.tscn")

func _ready() -> void:
	var runner := Runner.new()
	runner.name = "PixelfxCaptureRunner"
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(runner)

class Runner extends Node:
	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute("res://artifacts/pixelfx")
		_run.call_deferred()

	func _frames(count: int) -> void:
		for i in count:
			await get_tree().process_frame
			# レベルアップの選択は自動で1枚目を取って閉じる（撮りたいのは戦場）。
			var game := get_tree().current_scene
			var ui := game.get_node_or_null("LevelUpSelect") as LevelUpSelect if game else null
			if ui and ui.visible and ui.grid_container.get_child_count() > 0:
				(ui.grid_container.get_child(0) as Button).pressed.emit()
				ui.confirm_selection()

	func _capture(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/pixelfx/%s.png" % name)
		print("PIXELFX_CAPTURE ", name)

	func _run() -> void:
		SaveManager.begin_ephemeral_session()
		SaveManager.data["survival_depth"] = 1
		GameManager.selected_survival_map = 1
		GameManager.selected_character_id = "swordsman"
		seed(2026)
		get_tree().change_scene_to_packed(GAME_SCENE)
		await _frames(45)
		var game := get_tree().current_scene
		var player := game.get_node("Player") as Player
		player.health_component.invincible = true
		var controller := game.get_node("MapRunController") as MapRunController
		controller.set_process(false)
		var wave := game.get_node("WaveSpawner") as WaveSpawner
		var upgrades := player.upgrades_component
		for id in ["survival_chain", "survival_chain", "survival_echo", "survival_power", "survival_guard", "survival_haste"]:
			upgrades.apply_upgrade(DataLoader.upgrades[id])
		var drops := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
		var sword := drops.debug_generate_equipment("wanderer_iron_sword", "rare")
		player.equipment_component.add_item(sword)
		player.equipment_component.equip(sword)
		for i in 26:
			wave._spawn_enemy_at(DataLoader.enemies.slime if i % 3 else DataLoader.enemies.bat, player.global_position + Vector2.from_angle(i * 0.9) * (90 + (i % 5) * 28), player)
		await _frames(150)
		await _capture("combat_chain_echo")
		# 秘技2種
		upgrades.apply_upgrade(DataLoader.upgrades.arcana_thunderlord_descent)
		upgrades.apply_upgrade(DataLoader.upgrades.arcana_inferno_pillar)
		await _frames(140)
		await _capture("arcana")
		# 床ドロップ（各レア度）
		for e in get_tree().get_nodes_in_group("enemies"): e.queue_free()
		wave.set_process(false)
		await _frames(4)
		var rarities := ["uncommon", "rare", "epic", "legendary", "mythic"]
		for index in rarities.size():
			var item := drops.debug_generate_equipment("wanderer_iron_sword", rarities[index])
			drops.debug_drop_equipment(item, player.global_position + Vector2(-220 + index * 110, 80))
		await _frames(70)
		await _capture("loot")
		# 警告円・敵弾
		var warning := WarningCircle.new()
		warning.radius = 120.0
		warning.duration = 1.2
		GameManager.get_runtime_world(player).add_child(warning)
		warning.global_position = player.global_position + Vector2(240, -60)
		var archer := wave._spawn_enemy_at(DataLoader.enemies.skeleton_archer, player.global_position + Vector2(-200, -40), player)
		await _frames(110)
		await _capture("telegraph_enemy_shot")
		AudioManager.stop_all(false)
		get_tree().quit()
