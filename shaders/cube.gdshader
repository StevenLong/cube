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

varying vec3 v_obj_normal;

void vertex() {
	v_obj_normal = NORMAL;   // object space: fixed to the mesh face, rolls with the cube
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
}
