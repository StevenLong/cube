shader_type spatial;
render_mode unshaded;

// World-space, per-tile rendering. Single material shared by every FloorTile,
// so uniforms still get pushed once per frame. Top faces show the full pipeline
// (grid, waves, footprints, LoS-gated cone, fog); side faces show a flat darker
// color so the slab edge reads against the void background.

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

uniform vec2 player_xz;
uniform vec2 wall_mins[16];
uniform vec2 wall_maxs[16];
uniform int wall_count;
uniform float dark_factor = 0.25;

uniform vec3 top_base_color : source_color = vec3(0.06, 0.06, 0.12);
uniform vec3 side_color : source_color = vec3(0.04, 0.04, 0.08);
uniform vec3 grid_line_color : source_color = vec3(0.0, 1.0, 1.0);

varying vec3 v_world_pos;
varying vec3 v_world_norm;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 2D segment-vs-AABB slab test. Returns true if the segment from a to b passes
// through any wall AABB in wall_mins/wall_maxs.
bool segment_blocked(vec2 a, vec2 b) {
	vec2 dir = b - a;
	for (int i = 0; i < wall_count; i++) {
		vec2 wmin = wall_mins[i];
		vec2 wmax = wall_maxs[i];
		float t_near = 0.0;
		float t_far = 1.0;
		bool miss = false;
		for (int j = 0; j < 2; j++) {
			float d = dir[j];
			float p = a[j];
			if (abs(d) < 1e-6) {
				if (p < wmin[j] || p > wmax[j]) {
					miss = true;
					break;
				}
			} else {
				float t1 = (wmin[j] - p) / d;
				float t2 = (wmax[j] - p) / d;
				if (t1 > t2) { float tmp = t1; t1 = t2; t2 = tmp; }
				t_near = max(t_near, t1);
				t_far = min(t_far, t2);
			}
		}
		if (!miss && t_near <= t_far && t_near < 1.0 && t_far > 0.0) {
			return true;
		}
	}
	return false;
}

void fragment() {
	// Side / bottom faces get a flat darker color. Threshold .5 separates the
	// +Y top from every other cardinal face.
	if (v_world_norm.y < 0.5) {
		ALBEDO = side_color;
	} else {
		vec2 world_xz = v_world_pos.xz;

		// Grid: thin cyan lines on integer cell boundaries. Cell centers sit at
		// integer XZ, so fract(x + 0.5) ramps 0..1 across one cell.
		vec2 cell_uv = fract(world_xz + vec2(0.5));
		float lw = 0.08;
		float gx = step(1.0 - lw, cell_uv.x) + step(cell_uv.x, lw);
		float gy = step(1.0 - lw, cell_uv.y) + step(cell_uv.y, lw);
		float on_line = clamp(gx + gy, 0.0, 1.0);
		vec3 grid_color = mix(top_base_color, grid_line_color, on_line);

		// Noise waves: each emanates from a rectangular footprint.
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

		// Player line-of-sight: 1 if straight line from player to fragment clears
		// every wall AABB, else 0.
		float visibility = segment_blocked(player_xz, world_xz) ? 0.0 : 1.0;

		// Vision cone overlay: tinted sector from the enemy with soft edges and
		// distance falloff. cone_radius == 0 disables. Gated on visibility so the
		// cone only renders on ground the player can see.
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
		vec3 with_cone = mix(with_waves, cone_color, cone_intensity * visibility);

		// Ink footprints: each print is a soft-edge tile centered on its cell, so
		// adjacent per-cell prints tile into a continuous oblong.
		float ink_total = 0.0;
		for (int i = 0; i < 64; i++) {
			vec2 d = max(vec2(0.0), abs(world_xz - footprint_positions[i]) - vec2(0.4));
			float dist = length(d);
			float in_range = 1.0 - smoothstep(0.0, 0.1, dist);
			ink_total = clamp(ink_total + in_range * footprint_alphas[i], 0.0, 1.0);
		}

		vec3 final_color = mix(with_cone, vec3(0.1, 0.15, 0.3), ink_total);
		ALBEDO = final_color * mix(dark_factor, 1.0, visibility);
	}
}
