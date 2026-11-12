extends CharacterBody2D
class_name Entity
## キャラクターの基底クラス。Componentを取りまとめて move_and_slide() を呼ぶことだけを担う。
## 個別の挙動は各Componentやサブクラスに委ねる。

@onready var health_component: HealthComponent = $HealthComponent if has_node("HealthComponent") else null
@onready var movement_component: MovementComponent = $MovementComponent if has_node("MovementComponent") else null
@onready var animation_component: AnimationComponent = $AnimationComponent if has_node("AnimationComponent") else null

func _physics_process(_delta: float) -> void:
	if movement_component:
		velocity = movement_component.get_velocity()
		move_and_slide()
