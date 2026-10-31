extends RefCounted
class_name SpriteSheetBuilder
## assets/sprites/以下のスプライトシート(1コマ=正方形、横一列)から
## 実行時にSpriteFramesを組み立てる共通ユーティリティ。
## Player(職業ごと)・EnemyBasic(敵種ごと)の両方から使う。
##
## 素材フォルダごとにファイル名の付け方(Idle/Walk/Walk01/Flying、
## Attack01/Attack1、Death/DEATH等)や、フォルダ構成(直下 or
## "○○ with shadows"/"○○"サブフォルダ)がまちまちなため、候補を
## 順番に試して最初に見つかったものを採用する形にしてある。
## コマ数はハードコードせず、画像の実サイズ(幅÷高さ)から自動算出する
## (1コマ=正方形という前提のみ利用)。

const ANIM_SUFFIX_CANDIDATES := {
	"idle": ["Idle", "Flying", "Walk"],
	"walk": ["Walk", "Walk01", "Flying", "Idle"],
	"attack1": ["Attack01", "Attack1", "Attack"],
	# Native effect-free variants keep Ghostfire/Lava Slime's melee hit honest.
	"attack2": ["Attack02(No beam effects)", "Attack02(No spike effects)", "Attack02", "Attack2"],
	"attack3": ["Attack03", "Attack3"],
	"block": ["Block"],
	"hurt": ["Hurt"],
	"death": ["Death", "DEATH"],
}
const LOOPING_ANIMS := ["idle", "walk"]
static var _sprite_frames_cache: Dictionary = {}

## sprite_folderは"player/Soldier"のように assets/sprites/ からの相対パス。
## 1つもアニメーションが見つからなければnullを返す。
static func build_sprite_frames(sprite_folder: String) -> SpriteFrames:
	if _sprite_frames_cache.has(sprite_folder):
		return _sprite_frames_cache[sprite_folder] as SpriteFrames
	var base_dir := "res://assets/sprites/%s" % sprite_folder
	var character_name := sprite_folder.get_file()
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")

	var any_found := false
	for anim_name in ANIM_SUFFIX_CANDIDATES.keys():
		var path := _resolve_path(base_dir, character_name, ANIM_SUFFIX_CANDIDATES[anim_name])
		if path == "":
			continue
		var texture: Texture2D = load(path)
		if texture == null:
			continue
		var frame_height := texture.get_height()
		if frame_height <= 0:
			continue
		var frame_count := int(round(float(texture.get_width()) / float(frame_height)))
		if frame_count <= 0:
			continue

		if not frames.has_animation(anim_name):
			frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, anim_name in LOOPING_ANIMS)
		frames.set_animation_speed(anim_name, _default_fps(anim_name))
		for i in frame_count:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_height, 0, frame_height, frame_height)
			frames.add_frame(anim_name, atlas)
		any_found = true

	if not any_found:
		return null
	_sprite_frames_cache[sprite_folder] = frames
	return frames

static func is_cached(sprite_folder: String) -> bool:
	return _sprite_frames_cache.has(sprite_folder)

## ポートレート用: 指定フォルダの"Idle"系スプライトシートから、1コマ目だけを
## 切り出したAtlasTextureを返す(ホーム画面のキャラクター選択グリッド等、
## 複数コマのシートをそのまま表示すると横に並んで見えてしまう場面で使う)。
## 見つからなければnullを返す。
static func build_portrait_texture(sprite_folder: String) -> Texture2D:
	var base_dir := "res://assets/sprites/%s" % sprite_folder
	var character_name := sprite_folder.get_file()
	var path := _resolve_path(base_dir, character_name, ANIM_SUFFIX_CANDIDATES["idle"])
	if path == "":
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		return null
	var frame_height := texture.get_height()
	if frame_height <= 0:
		return null

	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	# 1コマ目のキャンバスは正方形(frame_height角)だが、実際に描かれた
	# キャラクター部分はキャンバス内の一部だけのことが多い(アニメーション間で
	# コマ位置を揃えるための余白を持たせた素材のため)。そのまま拡大表示すると
	# 余白ごと拡大されキャラクターが小さく見えてしまうため、可能なら不透明
	# ピクセルの外接矩形だけに切り詰める(取得できない場合はコマ全体を使う)。
	var image := texture.get_image()
	var region := Rect2(0, 0, frame_height, frame_height)
	if image != null:
		var frame_image := Image.create(int(frame_height), int(frame_height), false, image.get_format())
		frame_image.blit_rect(image, Rect2i(0, 0, int(frame_height), int(frame_height)), Vector2i.ZERO)
		var used_rect := frame_image.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0:
			region = Rect2(used_rect.position, used_rect.size)
	atlas.region = region
	return atlas

