shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec2 wave_origins[8];
uniform float wave_radii[8];
uniform float wave_alphas[8];

void fragment() {
	// Grid
	vec2 coord = UV * 20.0 + vec2(0.5);
	vec2 wrapped = fract(coord);
	float lw = 0.08;
	float gx = step(1.0 - lw, wrapped.x) + step(wrapped.x, lw);
	float gy = step(1.0 - lw, wrapped.y) + step(wrapped.y, lw);
	float on_line = clamp(gx + gy, 0.0, 1.0);
	vec3 grid_color = mix(vec3(0.06, 0.06, 0.12), vec3(0.0, 1.0, 1.0), on_line);

	// Noise waves
	vec2 world_xz = UV * 20.0 - vec2(10.0);
	vec2 cell_center = round(world_xz);
	float wave_total = 0.0;
	for (int i = 0; i < 8; i++) {
		float cell_dist = length(cell_center - wave_origins[i]);
		float r = wave_radii[i];
		float in_range = 1.0 - smoothstep(r - 0.5, r + 0.5, cell_dist);
		wave_total = clamp(wave_total + in_range * wave_alphas[i], 0.0, 1.0);
	}

	ALBEDO = mix(grid_color, vec3(0.9, 0.55, 0.0), wave_total * 0.55);
}
