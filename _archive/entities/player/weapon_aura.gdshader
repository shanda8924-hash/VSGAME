shader_type canvas_item;

uniform vec4 rarity_color : source_color = vec4(0.42, 0.72, 0.55, 1.0);
uniform float rarity_rank : hint_range(0.0, 4.0) = 0.0;
uniform float aura_strength : hint_range(0.0, 1.0) = 0.3;
const float PADDING = 10.0;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
	VERTEX += (UV * 2.0 - 1.0) * PADDING;
}

float mask_at(vec2 uv, float alpha) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 0.0;
	return step(0.5, alpha);
}

void fragment() {
	vec4 modulation = vertex_tint;
	vec2 pixels = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 uv = (UV * (pixels + PADDING * 2.0) - PADDING) / pixels;
	vec4 base = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
	base.a = mask_at(uv, base.a);
	float pulse = 0.5 + 0.5 * sin(TIME * (5.0 + rarity_rank) + uv.x * 35.0 + uv.y * 11.0);
	float rise = 2.0 + rarity_rank * 0.7 + pulse * (2.0 + rarity_rank * 0.5);
	float wind = sin(TIME * 4.0 + uv.y * 20.0) * 1.4;
	float edge = 0.0;
	float flame = 0.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		vec2 direction = vec2(cos(angle), sin(angle));
		vec2 edge_uv = uv + direction * TEXTURE_PIXEL_SIZE;
		edge = max(edge, mask_at(edge_uv, texture(TEXTURE, edge_uv).a));
		vec2 flame_uv = uv + (direction * (1.5 + rarity_rank * 0.45) + vec2(wind, rise)) * TEXTURE_PIXEL_SIZE;
		flame = max(flame, mask_at(flame_uv, texture(TEXTURE, flame_uv).a));
	}
	float outline = edge * (1.0 - base.a);
	float aura = flame * (1.0 - edge) * aura_strength * (0.45 + pulse * 0.55);
	vec3 light = mix(rarity_color.rgb, vec3(1.0, 0.95, 0.84), pulse * 0.25);
	vec3 rgb = base.a > 0.0 ? base.rgb : (outline > 0.0 ? rarity_color.rgb : light);
	COLOR = vec4(rgb, max(base.a, max(outline, aura))) * modulation;
}
