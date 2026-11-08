extends Node2D
class_name WarningCircle
## SlamStrategyが着弾予告として床に表示する警告円。生成側が座標へ配置し、
## 演出時間が終わったらqueue_free()する単純な描画専用ノード。

## 円周の装飾は pixelfx arcane/rune-circle を危険色で書き出したもの（warning_ring、ループ）。
## 当たり判定と同じ半径は _draw の円（面と進行の弧）が正確に示し、装飾はその半径に合わせて伸縮する。
const RING_KEY := "warning_ring"

@export var radius: float = 100.0
## Nova/Summon生成側との互換。薄い面塗りはPNG内の固定ドット密度で表現する。
## 色は pixelfx_effects.json の danger パレット（本体 e83a22、芯 ffe0c8）と同じ。
@export var fill_color: Color = Color("e83a2247")
@export var border_color: Color = Color("e83a22e6")

var duration := 0.0
var elapsed := 0.0
var source: EnemyBasic
var radial_rays := 0

func _ready() -> void:
	add_to_group("boss_attack_transient")
	var ring := make_ring(radius, border_color)
	if ring:
		add_child(ring)
		ring.play_once(global_position)
		ring.position = Vector2.ZERO

## 半径 radius に合わせた装飾リング（常駐・ループ）。親へ add_child するのは呼び出し側。
static func make_ring(ring_radius: float, color: Color) -> PixelSpriteVFX:
	var ring := PixelSpriteVFX.make_persistent(RING_KEY, Vector2.ZERO, true)
	if ring == null:
		return null
	ring.name = "PixelRing"
	var width := PixelSpriteVFX.frame_size_for(RING_KEY).x
	ring.scale = Vector2.ONE * (ring_radius * 2.0 / maxf(width, 1.0))
	ring.set_tint(color)
	ring.z_index = 0
	return ring

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
		draw_arc(Vector2.ZERO,radius,-PI/2,-PI/2+TAU*progress,48,Color("ffe0c8e6"),2.0,false)
	for index in radial_rays:
		var direction := Vector2.from_angle(TAU*float(index)/float(radial_rays))
		draw_line(direction*radius*0.45,direction*radius*1.35,border_color,2.0,false)
