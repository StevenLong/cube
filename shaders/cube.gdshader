shader_type spatial;

// The player cube's surface, treated as six independent "screens". Stays SHADED
// (Godot lights ALBEDO as before), but colours each face by its object-space
// normal so state can be shown per-face. First use: ink. face_ink[i] flags the
// mesh-local face i as inked; the player maps logical face marks to mesh faces
// via its orientation and pushes this array. Later: expressions, debuff/timer
// readouts, etc. Face index matches the player's FACE_* ids:
//   0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z.

uniform vec3 base_color : source_color = vec3(0.9, 0.9, 0.9);
uniform vec3 cover_color : source_color = vec3(0.4, 0.4, 0.45);
uniform vec3 ink_color : source_color = vec3(0.25, 0.35, 0.55);
uniform float blend_phase = 0.0;       // 0 exposed -> 1 fully blended into cover
uniform float face_ink[6];             // per mesh-local face: 1 = inked

// Dodge "cooldown as heat": a dodge leaves the edges glowing hot (red); the heat
// dissipates from the corners inward, retreating to the middle of each edge as it
// cools, then a quick green edge blink signals ready. Emissive + understated.
uniform vec3 cube_half = vec3(0.5);    // half-extent per axis, so the edge math holds when extended
uniform float dodge_heat = 0.0;        // 1 just-dodged (edges fully hot) -> 0 cooled
uniform float dodge_flash = 0.0;       // brief 1 -> 0 green "ready" pulse
uniform vec3 heat_color : source_color = vec3(1.0, 0.25, 0.05);
uniform vec3 ready_color : source_color = vec3(0.2, 1.0, 0.35);
uniform float edge_band = 0.16;        // how thick the glowing edge strip is (normalized)
uniform float glow_strength = 1.0;
uniform float edge_darken = 0.1;       // how dark the glowing edge groove goes (so the colour reads on a white cube too)

varying vec3 v_obj_normal;
varying vec3 v_obj_pos;

void vertex() {
	v_obj_normal = NORMAL;   // object space: fixed to the mesh face, rolls with the cube
	v_obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(v_obj_normal);
	int face;
	if (n.x > 0.5) { face = 0; }
	else if (n.x < -0.5) { face = 1; }
	else if (n.y > 0.5) { face = 2; }
	else if (n.y < -0.5) { face = 3; }
	else if (n.z > 0.5) { face = 4; }
	else { face = 5; }
	vec3 col = mix(base_color, ink_color, face_ink[face]);
	ALBEDO = mix(col, cover_color, blend_phase);   // blend fades the whole cube (ink included) into cover

	// Edge-heat glow. q is the surface point normalized to [0,1] per axis: the
	// largest component (~1) is the face axis, the second-largest tells us how
	// close to an EDGE we are, and the smallest is the position ALONG that edge
	// (0 at the middle, 1 at a corner). Heat covers along-edge positions below
	// dodge_heat, so it retreats from the corners to the middle as the cube cools.
	vec3 q = clamp(abs(v_obj_pos) / max(cube_half, vec3(0.0001)), 0.0, 1.0);
	float lo = min(q.x, min(q.y, q.z));
	float hi = max(q.x, max(q.y, q.z));
	float mid = (q.x + q.y + q.z) - lo - hi;
	float edge = smoothstep(1.0 - edge_band, 1.0, mid);
	float heat = (1.0 - smoothstep(dodge_heat, dodge_heat + 0.06, lo)) * step(0.001, dodge_heat);
	float red_amt = edge * heat;
	float green_amt = edge * dodge_flash;
	float glow_amt = clamp(red_amt + green_amt, 0.0, 1.0);
	// Darken the glowing edge into a groove FIRST, so the emitted colour reads with
	// contrast on any face colour (a red glow on a bright white cube otherwise just
	// looks faintly pink). Then add the emission: the edge becomes a hot channel.
	ALBEDO = mix(ALBEDO, ALBEDO * edge_darken, glow_amt);
	EMISSION = (heat_color * red_amt + ready_color * green_amt) * glow_strength;
}
