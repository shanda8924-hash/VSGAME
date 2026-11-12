extends CharacterBody2D
class_name Entity
## Player/Enemy共通の基底クラス。
## 「Componentを取りまとめてmove_and_slide()を呼ぶ」ことだけに責務を絞り、
## 個別の挙動(入力/AI)は各Componentやサブクラスに委譲する(単一責任の原則)。

@onready var health_component: HealthComponent = $HealthComponent if has_node("HealthComponent") else null
@onready var movement_component: MovementComponent = $MovementComponent if has_node("MovementComponent") else null
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent if has_node("StatusEffectComponent") else null
@onready var animation_component: AnimationComponent = $AnimationComponent if has_node("AnimationComponent") else null

func _physics_process(_delta: float) -> void:
	if movement_component:
		if status_effect_component:
			movement_component.speed_multiplier = status_effect_component.slow_multiplier
		velocity = movement_component.get_velocity()
		move_and_slide()
