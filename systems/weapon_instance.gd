extends RefCounted
class_name WeaponInstance
## 完成武器1つぶんの実行時状態(クールダウン管理等)を持つ軽量クラス。
## Node化しないことで大量の武器を持っても軽量に保つ。

var data: WeaponData
var level: int = 1
var _cooldown: float = 0.0

func _init(weapon_data: WeaponData) -> void:
	data = weapon_data

func tick(delta: float, owner_entity: Node2D, manager: WeaponManagerComponent) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		var target := manager.find_nearest_enemy(owner_entity.global_position)
		if target == null:
			return
		# rapid_barrageのようなトレードオフ強化で射程が変動する場合があるため、
		# 素のattack_rangeではなく実効射程(倍率込み)で判定する。範囲外なら
		# クールダウンをリセットせず、次フレームも射程内かどうかを再チェックする
		# (敵が射程内に入った瞬間、余計な待ち時間なしに発射できるように)。
		var effective_range: float = data.attack_range * manager.get_attack_range_multiplier()
		if owner_entity.global_position.distance_to(target.global_position) > effective_range:
			return
		manager.spawn_projectile(data, owner_entity.global_position, target.global_position)
		# quick_handsのようなアイテムで蓄積した攻撃間隔短縮率を反映する。
		_cooldown = data.attack_interval * manager.get_attack_interval_multiplier()
