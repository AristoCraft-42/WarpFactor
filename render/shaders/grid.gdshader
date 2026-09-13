shader_type canvas_item;
// Сетка тайлов и (опционально) границы чанков, рисуется одним прямоугольником на всю карту.
// Толщина линий считается в экранных пикселях через fwidth, поэтому не зависит от масштаба.

uniform float tile_size = 32.0;
uniform float chunk_tiles = 32.0;
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.22);
uniform vec4 chunk_color : source_color = vec4(0.98, 0.74, 0.18, 0.0);

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

float line_alpha(vec2 pos, float period, float width_px) {
	vec2 px = max(fwidth(pos), vec2(1e-4));
	vec2 dist = abs(fract(pos / period + 0.5) - 0.5) * period / px;
	return 1.0 - clamp(min(dist.x, dist.y) - width_px * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	float tile_line = line_alpha(world_pos, tile_size, 1.0);
	float chunk_line = line_alpha(world_pos, tile_size * chunk_tiles, 2.0) * chunk_color.a;
	vec4 col = vec4(line_color.rgb, line_color.a * tile_line);
	col = mix(col, vec4(chunk_color.rgb, 1.0), chunk_line);
	col.a = max(col.a, chunk_line);
	COLOR = col;
}
