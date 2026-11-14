shader_type spatial;
render_mode cull_back;
// Procedural facades for unit boxes drawn through one MultiMesh. Per instance:
// COLOR = base (wall) colour, INSTANCE_CUSTOM = (style, seed, roof type, band flag).
// Styles: 0 glass curtain wall, 1 concrete with punched windows, 2 brick,
// 3 painted metal, 4 vehicle, 5 warehouse. Roof type 1 = helipad.

varying vec4 v_fac;   // u, v (metres), face width, 1 for roofs
varying vec3 v_dims;  // box size in metres
varying vec4 v_info;
varying vec3 v_base;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_dims = sc;
	vec3 lp = VERTEX + vec3(0.5);
	vec3 n = abs(NORMAL);
	if (n.y > 0.5) {
		v_fac = vec4(lp.x * sc.x, lp.z * sc.z, sc.x, 1.0);
	} else if (n.x > 0.5) {
		v_fac = vec4(lp.z * sc.z, lp.y * sc.y, sc.z, 0.0);
	} else {
		v_fac = vec4(lp.x * sc.x, lp.y * sc.y, sc.x, 0.0);
	}
	v_info = INSTANCE_CUSTOM;
	v_base = COLOR.rgb;
}

void fragment() {
	float st = floor(v_info.x + 0.5);
	float seed = v_info.y;
	vec3 base = v_base;
	vec3 col = base;
	float rough = 0.9;
	float spec = 0.15;
	vec3 emis = vec3(0.0);
	if (v_fac.w > 0.5) {
		// ---- roof ----
		float ru = v_fac.x;
		float rv = v_fac.y;
		vec2 rd = v_dims.xz;
		float e = min(min(ru, rd.x - ru), min(rv, rd.y - rv));
		if (st > 2.5 && st < 3.5) {
			col = base * (0.92 + 0.08 * sin(ru * 3.0));
		} else if (st > 3.5 && st < 4.5) {
			col = base;
		} else {
			vec3 tar = vec3(0.24, 0.24, 0.26);
			float tile = hash21(floor(vec2(ru, rv) / 3.0) + seed * 91.0);
			col = tar * (0.85 + 0.3 * tile);
			vec2 sm = abs(fract(vec2(ru, rv) / 3.0 - 0.5) - 0.5) * 3.0;
			col *= 1.0 - 0.15 * (1.0 - smoothstep(0.0, 0.08, min(sm.x, sm.y)));
			col = mix(col, base * 0.85 + 0.1, 1.0 - smoothstep(0.35, 0.6, e));
			if (v_info.z > 0.5 && v_dims.y > 12.0) {
				// Helipad: ring and H.
				vec2 c = vec2(ru, rv) - rd * 0.5;
				float r = min(rd.x, rd.y) * 0.4;
				float d = length(c);
				col = mix(col, vec3(0.2, 0.22, 0.24), 1.0 - smoothstep(r, r + 0.5, d));
				col = mix(col, vec3(0.95, 0.8, 0.1), (1.0 - smoothstep(0.0, 0.5, abs(d - r * 0.92))) );
				vec2 q = c / r;
				float h = step(abs(q.x), 0.42) * step(abs(q.y), 0.6) * (1.0 - step(abs(q.x), 0.28) * (1.0 - step(abs(q.y), 0.1)));
				col = mix(col, vec3(0.95), h * step(d, r));
			}
		}
	} else {
		float W = v_fac.z;
		float H = v_dims.y;
		float u = v_fac.x;
		float v = v_fac.y;
		if (st > 3.5 && st < 4.5) {
			// ---- vehicle ----
			float fu = u / W;
			float fv = v / H;
			float glass = step(0.2, fu) * step(fu, 0.82) * step(0.52, fv) * step(fv, 0.88);
			col = mix(base, vec3(0.04, 0.06, 0.08), glass);
			col = mix(col, vec3(0.03), step(fv, 0.18));
			spec = mix(0.3, 0.8, glass);
			rough = mix(0.5, 0.15, glass);
		} else if (st > 2.5 && st < 3.5) {
			col = base * (0.92 + 0.08 * sin(u * 7.0));
		} else {
			float band = (v_info.w > 0.5 && H > 12.0) ? 4.5 : 0.0;
			float fh = mix(3.0, 3.6, fract(seed * 13.7));
			float cwt = 1.7;
			if (st > 0.5 && st < 1.5) { cwt = 3.0; }
			else if (st > 1.5 && st < 2.5) { cwt = 2.8; }
			else if (st > 4.5) { cwt = 5.0; }
			cwt *= mix(0.9, 1.3, fract(seed * 5.1));
			float ncol = max(1.0, floor(W / cwt + 0.5));
			float cw = W / ncol;
			float vv = v - band;
			float nfl = max(1.0, floor((H - band) / fh + 0.5));
			float fhe = (H - band) / nfl;
			vec2 cell = vec2(u / cw, vv / fhe);
			vec2 f = fract(cell);
			vec2 id = floor(cell);
			float aa = max(fwidth(cell.x), fwidth(cell.y));
			float fade = smoothstep(0.25, 0.7, aa);
			vec4 wr = vec4(0.04, 0.96, 0.1, 0.9);
			vec3 glassc = vec3(0.2, 0.3, 0.4);
			float sky = 0.35 + 0.5 * clamp(v / max(H, 1.0), 0.0, 1.0);
			float wvar = 0.8 + 0.4 * hash21(id + seed * 37.0);
			float wfrac = 0.75;
			if (st < 0.5) {
				glassc = mix(vec3(0.07, 0.12, 0.18), vec3(0.42, 0.58, 0.72), sky) * wvar;
				wrap_glass:
				wfrac = 0.78;
			} else if (st < 1.5) {
				wr = vec4(0.2, 0.8, 0.25, 0.8);
				glassc = mix(vec3(0.08, 0.11, 0.15), vec3(0.3, 0.4, 0.5), sky * 0.7) * wvar;
				wfrac = 0.33;
			} else if (st < 2.5) {
				wr = vec4(0.28, 0.72, 0.18, 0.85);
				glassc = mix(vec3(0.07, 0.1, 0.13), vec3(0.28, 0.38, 0.46), sky * 0.6) * wvar;
				wfrac = 0.29;
			} else {
				wr = vec4(0.1, 0.9, 0.7, 0.86);
				glassc = mix(vec3(0.1, 0.13, 0.16), vec3(0.4, 0.5, 0.58), sky * 0.5) * wvar;
				wfrac = 0.2;
			}
			float inx = min(f.x - wr.x, wr.z - f.x);
			float iny = min(f.y - wr.y, wr.w - f.y);
			float win = step(0.0, inx) * step(0.0, iny);
			float edge = smoothstep(0.0, 0.07, min(inx, iny));
			vec3 wall = base;
			if (st > 1.5 && st < 2.5) {
				float by = v / 0.077;
				float bx = u / 0.24 + 0.5 * mod(floor(by), 2.0);
				float brick = 1.0 - smoothstep(0.03, 0.12, max(fwidth(u), fwidth(v)) / 0.077);
				float mortar = max(step(fract(by), 0.14), step(fract(bx), 0.05));
				float bvar = hash21(vec2(floor(bx), floor(by)));
				wall = base * (0.88 + 0.24 * bvar);
				wall = mix(wall, vec3(0.62, 0.6, 0.56), mortar * 0.7);
				wall = mix(base, wall, brick);
			} else if (st > 4.5) {
				wall = base * (0.9 + 0.1 * sin(u * 9.0));
			} else if (st > 0.5) {
				wall = base * (1.0 - 0.1 * step(f.y, 0.06));
			} else {
				wall = base * (0.8 + 0.2 * step(0.5, f.y)) ;
			}
			vec3 gl = glassc * mix(0.55, 1.0, edge);
			float lit = step(hash21(id + seed * 57.0), 0.16) * win;
			gl = mix(gl, vec3(0.9, 0.75, 0.5) * 0.6, lit * 0.8);
			vec3 detail = mix(wall, gl, win);
			vec3 avg = mix(base, glassc * 0.9, wfrac);
			col = mix(detail, avg, fade);
			emis = vec3(1.0, 0.75, 0.4) * 0.28 * lit * (1.0 - fade);
			rough = mix(0.88, 0.22, win * (1.0 - fade));
			spec = mix(0.12, 0.7, win * (1.0 - fade));
			if (st > 5.5) { }
			if (vv < 0.0) {
				// Ground-floor shopfront: dark glazing, pillars, coloured awnings.
				float sw = max(1.0, floor(W / 4.5 + 0.5));
				float sf = fract(u / (W / sw));
				float pillar = step(sf, 0.06) + step(0.94, sf);
				float aw = step(band - 1.0, v) * step(v, band - 0.4);
				vec3 awc = 0.35 + 0.5 * vec3(hash21(vec2(floor(u / (W / sw)), seed)), hash21(vec2(seed, floor(u / (W / sw)) + 3.0)), 0.3);
				float shop = step(0.5, v) * step(v, band - 1.0) * (1.0 - clamp(pillar, 0.0, 1.0));
				col = mix(base * 0.8, vec3(0.06, 0.09, 0.11) + 0.1 * hash21(vec2(floor(u / (W / sw)), seed + 5.0)), shop);
				col = mix(col, awc, aw);
				emis = vec3(0.0);
				rough = 0.5;
				spec = 0.4 * shop;
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
}
