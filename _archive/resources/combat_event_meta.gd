extends RefCounted
class_name CombatEventMeta

## Damage APIを置き換えず、確定Hitへ安全なTrigger文脈だけを添える軽量Metadata。
static var _next_event_id: int = 1
static var _next_chain_id: int = 1


static func create_direct(source_kind: String, is_critical: bool = false, element_tags: Array = [], combo_eligible: bool = true) -> Dictionary:
	var result := _base(source_kind, _take_chain_id(), 0, element_tags, true, false, combo_eligible)
	result["is_critical"] = is_critical
	return result


static func create_secondary(source_kind: String, element_tags: Array = [], combo_eligible: bool = true) -> Dictionary:
	return _base(source_kind, _take_chain_id(), 0, element_tags, false, false, combo_eligible)


static func create_triggered(parent: Dictionary, source_kind: String, element_tags: Array, chain_index: int, combo_eligible: bool = true) -> Dictionary:
	var normalized := normalize(parent)
	var lineage: Array = normalized.get("triggered_chain_indices", []).duplicate()
	if chain_index not in lineage:
		lineage.append(chain_index)
	var result := _base(
		source_kind,
		int(normalized.get("chain_id", _take_chain_id())),
		int(normalized.get("generation_depth", 0)) + 1,
		element_tags,
		false,
		true,
		combo_eligible
	)
	result["triggered_chain_indices"] = lineage
	return result


static func fork_event(parent: Dictionary, source_kind: String = "") -> Dictionary:
	var normalized := normalize(parent)
	var result := normalized.duplicate(true)
	result["event_id"] = _take_event_id()
	result["source_kind"] = source_kind if source_kind != "" else String(normalized.get("source_kind", "unknown"))
	result.erase("killed")
	return result


static func normalize(metadata: Dictionary, default_source: String = "secondary") -> Dictionary:
	if metadata.is_empty():
		return create_secondary(default_source)
	var result := metadata.duplicate(true)
	if not result.has("event_id"):
		result["event_id"] = _take_event_id()
	if not result.has("source_kind"):
		result["source_kind"] = default_source
	if not result.has("chain_id"):
		result["chain_id"] = _take_chain_id()
	result["generation_depth"] = int(result.get("generation_depth", 0))
	result["element_tags"] = result.get("element_tags", [])
	result["is_direct"] = bool(result.get("is_direct", false))
	result["is_triggered"] = bool(result.get("is_triggered", false))
	result["combo_eligible"] = bool(result.get("combo_eligible", true))
	result["is_critical"] = bool(result.get("is_critical", false))
	result["triggered_chain_indices"] = result.get("triggered_chain_indices", [])
	return result


static func _base(source_kind: String, chain_id: int, depth: int, element_tags: Array, is_direct: bool, is_triggered: bool, combo_eligible: bool) -> Dictionary:
	return {
		"event_id": _take_event_id(),
		"source_kind": source_kind,
		"chain_id": chain_id,
		"generation_depth": depth,
		"element_tags": element_tags.duplicate(),
		"is_direct": is_direct,
		"is_triggered": is_triggered,
		"combo_eligible": combo_eligible,
		"is_critical": false,
		"triggered_chain_indices": [],
	}


static func _take_event_id() -> int:
	var value := _next_event_id
	_next_event_id += 1
	return value


static func _take_chain_id() -> int:
	var value := _next_chain_id
	_next_chain_id += 1
	return value
