shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	vec2 coord = UV * 20.0;
	vec2 wrapped = fract(coord);
	float lw = 0.08;
	float gx = step(1.0 - lw, wrapped.x) + step(wrapped.x, lw);
	float gy = step(1.0 - lw, wrapped.y) + step(wrapped.y, lw);
	float on_line = clamp(gx + gy, 0.0, 1.0);
	ALBEDO = mix(vec3(0.06, 0.06, 0.12), vec3(0.0, 1.0, 1.0), on_line);
}
