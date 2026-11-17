shader_type spatial;
render_mode cull_disabled;
// Shared by every airframe part. One material for the whole fleet keeps draw
// state changes down; per-part variation rides on instance uniforms.
//
// Crumple: up to two dents per part displace vertices near an impact point
// along the impact direction, scaled by absorbed energy (set from script).
// Cutaway: fragments on the +X side of the aircraft centreline are discarded
// while the global cutaway_amount is above zero.
// Skin is drawn two-sided: the inside face shows primer, so torn panels and
// the cutaway read as sheet metal rather than vanishing when seen from behind.

uniform sampler2D atlas : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;
// Airliner paint is a glossy clear-coated enamel, not plastic: low roughness
// plus a clear coat is what makes the sky reflect along the fuselage.
uniform float roughness_value : hint_range(0.0, 1.0) = 0.3;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.04;
uniform float clearcoat_value : hint_range(0.0, 1.0) = 0.55;
uniform vec3 primer : source_color = vec3(0.42, 0.5, 0.27);

// Fuselage markings, drawn analytically from the aircraft's real dimensions
// so they are sharp at any distance (one aircraft is on screen at a time, so
// these live on the shared material; AirframeBuilder.apply_livery sets them).
// Fuselage frame: x lateral, y height above the fuselage centreline, z
// station aft of the nose tip, all in metres.
uniform vec4 win_size = vec4(0.24, 0.34, 0.08, 0.53);   // width, height, corner radius, pitch
uniform vec4 win_row0 = vec4(0.0);   // centre height, first station, last station, on
uniform vec4 win_row1 = vec4(0.0);   // second row (upper deck), same layout
uniform vec4 doors[12];              // station, width, height, sill height (width 0 = none)
uniform vec4 cockpit_a = vec4(0.0);  // first station, last station, sill height at first, at last
uniform vec4 cockpit_b = vec4(0.0);  // top height at first, at last, frame width, black surround width
uniform vec4 cockpit_splits = vec4(0.0); // pane boundaries (stations); 0 = unused
uniform vec4 panel_lines = vec4(2.4, 0.012, 0.22, 0.0); // butt-joint spacing, line width, strength

global uniform float cutaway_amount;

// Part-local X of the aircraft centreline plane.
instance uniform float cut_plane_x = 0.0;
// xyz = dent centre (part-local), w = radius. Zero radius = unused.
instance uniform vec4 dent_a = vec4(0.0);
instance uniform vec4 dent_b = vec4(0.0);
// xyz = displacement at the dent centre (part-local).
instance uniform vec3 dent_a_push = vec3(0.0);
instance uniform vec3 dent_b_push = vec3(0.0);
instance uniform float scorch = 0.0;
// Multiplies the vertex colour; used by debris, which shares this material.
instance uniform vec3 tint : source_color = vec3(1.0);
// Remaps UVs into an atlas region (offset.xy, scale.zw) for primitive meshes.
instance uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Offset from part-local coordinates to the fuselage frame above; w = 1 on
// fuselage skin (which then gets the analytic markings).
instance uniform vec4 livery_frame = vec4(0.0);

varying vec3 local_pos;
varying vec3 fpos;

