extends Node2D
## Brief, directional contact mark. Damage and freeze remain in their existing pipeline.
var heavy := false
var age := 0.0
func _ready() -> void:
 z_index = 70
func _process(delta: float) -> void:
 age += delta
 if age >= 0.13:
  queue_free()
 else:
  queue_redraw()
func _draw() -> void:
 var fade := 1.0 - age / 0.13
 var reach := (11.0 if heavy else 8.0) * (1.0 + age * 3.0)
 draw_line(Vector2(-3,-reach),Vector2(3,reach),Color(0.96,0.98,1,fade),2.0)
 draw_line(Vector2(-reach*0.55,2),Vector2(reach*0.55,-2),Color(1,0.86,0.64,fade),1.0)
 for side in [-1.0,1.0]:
  draw_line(Vector2(4,side*3)*(1+age*8),Vector2(8,side*5)*(1+age*8),Color(0.95,0.82,0.62,fade),1.0)