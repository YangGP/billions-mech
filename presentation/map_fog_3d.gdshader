shader_type spatial;
render_mode cull_disabled;

uniform sampler2D fog_cells : filter_nearest, repeat_disable;
uniform vec2 map_dimensions = vec2(1.0);
uniform bool ground_grid = false;
varying vec2 map_position;

void vertex() {
	map_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float state = texture(fog_cells, map_position / map_dimensions).r;
	// 黑雾区域不写入颜色/深度，避免灯光把地图轮廓或高模型照出来。
	if (state < 0.25) {
		discard;
	}
	vec3 base = COLOR.rgb;
	if (ground_grid) {
		vec2 cell = fract(map_position);
		float border = step(0.975, max(cell.x, cell.y));
		base = mix(base, vec3(0.28, 0.38, 0.39), border * 0.45);
	}
	float visible = step(0.75, state);
	ALBEDO = base * mix(0.28, 1.0, visible);
	ROUGHNESS = 0.95;
}