float round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Fuselage markings at fuselage-frame point `f`. Returns glass mask in x,
// darkening (seams, frames, door gaps) in y, black paint in z.
vec3 markings(vec3 f) {
	float st = f.z;
	float h = f.y;
	vec2 sh = vec2(st, h);
	float aa = max(fwidth(st), fwidth(h)) * 1.3 + 1.0e-4;
	float glass = 0.0;
	float dark = 0.0;
	float black = 0.0;
	// Doors: rounded outline with a small window.
	for (int i = 0; i < 12; i++) {
		vec4 d = doors[i];
		if (d.y <= 0.0) {
			continue;
		}
		float dd = round_rect(sh - vec2(d.x, d.w + d.z * 0.5), vec2(d.y, d.z) * 0.5, 0.16);
		dark = max(dark, (1.0 - smoothstep(0.0, aa * 1.5, abs(dd) - 0.011)) * 0.75);
		if (d.y > 0.7 && d.z > 1.3) {
			float dw = round_rect(sh - vec2(d.x, d.w + d.z * 0.66), vec2(0.1, 0.13), 0.07);
			glass = max(glass, 1.0 - smoothstep(-aa, aa, dw));
		}
	}
	// Cabin window rows, broken where a door stands in the row.
	for (int r = 0; r < 2; r++) {
		vec4 row = r == 0 ? win_row0 : win_row1;
		if (row.w < 0.5) {
			continue;
		}
		float k = floor((st - row.y) / win_size.w + 0.5);
		float wc = row.y + k * win_size.w;
		if (wc < row.y - 0.01 || wc > row.z + 0.01) {
			continue;
		}
		bool blocked = false;
		for (int i = 0; i < 12; i++) {
			vec4 d = doors[i];
			if (d.y > 0.0 && abs(wc - d.x) < d.y * 0.5 + win_size.x * 0.75
					&& row.x > d.w && row.x < d.w + d.z) {
				blocked = true;
			}
		}
		if (blocked) {
			continue;
		}
		float dw = round_rect(sh - vec2(wc, row.x), win_size.xy * 0.5, win_size.z);
		glass = max(glass, 1.0 - smoothstep(-aa, aa, dw));
		// Window seal and the slightly recessed reveal around it.
		dark = max(dark, (1.0 - smoothstep(0.0, aa + 0.03, dw)) * smoothstep(-aa, 0.0, dw) * 0.55);
	}
	// Cockpit windscreen: panes between sloping sill and top lines, split by
	// frames, with an optional black surround.
	if (cockpit_a.y > cockpit_a.x) {
		float t = clamp((st - cockpit_a.x) / (cockpit_a.y - cockpit_a.x), 0.0, 1.0);
		float sill = mix(cockpit_a.z, cockpit_a.w, t);
		float top = mix(cockpit_b.x, cockpit_b.y, t);
		float in_st = min(st - cockpit_a.x, cockpit_a.y - st);
		float in_h = min(h - sill, top - h);
		float inside = min(in_st, in_h);
		float pane = smoothstep(-aa, aa, inside);
		// Centre post between the two front panes is wider than the frames.
		float frame = 1.0 - smoothstep(cockpit_b.z * 1.4 - aa, cockpit_b.z * 1.4 + aa, abs(f.x));
		for (int i = 0; i < 4; i++) {
			if (cockpit_splits[i] > 0.0) {
				frame = max(frame, 1.0 - smoothstep(cockpit_b.z * 0.5 - aa, cockpit_b.z * 0.5 + aa,
						abs(st - cockpit_splits[i])));
			}
		}
		glass = max(glass, pane * (1.0 - frame));
		black = max(black, pane * frame);
		if (cockpit_b.w > 0.0) {
			black = max(black, (1.0 - smoothstep(cockpit_b.w - aa, cockpit_b.w + aa, -inside)) * (1.0 - pane));
		} else {
			dark = max(dark, (1.0 - smoothstep(0.0, aa + 0.02, -inside)) * (1.0 - pane) * 0.6);
		}
	}
	// Skin seams: circumferential butt joints and two longitudinal laps.
	if (panel_lines.x > 0.0) {
		float seam = abs(fract(st / panel_lines.x + 0.5) - 0.5) * panel_lines.x;
		float lap = min(abs(h - win_row0.x - 0.75), abs(h - win_row0.x + 0.95));
		float line = 1.0 - smoothstep(panel_lines.y - aa, panel_lines.y + aa, min(seam, lap));
		dark = max(dark, line * panel_lines.z);
	}
	return vec3(glass, dark, black);
}

float panel_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
varying float dent_weight;

vec3 crumple(vec3 p, vec4 dent, vec3 push, inout float weight) {
	if (dent.w <= 0.0) {
		return p;
	}
	float w = 1.0 - smoothstep(0.0, dent.w, distance(p, dent.xyz));
	// Cheap wrinkles so the dent reads as buckled skin rather than a smooth bowl.
	float wrinkle = sin(p.x * 7.3 + p.z * 5.1) * sin(p.y * 6.7 - p.z * 3.3);
	weight += w;
	return p + push * (w * (1.0 + 0.4 * wrinkle));
}

void vertex() {
	local_pos = VERTEX;
	fpos = VERTEX + livery_frame.xyz;
	float weight = 0.0;
	vec3 p = crumple(VERTEX, dent_a, dent_a_push, weight);
	p = crumple(p, dent_b, dent_b_push, weight);
	VERTEX = p;
	dent_weight = clamp(weight, 0.0, 1.0);
}

void fragment() {
	// The cut plane sweeps in from the wingtip side as cutaway_amount rises.
	if (cutaway_amount > 0.001
			&& local_pos.x > cut_plane_x + (1.0 - cutaway_amount) * 40.0) {
		discard;
	}
	vec3 tex = texture(atlas, uv_rect.xy + UV * uv_rect.zw).rgb;
	vec3 base = COLOR.rgb * tint * tex;
	// Glass: the atlas paints windows near-black. Make them a dark, mirror-like
	// surface so they pick up the sky, as real cabin and cockpit windows do.
	float glass = 1.0 - smoothstep(0.08, 0.2, max(tex.r, max(tex.g, tex.b)));
	if (livery_frame.w > 0.5 && FRONT_FACING) {
		vec3 m = markings(fpos);
		glass = max(glass, m.x);
		base = mix(base, base * 0.45, m.y);
		base = mix(base, vec3(0.02, 0.022, 0.026), m.z);
	}
	// Real skins are not one flat colour: panels differ very slightly in shade.
	float shade = panel_hash(floor(local_pos * vec3(0.55, 0.9, 0.42)));
	base *= 1.0 + (shade - 0.5) * 0.045;
	float rough = roughness_value + (shade - 0.5) * 0.08;
	if (!FRONT_FACING) {
		base = primer;
		glass = 0.0;
		rough = 0.7;
	}
	base = mix(base, vec3(0.012, 0.016, 0.022), glass);
	base = mix(base, base * 0.5, dent_weight * 0.7);
	base = mix(base, vec3(0.025), scorch);
	float wear = max(scorch, dent_weight * 0.6);
	ALBEDO = base;
	ROUGHNESS = mix(mix(rough, 0.04, glass), 0.95, wear);
	METALLIC = metallic_value * (1.0 - scorch);
	SPECULAR = mix(0.5, 0.9, glass);
	CLEARCOAT = FRONT_FACING ? clearcoat_value * (1.0 - wear) : 0.0;
	CLEARCOAT_ROUGHNESS = 0.12;
}
