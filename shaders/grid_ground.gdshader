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

uniform vec2 cone_origins[8];
uniform vec2 cone_dirs[8];
uniform float cone_half_angle_cos[8];
uniform float cone_radii[8];
uniform vec3 cone_colors[8];
uniform float cone_alphas[8];

// Echo pyramids: per-slot danger disc + live pulse front, drawn on the floor tiles.
uniform vec2 pyr_origins[4];
uniform float pyr_zone_radii[4];   // persistent danger radius (dim disc); 0 = inactive slot
uniform float pyr_pulse_radii[4];  // current expanding front radius; 0 = no live pulse
uniform float pyr_charge[4];       // 0..1 zone brighten during the charge tell / catch flash

uniform vec2 player_xz;
uniform vec2 wall_mins[64];
uniform vec2 wall_maxs[64];
uniform int wall_count;
uniform float dark_factor = 0.25;
// Player line-of-sight fog is OFF for base play (perfect vision). Kept here behind
// this flag for a future "blinded" debuff. Cones still clip on walls regardless.
uniform bool player_los_enabled = false;

uniform vec3 top_base_color : source_color = vec3(0.06, 0.06, 0.12);
uniform vec3 side_color : source_color = vec3(0.04, 0.04, 0.08);
uniform vec3 grid_line_color : source_color = vec3(0.0, 1.0, 1.0);

// Infinite-floor fade: the column SIDES dissolve to the void colour as they
// descend, so deep platforms read as plunging into nothing rather than ending at
// a visible bottom (which shows at steep near-top-down camera angles). void_color
// must match the WorldEnvironment background so the fade is seamless.
uniform vec3 void_color : source_color = vec3(0.03, 0.03, 0.04);
uniform float fade_start = -0.5;   // world y where the side fade begins
uniform float fade_end = -45.0;    // world y where the side is fully void (must be above FLOOR_DEPTH)

// Top-face edge line: thin bright core + power-curve glow halo. The glow
// drops fast at first (high exp) and lingers further than smoothstep would.
uniform float line_core_width : hint_range(0.0, 0.05) = 0.008;
uniform float line_falloff_width : hint_range(0.0, 0.5) = 0.3;
uniform float line_falloff_exp : hint_range(1.0, 10.0) = 4.0;
uniform float line_glow_strength : hint_range(0.0, 1.5) = 0.7;

// Side-face vertical-corner line: thinner core, glow-dominated. Lights up
// only the vertical edges where two side faces meet (the slab's corners),
// running from floor top down to the slab bottom.
uniform float side_line_core_width : hint_range(0.0, 0.05) = 0.002;
uniform float side_line_falloff_width : hint_range(0.0, 0.5) = 0.25;
uniform float side_line_falloff_exp : hint_range(1.0, 10.0) = 4.0;
uniform float side_line_glow_strength : hint_range(0.0, 1.5) = 0.8;

