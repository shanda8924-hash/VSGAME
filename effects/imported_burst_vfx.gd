extends RefCounted
class_name ImportedBurstVFX
## 回避と宝箱開封の一発演出。見た目は pixelfx（dodge_burst＝spawn/poof、chest_burst＝holy/feather-burst）。

static func spawn(parent: Node2D, position: Vector2, kind: String) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var key := "chest_burst" if kind == "chest" else "dodge_burst"
	var effect := PixelSpriteVFX.spawn(parent, position, key)
	if effect:
		effect.name = "ImportedBurst_%s" % kind
		effect.z_index = 18
		effect.ignore_time_scale = true