## ホーム画面のホバー攻撃プレビュー用: build_sprite_frames()を再利用して
## 職業の攻撃アニメーション(attack1/attack2/attack3のうち存在するものから
## ランダムに1つ)のコマ列を取得し、build_portrait_texture()と同じ考え方で
## 不透明ピクセルの外接矩形へ切り詰めたAtlasTexture配列を返す。
## 攻撃アニメーションが1つも無い場合は空のDictionaryを返す。
## 戻り値: {"attack_frames": Array[Texture2D], "fps": float}
static func build_hover_attack_frames(sprite_folder: String) -> Dictionary:
	var frames := build_sprite_frames(sprite_folder)
	if frames == null:
		return {}

	var candidates: Array[String] = []
	for anim_name in ["attack1", "attack2", "attack3"]:
		if frames.has_animation(anim_name):
			candidates.append(anim_name)
	if candidates.is_empty():
		return {}

	var anim_name: String = candidates[randi() % candidates.size()]
	var frame_count := frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return {}

	var first_frame := frames.get_frame_texture(anim_name, 0) as AtlasTexture
	if first_frame == null or first_frame.atlas == null:
		return {}
	var atlas_image := first_frame.atlas.get_image()
	var frame_size: Vector2 = first_frame.region.size
	if atlas_image == null or frame_size.x <= 0 or frame_size.y <= 0:
		return {}

	# 全コマに共通の切り抜き範囲(コマごとのローカル座標)を使うことで、
	# コマ単位に外接矩形を取り直した場合に生じる拡大率のガクガクした変動
	# (キャラクターの写る面積がコマごとに違うと、STRETCH_KEEP_ASPECT_CENTEREDの
	# 拡大率もコマごとに変わってしまう)を防ぐ。
	var union_rect := Rect2()
	var has_union := false
	for i in frame_count:
		var frame_tex := frames.get_frame_texture(anim_name, i) as AtlasTexture
		if frame_tex == null:
			continue
		var region: Rect2 = frame_tex.region
		var region_i := Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y))
		var frame_image := Image.create(int(frame_size.x), int(frame_size.y), false, atlas_image.get_format())
		frame_image.blit_rect(atlas_image, region_i, Vector2i.ZERO)
		var used := frame_image.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		union_rect = used if not has_union else union_rect.merge(used)
		has_union = true

	if not has_union:
		union_rect = Rect2(Vector2.ZERO, frame_size)

	var result_frames: Array[Texture2D] = []
	for i in frame_count:
		var frame_tex := frames.get_frame_texture(anim_name, i) as AtlasTexture
		if frame_tex == null:
			continue
		var cropped := AtlasTexture.new()
		cropped.atlas = frame_tex.atlas
		cropped.region = Rect2(frame_tex.region.position + union_rect.position, union_rect.size)
		result_frames.append(cropped)

	return {
		"attack_frames": result_frames,
		"fps": frames.get_animation_speed(anim_name),
	}

static func _resolve_path(base_dir: String, character_name: String, suffixes: Array) -> String:
	var location_candidates := [
		base_dir,
		"%s/%s with shadows" % [base_dir, character_name],
		"%s/%s" % [base_dir, character_name],
	]
	for loc in location_candidates:
		# FileAccess.file_exists()はWindowsでは大文字小文字を区別しないため、
		# `Death`候補が実在する`DEATH`を誤って拾い、case-sensitiveなExport先で
		# 読めなくなる。Directory listingの実ファイル名との完全一致だけを採用する。
		var directory := DirAccess.open(loc)
		if directory == null:
			continue
		var actual_files := directory.get_files()
		for suffix in suffixes:
			var file_name := "%s_%s.png" % [character_name, suffix]
			if file_name in actual_files:
				return "%s/%s" % [loc, file_name]
	return ""

static func _default_fps(anim_name: String) -> float:
	match anim_name:
		"idle":
			return 6.0
		"walk":
			return 8.0
		"hurt":
			return 10.0
		"death":
			return 6.0
		_:
			return 12.0
