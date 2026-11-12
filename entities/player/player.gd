extends Entity
class_name Player
## 主人公。選んだ職業(GameManager.selected_character_id)の見た目と基本ステータスを反映して立つだけ。
## 戦闘は自走式にする予定で、プレイヤーの移動入力は持たない。
## 攻撃・回避・職業技・装備・成長などピボット前の機能は _archive/ に退避済み。

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var character_data: CharacterData

func _ready() -> void:
	apply_character(GameManager.get_selected_character())

## 職業の見た目(SpriteFrames)と基本ステータス(HP・移動速度)を反映する。
func apply_character(data: CharacterData) -> void:
	if data == null:
		return
	character_data = data
	health_component.max_hp = data.max_hp
	health_component.current_hp = data.max_hp
	movement_component.base_speed = data.move_speed
	if data.sprite_folder != "":
		var frames := SpriteSheetBuilder.build_sprite_frames(data.sprite_folder)
		if frames:
			animated_sprite.sprite_frames = frames
			if frames.has_animation("idle"):
				animated_sprite.play("idle")
