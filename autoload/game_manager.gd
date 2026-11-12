extends Node
## ゲーム全体で共有する最小限の状態。現在は「選んでいる職業」だけ。
## ランの進行・経済・マップなどピボット前の状態は _archive/ に退避済み。

const DEFAULT_CHARACTER_ID := "soldier"

var selected_character_id: String = DEFAULT_CHARACTER_ID

## 選択中の職業のデータ。無効なIDなら既定の職業へ戻す。
func get_selected_character() -> CharacterData:
	if not DataLoader.characters.has(selected_character_id):
		selected_character_id = DEFAULT_CHARACTER_ID
	return DataLoader.characters.get(selected_character_id)
