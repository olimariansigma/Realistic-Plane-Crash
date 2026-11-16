shader_type spatial;
render_mode cull_back, specular_disabled;
// Airport and road surfaces. COLOR.r*16 = kind, UV = (across, along) metres,
// UV2 = (width, length) of the strip.
// Kinds: 0 taxiway, 1 apron concrete, 2 road, 3 car park, 4 yellow paint,
// 5 white paint, 6 plain concrete, 7 gravel.

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

float line(float d, float hw, float px) {
	return clamp((hw - d) / px + 0.5, 0.0, 1.0) * min(1.0, 2.0 * hw / px);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float kind = floor(COLOR.r * 16.0 + 0.5);
	float across = UV.x - UV2.x * 0.5;
	float along = UV.y;
	float px = max(max(fwidth(UV.x), fwidth(UV.y)), 0.001);
	float n = vnoise(wp * 0.05);
	vec3 col = vec3(0.2);
	if (kind < 0.5) {
		col = vec3(0.17, 0.175, 0.18) * (0.88 + 0.24 * n);
		float hw = UV2.x * 0.5;
		col = mix(col, vec3(0.9, 0.72, 0.1), line(abs(across), 0.15, px));
		col = mix(col, vec3(0.9, 0.72, 0.1), line(abs(abs(across) - (hw - 0.8)), 0.12, px) * 0.9);
	} else if (kind < 1.5) {
		col = vec3(0.38, 0.38, 0.37) * (0.88 + 0.2 * n);
		float j = min(line(abs(fract(UV.x / 25.0 + 0.5) - 0.5) * 25.0, 0.04, px),
				1.0) + line(abs(fract(UV.y / 25.0 + 0.5) - 0.5) * 25.0, 0.04, px);
		col *= 1.0 - 0.25 * clamp(j, 0.0, 1.0);
		col *= 1.0 - 0.15 * smoothstep(0.62, 0.8, vnoise(wp * 0.4));
	} else if (kind < 2.5) {
		col = vec3(0.14, 0.14, 0.15) * (0.9 + 0.2 * n);
		float hw = UV2.x * 0.5;
		float dash = step(mod(along, 9.0), 4.5);
		col = mix(col, vec3(0.85), line(abs(across), 0.12, px) * dash);
		col = mix(col, vec3(0.8), line(abs(abs(across) - (hw - 0.5)), 0.1, px));
	} else if (kind < 3.5) {
		col = vec3(0.15, 0.15, 0.16) * (0.9 + 0.2 * n);
		float v = mod(along, 18.0);
		float stall = step(v, 5.5) + step(12.5, v);
		float l = line(abs(fract(UV.x / 2.6 + 0.5) - 0.5) * 2.6, 0.06, px) * stall;
		float rows = max(max(line(abs(v - 5.5), 0.06, px), line(abs(v - 12.5), 0.06, px)), line(min(v, 18.0 - v), 0.06, px));
		col = mix(col, vec3(0.75), max(l, rows));
	} else if (kind < 4.5) {
		col = vec3(0.92, 0.74, 0.1);
	} else if (kind < 5.5) {
		col = vec3(0.88);
	} else if (kind < 6.5) {
		col = vec3(0.55, 0.55, 0.53) * (0.9 + 0.2 * n);
	} else {
		col = vec3(0.5, 0.45, 0.36) * (0.85 + 0.3 * vnoise(wp * 0.7));
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
