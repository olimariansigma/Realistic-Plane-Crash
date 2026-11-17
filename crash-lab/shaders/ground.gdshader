shader_type spatial;
render_mode cull_back, specular_disabled;
// Countryside from world position: a patchwork of fields with hedgerows,
// mown airfield grass, forest floor and fine near-field grain for speed cues.

uniform vec4 forests[16];
uniform int forest_count = 0;

varying vec2 wp;

float hash21(vec2 p) {
	// Wrap first: at kilometres from the origin the product loses precision
	// and the noise turns blocky.
	p = mod(p, 1024.0);
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

vec3 palette(float h) {
	vec3 c = vec3(0.25, 0.42, 0.14);
	c = mix(c, vec3(0.38, 0.52, 0.2), step(0.18, h));
	c = mix(c, vec3(0.72, 0.64, 0.3), step(0.36, h));
	c = mix(c, vec3(0.36, 0.26, 0.17), step(0.5, h));
	c = mix(c, vec3(0.17, 0.33, 0.12), step(0.64, h));
	c = mix(c, vec3(0.5, 0.5, 0.26), step(0.8, h));
	c = mix(c, vec3(0.3, 0.46, 0.18), step(0.92, h));
	return c;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = wp;
	float dcam = length(VERTEX);
	float pxm = max(fwidth(p.x), fwidth(p.y));
	vec2 warp = vec2(vnoise(p * 0.0023), vnoise(p * 0.0023 + 31.7)) * 140.0;
	vec2 pw = p + warp;
	vec2 big = floor(pw / 1400.0);
	float ang = hash21(big) * 3.14159;
	float cs = cos(ang);
	float sn = sin(ang);
	vec2 q = vec2(cs * pw.x - sn * pw.y, sn * pw.x + cs * pw.y);
	vec2 csz = vec2(240.0, 170.0) * (0.8 + 0.5 * hash21(big + 7.0));
	vec2 cell = q / csz;
	vec2 id = floor(cell) + big * 31.0;
	vec2 f = fract(cell);
	float h = hash21(id);
	vec3 col = palette(h);
	// Crop rows.
	float rang = hash21(id + 3.0) * 3.14159;
	float rows = sin(dot(q, vec2(cos(rang), sin(rang))) * 2.4);
	float rowfade = 1.0 - smoothstep(0.3, 1.2, pxm);
	col *= 1.0 + 0.07 * rows * rowfade;
	col *= 0.93 + 0.14 * vnoise(p * 0.004);
	// Hedgerows on field boundaries.
	vec2 ed = min(f, 1.0 - f) * csz;
	float e = min(ed.x, ed.y);
	float hw = 1.8;
	float hedge = clamp((hw - e) / max(pxm, 0.01) + 0.5, 0.0, 1.0);
	hedge *= 1.0 - smoothstep(10.0, 40.0, pxm);
	col = mix(col, vec3(0.1, 0.19, 0.08), hedge * 0.85);
	// Mown airfield grass.
	vec2 ad = vec2(abs(p.x - 130.0) - 520.0, abs(p.y + 1400.0) - 1950.0);
	float am = 1.0 - smoothstep(0.0, 140.0, max(ad.x, ad.y));
	vec3 mown = vec3(0.22, 0.36, 0.14) * (1.0 + 0.04 * step(0.5, fract(p.x / 30.0)));
	col = mix(col, mown, am);
	// Forest floor.
	for (int i = 0; i < 16; i++) {
		if (i >= forest_count) { break; }
		vec4 fo = forests[i];
		float d = length(p - fo.xy) / fo.z;
		col = mix(col, vec3(0.1, 0.2, 0.08), (1.0 - smoothstep(0.7, 1.0, d)) * fo.w * 0.7);
	}
	// Near-field grain.
	float near = 1.0 - smoothstep(30.0, 350.0, dcam);
	float g1 = vnoise(p * 0.7);
	float g2 = vnoise(p * 3.1);
	col *= 1.0 + near * (0.16 * (g1 - 0.5) + 0.2 * (g2 - 0.5));
	ALBEDO = col * 0.6;
	ROUGHNESS = 1.0;
}
