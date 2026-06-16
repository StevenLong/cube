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

// Fail-state "broken screen" expression: when >= 0, the faces show this pattern
// (a fail readout) instead of the normal cube. The player picks one at random on
// a fail and pushes the index. Add patterns in expr_color and bump EXPRESSION_COUNT.
uniform int expression = -1;

varying vec3 v_obj_normal;
varying vec3 v_obj_pos;

void vertex() {
	v_obj_normal = NORMAL;   // object space: fixed to the mesh face, rolls with the cube
	v_obj_pos = VERTEX;
}

vec3 expr_color(int e, vec2 uv) {
	if (e == 0) {
		// Missing texture: magenta/black checker.
		vec2 c = floor(uv * 4.0);
		return mod(c.x + c.y, 2.0) > 0.5 ? vec3(0.85, 0.0, 0.85) : vec3(0.02, 0.0, 0.02);
	} else if (e == 1) {
		// Red X error.
		float d = min(abs(uv.x - uv.y), abs(uv.x - (1.0 - uv.y)));
		float line = 1.0 - smoothstep(0.06, 0.12, d);
		return mix(vec3(0.03, 0.0, 0.0), vec3(1.0, 0.12, 0.08), line);
	} else if (e == 2) {
		// Damaged-display colour bars: random horizontal bands with a glitch jitter.
		float row = floor(uv.y * 7.0);
		float h = fract(sin(row * 12.9898) * 43758.5453);
		vec3 b = vec3(fract(h * 3.0), fract(h * 7.0), fract(h * 13.0));
		float jitter = step(0.5, fract(uv.x * 4.0 + h * 10.0));
		return b * mix(0.4, 1.0, jitter);
	}
	// Sad face on a blue screen (BSOD-ish).
	vec3 bg = vec3(0.06, 0.12, 0.5);
	float eyes = 1.0 - smoothstep(0.05, 0.07, length(uv - vec2(0.37, 0.62)));
	eyes += 1.0 - smoothstep(0.05, 0.07, length(uv - vec2(0.63, 0.62)));
	float fy = 0.32 + 1.4 * (uv.x - 0.5) * (uv.x - 0.5);   // upward-curving (sad) mouth
	float mouth = (1.0 - smoothstep(0.03, 0.055, abs(uv.y - fy))) * step(0.3, uv.x) * step(uv.x, 0.7);
	return mix(bg, vec3(0.95), clamp(eyes + mouth, 0.0, 1.0));
}

void fragment() {
	if (expression >= 0) {
		// Fail expression takes over the whole face as a self-lit "screen".
		vec3 an = abs(normalize(v_obj_normal));
		vec2 uv;
		if (an.x > 0.5) { uv = v_obj_pos.zy / cube_half.zy; }
		else if (an.y > 0.5) { uv = v_obj_pos.xz / cube_half.xz; }
		else { uv = v_obj_pos.xy / cube_half.xy; }
		uv = uv * 0.5 + 0.5;
		vec3 pat = expr_color(expression, uv);
		ALBEDO = pat * 0.2;
		EMISSION = pat;
	} else {
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
		// Darken the glowing edge into a groove FIRST, so the emitted colour reads
		// with contrast on any face colour (a red glow on a bright white cube
		// otherwise looks faintly pink). Then add the emission: a hot channel.
		ALBEDO = mix(ALBEDO, ALBEDO * edge_darken, glow_amt);
		EMISSION = (heat_color * red_amt + ready_color * green_amt) * glow_strength;
	}
}
