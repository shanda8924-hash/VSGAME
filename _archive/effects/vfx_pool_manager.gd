extends Node
class_name VFXPoolManager
## 大量撃破の一発演出（pixelfx explosions/plasma-explosion、mass_kill）を最大6個で使い回す。
@export var pool_size: int = 6

var _pool: Array[PixelSpriteVFX] = []

func _ready() -> void:
	for i in clampi(pool_size, 0, 6):
		var p := PixelSpriteVFX.new()
		p.pooled = true
		if not p.configure("mass_kill", Vector2(144.0, 144.0), 0.6):
			p.free()
			return
		add_child(p)
		_pool.append(p)

func play_mass_kill_burst(at_position: Vector2) -> void:
	for p in _pool:
		if not p.active:
			p.play_once(at_position)
			return
