shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D fog_cells : filter_nearest, repeat_disable;
uniform vec2 map_dimensions = vec2(1.0);
uniform vec4 preview_tint : source_color = vec4(0.45, 0.91, 0.82, 0.26);
varying vec2 map_position;

void vertex() {
	map_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float state = texture(fog_cells, map_position / map_dimensions).r;
	if (state < 0.25 || any(lessThan(map_position, vec2(0.0))) || any(greaterThanEqual(map_position, map_dimensions))) {
		discard;
	}
	ALBEDO = preview_tint.rgb;
	ALPHA = preview_tint.a;
}
