extends Node
class_name VFXPoolManager
## パーティクルのオブジェクトプール管理。
## 大量撃破時にinstantiate/queue_freeを連発するとGC負荷でカクつくため、
## あらかじめプールしておいた粒子を使い回す。

@export var mass_kill_particle_scene: PackedScene
@export var pool_size: int = 6

var _pool: Array[GPUParticles2D] = []

func _ready() -> void:
	if mass_kill_particle_scene == null:
		return
	for i in pool_size:
		var p: GPUParticles2D = mass_kill_particle_scene.instantiate()
		p.emitting = false
		add_child(p)
		_pool.append(p)

func play_mass_kill_burst(at_position: Vector2) -> void:
	for p in _pool:
		if not p.emitting:
			p.global_position = at_position
			p.restart()
			p.emitting = true
			return
