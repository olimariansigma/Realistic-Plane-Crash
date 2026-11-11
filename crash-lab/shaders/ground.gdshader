shader_type spatial;
render_mode cull_back, specular_disabled;
// Procedural terrain colour from world position: no textures, no tiling
// artefacts over tens of kilometres, and enough near-field detail to read speed.

uniform vec3 grass_a : source_color = vec3(0.23, 0.36, 0.17);
uniform vec3 grass_b : source_color = vec3(0.34, 0.42, 0.20);
uniform vec3 dirt : source_color = vec3(0.42, 0.36, 0.26);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float broad = value_noise(world_pos.xz * 0.0021);
	float field = value_noise(world_pos.xz * 0.013 + 17.0);
	float fine = value_noise(world_pos.xz * 0.45);
	vec3 col = mix(grass_a, grass_b, broad);
	col = mix(col, dirt, smoothstep(0.62, 0.9, field) * 0.55);
	// Fine grain only near the camera, where it sells ground speed.
	float near = 1.0 - smoothstep(40.0, 400.0, length(VERTEX));
	col *= 0.9 + 0.2 * fine * near;
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
