extends Node2D
## Hand-aligned poses with a held wind-up and a short impact. Feet never slide.
const SHEET := "res://assets/tiles/landmarks/miner_pixel_v3.png"
var elapsed := 0.0
var pose := -1
var worker: Sprite2D
var textures: Array[AtlasTexture] = []
func _ready() -> void:
	var sheet := load(SHEET) as Texture2D
	# Body centres differ in the generated sheet; all regions share foot baseline.
	for index in 4:
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(index * 24, 0, 24, 24)
		textures.append(texture)
	worker = Sprite2D.new()
	worker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	worker.scale = Vector2.ONE * 2.0
	worker.position = Vector2(0, -24.0)
	add_child(worker)
	_update_pose()
func _process(delta: float) -> void:
	elapsed = fmod(elapsed + delta, 2.8)
	_update_pose()
func _update_pose() -> void:
	var next := 0
	if elapsed >= 0.85 and elapsed < 1.38:
		next = 1
	elif elapsed >= 1.38 and elapsed < 1.54:
		next = 2
	elif elapsed >= 1.54 and elapsed < 1.9:
		next = 3
	if next != pose:
		pose = next
		worker.texture = textures[pose]
		worker.position.x = -2.0 if pose == 2 else 0.0
		queue_redraw()
func _draw() -> void:
	if pose == 2:
		# A few stone chips on contact, confined to the work area.
		for offset in [Vector2(-21,-12), Vector2(-18,-15), Vector2(-25,-9)]:
			draw_rect(Rect2(offset, Vector2(2,2)), Color("a39aaf"))
