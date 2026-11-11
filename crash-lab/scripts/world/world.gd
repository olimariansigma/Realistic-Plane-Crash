class_name World
extends Node3D
## The test range: flat ground with a runway, plus things to hit - an
## airfield, a town of tower blocks and a ridge. Built in code so the APK
## carries no level data, with static colliders only.

const LAYER_WORLD := 1
const RUNWAY_LENGTH := 3400.0
const RUNWAY_WIDTH := 60.0
## The runway runs along -Z from this point; aircraft spawn here facing -Z.
const RUNWAY_START := Vector3(0.0, 0.0, 250.0)

var sun: DirectionalLight3D
var environment: Environment

var _box_mesh: BoxMesh
var _building_xforms: Array[Transform3D] = []
var _building_colors: Array[Color] = []
var _ground_physics: PhysicsMaterial


func _ready() -> void:
	_ground_physics = PhysicsMaterial.new()
	_ground_physics.friction = 0.7
	_ground_physics.bounce = 0.0
	_build_sky()
	_build_ground()
	_build_runway()
	_build_airfield()
	_build_town()
	_build_ridge()
	_commit_buildings()
	_build_trees()


## Applies the graphics quality tier (0 low, 1 medium, 2 high).
func apply_quality(quality: int) -> void:
	sun.shadow_enabled = quality >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality >= 2 \
			else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 320.0 if quality >= 2 else 180.0
	environment.fog_enabled = true
	environment.glow_enabled = false
	environment.ssao_enabled = false


func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.38, 0.70)
	sky_mat.sky_horizon_color = Color(0.66, 0.76, 0.86)
	sky_mat.ground_bottom_color = Color(0.22, 0.27, 0.20)
	sky_mat.ground_horizon_color = Color(0.62, 0.70, 0.74)
	sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.66, 0.74, 0.82)
	environment.fog_density = 0.00006
	environment.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)


func _static_box(node_name: String, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.physics_material_override = _ground_physics
	body.transform = Transform3D(basis, center)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


func _build_ground() -> void:
	# A thick slab rather than a plane: nothing tunnels through at 250 m/s.
	_static_box("Ground", Vector3(0.0, -250.0, 0.0), Vector3(80000.0, 500.0, 80000.0))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80000.0, 80000.0)
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader") as Shader
	var mi := MeshInstance3D.new()
	mi.name = "GroundMesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_runway() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(RUNWAY_WIDTH, RUNWAY_LENGTH)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/runway.gdshader") as Shader
	mat.set_shader_parameter(&"size_m", Vector2(RUNWAY_WIDTH, RUNWAY_LENGTH))
	var mi := MeshInstance3D.new()
	mi.name = "Runway"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = RUNWAY_START + Vector3(0.0, 0.03, 100.0 - RUNWAY_LENGTH * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_building(center: Vector3, size: Vector3, color: Color, yaw_deg: float = 0.0,
		occluder: bool = false) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var body := _static_box("Building", center, size, basis)
	_building_xforms.append(Transform3D(basis.scaled(size), center))
	_building_colors.append(color)
	if occluder:
		var occ := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = size * 0.96
		occ.occluder = box
		body.add_child(occ)


func _build_airfield() -> void:
	var z0 := RUNWAY_START.z
	# Terminal, hangars and a control tower along the east side of the runway.
	_add_building(Vector3(210.0, 9.0, z0 - 700.0), Vector3(60.0, 18.0, 260.0), Color(0.72, 0.74, 0.76), 0.0, true)
	for i: int in 4:
		_add_building(Vector3(190.0, 11.0, z0 - 1150.0 - 110.0 * float(i)), Vector3(70.0, 22.0, 85.0),
				Color(0.55, 0.58, 0.62), 0.0, true)
	_add_building(Vector3(150.0, 22.0, z0 - 430.0), Vector3(9.0, 44.0, 9.0), Color(0.82, 0.82, 0.8))
	_add_building(Vector3(150.0, 47.0, z0 - 430.0), Vector3(16.0, 6.0, 16.0), Color(0.25, 0.33, 0.4))
	# Fuel farm on the west side.
	for i: int in 5:
		_add_building(Vector3(-170.0 - 26.0 * float(i % 3), 7.0, z0 - 900.0 - 30.0 * float(i / 3)),
				Vector3(18.0, 14.0, 18.0), Color(0.85, 0.85, 0.83))


func _build_town() -> void:
	# A grid of tower blocks straight off the far end of the runway.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260711
	var base := Vector3(0.0, 0.0, RUNWAY_START.z - RUNWAY_LENGTH - 1500.0)
	for gx: int in range(-4, 5):
		for gz: int in 6:
			if rng.randf() < 0.22:
				continue
			var h := rng.randf_range(24.0, 150.0) if absi(gx) < 3 else rng.randf_range(15.0, 60.0)
			var w := rng.randf_range(26.0, 44.0)
			var d := rng.randf_range(26.0, 44.0)
			var c := base + Vector3(float(gx) * 72.0, h * 0.5, -float(gz) * 78.0)
			var tone := rng.randf_range(0.42, 0.78)
			_add_building(c, Vector3(w, h, d), Color(tone, tone * 1.02, tone * 1.06), 0.0, h > 60.0)


func _build_ridge() -> void:
	# A line of hills to the west: one shared cone mesh in a MultiMesh, each
	# with a matching convex collider. Something solid to fly into.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cone := CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 12
	cone.rings = 2
	cone.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	cone.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cone
	var count := 14
	mm.instance_count = count
	for i: int in count:
		var radius := rng.randf_range(520.0, 980.0)
		var height := rng.randf_range(220.0, 560.0)
		var center := Vector3(-4300.0 + rng.randf_range(-500.0, 500.0), 0.0, 2200.0 - float(i) * 620.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(radius, height, radius)),
				center + Vector3(0.0, height * 0.5, 0.0)))
		var tone := rng.randf_range(0.85, 1.1)
		mm.set_instance_color(i, Color(0.3 * tone, 0.36 * tone, 0.24 * tone))
		var points := PackedVector3Array([Vector3(0.0, height, 0.0)])
		for k: int in 10:
			var a := TAU * float(k) / 10.0
			points.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
			points.append(Vector3(cos(a) * radius, -20.0, sin(a) * radius))
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		var body := StaticBody3D.new()
		body.name = "Hill%d" % i
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		body.physics_material_override = _ground_physics
		body.position = center
		var shape := CollisionShape3D.new()
		shape.shape = hull
		body.add_child(shape)
		add_child(body)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Hills"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _commit_buildings() -> void:
	# One MultiMesh for every box in the world: a single draw call.
	_box_mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_box_mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _box_mesh
	mm.instance_count = _building_xforms.size()
	for i: int in _building_xforms.size():
		mm.set_instance_transform(i, _building_xforms[i])
		mm.set_instance_color(i, _building_colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Buildings"
	mmi.multimesh = mm
	add_child(mmi)
	_building_xforms.clear()
	_building_colors.clear()


func _build_trees() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.6
	cone.height = 9.0
	cone.radial_segments = 5
	cone.rings = 1
	cone.cap_top = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.27, 0.13)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	cone.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var count := 1400
	mm.instance_count = count
	for i: int in count:
		# Belts of woodland either side of the runway, clear of the strip itself.
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(320.0, 1500.0)
		var z := rng.randf_range(RUNWAY_START.z - RUNWAY_LENGTH - 900.0, RUNWAY_START.z + 1200.0)
		var s := rng.randf_range(0.7, 1.7)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(x, 4.5 * s, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 2600.0
	add_child(mmi)
