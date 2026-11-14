shader_type spatial;
render_mode cull_back, specular_disabled;
// Asphalt with painted markings, computed from UV in metres (UV.x across,
// UV.y along). The threshold at v = size.y is the START end (aircraft face -Z);
// numbers read upright from either approach.

uniform vec2 size_m = vec2(60.0, 3400.0);

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

// Seven-segment digit in a 4 x 9 m cell (x across, y up the glyph).
float digit(vec2 p, int d) {
	// segments: a top, b upper right, c lower right, d bottom, e lower left, f upper left, g middle
	int mask = 0;
	if (d == 1) { mask = 6; }
	else if (d == 3) { mask = 1 + 2 + 4 + 8 + 64; }
	else if (d == 6) { mask = 1 + 4 + 8 + 16 + 32 + 64; }
	else if (d == 8) { mask = 127; }
	float t = 0.6;
	float r = 0.0;
	vec2 q = p;
	if ((mask & 1) != 0) { r = max(r, step(abs(q.x - 2.0), 2.0) * step(abs(q.y - 8.4), t)); }
	if ((mask & 2) != 0) { r = max(r, step(abs(q.x - 3.6), t) * step(abs(q.y - 6.5), 2.2)); }
	if ((mask & 4) != 0) { r = max(r, step(abs(q.x - 3.6), t) * step(abs(q.y - 2.5), 2.2)); }
	if ((mask & 8) != 0) { r = max(r, step(abs(q.x - 2.0), 2.0) * step(abs(q.y - 0.6), t)); }
	if ((mask & 16) != 0) { r = max(r, step(abs(q.x - 0.4), t) * step(abs(q.y - 2.5), 2.2)); }
	if ((mask & 32) != 0) { r = max(r, step(abs(q.x - 0.4), t) * step(abs(q.y - 6.5), 2.2)); }
	if ((mask & 64) != 0) { r = max(r, step(abs(q.x - 2.0), 2.0) * step(abs(q.y - 4.5), t)); }
	return r;
}

float number(vec2 p, int left, int right) {
	// p.x across from the left of a 11 m wide group, p.y up the glyph.
	float a = digit(p - vec2(0.0, 0.0), left);
	float b = digit(p - vec2(6.0, 0.0), right);
	return max(a, b) * step(0.0, p.y) * step(p.y, 9.0);
}

void fragment() {
	vec2 m = UV * size_m;
	float across = m.x - size_m.x * 0.5;
	float n1 = vnoise(m * vec2(0.3, 0.05));
	float n2 = vnoise(m * 0.9);
	vec3 col = vec3(0.13, 0.135, 0.14) * (0.88 + 0.2 * n1 + 0.08 * n2);
	// Slab joints every 75 m.
	col *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.12, abs(fract(m.y / 75.0 + 0.5) - 0.5) * 75.0));
	float paint = 0.0;
	paint = max(paint, step(size_m.x * 0.5 - 1.6, abs(across)) * step(abs(across), size_m.x * 0.5 - 0.7));
	paint = max(paint, step(abs(across), 0.45) * step(mod(m.y, 50.0), 30.0));
	float end_dist = min(m.y, size_m.y - m.y);
	float keys = step(6.0, end_dist) * step(end_dist, 36.0) * step(mod(across + 1.5, 3.6), 1.8)
			* step(abs(across), size_m.x * 0.5 - 3.0);
	paint = max(paint, keys);
	float tdz = step(mod(end_dist - 150.0, 150.0), 22.0) * step(150.0, end_dist) * step(end_dist, 620.0)
			* step(4.0, abs(across)) * step(abs(across), 9.0) * (1.0 - step(299.0, end_dist) * step(end_dist, 323.0));
	paint = max(paint, tdz);
	// Aiming point.
	paint = max(paint, step(300.0, end_dist) * step(end_dist, 345.0) * step(10.0, abs(across)) * step(abs(across), 16.0));
	// Numbers: far end of the plane (m.y = 0) reads 18, near end reads 36.
	float num = 0.0;
	if (m.y > size_m.y * 0.5) {
		// Start end, aircraft look toward -Z (decreasing m.y); glyph up = decreasing m.y.
		num = number(vec2(across + 5.5, size_m.y - 46.0 - m.y), 3, 6);
	} else {
		vec2 g = vec2(5.5 - across, m.y - 46.0);
		num = number(g, 1, 8);
	}
	paint = max(paint, num);
	// Rubber in the touchdown zones and a few tyre marks.
	float rub_z = smoothstep(80.0, 150.0, end_dist) * (1.0 - smoothstep(420.0, 560.0, end_dist));
	float rub = vnoise(vec2(m.x * 0.8, m.y * 0.05)) * rub_z * (1.0 - smoothstep(6.0, 13.0, abs(across)));
	col *= 1.0 - 0.45 * smoothstep(0.35, 0.8, rub);
	ALBEDO = mix(col, vec3(0.86, 0.86, 0.82) * (0.92 + 0.08 * n2), paint);
	ROUGHNESS = 0.9;
}
