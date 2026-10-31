extends RefCounted
class_name ExplorationLayout
## Route roles first, rooms second. All numbers below are VSGAME design values,
## not claimed reverse-engineered Emberville constants.
const COORDS := [Vector2i(0,1),Vector2i(1,1),Vector2i(2,1),Vector2i(2,0),Vector2i(3,0),Vector2i(3,1),Vector2i(4,1),Vector2i(4,2),Vector2i(1,2),Vector2i(0,2),Vector2i(2,2),Vector2i(3,2),Vector2i(2,3),Vector2i(3,3),Vector2i(1,0),Vector2i(4,0),Vector2i(0,0)]
const ROLES := ["entry","first_guard","junction","guard","key_guard","junction_guard","antechamber","boss","guard","cache","flank","rest","elite","cache","landmark","guard","cache"]
const EDGES := [Vector2i(0,1),Vector2i(1,2),Vector2i(2,5),Vector2i(5,6),Vector2i(6,7),Vector2i(2,3),Vector2i(3,4),Vector2i(4,5),Vector2i(1,8),Vector2i(8,9),Vector2i(8,10),Vector2i(10,2),Vector2i(10,11),Vector2i(11,5),Vector2i(10,12),Vector2i(12,13),Vector2i(13,11),Vector2i(1,14),Vector2i(6,15),Vector2i(14,16)]

static func generate(map_index: int, rng: RandomNumberGenerator = null, floor_index: int = 1) -> DungeonMap:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var layout_seed := rng.state
	var depth := (map_index - 1) * 20 + floor_index
	var count := mini(17, int([13,15,17][clampi(map_index-1,0,2)]) + floori(float(depth - 1) / 6.0))
	var pitch := 22 + mini(map_index-1,2)
	var flip_x := -1 if rng.randf() < 0.5 else 1
	var flip_y := -1 if rng.randf() < 0.5 else 1
	var map := DungeonMap.new(pitch*4+28,pitch*3+28)
	var centres: Array[Vector2i] = []
	var roles: Array[String] = []
	var shapes: Array[String] = []
	for i in count:
		var c: Vector2i = COORDS[i]*pitch - Vector2i(pitch*2,pitch*3/2)
		c += Vector2i(rng.randi_range(-1,1),rng.randi_range(-1,1))
		c *= Vector2i(flip_x,flip_y)
		var role: String = ROLES[i]
		var size := Vector2i(rng.randi_range(12,16),rng.randi_range(11,15))
		if role == "entry": size = Vector2i(10,10)
		if role == "boss": size = Vector2i(18,18)
		if role in ["cache","rest"]: size = Vector2i(10,11)
		if role in ["junction","junction_guard"]: size = Vector2i(16,15)
		var rect := Rect2i(c-size/2,size)
		var shape: String = ["alcove","cross","cut_corner","gallery"][(i+rng.randi_range(0,3)+map_index)%4]
		if role in ["entry","boss","landmark","rest"]: shape = "alcove"
		map.rooms.append(rect)
		centres.append(c)
		roles.append(role)
		shapes.append(shape)
		_carve_room(map,rect,shape)
	var edges: Array[Vector2i] = []
	var lower_route := rng.randi_range(0,2)
	for edge: Vector2i in EDGES:
		if edge.x >= count or edge.y >= count: continue
		if (edge==Vector2i(8,10) and lower_route==0) or (edge==Vector2i(10,2) and lower_route==1): continue
		edges.append(edge)
		var lane_width := 4 if 7 in [edge.x,edge.y] else (3 if rng.randf()<0.65 else 4)
		_connect(map,centres[edge.x],centres[edge.y],lane_width,COORDS[edge.x].y == COORDS[edge.y].y)
	map.spawn_point = centres[0]
	map.boss_room_index = 7
	map.set_combat_region(7,DungeonMap.REGION_ARENA,map.rooms[7])
	# An off-centre wall changes sight lines without a one-tile choke or blocked exit.
	for i in [3,10,12]:
		var c := centres[i]
		var room := map.rooms[i]
		var wall := Rect2i(c+Vector2i(-4,-3),Vector2i(2,3))
		for y in range(wall.position.y,wall.end.y):
			for x in range(wall.position.x,wall.end.x):
				map.mark_terrain_obstacle(Vector2i(x,y))
		map.set_combat_region(i,DungeonMap.REGION_PILLAR_FIELD if i == 12 else DungeonMap.REGION_CHOKEPOINT,room)
	map.set_meta("exploration_layout",true)
	map.set_meta("floor_index", floor_index)
	map.set_meta("global_depth", (map_index - 1) * 20 + floor_index)
	map.set_meta("layout_seed",layout_seed)
	map.set_meta("room_roles",roles)
	map.set_meta("room_shapes",shapes)
	map.set_meta("route_edges",edges)
	map.set_meta("key_room",4)
	map.set_meta("room_depths",_depths(count,edges))
	# These positions are reserved before scenic art/props are installed.
	var objectives := {4: centres[4]+Vector2i(3,-1),9:centres[9]+Vector2i(2,-1),11:centres[11]+Vector2i(2,-1),12:centres[12]+Vector2i(3,1)}
	for i in [13,16]:
		if i<count: objectives[i]=centres[i]+Vector2i(2,-1)
	map.set_meta("objective_cells",objectives)
	var reserved: Dictionary = map.get_meta("exploration_routes", {}).duplicate()
	for cell: Vector2i in objectives.values():
		for y in range(-2,3):
			for x in range(-2,3): reserved[cell+Vector2i(x,y)] = true
	map.set_meta("exploration_reserved",reserved)
	return map

