shader_type spatial;
render_mode unshaded;

// Wall variant of the grid look (see grid_ground.gdshader). STATIC only: wall
// tops draw the same per-cell world-space grid as the floor but with a thin
// line and no gradient halo, and none of the floor's dynamic overlays (waves,
// cones, footprints, LoS fog), those are gameplay readouts that belong on the
// ground plane. Side faces match the floor slab sides exactly (flat dark color
// plus thin vertical corner lines) so a wall reads as a risen floor tile.

uniform vec3 top_color : source_color = vec3(0.08, 0.08, 0.15);
uniform vec3 side_color : source_color = vec3(0.04, 0.04, 0.08);
uniform vec3 grid_line_color : source_color = vec3(0.0, 1.0, 1.0);

// Top-face cell line: thin core, short falloff, modest glow (no halo gradient).
uniform float line_core_width : hint_range(0.0, 0.05) = 0.008;
uniform float line_falloff_width : hint_range(0.0, 0.5) = 0.06;
uniform float line_falloff_exp : hint_range(1.0, 10.0) = 4.0;
uniform float line_glow_strength : hint_range(0.0, 1.5) = 0.5;

// Side-face vertical-corner line: pure thin core, NO glow. These match the
// floor's MATERIAL INSTANCE values (grid_ground_material.tres), not the floor
// shader's defaults, which are glow-heavy and never used in game.
uniform float side_line_core_width : hint_range(0.0, 0.05) = 0.01;
uniform float side_line_falloff_width : hint_range(0.0, 0.5) = 0.0;
uniform float side_line_falloff_exp : hint_range(1.0, 10.0) = 1.0;
uniform float side_line_glow_strength : hint_range(0.0, 1.5) = 0.0;

// Infinite-floor fade: wall column sides dissolve to the void colour as they
// descend (matches grid_ground.gdshader). void_color must match the background.
uniform vec3 void_color : source_color = vec3(0.03, 0.03, 0.04);
uniform float fade_start = -0.5;
uniform float fade_end = -45.0;

varying vec3 v_world_pos;
varying vec3 v_world_norm;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float edge_line_intensity(float d, float core_w, float falloff_w, float falloff_exp, float glow_strength) {
	float core = 1.0 - smoothstep(0.0, max(core_w, 0.0001), d);
	float glow_t = clamp(d / max(falloff_w, 0.0001), 0.0, 1.0);
	float glow = pow(1.0 - glow_t, falloff_exp) * glow_strength;
	return max(core, glow);
}

void fragment() {
	if (v_world_norm.y < 0.5) {
		// Side / bottom face: vertical corner lines only, like the floor slabs.
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
		// Top face: thin per-cell grid lines, nothing else.
		vec2 cell_uv = fract(v_world_pos.xz + vec2(0.5));
		vec2 edge_dist_xy = min(cell_uv, vec2(1.0) - cell_uv);
		float edge_d = min(edge_dist_xy.x, edge_dist_xy.y);
		float line_intensity = edge_line_intensity(
			edge_d,
			line_core_width,
			line_falloff_width,
			line_falloff_exp,
			line_glow_strength
		);
		ALBEDO = mix(top_color, grid_line_color, line_intensity);
	}
}
