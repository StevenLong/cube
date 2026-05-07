shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	vec2 coord = UV * 20.0;
	vec2 wrapped = fract(coord);
	float lw = 0.04;
	float gx = step(1.0 - lw, wrapped.x) + step(wrapped.x, lw);
	float gy = step(1.0 - lw, wrapped.y) + step(wrapped.y, lw);
	float on_line = clamp(gx + gy, 0.0, 1.0);
	ALBEDO = mix(vec3(0.02, 0.02, 0.05), vec3(0.0, 0.75, 1.0), on_line);
}