varying vec3 v_world_pos;
varying vec3 v_world_norm;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Dual core+glow intensity profile. The core is a hard smoothstep within
// core_width (the bright line itself); the glow is a power-curve falloff
// out to falloff_width (the lingering halo). Combined via max so neither
// component saturates the other.
float edge_line_intensity(float d, float core_w, float falloff_w, float falloff_exp, float glow_strength) {
	float core = 1.0 - smoothstep(0.0, max(core_w, 0.0001), d);
	float glow_t = clamp(d / max(falloff_w, 0.0001), 0.0, 1.0);
	float glow = pow(1.0 - glow_t, falloff_exp) * glow_strength;
	return max(core, glow);
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
	// Threshold .5 separates the +Y top from every other cardinal face.
	if (v_world_norm.y < 0.5) {
		// Side / bottom face. Light up just the vertical corner edges where
		// two side faces meet; ignore the horizontal top/bottom edges. The
		// relevant axis is whichever XZ axis is perpendicular to the face
		// normal (X face -> Z corners, Z face -> X corners).
		float perp_coord;
		if (abs(v_world_norm.x) > 0.5) {
			perp_coord = v_world_pos.z;
		} else {
			perp_coord = v_world_pos.x;
		}
		float perp_uv = fract(perp_coord + 0.5);
		float side_edge_d = min(perp_uv, 1.0 - perp_uv);
		float side_intensity = edge_line_intensity(
			side_edge_d,
			side_line_core_width,
			side_line_falloff_width,
			side_line_falloff_exp,
			side_line_glow_strength
		);
		vec3 side_albedo = mix(side_color, grid_line_color, side_intensity);
		float depth_fade = clamp((fade_start - v_world_pos.y) / (fade_start - fade_end), 0.0, 1.0);
		ALBEDO = mix(side_albedo, void_color, depth_fade);
	} else {
		vec2 world_xz = v_world_pos.xz;

		// Top face per-cell edge line: thin bright core plus power-curve glow
		// that drops fast at first and lingers far into the tile. Distance
		// edge_d is from this fragment to the nearest of the cell's four
		// edges (0 at edge, 0.5 at center).
		vec2 cell_uv = fract(world_xz + vec2(0.5));
		vec2 edge_dist_xy = min(cell_uv, vec2(1.0) - cell_uv);
		float edge_d = min(edge_dist_xy.x, edge_dist_xy.y);
		float line_intensity = edge_line_intensity(
			edge_d,
			line_core_width,
			line_falloff_width,
			line_falloff_exp,
			line_glow_strength
		);
		vec3 grid_color = mix(top_base_color, grid_line_color, line_intensity);

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

		// Player line-of-sight fog: OFF by default (perfect vision), so floor stays
		// fully lit and the whole level reads. Enable player_los_enabled for the
		// future "blinded" debuff to darken floor the player cannot see.
		float player_vis = 1.0;
		if (player_los_enabled) {
			player_vis = segment_blocked(player_xz, world_xz) ? 0.0 : 1.0;
		}

		// Vision cone overlays: one tinted sector per enemy, each in its own array
		// slot, so multiple cones coexist instead of stomping a single set of
		// uniforms. A slot with cone_radii[i] <= 0 is inactive. Where cones overlap
		// the strongest (highest intensity) wins the color so neither washes out.
		// Each cone is clipped on walls from the ENEMY's viewpoint, so the danger
		// sector stops at a wall instead of bleeding to the far side (accurate to
		// what the enemy can actually see). The wall test runs only for in-sector
		// pixels to keep the cost down.
		float cone_intensity = 0.0;
		vec3 cone_color = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			if (cone_radii[i] <= 0.01) {
				continue;
			}
			vec2 to_cone = world_xz - cone_origins[i];
			float cone_dist = length(to_cone);
			if (cone_dist > 0.05 && cone_dist < cone_radii[i]) {
				float cone_dot = dot(to_cone / cone_dist, cone_dirs[i]);
				if (cone_dot >= cone_half_angle_cos[i] && !segment_blocked(cone_origins[i], world_xz)) {
					float dist_fade = 1.0 - cone_dist / cone_radii[i];
					float edge_fade = smoothstep(
						cone_half_angle_cos[i],
						cone_half_angle_cos[i] + 0.05,
						cone_dot
					);
					float ci = cone_alphas[i] * dist_fade * edge_fade;
					if (ci > cone_intensity) {
						cone_intensity = ci;
						cone_color = cone_colors[i];
					}
				}
			}
		}
		vec3 with_cone = mix(with_waves, cone_color, cone_intensity);

		// Echo pyramids: a per-TILE danger indicator + an expanding scan, drawn on the floor
		// tiles. Distance is measured to the cell CENTRE (round(world_xz)) so each tile is a
		// uniform block. Two tiers: a tile whose centre is within the catch radius is FULL
		// colour (a ping catches you there -- matches enemy_pyramid's d <= radius test); a
		// tile the radius circle only clips (centre outside, but part of the tile inside) gets
		// a dimmer wash, so the disc still reads round at the edges. Floor-only, never void.
		vec2 pyr_cell = round(world_xz);
		float pyr_total = 0.0;   // per-tile danger area: full = catchable, dim = clipped fringe
		float pyr_scan = 0.0;    // per-tile scan front riding the live sweep
		for (int i = 0; i < 4; i++) {
			float zr = pyr_zone_radii[i];
			if (zr <= 0.01) { continue; }
			vec2 oc = pyr_origins[i] - pyr_cell;
			float cd = length(oc);                                          // centre distance
			float nearest = length(max(abs(oc) - vec2(0.5), vec2(0.0)));    // nearest point of the tile
			float tier = max(step(cd, zr), step(nearest, zr) * 0.6);        // 1 = centre in, 0.6 = only clipped
			float zone_a = mix(0.10, 0.35, pyr_charge[i]) * tier;
			pyr_total = clamp(pyr_total + zone_a, 0.0, 1.0);
			// Scan: a bright per-tile band at the expanding front (an outward sonar wave).
			float pr = pyr_pulse_radii[i];
			float front = (pr > 0.01) ? (1.0 - smoothstep(0.0, 1.0, abs(cd - pr))) * tier : 0.0;
			pyr_scan = clamp(pyr_scan + front, 0.0, 1.0);
		}
		vec3 with_pyr = mix(with_cone, vec3(0.32, 0.62, 1.0), pyr_total);
		with_pyr = mix(with_pyr, vec3(0.7, 0.95, 1.0), pyr_scan);

		// Ink footprints: each print is a soft-edge tile centered on its cell, so
		// adjacent per-cell prints tile into a continuous oblong.
		float ink_total = 0.0;
		for (int i = 0; i < 64; i++) {
			vec2 d = max(vec2(0.0), abs(world_xz - footprint_positions[i]) - vec2(0.4));
			float dist = length(d);
			float in_range = 1.0 - smoothstep(0.0, 0.1, dist);
			ink_total = clamp(ink_total + in_range * footprint_alphas[i], 0.0, 1.0);
		}

		vec3 final_color = mix(with_pyr, vec3(0.1, 0.15, 0.3), ink_total);
		ALBEDO = final_color * mix(dark_factor, 1.0, player_vis);
	}
}
