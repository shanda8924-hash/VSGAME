extends RefCounted
class_name Army
## 召喚したキャラクターの一覧と、融合による転職のルール（描画なし）。
## 同じ職業が fusion_count 体いれば融合でき、その職業の promotes_to の職業1体に変わる（例：ソルジャー2体→剣士）。
## 系統と必要数は data/characters/*.json。

signal changed()

var capacity := 20
## { "uid": 通し番号, "id": 職業ID } の配列。並び順が部屋での立ち位置。
var units: Array[Dictionary] = []
var _next_uid := 1

func _init(max_units: int = 20) -> void:
	capacity = max_units

func is_full() -> bool:
	return units.size() >= capacity

func count_of(character_id: String) -> int:
	var count := 0
	for unit in units:
		if String(unit.id) == character_id:
			count += 1
	return count

func index_of(uid: int) -> int:
	for index in units.size():
		if int(units[index].uid) == uid:
			return index
	return -1

func character_of(uid: int) -> CharacterData:
	var index := index_of(uid)
	return DataLoader.characters.get(String(units[index].id)) if index >= 0 else null

## 1体加える。満員なら -1、入れば通し番号を返す。
func add(character_id: String) -> int:
	if is_full() or not DataLoader.characters.has(character_id):
		return -1
	var uid := _next_uid
	_next_uid += 1
	units.append({"uid": uid, "id": character_id})
	changed.emit()
	return uid

## 転職先。無ければ null。
func promotion_of(uid: int) -> CharacterData:
	var character := character_of(uid)
	if character == null or character.promotes_to == "":
		return null
	return DataLoader.characters.get(character.promotes_to)

func can_fuse(uid: int) -> bool:
	var character := character_of(uid)
	return character != null and promotion_of(uid) != null and count_of(character.id) >= character.fusion_count

## uid のキャラクターと同じ職業の仲間を融合し、転職後の1体に置き換える（uid の立ち位置を引き継ぐ）。
## 成功すれば転職後の通し番号、できなければ -1。
func fuse(uid: int) -> int:
	if not can_fuse(uid):
		return -1
	var character := character_of(uid)
	var target := promotion_of(uid)
	var consumed := 1
	for index in range(units.size() - 1, -1, -1):
		if consumed >= character.fusion_count:
			break
		if String(units[index].id) == character.id and int(units[index].uid) != uid:
			units.remove_at(index)
			consumed += 1
	var new_uid := _next_uid
	_next_uid += 1
	units[index_of(uid)] = {"uid": new_uid, "id": target.id}
	changed.emit()
	return new_uid
