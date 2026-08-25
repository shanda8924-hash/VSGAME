extends RefCounted
class_name ElementRewardSystem
## Boss属性報酬の4択Poolを、現在Buildだけから構築・適用する純粋な選択System。

const ELEMENT_LABELS := {
	"element_fire": ["火", "#ff7043"],
	"element_ice": ["氷", "#72d7ff"],
	"element_lightning": ["雷", "#ffe45c"],
	"element_light": ["光", "#fff1a8"],
	"element_dark": ["闇", "#b56cff"],
}
const GENERAL_MASTERY := {
	"power": ["属性威力", "属性ダメージ +15%"],
	"echo": ["属性反響", "属性二重発動率 +15%（最大45%）"],
	"haste": ["属性加速", "属性効果の発動間隔 -10%"],
	"reach": ["属性拡張", "属性の範囲 +12%"],
}
const ELEMENT_MASTERY := {
	"power": ["威力熟練", "この属性のダメージ +25%"],
	"echo": ["反響熟練", "この属性の二重発動率 +15%"],
	"reach": ["範囲熟練", "この属性の範囲 +20%"],
	"signature": ["固有熟練", "固有効果を1段階強化"],
}
const FUSION_MASTERY := {
	"power": ["融合威力", "融合属性ダメージ +25%"],
	"echo": ["融合反響", "融合属性の二重発動率 +15%"],
	"haste": ["融合加速", "融合属性の発動間隔 -12%"],
	"signature": ["固有熟練", "融合属性の固有効果を進化"],
}
const FUSION_SIGNATURE := {
	"frostfire": [["熱崩壊 I", "熱崩壊の範囲を拡大"], ["熱崩壊 II", "熱崩壊のダメージと衝撃波を強化"], ["熱崩壊 III", "最大範囲の蒸気爆発へ進化"]],
	"plasma": [["過充電 I", "プラズマ核のダメージ +30%"], ["過充電 II", "核爆発の範囲 +25%"], ["過充電 III", "爆発後に核を別の敵へ伝播"]],
	"solar": [["光冠 I", "太陽閃光の範囲を拡大"], ["光冠 II", "閃光ダメージを強化"], ["光冠 III", "最大光冠爆発へ進化"]],
	"inferno": [["魂喰らい I", "魂の取得量 +1"], ["魂喰らい II", "最大蓄積までの必要数を短縮"], ["魂喰らい III", "最大蓄積の黒炎を強化"]],
	"superconductor": [["共振破砕 I", "共振破砕の範囲を拡大"], ["共振破砕 II", "連鎖破砕の対象を追加"], ["共振破砕 III", "大規模破砕へ進化"]],
	"aurora": [["屈折 I", "屈折対象 +1"], ["屈折 II", "光晶ダメージを強化"], ["屈折 III", "多重光晶へ進化"]],
	"void_frost": [["重力 I", "吸引範囲を拡大"], ["重力 II", "崩壊ダメージを強化"], ["重力 III", "最大重力崩壊へ進化"]],
	"judgment": [["審判 I", "審判対象 +1"], ["審判 II", "高HP対象へのダメージを強化"], ["審判 III", "多重審判へ進化"]],
	"voidstorm": [["空間跳躍 I", "転移回数 +1"], ["空間跳躍 II", "転移ダメージを強化"], ["空間跳躍 III", "転移網へ進化"]],
	"eclipse": [["日蝕 I", "発動に必要な蓄積量を短縮"], ["日蝕 II", "日蝕の持続時間を延長"], ["日蝕 III", "日蝕専用攻撃を最大強化"]],
}

static func get_localized_fusion_name(fusion_id: String = GameManager.active_fusion_id) -> String:
	var display := GameManager.get_fusion_display_name(fusion_id)
	return display.get_slice("/", 1).strip_edges() if display.contains("/") else display

