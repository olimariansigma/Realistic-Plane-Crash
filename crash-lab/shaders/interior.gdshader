shader_type spatial;
render_mode cull_disabled;
// Internal structure (frames, stringers, spars, ribs, floor, engine cores),
// drawn two-sided. Same centreline clip as the exterior shell, except that
// vertices with alpha 0 (the floor) are kept whole so the cabin reads as a
// cross-section standing on its floor. Dents and scorch use the same instance
// uniforms as the skin, so structure buckles and burns with it, and a member
// torn loose keeps the shape it was bent into.

uniform sampler2D atlas : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;

global uniform float cutaway_amount;
instance uniform float cut_plane_x = 0.0;
instance uniform vec4 dent_a = vec4(0.0);
instance uniform vec4 dent_b = vec4(0.0);
instance uniform vec3 dent_a_push = vec3(0.0);
instance uniform vec3 dent_b_push = vec3(0.0);
instance uniform float scorch = 0.0;
// Unused here; declared so a node can switch between the skin and the
// structure material without losing its parameters.
instance uniform vec4 livery_frame = vec4(0.0);

varying vec3 local_pos;
varying float dent_weight;

vec3 crumple(vec3 p, vec4 dent, vec3 push, inout float weight) {
	if (dent.w <= 0.0) {
		return p;
	}
	float w = 1.0 - smoothstep(0.0, dent.w, distance(p, dent.xyz));
	// Thin members buckle in kinks, not smooth bowls.
	float kink = sin(p.x * 9.1 + p.z * 6.3) * sin(p.y * 8.2 - p.z * 4.7);
	weight += w;
	return p + push * (w * (1.1 + 0.6 * kink));
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
	if (COLOR.a > 0.5 && cutaway_amount > 0.001
			&& local_pos.x > cut_plane_x + (1.0 - cutaway_amount) * 40.0) {
		discard;
	}
	// Two-sided: the outer face of the liner is never the one being looked at.
	vec3 base = COLOR.rgb * texture(atlas, UV).rgb * (FRONT_FACING ? 1.0 : 0.8);
	// Bent metal cracks its primer and shows bare aluminium.
	base = mix(base, vec3(0.55, 0.56, 0.58), dent_weight * 0.35);
	base = mix(base, vec3(0.03), scorch);
	ALBEDO = base;
	ROUGHNESS = mix(0.8, 0.5, dent_weight);
	METALLIC = 0.15 * dent_weight * (1.0 - scorch);
	SPECULAR = 0.15;
}
