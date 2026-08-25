extends Node2D
class_name WarningCircle
## SlamStrategyが着弾予告として床に表示する警告円。生成側が座標へ配置し、
## 演出時間が終わったらqueue_free()する単純な描画専用ノード。

@export var radius: float = 100.0
@export var fill_color: Color = Color(1.0, 0.15, 0.1, 0.28)
@export var border_color: Color = Color(1.0, 0.25, 0.15, 0.9)

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, border_color, 3.0, true)

func _ready() -> void:
	add_to_group("boss_attack_transient")
	queue_redraw()
