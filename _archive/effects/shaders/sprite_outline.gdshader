shader_type canvas_item;
// 透明ピクセルの周囲8方向をサンプリングし、隣接する不透明ピクセルがあれば
// outline_colorで塗る、一般的なスプライト用アウトラインシェーダー。
// ボス(EnemyBasic._apply_boss_outline)のAnimatedSprite2D.materialに適用し、
// 「これはボスだ」と一目で分かる赤い縁取りを付けるために使う。

uniform vec4 outline_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float outline_width : hint_range(0.0, 8.0) = 2.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (tex_color.a > 0.5) {
		COLOR = tex_color;
	} else {
		vec2 texel = TEXTURE_PIXEL_SIZE * outline_width;
		float neighbor_alpha = 0.0;
		neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(-texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, -texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(-texel.x, -texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, -texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(-texel.x, texel.y)).a;

		if (neighbor_alpha > 0.0) {
			COLOR = vec4(outline_color.rgb, outline_color.a);
		} else {
			COLOR = tex_color;
		}
	}
}
