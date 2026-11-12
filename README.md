# VSGAME

Godot 4.7 のドット絵ゲーム。2026-11-12 にピボットし、いまは**キャラクターだけの土台**の状態。

- 新しい方向と現状：`game_specification.md`
- ピボット前の仕様：`game_specification_old.md`、コードと素材：`_archive/`、直前の状態：git タグ `pre-pivot`

## 検査（Godot 4.7.1、headless）
```
godot --headless --path . --import
godot --headless --path . --script res://tests/script_load_check.gd
godot --headless --audio-driver Dummy --path . res://tests/character_base_check.tscn
godot --headless --audio-driver Dummy --path . res://tests/room_base_check.tscn
godot --headless --audio-driver Dummy --path . --quit-after 180
```
エラー・警告が0件であること。
