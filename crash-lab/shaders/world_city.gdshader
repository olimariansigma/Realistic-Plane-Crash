shader_type spatial;
render_mode cull_back, specular_disabled;
// City ground: street grid, lane markings, crossings, pavements and lots.
// block_map (one texel per block): R = lot type (0 grass, 1 concrete, 2 park).

uniform sampler2D block_map : filter_nearest, repeat_disable;
uniform vec2 origin = vec2(900.0, -3800.0);
uniform vec2 grid = vec2(22.0, 27.0);
uniform float pitch = 110.0;
uniform float road_w = 14.0;

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
	vec2 rel = vec2(wp.x - origin.x, origin.y - wp.y);
	vec2 span = grid * pitch;
	vec2 cell = floor(rel / pitch);
	vec2 l = rel - cell * pitch;
	float px = max(max(fwidth(wp.x), fwidth(wp.y)), 0.01);
	float n = vnoise(wp * 0.08);
	bool in_x = l.y < road_w;  // road running along X
	bool in_z = l.x < road_w;  // road running along Z
	vec3 col;
	if (in_x || in_z) {
		col = vec3(0.13, 0.13, 0.14) * (0.88 + 0.24 * n);
		bool inter = in_x && in_z;
		if (!inter) {
			float across = in_x ? l.y - road_w * 0.5 : l.x - road_w * 0.5;
			float along = in_x ? l.x : l.y;
			float dash = step(mod(along, 8.0), 4.0);
			col = mix(col, vec3(0.85), line(abs(across), 0.1, px) * dash);
			col = mix(col, vec3(0.75), line(abs(abs(across) - (road_w * 0.5 - 0.6)), 0.09, px));
			// Zebra crossing just beyond each junction.
			float zone = step(along, 19.0) * step(14.0, along);
			float stripe = step(mod(across + 7.0, 1.7), 0.85);
			col = mix(col, vec3(0.8), zone * stripe * (1.0 - smoothstep(0.6, 2.0, px)) * 0.9);
		}
	} else {
		float pv_x = min(l.x - road_w, pitch - l.x);
		float pv_y = min(l.y - road_w, pitch - l.y);
		float edge = min(pv_x, pv_y);
		if (edge < 3.0) {
			float joint = line(abs(fract(wp.x / 1.5 + wp.y / 1.5) - 0.5) * 1.5, 0.02, px) * 0.0;
			col = vec3(0.56, 0.56, 0.54) * (0.92 + 0.12 * n);
			col *= 1.0 - 0.2 * line(edge, 0.12, px) - joint;
		} else {
			vec2 uvb = (cell + 0.5) / grid;
			float t = floor(texture(block_map, uvb).r * 255.0 / 64.0 + 0.5);
			vec2 b = l - (road_w + 3.0);
			float bs = pitch - road_w - 6.0;
			if (t < 0.5) {
				col = vec3(0.24, 0.38, 0.16) * (0.85 + 0.3 * vnoise(wp * 0.3));
			} else if (t < 1.5) {
				col = vec3(0.46, 0.46, 0.45) * (0.9 + 0.2 * n);
			} else {
				col = vec3(0.2, 0.4, 0.15) * (0.8 + 0.4 * vnoise(wp * 0.25));
				float p1 = abs(b.x - b.y) * 0.7071;
				float p2 = abs(b.x + b.y - bs) * 0.7071;
				float path = max(line(p1, 1.2, px), line(p2, 1.2, px));
				col = mix(col, vec3(0.7, 0.62, 0.45), path);
				float pond = 1.0 - smoothstep(7.0, 8.0, length(b - bs * 0.5));
				col = mix(col, vec3(0.2, 0.42, 0.55), pond);
			}
		}
	}
	// Opaque (a blended pass this size is costly on phone GPUs): the edge
	// fades into the grass colour instead of into transparency.
	float edge_d = min(min(rel.x, span.x - rel.x), min(rel.y, span.y - rel.y));
	ALBEDO = mix(vec3(0.3, 0.46, 0.18), col, smoothstep(0.0, 80.0, edge_d));
	ROUGHNESS = 0.95;
}
