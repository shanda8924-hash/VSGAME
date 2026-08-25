extends Node

var failures: Array[String] = []

func _ready() -> void:
	# Pure logic test: suppress rapid pickup SE so Dummy audio does not retain
	# playback objects while dozens of rewards are applied in one frame.
	AudioManager.stop_all()
	AudioManager.sfx_table.clear()
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	_check_zero_elements()
	_check_one_element()
	_check_two_element_lock()
	_check_level_three_and_fusion()
	for failure in failures:
		push_error(failure)
	print("ELEMENT_REWARD_POOL_CHECK failures=%d" % failures.size())
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_zero_elements() -> void:
	var choices := ElementRewardSystem.build_choices()
	_check(choices.size() == 4, "zero elements keeps four choices for Boss/Test Lab compatibility")
	var elements := choices.filter(func(choice): return choice["kind"] == "element")
	var training := choices.filter(func(choice): return choice["kind"] == "general_mastery")
	_check(elements.size() == 3 and training.size() == 1, "zero elements gives three core elements plus training")
	var ids := {}
	for choice in elements:
		ids[choice["element_id"]] = true
	_check(ids.size() == 3, "initial element candidates are distinct")

func _check_one_element() -> void:
	GameManager.add_fragment("fire")
	var choices := ElementRewardSystem.build_choices()
	var element_choices := choices.filter(func(choice): return choice["kind"] == "element")
	var owned := element_choices.filter(func(choice): return choice["element_id"] == "element_fire")
	var unowned := element_choices.filter(func(choice): return choice["element_id"] != "element_fire")
	_check(choices.size() == 4, "one element keeps four choices for Boss/Test Lab compatibility")
	_check(owned.size() == 1 and int(owned[0]["rank"]) == 2, "one element offers owned level up")
	_check(unowned.size() == 2, "one element offers two unowned candidates")
	_check(unowned.any(func(choice): return choice["element_id"] in ["element_fire", "element_ice", "element_lightning"]), "one element keeps a core cross-skill complement available")
	_check(choices.filter(func(choice): return choice["kind"] == "general_mastery").size() == 1, "one element retains training for the four-choice Boss pool")

func _check_two_element_lock() -> void:
	GameManager.add_fragment("lightning")
	var before := GameManager.get_active_element_ids()
	GameManager.add_fragment("ice")
	_check(GameManager.get_active_element_ids() == before, "third element cannot replace locked build")
	_check(GameManager.get_element_stack("element_ice") == 0, "rejected third element gets no stack")
	var choices := ElementRewardSystem.build_choices()
	var bad := choices.filter(func(choice): return choice.get("kind") == "element" and choice.get("element_id") not in before)
	_check(choices.size() == 4, "locked build still produces four choices")
	_check(bad.is_empty(), "locked build offers no unowned element")

func _check_level_three_and_fusion() -> void:
	GameManager.add_fragment("fire")
	GameManager.add_fragment("fire")
	var choices := ElementRewardSystem.build_choices()
	var fire_level_cards := choices.filter(func(choice): return choice.get("kind") == "element" and choice.get("element_id") == "element_fire")
	_check(fire_level_cards.is_empty(), "Lv3 element has no normal level card")
	GameManager.add_fragment("lightning")
	GameManager.add_fragment("lightning")
	_check(GameManager.active_fusion_id == "plasma", "both Lv3 immediately form the pair fusion")
	var fusion_choices := ElementRewardSystem.build_choices()
	_check(fusion_choices.size() == 4, "fusion produces four mastery choices")
	_check(fusion_choices.all(func(choice): return choice["kind"] == "fusion_mastery"), "fusion pool contains no normal element card")
	_check(fusion_choices.map(func(choice): return choice["mastery_id"]) == ["power", "echo", "haste", "signature"], "fusion pool has four fixed mastery categories")
	_check(ElementRewardSystem.apply_choice(fusion_choices[3]), "fusion signature choice applies")
	_check(GameManager.get_fusion_mastery_rank("signature") == 1, "fusion signature rank increments")
	for mastery_id in ["power", "echo", "haste", "signature"]:
		while GameManager.get_fusion_mastery_rank(mastery_id) < GameManager.MASTERY_RANK_CAP:
			GameManager.add_fusion_mastery(mastery_id)
	var completed_choices := ElementRewardSystem.build_choices()
	_check(completed_choices.size() == 4, "completed fusion still produces four choices")
	_check(completed_choices[0]["kind"] == "fusion_complete", "completed fusion exposes an escapable completion card")
	_check(ElementRewardSystem.apply_choice(completed_choices[0]), "completed fusion reward can close normally")
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	_check(GameManager.active_fusion_id == "" and GameManager.get_fusion_mastery_rank("signature") == 0, "run reset clears fusion and mastery")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
