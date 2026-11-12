extends Node2D
func _ready():
 var frames=SpriteSheetBuilder.build_sprite_frames('player/Swordsman')
 for variant in 3:
  var anim='attack%d' % (variant+1)
  print(anim,' frames=',frames.get_frame_count(anim),' fps=',frames.get_animation_speed(anim))
  for i in frames.get_frame_count(anim):
   var sprite=Sprite2D.new()
   sprite.texture=frames.get_frame_texture(anim,i)
   sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
   sprite.scale=Vector2(2.4,2.4)
   sprite.position=Vector2(65+i*125,125+variant*230)
   add_child(sprite)
   var label=Label.new()
   label.text='%s:%d' % [anim,i]
   label.position=Vector2(15+i*125,195+variant*230)
   add_child(label)
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png('res://artifacts/sword_frames.png')
 get_tree().quit()
