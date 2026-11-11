shader_type spatial;
render_mode unshaded, cull_disabled;
// Hangar shell with its lighting baked into the shader: a vertical falloff
// plus ribbed panels and strip lights. Unshaded, so it costs no light passes.

uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.21);
uniform vec3 light_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec2 size_m = vec2(200.0, 40.0);
uniform float is_floor = 0.0;

void fragment() {
	vec2 m = UV * size_m;
	vec3 col = base_color;
	if (is_floor > 0.5) {
		// Polished concrete: pooled light in the middle, expansion joints.
		vec2 c = (UV - 0.5) * size_m;
		float pool = exp(-dot(c, c) / 2600.0);
		float joints = step(0.985, fract(m.x / 8.0)) + step(0.985, fract(m.y / 8.0));
		col = mix(base_color * 0.55, base_color * 1.9, pool) * (1.0 - 0.25 * min(joints, 1.0));
	} else {
		float ribs = 0.86 + 0.14 * step(0.5, fract(m.x / 3.0));
		float height = 1.0 - UV.y;
		col = base_color * ribs * mix(0.55, 1.25, height);
		// Strip lights near the top of the walls.
		float strip = step(0.86, height) * step(height, 0.9) * step(0.25, fract(m.x / 12.0));
		col = mix(col, light_color, strip);
	}
	ALBEDO = col;
}
