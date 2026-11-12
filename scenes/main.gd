extends Node2D
## 最小の土台：何もない1部屋に、選んだ職業のキャラクターが立って待機しているだけ。
## 攻撃・敵・UIは無い。部屋の中身はあとで決める。
## 職業は GameManager.selected_character_id。確認用に起動引数 `-- --character=<id>` でも選べる。

## 部屋の床の大きさ（px）。原点が部屋の中心で、カメラも原点に固定する（2倍表示で800×450の視野に収まる）。
const ROOM_SIZE := Vector2(704, 384)
const FLOOR_COLOR := Color("23283a")
const FLOOR_LINE_COLOR := Color("2c3350")
const WALL_COLOR := Color("4a5578")
const GRID := 32.0

@onready var player: Player = $Player

func _enter_tree() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="):
			GameManager.selected_character_id = argument.trim_prefix("--character=")

func _ready() -> void:
	player.position = Vector2.ZERO

func get_room_rect() -> Rect2:
	return Rect2(-ROOM_SIZE * 0.5, ROOM_SIZE)

func _draw() -> void:
	var rect := get_room_rect()
	draw_rect(rect, FLOOR_COLOR)
	var x := rect.position.x + GRID
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), FLOOR_LINE_COLOR, 1.0)
		x += GRID
	var y := rect.position.y + GRID
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), FLOOR_LINE_COLOR, 1.0)
		y += GRID
	draw_rect(rect, WALL_COLOR, false, 4.0)