static func build_choices() -> Array[Dictionary]:
	if GameManager.active_fusion_id != "":
		return _fusion_choices()
	var owned := GameManager.get_active_element_ids()
	if owned.is_empty():
		# 完成済みスキルの初期セットが揃う3属性を最初の3択にする。
		# 光・闇は2枠目候補として以後も取得でき、既存Fusion経路は維持する。
		var initial: Array[String] = ["element_fire", "element_ice", "element_lightning"]
		initial.shuffle()
		var choices: Array[Dictionary] = []
		for index in 3:
			choices.append(_element_choice(initial[index]))
		choices.append(_pick_general_choice())
		return choices
	if owned.size() == 1:
		var result: Array[Dictionary] = []
		result.append(_owned_progress_choice(owned[0]))
		var unowned := GameManager.ELEMENT_IDS.filter(func(id): return id not in owned)
		unowned.shuffle()
		var core_complements := unowned.filter(func(id): return id in ["element_fire", "element_ice", "element_lightning"])
		core_complements.shuffle()
		var first_new := String(core_complements[0]) if not core_complements.is_empty() else String(unowned[0])
		result.append(_element_choice(first_new))
		for candidate in unowned:
			if String(candidate) != first_new:
				result.append(_element_choice(String(candidate)))
				break
		result.append(_pick_general_choice())
		return result
	return _locked_build_choices(owned)

static func apply_choice(choice: Dictionary) -> bool:
	var applied := false
	match String(choice.get("kind", "")):
		"element":
			var element_id := String(choice.get("element_id", ""))
			var fragment_id := element_id.trim_prefix("element_")
			var before := GameManager.get_element_stack(element_id)
			GameManager.add_fragment(fragment_id)
			applied = GameManager.get_element_stack(element_id) > before
		"general_mastery":
			applied = GameManager.add_general_mastery(String(choice.get("mastery_id", "")))
		"element_mastery":
			applied = GameManager.add_element_mastery(String(choice.get("element_id", "")), String(choice.get("mastery_id", "")))
		"fusion_mastery":
			applied = GameManager.add_fusion_mastery(String(choice.get("mastery_id", "")))
		"fusion_complete":
			# Keep the modal escapable after every capped Fusion mastery has been earned.
			applied = GameManager.active_fusion_id != ""
	if applied:
		EventBus.element_reward_selected.emit(choice.duplicate(true))
	return applied

static func build_summary() -> String:
	if GameManager.active_fusion_id != "":
		return "融合属性\n%s\n固有熟練 %d" % [get_localized_fusion_name(), GameManager.get_fusion_mastery_rank("signature")]
	var lines: Array[String] = ["属性ビルド"]
	for element_id in GameManager.get_active_element_ids():
		var label := String(ELEMENT_LABELS.get(element_id, [element_id, ""])[0])
		var level := GameManager.get_element_stack(element_id)
		lines.append("%s Lv%d%s" % [label, level, " 最大" if level >= 3 else ""])
	lines.append("属性枠  %d / 2%s" % [GameManager.get_active_element_ids().size(), "  固定済み" if GameManager.get_active_element_ids().size() >= 2 else ""])
	return "\n".join(lines)

static func _locked_build_choices(owned: Array[String]) -> Array[Dictionary]:
	var priority: Array[Dictionary] = []
	var secondary: Array[Dictionary] = []
	for element_id in owned:
		if GameManager.get_element_stack(element_id) < 3:
			priority.append(_element_choice(element_id))
		else:
			secondary.append_array(_all_element_mastery_choices(element_id))
	for mastery_id in GENERAL_MASTERY.keys():
		if GameManager.get_general_mastery_rank(mastery_id) < GameManager.MASTERY_RANK_CAP:
			secondary.append(_general_choice(mastery_id))
	secondary.shuffle()
	for choice in secondary:
		if priority.size() >= 4:
			break
		priority.append(choice)
	# 全GeneralがCap済みでも2×2枠は維持し、MAXカードを明示する。
	for mastery_id in GENERAL_MASTERY.keys():
		if priority.size() >= 4:
			break
		var fallback := _general_choice(mastery_id)
		if not priority.any(func(choice): return choice.get("id") == fallback.get("id")):
			priority.append(fallback)
	return priority

