extends Node
## ステータス表示と融合（転職）の検査。実際の画面で、部屋のキャラクターをクリックし、融合ボタンを押す。
## ルール：同じ職業が必要数いれば融合でき、転職先1体に置き換わる。系統は全職でつながり、上位ほどHPが高い。満員なら召喚できない。
## Godot --headless --path . res://tests/army_fusion_check.tscn
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func click(target: Vector2) -> void:
	var point := get_viewport().get_stretch_transform() * target
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame

func ids(army: Army) -> Array:
	var result: Array = []
	for unit in army.units:
		result.append(String(unit.id))
	return result

func _run() -> void:
	# --- 系統のデータ
	var roots := 0
	for character: CharacterData in DataLoader.get_all_characters():
		if character.tier == 1:
			roots += 1
		if character.promotes_to != "":
			var target: CharacterData = DataLoader.characters.get(character.promotes_to)
			check(target != null and target.tier == character.tier + 1, "%s promotes to a missing or wrong-tier class" % character.id)
			check(target != null and target.max_hp > character.max_hp, "%s → %s is not stronger (HP)" % [character.id, character.promotes_to])
		check(character.fusion_count >= 2, "%s fusion count below 2" % character.id)
	check(roots == 5, "expected 5 base classes, got %d" % roots)
	check(DataLoader.characters.wizard.tier == 1 and DataLoader.characters.wizard.promotes_to == "necromancer" and DataLoader.characters.necromancer.tier == 2, "wizard → necromancer line is wrong")
	check(DataLoader.characters.archer.promotes_to == "", "archer should have no promotion for now")
	# --- ルール（Army）
	var army := Army.new(3)
	var first := army.add("soldier")
	check(first > 0 and not army.can_fuse(first) and army.fuse(first) == -1, "a lone soldier can fuse")
	var archer := army.add("archer")
	var second := army.add("soldier")
	check(army.is_full() and army.add("soldier") == -1, "army accepts units beyond its capacity")
	check(army.can_fuse(first) and army.can_fuse(second) and not army.can_fuse(archer), "fusion availability is wrong")
	var promoted := army.fuse(second)
	check(promoted > 0 and ids(army) == ["archer", "swordsman"], "two soldiers did not become one swordsman: %s" % str(ids(army)))
	check(army.index_of(first) == -1 and army.index_of(second) == -1 and army.character_of(promoted).id == "swordsman", "fused units still exist")
	army.add("swordsman")
	var knight := army.fuse(promoted)
	check(knight > 0 and ids(army) == ["archer", "knight"], "two swordsmen did not become a knight: %s" % str(ids(army)))
	army.add("knight")
	check(not army.can_fuse(knight) and army.promotion_of(knight) == null, "top-tier class can still fuse")
	# --- 画面
	var screen := (load("res://scenes/puzzle_prototype.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	check(get_viewport().get_visible_rect().encloses(screen.status_panel.get_global_rect()), "status panel is off screen")
	check(not screen.fuse_button.visible and screen.status_promotion.text.contains("タップ"), "empty status panel does not prompt to tap")
	var soldier_uid: int = screen.add_unit("soldier")
	screen.add_unit("archer")
	await get_tree().process_frame
	await click(screen.units[0].global_position)
	var soldier: CharacterData = DataLoader.characters.soldier
	check(screen.selected_uid == soldier_uid, "clicking a character in the room does not select it")
	check(screen.status_name.text == soldier.display_name and screen.status_tier.text == "★☆☆", "status panel shows the wrong name or tier: %s %s" % [screen.status_name.text, screen.status_tier.text])
	check(screen.status_stats.text.contains("HP　%d" % roundi(soldier.max_hp)) and screen.status_stats.text.contains("移動速度　%d" % roundi(soldier.move_speed)), "status panel stats are wrong: " + screen.status_stats.text)
	check(screen.status_icon.texture != null and screen.status_icon.texture.resource_path == soldier.icon_path, "status panel has no class icon")
	check(screen.status_promotion.text.contains("剣士") and screen.status_promotion.text.contains("1 / 2") and screen.fuse_button.visible and screen.fuse_button.disabled, "one soldier should show the path to swordsman with a disabled button: " + screen.status_promotion.text)
	await click(screen.units[1].global_position)
	check(screen.status_name.text == "弓兵" and screen.status_promotion.text.contains("最上位") and not screen.fuse_button.visible, "clicking another character does not switch the panel")
	screen.add_unit("soldier")
	await get_tree().process_frame
	await click(screen.units[0].global_position)
	check(screen.status_promotion.text.contains("2 / 2") and not screen.fuse_button.disabled, "two soldiers do not enable fusion")
	await click(screen.fuse_button.get_global_rect().get_center())
	await get_tree().process_frame
	check(ids(screen.army) == ["swordsman", "archer"] and screen.fusions == 1, "fusion button did not turn two soldiers into a swordsman: %s" % str(ids(screen.army)))
	check(screen.units.size() == 2 and screen.units_root.get_child_count() == 2 and screen.units[0].character_data.id == "swordsman", "room does not show the swordsman after fusion")
	check(screen.units[0].animated_sprite.animation == &"idle" and screen.units[0].animated_sprite.is_playing(), "promoted character is not idling")
	for i in 20:
		await get_tree().physics_frame
	for index in screen.units.size():
		check(screen.units[index].position.is_equal_approx(screen.slot_position(index)), "character %d drifted from its slot after fusion (%s)" % [index, screen.units[index].position])
	check(screen.status_name.text == "剣士" and screen.status_tier.text == "★★☆" and screen.status_stats.text.contains("HP　%d" % roundi(DataLoader.characters.swordsman.max_hp)), "panel does not follow the promoted character: " + screen.status_name.text)
	check(screen.message_label.text.contains("転職"), "fusion is not announced: " + screen.message_label.text)
	screen.add_unit("swordsman")
	await get_tree().process_frame
	check(screen.fuse_selected() and ids(screen.army) == ["knight", "archer"], "swordsmen did not fuse into a knight")
	check(screen.status_tier.text == "★★★" and not screen.fuse_button.visible and screen.status_promotion.text.contains("最上位"), "top tier is not shown as final")
	# 何も無い所をクリックすると選択が外れる
	await click(screen.room_panel.get_global_rect().end - Vector2(12, 12))
	check(screen.selected_uid == -1 and not screen.fuse_button.visible, "clicking empty floor does not clear the selection")
	# 満員
	for index in 40:
		screen.add_unit("priest")
	check(screen.army.units.size() == screen.army.capacity and screen.units.size() == screen.army.capacity, "room exceeds the army capacity")
	for unit in screen.units:
		check(screen.room_panel.get_global_rect().has_point(unit.global_position), "a character stands outside the room at full capacity")
	print("ARMY_FUSION_CHECK failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
