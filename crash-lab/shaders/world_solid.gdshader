shader_type spatial;
render_mode cull_back;
// Merged airport geometry. COLOR = base colour, UV = metres along the face,
// UV2 = (style, parameter). Styles: 0 plain, 1 glass facade, 2 hangar door,
// 3 corrugated roof, 4 tank, 5 tower cab glass, 7 weathered concrete.

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

void fragment() {
	float st = floor(UV2.x + 0.5);
	vec3 col = COLOR.rgb;
	float rough = 0.85;
	float spec = 0.2;
	float px = max(max(fwidth(UV.x), fwidth(UV.y)), 0.001);
	if (st > 0.5 && st < 1.5) {
		float dx = abs(fract(UV.x / 3.0 + 0.5) - 0.5) * 3.0;
		float dy = abs(fract(UV.y / 4.0 + 0.5) - 0.5) * 4.0;
		float fr = max(line(dx, 0.07, px), line(dy, 0.09, px));
		vec3 gl = mix(vec3(0.10, 0.2, 0.3), vec3(0.5, 0.68, 0.84), 0.35 + 0.5 * smoothstep(0.0, 14.0, UV.y));
		gl *= 0.85 + 0.3 * hash21(floor(vec2(UV.x / 3.0, UV.y / 4.0)));
		col = mix(gl, vec3(0.55), fr);
		rough = mix(0.15, 0.6, fr);
		spec = mix(0.8, 0.2, fr);
	} else if (st > 1.5 && st < 2.5) {
		float d = abs(fract(UV.x / 5.0 + 0.5) - 0.5) * 5.0;
		float seam = line(d, 0.05, px);
		float top = line(abs(UV.y - 0.6), 0.3, px);
		col = col * (1.0 - 0.35 * seam);
		col = mix(col, vec3(0.9, 0.7, 0.1), top * 0.8);
		float rail = line(abs(UV.y - UV2.y), 0.15, px);
		col = mix(col, vec3(0.2), rail);
	} else if (st > 2.5 && st < 3.5) {
		float rib = 0.5 + 0.5 * sin(UV.x * 10.0);
		float k = 1.0 - smoothstep(0.1, 0.3, px);
		col *= 1.0 - 0.18 * rib * k;
		rough = 0.6;
		spec = 0.4;
	} else if (st > 3.5 && st < 4.5) {
		float ring = line(abs(fract(UV.y / 2.5 + 0.5) - 0.5) * 2.5, 0.04, px);
		float seam = line(abs(fract(UV.x / 5.0 + 0.5) - 0.5) * 5.0, 0.04, px);
		col *= 1.0 - 0.25 * max(ring, seam);
		col *= 0.92 + 0.12 * smoothstep(0.0, 14.0, UV.y);
		rough = 0.5;
	} else if (st > 4.5 && st < 5.5) {
		float dx = abs(fract(UV.x / 2.4 + 0.5) - 0.5) * 2.4;
		float fr = line(dx, 0.06, px);
		vec3 gl = mix(vec3(0.05, 0.12, 0.14), vec3(0.45, 0.62, 0.7), 0.3 + 0.6 * clamp(UV.y / 6.0, 0.0, 1.0));
		col = mix(gl, vec3(0.7), fr);
		rough = mix(0.1, 0.5, fr);
		spec = 0.9;
	} else if (st > 6.5) {
		float n = vnoise(vec2(UV.x * 1.3, UV.y * 0.1));
		col *= 0.86 + 0.2 * n;
		float slab = line(abs(fract(UV.y / 3.5 + 0.5) - 0.5) * 3.5, 0.05, px);
		col *= 1.0 - 0.2 * slab;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
