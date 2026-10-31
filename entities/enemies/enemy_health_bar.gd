extends Node2D
## Shared by normal/strong/elite enemies; bosses keep their dedicated HUD.
var enemy: EnemyBasic
var last_ratio := -1.0
func _ready() -> void:
 enemy = get_parent() as EnemyBasic
 z_index = 8
 var sprite := enemy.animated_sprite
 var height := 32.0
 if sprite.sprite_frames and sprite.sprite_frames.has_animation(sprite.animation) and sprite.sprite_frames.get_frame_count(sprite.animation) > 0:
  height = sprite.sprite_frames.get_frame_texture(sprite.animation, 0).get_height()
 var top: float = sprite.position.y - height * absf(sprite.scale.y) * 0.5
 position.y = minf(-24.0, top - 7.0)
 enemy.state_indicator.position.y = position.y - 9.0
 _process(0.0)
func _process(_delta: float) -> void:
 var health := enemy.health_component
 var ratio := clampf(health.current_hp / maxf(health.max_hp, 1.0), 0.0, 1.0)
 # Crowds must stay readable: full-health mobs need no gauge; strong/elite do.
 var important := enemy.strong_attack != null or enemy.is_in_group("elite_enemies")
 visible = ratio > 0.0 and not enemy._is_dead and (important or ratio < 0.999 or not GameManager.map_mode_active)
 if not is_equal_approx(ratio, last_ratio):
  last_ratio = ratio
  queue_redraw()
func _draw() -> void:
 var width := 32.0 if enemy.strong_attack != null or enemy.is_in_group("elite_enemies") else 24.0
 var left := -width * 0.5
 draw_rect(Rect2(left-1,-1,width+2,5), Color(0.025,0.025,0.03,0.95))
 draw_rect(Rect2(left,0,width,3), Color(0.23,0.07,0.07))
 draw_rect(Rect2(left,0,width*maxf(last_ratio,0.0),3), Color(0.84,0.16,0.13))
 draw_line(Vector2(left,0),Vector2(left+width*maxf(last_ratio,0.0),0),Color(1.0,0.45,0.32),1.0)
