extends Sprite2D
class_name StateIndicator
## Enemyの頭上へ5属性状態を小さなPixel Barで表示する。状態組み合わせ(最大32)ごとに
## 極小Textureを共有し、敵1体につき単一Sprite描画に抑える。更新は状態変更時だけ。

const STATE_ELEMENT := {
	"burning": "element_fire",
	"frozen": "element_ice",
	"charged": "element_lightning",
	"marked": "element_light",
	"cursed": "element_dark",
}
const FALLBACK_COLORS := {
	"burning": Color("#ff7043"),
	"frozen": Color("#72d7ff"),
	"charged": Color("#ffe45c"),
	"marked": Color("#fff1a8"),
	"cursed": Color("#b56cff"),
}

static var _texture_cache: Dictionary = {}
var _states: Array[String] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true

func set_states(states: Array[String]) -> void:
	if states == _states:
		return
	_states = states.duplicate()
	visible = not _states.is_empty()
	texture = _texture_for_states(_states) if visible else null

func _texture_for_states(states: Array[String]) -> Texture2D:
	var key := ",".join(states)
	if _texture_cache.has(key):
		return _texture_cache[key]
	var spacing := 6
	var width := states.size() * spacing + 2
	var image := Image.create(width, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.035, 0.045, 0.07, 0.9))
	for index in states.size():
		var color := _state_color(states[index])
		var start_x := 2 + index * spacing
		for x in range(start_x, start_x + 4):
			for y in range(1, 5):
				image.set_pixel(x, y, color)
	var generated := ImageTexture.create_from_image(image)
	_texture_cache[key] = generated
	return generated

func _state_color(state_id: String) -> Color:
	return FALLBACK_COLORS.get(state_id, Color.WHITE)
