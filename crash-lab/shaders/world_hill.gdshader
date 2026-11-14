shader_type spatial;
render_mode cull_back, specular_disabled;
// Mountain shading by height and slope: grass, forest, rock, scree, snow.

varying vec3 wp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = vnoise(w0.xz * 0.006 + w0.y * 0.004);
	// Only ever pull inward so the mesh stays inside the convex collider.
	VERTEX.xz *= 1.0 - 0.06 * n;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float h = wp.y;
	float n1 = vnoise(wp.xz * 0.02);
	float n2 = vnoise(wp.xz * 0.12 + wp.y * 0.1);
	float slope = 1.0 - wn.y;
	vec3 grass = vec3(0.22, 0.32, 0.15);
	vec3 forest = vec3(0.1, 0.2, 0.09);
	vec3 rock = vec3(0.4, 0.37, 0.34);
	vec3 scree = vec3(0.52, 0.48, 0.42);
	vec3 snow = vec3(0.92, 0.94, 0.97);
	vec3 col = mix(grass, forest, smoothstep(120.0, 260.0, h + n1 * 80.0));
	float rock_m = smoothstep(260.0, 340.0, h + n1 * 100.0) + smoothstep(0.16, 0.28, slope + n2 * 0.06);
	col = mix(col, mix(rock, scree, n2), clamp(rock_m, 0.0, 1.0));
	col *= 0.85 + 0.3 * n2;
	float snow_m = smoothstep(380.0, 410.0, h + (n1 - 0.5) * 60.0 - slope * 120.0);
	col = mix(col, snow * (0.92 + 0.08 * n2), snow_m);
	ALBEDO = col * 0.72;
	ROUGHNESS = 1.0;
}
