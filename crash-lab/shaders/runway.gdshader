shader_type spatial;
render_mode cull_back, specular_disabled;
// Asphalt with painted markings, computed from UV in metres (UV.x across,
// UV.y along). Uniforms carry the real size so markings keep their scale.

uniform vec2 size_m = vec2(60.0, 3400.0);

void fragment() {
	vec2 m = UV * size_m;
	float across = m.x - size_m.x * 0.5;
	vec3 col = vec3(0.13, 0.135, 0.14) * (0.92 + 0.08 * sin(m.y * 0.9) * sin(m.x * 1.3));
	float paint = 0.0;
	// Edge lines.
	paint = max(paint, step(size_m.x * 0.5 - 1.6, abs(across)) * step(abs(across), size_m.x * 0.5 - 0.7));
	// Dashed centreline: 30 m on, 20 m off.
	paint = max(paint, step(abs(across), 0.45) * step(mod(m.y, 50.0), 30.0));
	// Threshold piano keys at both ends.
	float end_dist = min(m.y, size_m.y - m.y);
	float keys = step(6.0, end_dist) * step(end_dist, 36.0) * step(mod(across + 1.5, 3.6), 1.8)
			* step(abs(across), size_m.x * 0.5 - 3.0);
	paint = max(paint, keys);
	// Touchdown zone bars.
	float tdz = step(mod(end_dist - 150.0, 150.0), 22.0) * step(150.0, end_dist) * step(end_dist, 620.0)
			* step(5.0, abs(across)) * step(abs(across), 11.0);
	paint = max(paint, tdz);
	ALBEDO = mix(col, vec3(0.86, 0.86, 0.82), paint);
	ROUGHNESS = 0.9;
}
