shader_type canvas_item;
render_mode unshaded;
uniform int kind = 2;
uniform vec2 region_origin = vec2(20.0, 598.0);
uniform vec2 region_size = vec2(600.0, 604.0);


varying vec4 sprite_tint;

void vertex() {
    sprite_tint = COLOR;
}

void fragment() {
    // AtlasTexture passes atlas UVs to the shader, so artwork masks use
    // coordinates relative to this landmark's cropped region.
    vec2 local_uv = (UV / TEXTURE_PIXEL_SIZE - region_origin) / region_size;
    vec2 sampled_local = local_uv;
    float t = TIME;
    float light = 1.0;
    if (kind == 2) {
        vec2 q = (local_uv - vec2(0.495, 0.684)) / vec2(0.165, 0.157);
        if (dot(q, q) < 1.0 && local_uv.y < 0.755) {
            sampled_local.x += sin(local_uv.y * 85.0 - t * 10.0) / region_size.x;
            sampled_local.y += sin(local_uv.x * 75.0 + t * 7.0) / region_size.y;
            light += 0.12 * sin(t * 12.0 + local_uv.x * 40.0);
        }
    } else if (kind == 3) {
        bool waterfall = (local_uv.x > 0.69 && local_uv.x < 0.82 && local_uv.y > 0.13 && local_uv.y < 0.67)
            || (local_uv.x > 0.12 && local_uv.x < 0.20 && local_uv.y > 0.44 && local_uv.y < 0.64)
            || (local_uv.x > 0.46 && local_uv.x < 0.54 && local_uv.y > 0.49 && local_uv.y < 0.65);
        bool pool = local_uv.x > 0.12 && local_uv.x < 0.92 && local_uv.y > 0.56 && local_uv.y < 0.70;
        if (waterfall) {
            sampled_local.y += sin(t * 8.0 + local_uv.y * 80.0) / region_size.y;
            light += 0.11 * sin(t * 7.0 - local_uv.y * 60.0);
        } else if (pool) {
            sampled_local.x += sin(local_uv.y * 90.0 - t * 5.0) / region_size.x;
            light += 0.07 * sin(t * 8.0 + local_uv.x * 55.0);
        }
    }
    vec2 sample_pixel = region_origin + clamp(floor(sampled_local * region_size), vec2(0.0), region_size - vec2(1.0)) + vec2(0.5);
    vec2 sample_uv = sample_pixel * TEXTURE_PIXEL_SIZE;
    COLOR = texture(TEXTURE, sample_uv) * sprite_tint;
    COLOR.rgb *= light;
}
