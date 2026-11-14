shader_type spatial;
render_mode cull_back;
// Lake: UV.x is 0 at the centre and 1 at the shore; sand band at the rim.

varying vec2 wp;

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
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float d = UV.x;
	float n = vnoise(wp * 0.25);
	float n2 = vnoise(wp * 0.9 + 5.0);
	vec3 deep = vec3(0.04, 0.17, 0.27);
	vec3 shallow = vec3(0.14, 0.4, 0.45);
	vec3 col = mix(deep, shallow, smoothstep(0.4, 0.92, d));
	col *= 0.9 + 0.2 * n;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, vec3(0.55, 0.7, 0.85), fres * 0.7);
	float sand = smoothstep(0.93 + 0.03 * n, 0.95 + 0.03 * n, d);
	col = mix(col, vec3(0.7, 0.63, 0.46) * (0.9 + 0.2 * n2), sand);
	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.95, sand);
	SPECULAR = mix(0.9, 0.1, sand);
	NORMAL = normalize(NORMAL + (1.0 - sand) * 0.05 * vec3(n - 0.5, 0.0, n2 - 0.5));
}