static func _owned_progress_choice(element_id: String) -> Dictionary:
	if GameManager.get_element_stack(element_id) < 3:
		return _element_choice(element_id)
	var options := _all_element_mastery_choices(element_id)
	options.shuffle()
	return options[0] if not options.is_empty() else _pick_general_choice()

static func _element_choice(element_id: String) -> Dictionary:
	var level := GameManager.get_element_stack(element_id)
	var label_data: Array = ELEMENT_LABELS.get(element_id, [element_id, "#cccccc"])
	return {
		"id": "element:%s" % element_id,
		"kind": "element",
		"element_id": element_id,
		"title": "%s  Lv%d" % [label_data[0], level + 1],
		"description": "新しい属性を取得" if level == 0 else "属性レベルアップ",
		"color": label_data[1],
		"rank": level + 1,
		"max_rank": 3,
	}

static func _pick_general_choice() -> Dictionary:
	var available: Array[String] = []
	for mastery_id in GENERAL_MASTERY.keys():
		if GameManager.get_general_mastery_rank(mastery_id) < GameManager.MASTERY_RANK_CAP:
			available.append(mastery_id)
	if available.is_empty():
		available = GENERAL_MASTERY.keys()
	available.shuffle()
	return _general_choice(available[0])

static func _general_choice(mastery_id: String) -> Dictionary:
	var data: Array = GENERAL_MASTERY[mastery_id]
	var rank := GameManager.get_general_mastery_rank(mastery_id)
	return _mastery_choice("general_mastery", "general:%s" % mastery_id, mastery_id, data, rank, "#7ee6b5")

static func _all_element_mastery_choices(element_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mastery_id in ELEMENT_MASTERY.keys():
		var rank := GameManager.get_element_mastery_rank(element_id, mastery_id)
		if rank >= GameManager.MASTERY_RANK_CAP:
			continue
		var label := String(ELEMENT_LABELS.get(element_id, [element_id, "#cccccc"])[0])
		var choice := _mastery_choice("element_mastery", "mastery:%s:%s" % [element_id, mastery_id], mastery_id, ELEMENT_MASTERY[mastery_id], rank, String(ELEMENT_LABELS.get(element_id, ["", "#cccccc"])[1]))
		choice["element_id"] = element_id
		choice["title"] = "%s %s" % [label, choice["title"]]
		result.append(choice)
	return result

static func _fusion_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var all_maxed := true
	for mastery_id in ["power", "echo", "haste", "signature"]:
		var rank := GameManager.get_fusion_mastery_rank(mastery_id)
		all_maxed = all_maxed and rank >= GameManager.MASTERY_RANK_CAP
		var display_data: Array = FUSION_MASTERY[mastery_id]
		if mastery_id == "signature":
			var stages: Array = FUSION_SIGNATURE.get(GameManager.active_fusion_id, [])
			if not stages.is_empty():
				display_data = stages[clampi(rank, 0, stages.size() - 1)]
		var choice := _mastery_choice("fusion_mastery", "fusion:%s" % mastery_id, mastery_id, display_data, rank, "#ffcc66")
		choice["fusion_id"] = GameManager.active_fusion_id
		result.append(choice)
	if all_maxed:
		result[0] = {
			"id": "fusion:complete",
			"kind": "fusion_complete",
			"title": "融合属性 完成",
			"description": "完成した融合属性を維持します",
			"color": "#fff0a8",
			"rank": GameManager.MASTERY_RANK_CAP,
			"max_rank": GameManager.MASTERY_RANK_CAP,
			"maxed": false,
			"fusion_id": GameManager.active_fusion_id,
		}
	return result

static func _mastery_choice(kind: String, id: String, mastery_id: String, data: Array, rank: int, color: String) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"mastery_id": mastery_id,
		"title": "%s  段階 %d" % [data[0], mini(rank + 1, GameManager.MASTERY_RANK_CAP)],
		"description": data[1],
		"color": color,
		"rank": rank + 1,
		"max_rank": GameManager.MASTERY_RANK_CAP,
		"maxed": rank >= GameManager.MASTERY_RANK_CAP,
	}
