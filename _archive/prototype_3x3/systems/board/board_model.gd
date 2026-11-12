extends RefCounted
class_name BoardModel
## 3×3盤面のルールだけを持つ（描画なし）。マスは左上から右へ 0..8。
## 回す＝ホールドしていないマスを引き直す。ラインは縦3・横3・斜め2の8本で、3マスが同じ記号なら揃い。
## 記号と数値は data/board/board.json。記号の意味（効果）はまだ無い。

const CONFIG_PATH := "res://data/board/board.json"
const SIZE := 3
const CELL_COUNT := 9
## 横3本、縦3本、斜め2本。
const LINES: Array = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

var config: Dictionary = {}
var symbols: Array = []
var cells: Array[int] = []
var held: Array[bool] = []
var max_holds := 4
var holds_persist := true
var rng := RandomNumberGenerator.new()

func _init(seed_value: int = -1) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	symbols = config.get("symbols", [])
	max_holds = int(config.get("max_holds", 4))
	holds_persist = bool(config.get("holds_persist", true))
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	cells.resize(CELL_COUNT)
	held.resize(CELL_COUNT)
	held.fill(false)
	for index in CELL_COUNT:
		cells[index] = roll_symbol()

## 重みに従って記号を1つ引く（記号の番号）。
func roll_symbol() -> int:
	var total := 0.0
	for symbol in symbols:
		total += maxf(float(symbol.get("weight", 1.0)), 0.0)
	if total <= 0.0:
		return 0
	var roll := rng.randf() * total
	for index in symbols.size():
		roll -= maxf(float(symbols[index].get("weight", 1.0)), 0.0)
		if roll <= 0.0:
			return index
	return symbols.size() - 1

func held_count() -> int:
	return held.count(true)

## ホールドの切り替え。上限を超える追加は拒否して false を返す。
func toggle_hold(index: int) -> bool:
	if index < 0 or index >= CELL_COUNT:
		return false
	if held[index]:
		held[index] = false
		return true
	if held_count() >= max_holds:
		return false
	held[index] = true
	return true

## ホールドしていないマスを引き直す。引き直したマスの番号を返す。
func spin() -> Array[int]:
	var changed: Array[int] = []
	for index in CELL_COUNT:
		if not held[index]:
			cells[index] = roll_symbol()
			changed.append(index)
	if not holds_persist:
		held.fill(false)
	return changed

## 揃っているライン。{ "line": 0..7, "cells": [a,b,c], "symbol": 記号の番号 } の配列。
func matched_lines() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line_index in LINES.size():
		var line: Array = LINES[line_index]
		var first: int = cells[line[0]]
		if cells[line[1]] == first and cells[line[2]] == first:
			result.append({"line": line_index, "cells": line, "symbol": first})
	return result

func symbol_data(symbol_index: int) -> Dictionary:
	if symbol_index < 0 or symbol_index >= symbols.size():
		return {}
	return symbols[symbol_index]
