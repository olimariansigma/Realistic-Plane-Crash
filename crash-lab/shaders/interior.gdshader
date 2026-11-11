shader_type spatial;
render_mode cull_disabled;
// Cabin liner and floor, drawn only in cutaway view. Same centreline clip as
// the exterior shell, except that vertices with alpha 0 (the floor) are kept
// whole so the cabin reads as a cross-section standing on its floor.

global uniform float cutaway_amount;
instance uniform float cut_plane_x = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	if (COLOR.a > 0.5 && cutaway_amount > 0.001
			&& local_pos.x > cut_plane_x + (1.0 - cutaway_amount) * 40.0) {
		discard;
	}
	// Two-sided: the outer face of the liner is never the one being looked at.
	ALBEDO = COLOR.rgb * (FRONT_FACING ? 1.0 : 0.8);
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}
