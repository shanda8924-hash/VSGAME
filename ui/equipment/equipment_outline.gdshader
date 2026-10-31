shader_type canvas_item;
uniform vec4 rarity_color : source_color = vec4(1.0);
float alpha_at(vec2 uv, float source_alpha) {
 if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
 return smoothstep(0.35, 0.85, source_alpha);
}
void fragment() {
 vec2 uv = (UV - vec2(0.06)) / 0.88;
 vec4 base = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
 base.a = alpha_at(uv, base.a);
 vec2 step_uv = TEXTURE_PIXEL_SIZE;
 float edge = 0.0;
 for (int x = -1; x <= 1; x++) {
  for (int y = -1; y <= 1; y++) {
   edge = max(edge, step(0.65, alpha_at(uv + vec2(float(x),float(y)) * step_uv, texture(TEXTURE, uv + vec2(float(x),float(y)) * step_uv).a)));
  }
 }
 COLOR = vec4(mix(rarity_color.rgb, base.rgb, base.a / max(max(base.a, edge), 0.0001)), max(base.a, edge));
}
