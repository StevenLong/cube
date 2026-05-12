shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec2 wave_origins[8];
uniform vec2 wave_half_extents[8];
uniform float wave_radii[8];
uniform float wave_alphas[8];

uniform vec2 footprint_positions[64];
uniform float footprint_alphas[64];

uniform vec2 cone_origin;
uniform vec2 cone_dir;
uniform float cone_half_angle_cos;
uniform float cone_radius;
uniform vec3 cone_color;
uniform float cone_alpha;

void fragment() {
	// Grid
	vec2 coord = UV * 30.0 + vec2(0.5);
	vec2 wrapped = fract(coord);
	float lw = 0.08;
	float gx = step(1.0 - lw, wrapped.x) + step(wrapped.x, lw);
	float gy = step(1.0 - lw, wrapped.y) + step(wrapped.y, lw);
	float on_line = clamp(gx + gy, 0.0, 1.0);
	vec3 grid_color = mix(vec3(0.06, 0.06, 0.12), vec3(0.0, 1.0, 1.0), on_line);

	// Noise waves: each emanates from a rectangular footprint
	vec2 world_xz = UV * 30.0 - vec2(15.0);
	vec2 cell_center = round(world_xz);
	float wave_total = 0.0;
	for (int i = 0; i < 8; i++) {
		vec2 d = max(vec2(0.0), abs(cell_center - wave_origins[i]) - wave_half_extents[i]);
		float cell_dist = length(d);
		float r = wave_radii[i];
		float in_range = 1.0 - smoothstep(r - 0.5, r + 0.5, cell_dist);
		wave_total = clamp(wave_total + in_range * wave_alphas[i], 0.0, 1.0);
	}

	vec3 with_waves = mix(grid_color, vec3(0.9, 0.55, 0.0), wave_total * 0.55);

	// Vision cone overlay: tinted sector from the enemy with soft edges and
	// distance falloff. cone_radius == 0 disables (default state).
	float cone_intensity = 0.0;
	if (cone_radius > 0.01) {
		vec2 to_cone = world_xz - cone_origin;
		float cone_dist = length(to_cone);
		if (cone_dist > 0.05 && cone_dist < cone_radius) {
			float cone_dot = dot(to_cone / cone_dist, cone_dir);
			if (cone_dot >= cone_half_angle_cos) {
				float dist_fade = 1.0 - cone_dist / cone_radius;
				float edge_fade = smoothstep(
					cone_half_angle_cos,
					cone_half_angle_cos + 0.05,
					cone_dot
				);
				cone_intensity = cone_alpha * dist_fade * edge_fade;
			}
		}
	}
	vec3 with_cone = mix(with_waves, cone_color, cone_intensity);

	// Ink footprints: small dark blobs at deposited cells
	float ink_total = 0.0;
	for (int i = 0; i < 64; i++) {
		float d = length(world_xz - footprint_positions[i]);
		float in_range = 1.0 - smoothstep(0.25, 0.4, d);
		ink_total = clamp(ink_total + in_range * footprint_alphas[i], 0.0, 1.0);
	}

	ALBEDO = mix(with_cone, vec3(0.1, 0.15, 0.3), ink_total);
}
