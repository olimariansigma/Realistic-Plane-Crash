shader_type spatial;
render_mode cull_back;
// Shared by every airframe part. One material for the whole fleet keeps draw
// state changes down; per-part variation rides on instance uniforms.
//
// Crumple: up to two dents per part displace vertices near an impact point
// along the impact direction, scaled by absorbed energy (set from script).
// Cutaway: fragments on the +X side of the aircraft centreline are discarded
// while the global cutaway_amount is above zero.

uniform sampler2D atlas : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.42;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.15;
uniform vec3 interior_tint : source_color = vec3(0.55, 0.57, 0.6);

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

varying vec3 local_pos;
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
	vec3 base = COLOR.rgb * tint * texture(atlas, UV).rgb;
	base = mix(base, base * 0.5, dent_weight * 0.7);
	base = mix(base, vec3(0.025), scorch);
	ALBEDO = base;
	ROUGHNESS = mix(roughness_value, 0.95, max(scorch, dent_weight * 0.6));
	METALLIC = metallic_value * (1.0 - scorch);
}
