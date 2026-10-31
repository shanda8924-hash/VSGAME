extends Node
var game: Node
var output := "res://artifacts/gate_entry"
func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--gate-output="): output = arg.trim_prefix("--gate-output=")
 SaveManager.begin_ephemeral_session()
 run.call_deferred()
func frames(n: int) -> void:
 for i in n: await get_tree().process_frame
func capture(name: String) -> void:
 await frames(3)
 await RenderingServer.frame_post_draw
 assert(get_viewport().get_texture().get_image().save_png(output+"/%s.png" % name) == OK)
func run() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 game=load("res://scenes/game.tscn").instantiate()
 game.tree_entered.connect(func(): get_tree().current_scene=game)
 get_tree().root.add_child(game)
 var c:=game.get_node("MapRunController") as MapRunController
 while not c._active: await frames(1)
 var player:=game.get_node("Player") as Player
 player.health_component.invincible=true
 for theme in [1,2,3]:
  if theme!=1:
   c._transition_to_map(theme,1)
   while c._transitioning: await frames(1)
  var wave:=game.get_node("WaveSpawner") as WaveSpawner
  wave._sector_remaining=0
  wave.set_spawning_paused(true)
  for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
  await frames(4)
  var door:=c._sector_exit
  var map:=GameManager.dungeon_map
  var room:=map.rooms[c._sector_room_index]
  assert(is_equal_approx(door.position.y,map.grid_to_world(room.position).y-16),"door threshold must be in north wall")
  assert(map.get_meta("room_exit_wall_cells",[]).size()>0,"wall has a real opening")
  for cell in map.get_meta("room_exit_wall_cells"):
   var layer:=game.get_node("StageEnvironment")._tile_map_layer as TileMapLayer
   var data:=layer.get_cell_tile_data(cell)
   assert(data == null or data.get_collision_polygons_count(0)==0,"wall texture must stay without blocking entry")
  player.global_position=door.global_position+Vector2(0,72)
  player.movement_component.direction=Vector2.ZERO
  player.set_movement_locked(true)
  await capture("map%d_locked"%theme)
  c._sector_cleared=true
  if is_instance_valid(c._sector_chest): c._sector_chest.is_opened=true
  door.set_available(true)
  door._on_body_entered(player)
  await capture("map%d_open"%theme)
  var index:=c._sector_index
  var origin:=door.global_position
  assert(door.interact(player))
  assert(c._transitioning and c._sector_index==index,"interaction must not skip gate entry")
  while player.global_position.y > origin.y+8: await frames(1)
  assert(absf(player.global_position.x-origin.x)<1.0,"actor must enter center of opening")
  assert(c._sector_index==index,"room must stay until actor is inside gate")
  assert(door.get_node("DoorFrame").z_index+door.z_index>player.z_index,"frame must occlude actor at doorway")
  await capture("map%d_entering"%theme)
  while c._transitioning: await frames(1)
  assert(c._sector_index==index+1)
  assert(player.is_processing() and player.is_physics_processing())
  assert(player.modulate.a==1.0,"actor must be visible after arriving")
  player.set_movement_locked(false)
 print("GATE_ENTRY_CHECK PASS: 3 wall openings, center entry, foreground frame, delayed transition and restored actor")
 game.queue_free()
 await frames(4)
 AudioManager.stop_all(false)
 get_tree().quit()
