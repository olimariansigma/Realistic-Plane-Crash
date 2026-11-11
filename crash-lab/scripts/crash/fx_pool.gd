class_name FxPool
extends Node3D
## Pooled particle effects: sustained fires with smoke, and one-shot dust
## bursts. Emitters are created once and reused; nothing is instantiated
## during a crash.

const DUST_COUNT := 6

var max_fires: int = 0
var _fire: Array[GPUParticles3D] = []
var _smoke: Array[GPUParticles3D] = []
var _fire_source: Array[FireSource] = []
var _fires_used: int = 0
var _dust: Array[GPUParticles3D] = []
var _dust_next: int = 0
var _blob: GradientTexture2D


## `quality` 0..2 scales emitter count and particle amounts.
func setup(quality: int) -> void:
	max_fires = [3, 5, 8][clampi(quality, 0, 2)]
	var density: float = [0.5, 0.8, 1.0][clampi(quality, 0, 2)]
	_blob = _make_blob()
	for i: int in max_fires:
		var fire := _make_emitter("Fire%d" % i, int(44.0 * density), 0.8, _fire_process(), _billboard(true), 1.5)
		fire.emitting = false
		add_child(fire)
		_fire.append(fire)
		var smoke := _make_emitter("Smoke%d" % i, int(30.0 * density), 5.5, _smoke_process(), _billboard(false), 4.5)
		smoke.emitting = false
		add_child(smoke)
		_smoke.append(smoke)
		_fire_source.append(null)
	for i: int in DUST_COUNT:
		var dust := _make_emitter("Dust%d" % i, int(16.0 * density), 1.6, _dust_process(), _billboard(false), 3.2)
		dust.one_shot = true
		dust.explosiveness = 0.92
		dust.emitting = false
		add_child(dust)
		_dust.append(dust)


func start_fire(source: FireSource) -> void:
	if _fires_used >= max_fires:
		return
	var i := _fires_used
	_fires_used += 1
	_fire_source[i] = source
	var scale := 0.7 + source.intensity * 1.3
	_fire[i].scale = Vector3(scale, scale, scale)
	_smoke[i].scale = Vector3(scale, scale, scale)
	var pos := source.world_position()
	_fire[i].global_position = pos
	_smoke[i].global_position = pos
	_fire[i].restart()
	_smoke[i].restart()
	_fire[i].emitting = true
	_smoke[i].emitting = true


func burst_dust(pos: Vector3, size: float) -> void:
	var dust := _dust[_dust_next]
	_dust_next = (_dust_next + 1) % DUST_COUNT
	dust.global_position = pos
	var s := clampf(size, 0.5, 4.0)
	dust.scale = Vector3(s, s, s)
	dust.restart()
	dust.emitting = true


func active_fires() -> int:
	return _fires_used


func _process(_delta: float) -> void:
	# Emitters ride on the burning part; particles stay in world space.
	for i: int in _fires_used:
		var source := _fire_source[i]
		if source == null or not is_instance_valid(source.part):
			continue
		var pos := source.part.get_global_transform_interpolated() * source.local_pos
		pos.y = maxf(pos.y, 0.3)
		_fire[i].global_position = pos
		_smoke[i].global_position = pos


func _make_blob() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _billboard(additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _blob
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat


func _make_emitter(node_name: String, amount: int, lifetime: float, process: ParticleProcessMaterial,
		material: StandardMaterial3D, quad_size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = maxi(amount, 4)
	p.lifetime = lifetime
	p.local_coords = false
	p.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = material
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40.0, -5.0, -40.0), Vector3(80.0, 90.0, 80.0))
	return p


func _ramp(colors: Array[Color], offsets: Array[float]) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	tex.width = 32
	return tex


func _scale_curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	for pt: Vector2 in points:
		curve.add_point(pt)
	var tex := CurveTexture.new()
	tex.curve = curve
	tex.width = 32
	return tex


func _fire_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.1
	m.direction = Vector3.UP
	m.spread = 22.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 8.0
	m.gravity = Vector3(0.0, 5.0, 0.0)
	m.scale_min = 0.7
	m.scale_max = 1.5
	m.scale_curve = _scale_curve([Vector2(0.0, 0.45), Vector2(0.3, 1.0), Vector2(1.0, 0.2)])
	m.color_ramp = _ramp(
			[Color(1.0, 0.85, 0.45, 0.0), Color(1.0, 0.55, 0.12, 0.55), Color(0.8, 0.2, 0.03, 0.4), Color(0.2, 0.03, 0.0, 0.0)],
			[0.0, 0.15, 0.6, 1.0])
	return m


func _smoke_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.6
	m.direction = Vector3.UP
	m.spread = 16.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 8.0
	m.gravity = Vector3(1.2, 1.5, 0.4)
	m.scale_min = 0.8
	m.scale_max = 1.6
	m.scale_curve = _scale_curve([Vector2(0.0, 0.4), Vector2(0.4, 1.3), Vector2(1.0, 2.6)])
	m.color_ramp = _ramp(
			[Color(0.12, 0.11, 0.1, 0.0), Color(0.09, 0.085, 0.08, 0.6), Color(0.2, 0.2, 0.2, 0.35), Color(0.3, 0.3, 0.3, 0.0)],
			[0.0, 0.12, 0.6, 1.0])
	return m


func _dust_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.2
	m.direction = Vector3.UP
	m.spread = 75.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 11.0
	m.gravity = Vector3(0.0, -2.5, 0.0)
	m.damping_min = 2.0
	m.damping_max = 4.0
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.scale_curve = _scale_curve([Vector2(0.0, 0.3), Vector2(0.5, 1.0), Vector2(1.0, 1.6)])
	m.color_ramp = _ramp(
			[Color(0.5, 0.47, 0.42, 0.0), Color(0.48, 0.45, 0.4, 0.3), Color(0.5, 0.48, 0.45, 0.0)],
			[0.0, 0.15, 1.0])
	return m
