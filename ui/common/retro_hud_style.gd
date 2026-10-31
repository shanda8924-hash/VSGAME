class_name RetroHUDStyle
extends RefCounted
## 枠/画像はPixel Art、読ませる文字は可読性優先の日本語UI書体。

const VOID := Color("292532")
const VOID_DEEP := Color("14171e")
const PARCHMENT := Color("f2e6cd")
const PARCHMENT_DIM := Color("b4b4bf")
const BRONZE_DARK := Color("9d7138")
const BRONZE := Color("bd9250")
const BRONZE_LIGHT := Color("d6a957")
const HP_RED := Color("b94e4b")
const HP_RED_LIGHT := Color("e27458")
const IAI_TEAL := Color("509d9f")
const IAI_TEAL_LIGHT := Color("72c9cb")
const BOSS_PURPLE := Color("895e84")
const BOSS_PURPLE_LIGHT := Color("c28aae")

const FONT_PATH := "res://assets/fonts/MPLUS1p-Medium.ttf"

static var _font: Font = null
static var _font_checked := false

## 名称は呼出互換を維持。本文は滑らかなMediumウェイト、最低18pxを使う。
static func retro_font() -> Font:
	if not _font_checked:
		_font_checked = true
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH) as Font
			if _font is FontFile:
				(_font as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_GRAY
				(_font as FontFile).subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font

## RichTextLabelのnormal/boldはfontとは別。ここも同じ書体へ揃える。
static func apply_font(root: Node) -> void:
	var font := retro_font()
	if font == null or root == null:
		return
	if root is Control:
		(root as Control).add_theme_font_override("font", font)
		if root is RichTextLabel:
			for role in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
				(root as Control).add_theme_font_override(role, font)
	for child in root.get_children():
		apply_font(child)

## パネル本体(枠+背景)のStyleBoxFlat。グラデーション背景・鋲・グロー・ガラス光沢は
## RetroPanel(retro_panel.gd/.tscn)側で別レイヤーとして重ねるため、ここでは
## 「3px bronze枠」の担当だけに絞る(背景はStyleBoxFlatにグラデーションを持たせられないため
## 別のTextureRect(GradientTexture2D)に任せる)。
static func panel_border_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = BRONZE
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	return style

## パネル背景の縦グラデーション(#3c3468 → #241d48)。GradientTexture2Dを都度生成し、
## TextureRect(stretch_mode=STRETCH_SCALE)へ差し込んで使う。
static func panel_gradient_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color("3c3468"))
	gradient.set_color(1, Color("241d48"))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 4
	texture.height = 64
	return texture

## ゲージ/スロットの外枠(暗いvoid-deep地に細いbronze-dark枠)。
static func track_style(border_color: Color = BRONZE_DARK, bg: Color = VOID_DEEP) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style

## セグメント/ピップ1マスぶんの単色StyleBox(グラデーションは使わず、明るい方の色を
## そのまま塗ることで「発光しているマス」を表現する。小さいサイズではぼかしの有無が
## ほぼ判別できないため、パネル外周の柔らかいグローとは別手法で割り切る)。
static func segment_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	return style
