extends Node2D
class_name WarningCircle
## SlamStrategyが着弾予告として床に表示する警告円。生成側が座標へ配置し、
## 演出時間が終わったらqueue_free()する単純な描画専用ノード。

const RING_TEXTURE := preload("res://assets/vfx/pixel/warning_ring.png")
## 64px画像の円周本体外端は25px。29pxまで伸びる四方の目盛りは半径に含めない。
## テストでPNGを走査し、見える円周を実際の攻撃半径に合わせる。
const RING_PIXEL_RADIUS := 25.0

@export var radius: float = 100.0
## Nova/Summon生成側との互換。薄い面塗りはPNG内の固定ドット密度で表現する。
@export var fill_color: Color = Color(1.0, 0.15, 0.1, 0.28)
@export var border_color: Color = Color(1.0, 0.25, 0.15, 0.9)

var duration := 0.0
var elapsed := 0.0
var source: EnemyBasic
var radial_rays := 0

func _ready() -> void:
	add_to_group("boss_attack_transient")
	var ring := Sprite2D.new()
	ring.name = "PixelRing"
	ring.texture = RING_TEXTURE
	ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ring.scale = Vector2.ONE * (radius / RING_PIXEL_RADIUS)
	ring.modulate = border_color
	add_child(ring)

func _process(delta: float) -> void:
	if source != null and (not is_instance_valid(source) or source._is_dead):
		queue_free()
		return
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / maxf(duration,0.01),0.0,1.0)
	if duration > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(border_color,0.06+progress*0.13))
		draw_arc(Vector2.ZERO,radius,-PI/2,-PI/2+TAU*progress,48,Color(1.0,0.85,0.6,0.9),2.0,false)
	for index in radial_rays:
		var direction := Vector2.from_angle(TAU*float(index)/float(radial_rays))
		draw_line(direction*radius*0.45,direction*radius*1.35,border_color,2.0,false)
