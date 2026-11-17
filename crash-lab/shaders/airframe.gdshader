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

varying vec3 local_pos;

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
