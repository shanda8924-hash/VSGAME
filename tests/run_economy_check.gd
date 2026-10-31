extends Node
## `godot --headless --path . res://tests/run_economy_check.tscn`で実行する。

var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var meta_before := int(SaveManager.data.get("meta_currency", 0))
	var economy := RunEconomySystem.new()
	add_child(economy)
	await get_tree().process_frame

	GameManager.run_state = GameManager.RunState.PLAYING
	GameManager.map_mode_active = true
	GameManager.reset_run_gold()
	EventBus.enemy_drop_requested.emit(Vector2.ZERO, false, false)
	_expect(GameManager.run_gold == 1, "通常敵撃破が1Gになりません")
	EventBus.enemy_drop_requested.emit(Vector2.ZERO, true, false)
	_expect(GameManager.run_gold == 12, "精鋭撃破が通常1G+ボーナス10Gになりません")
	EventBus.enemy_drop_requested.emit(Vector2.ZERO, false, true)
	_expect(GameManager.run_gold == 13, "ボス個体撃破の基礎1Gが加算されません")
	EventBus.elite_room_cleared.emit(1)
	_expect(GameManager.run_gold == 63, "精鋭部屋クリア50Gが加算されません")
	EventBus.map_surge_ended.emit(1, 1, "recovery", Vector2.ZERO)
	_expect(GameManager.run_gold == 83, "サージ完了20Gが加算されません")
	EventBus.map_completed.emit(1, 10.0, 420)
	_expect(GameManager.run_gold == 183, "MAP1ボス100Gが加算されません")

	_expect(GameManager.try_spend_run_gold(100, "test_purchase"), "所持金内の購入に失敗します")
	_expect(GameManager.run_gold == 83, "購入後の残額が不正です")
	_expect(not GameManager.try_spend_run_gold(84, "test_over_budget"), "所持金を超える購入が成功します")
	_expect(GameManager.run_gold == 83, "購入失敗時に所持金が変化します")
	_expect(not GameManager.try_spend_run_gold(0, "test_zero"), "0G消費を購入として受理します")

	GameManager.end_run()
	_expect(GameManager.run_gold == 0, "Run終了時にゴールドがリセットされません")
	_expect(int(SaveManager.data.get("meta_currency", 0)) == meta_before, "ラン内通貨がメタ通貨を変更しました")

	if _failures.is_empty():
		print("RUN_ECONOMY_CHECK PASS normal=1 elite_total=11 boss_base=1 room=50 surge=20 boss1=100 spend_guard=ok reset=ok")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("RUN_ECONOMY_CHECK: %s" % failure)
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