static func _carve_room(map: DungeonMap, room: Rect2i, shape: String) -> void:
	for y in room.size.y:
		for x in room.size.x:
			var cut := false
			match shape:
				"alcove": cut = y<2 and (x<3 or x>=room.size.x-3)
				"cross": cut = (x<3 or x>=room.size.x-3) and (y<3 or y>=room.size.y-3)
				"cut_corner": cut = x<4 and y<4
				"gallery": cut = (x<2 and y<4) or (x>=room.size.x-3 and y>=room.size.y-3)
			if not cut: map.set_floor(room.position+Vector2i(x,y),true)

static func _connect(map: DungeonMap, a: Vector2i, b: Vector2i, width: int, horizontal: bool) -> void:
	# Adjacent macro cells only: turns are in the gap, never across a third room.
	var mid := (a+b)/2
	var points: Array[Vector2i]
	if horizontal: points = [a,Vector2i(mid.x,a.y),Vector2i(mid.x,b.y),b]
	else: points = [a,Vector2i(a.x,mid.y),Vector2i(b.x,mid.y),b]
	var routes: Dictionary = map.get_meta("exploration_routes",{})
	for i in range(points.size()-1):
		var p := points[i]
		var q := points[i+1]
		for y in range(mini(p.y,q.y),maxi(p.y,q.y)+1):
			for x in range(mini(p.x,q.x),maxi(p.x,q.x)+1):
				for ry in range(-1,2):
					for rx in range(-1,2): routes[Vector2i(x+rx,y+ry)]=true
				for dy in range(-width/2,width-width/2):
					for dx in range(-width/2,width-width/2): map.set_floor(Vector2i(x+dx,y+dy),true)
	map.set_meta("exploration_routes",routes)

static func _depths(count: int, edges: Array[Vector2i]) -> Array[int]:
	var values: Array[int] = []
	values.resize(count)
	values.fill(-1)
	values[0] = 0
	var queue: Array[int] = [0]
	for i in count:
		if i>=queue.size(): break
		var a := queue[i]
		for edge in edges:
			var b := edge.y if edge.x==a else (edge.x if edge.y==a else -1)
			if b>=0 and values[b]<0:
				values[b]=values[a]+1
				queue.append(b)
	return values

static func room_at(map: DungeonMap, cell: Vector2i) -> int:
	for i in map.rooms.size():
		if map.rooms[i].has_point(cell) and map.is_floor(cell): return i
	return -1
