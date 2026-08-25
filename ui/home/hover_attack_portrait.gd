extends TextureRect
class_name HoverAttackPortrait
## ホーム画面の職業選択カードで使うポートレート。通常はIdleの1コマ静止画を
## 表示し、start_attack()が呼ばれている間だけ攻撃アニメーションのコマ配列を
## ループ再生する(mouse_entered/mouse_exitedからhome.gdが呼び出す)。

var _idle_texture: Texture2D
var _attack_frames: Array[Texture2D] = []
var _fps: float = 10.0
var _frame_index: int = 0
var _elapsed: float = 0.0
var _playing: bool = false

## idle_texture: 通常時の静止画。attack_frames: 空なら再生対象なし
## (未解放セル、または攻撃アニメーションが見つからない職業用)。
func configure(idle_texture: Texture2D, attack_frames: Array[Texture2D], fps: float) -> void:
	_idle_texture = idle_texture
	_attack_frames = attack_frames
	_fps = maxf(fps, 1.0)
	texture = idle_texture

func start_attack() -> void:
	if _attack_frames.is_empty():
		return
	_playing = true
	_frame_index = 0
	_elapsed = 0.0
	texture = _attack_frames[0]

func stop_attack() -> void:
	_playing = false
	_frame_index = 0
	_elapsed = 0.0
	texture = _idle_texture

func _process(delta: float) -> void:
	if not _playing or _attack_frames.is_empty():
		return
	_elapsed += delta
	var frame_duration := 1.0 / _fps
	var advanced := false
	while _elapsed >= frame_duration:
		_elapsed -= frame_duration
		_frame_index = (_frame_index + 1) % _attack_frames.size()
		advanced = true
	if advanced:
		texture = _attack_frames[_frame_index]
