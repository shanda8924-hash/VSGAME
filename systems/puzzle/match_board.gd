extends RefCounted
class_name MatchBoard
## 3つ揃えて消すパズルのルールだけを持つ（描画なし）。
## マスは左上から右へ index = y * width + x。隣り合う2マスを入れ替え、縦か横に同じ種類が3つ以上並べば消える。
## 消えた上のマスが落ち、空いた所は上から新しいマスで埋まり、また揃えば連鎖する。
## 揃わない入れ替えはできない。動かせる手が無くなったら並べ直す。
## 盤の大きさと種類は data/puzzle/puzzle.json。

const CONFIG_PATH := "res://data/puzzle/puzzle.json"
const EMPTY := -1

var config: Dictionary = {}
var kinds: Array = []
var width := 8
var height := 8
var grid: Array[int] = []
var rng := RandomNumberGenerator.new()

func _init(seed_value: int = -1) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	kinds = config.get("kinds", [])
	width = int(config.get("width", 8))
	height = int(config.get("height", 8))
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	reshuffle()

func cell_count() -> int:
	return width * height

func index_of(x: int, y: int) -> int:
	return y * width + x

func kind_data(kind: int) -> Dictionary:
	if kind < 0 or kind >= kinds.size():
		return {}
	return kinds[kind]

func _roll() -> int:
	return rng.randi_range(0, maxi(kinds.size() - 1, 0))

## 盤を全部引き直す。最初から揃っている並びは作らず、動かせる手が必ずある状態にする。
func reshuffle() -> void:
	grid.resize(cell_count())
	for attempt in 200:
		for index in cell_count():
			var x := index % width
			var y := index / width
			var kind := _roll()
			for retry in 20:
				var row_match := x >= 2 and grid[index - 1] == kind and grid[index - 2] == kind
				var column_match := y >= 2 and grid[index - width] == kind and grid[index - width * 2] == kind
				if not row_match and not column_match:
					break
				kind = _roll()
			grid[index] = kind
		if find_matches().is_empty() and has_moves():
			return

func are_adjacent(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= cell_count() or b >= cell_count():
		return false
	return absi(a % width - b % width) + absi(a / width - b / width) == 1

## 揃っている並び。{ "kind": 種類, "cells": [index…] } の配列（横の並びと縦の並びを別々に数える）。
func find_matches() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for y in height:
		var x := 0
		while x < width:
			var kind := grid[index_of(x, y)]
			var run := 1
			while x + run < width and grid[index_of(x + run, y)] == kind:
				run += 1
			if kind != EMPTY and run >= 3:
				var cells: Array[int] = []
				for offset in run:
					cells.append(index_of(x + offset, y))
				result.append({"kind": kind, "cells": cells})
			x += run
	for x in width:
		var y := 0
		while y < height:
			var kind := grid[index_of(x, y)]
			var run := 1
			while y + run < height and grid[index_of(x, y + run)] == kind:
				run += 1
			if kind != EMPTY and run >= 3:
				var cells: Array[int] = []
				for offset in run:
					cells.append(index_of(x, y + offset))
				result.append({"kind": kind, "cells": cells})
			y += run
	return result

func _swap_raw(a: int, b: int) -> void:
	var kept := grid[a]
	grid[a] = grid[b]
	grid[b] = kept

## 入れ替えると何かが揃うか（隣同士だけ）。盤は変えない。
func can_swap(a: int, b: int) -> bool:
	if not are_adjacent(a, b) or grid[a] == grid[b]:
		return false
	_swap_raw(a, b)
	var ok := not find_matches().is_empty()
	_swap_raw(a, b)
	return ok

## 入れ替える。揃わない入れ替えは拒否して false。
func swap(a: int, b: int) -> bool:
	if not can_swap(a, b):
		return false
	_swap_raw(a, b)
	return true

## 揃っている並びを1回ぶん消して落とす。何も揃っていなければ空を返す。
## 返り値：groups（消えた並び）、cleared（消えたマス）、drop（各マスが何段落ちてきたか。新しいマスは列の空き数）。
func resolve_step() -> Dictionary:
	var groups := find_matches()
	if groups.is_empty():
		return {}
	var cleared := {}
	for group in groups:
		for cell in group.cells:
			cleared[cell] = true
	for cell in cleared.keys():
		grid[cell] = EMPTY
	var drop: Array[int] = []
	drop.resize(cell_count())
	drop.fill(0)
	for x in width:
		var write := height - 1
		for y in range(height - 1, -1, -1):
			var index := index_of(x, y)
			if grid[index] == EMPTY:
				continue
			if y != write:
				grid[index_of(x, write)] = grid[index]
				grid[index] = EMPTY
				drop[index_of(x, write)] = write - y
			write -= 1
		var empties := write + 1
		for y in range(write, -1, -1):
			grid[index_of(x, y)] = _roll()
			drop[index_of(x, y)] = empties
	var cleared_cells: Array[int] = []
	cleared_cells.assign(cleared.keys())
	return {"groups": groups, "cleared": cleared_cells, "drop": drop}

## 揃えられる入れ替えを1つ探す。[a, b]。無ければ空。
func find_move() -> Array[int]:
	for index in cell_count():
		if index % width < width - 1 and can_swap(index, index + 1):
			return [index, index + 1]
		if index / width < height - 1 and can_swap(index, index + width):
			return [index, index + width]
	return []

func has_moves() -> bool:
	return not find_move().is_empty()

## 並び1本の報酬の数（3つで1、4つで2、5つで3…）。
func reward_for(group: Dictionary) -> int:
	var base := int(config.get("reward_base_length", 3))
	return 1 + maxi(group.cells.size() - base, 0) * int(config.get("reward_per_extra_tile", 1))
