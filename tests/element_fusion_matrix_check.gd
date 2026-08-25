extends Node

const MATRIX := {
	"fire+ice": "frostfire", "fire+lightning": "plasma", "fire+light": "solar", "fire+dark": "inferno",
	"ice+lightning": "superconductor", "ice+light": "aurora", "ice+dark": "void_frost",
	"lightning+light": "judgment", "lightning+dark": "voidstorm", "light+dark": "eclipse",
}
var failures: Array[String] = []
var formed_count := 0

func _ready() -> void:
	# Matrix acquisition is intentionally much faster than real gameplay.
	# Keep Dummy audio out of this pure state test and verify audio in game tests.
	AudioManager.stop_all()
	AudioManager.sfx_table.clear()
	EventBus.element_fusion_formed.connect(func(_id, _name, _sources): formed_count += 1)
	for pair_key in MATRIX.keys():
		var parts := String(pair_key).split("+")
		_check_pair(parts[0], parts[1], MATRIX[pair_key])
		_check_pair(parts[1], parts[0], MATRIX[pair_key])
	for failure in failures:
		push_error(failure)
	print("ELEMENT_FUSION_MATRIX_CHECK failures=%d pairs=%d" % [failures.size(), MATRIX.size()])
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_pair(first: String, second: String, expected: String) -> void:
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	formed_count = 0
	for _rank in 3:
		GameManager.add_fragment(first)
	for _rank in 3:
		GameManager.add_fragment(second)
	_check(GameManager.active_fusion_id == expected, "%s + %s resolves to %s" % [first, second, expected])
	_check(formed_count == 1, "%s forms exactly once" % expected)
	GameManager.add_fragment(first)
	GameManager.add_fragment(second)
	_check(formed_count == 1, "%s cannot form twice at capped ranks" % expected)
	_check(GameManager.get_active_element_ids().size() == 2, "%s keeps exactly two sources" % expected)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
