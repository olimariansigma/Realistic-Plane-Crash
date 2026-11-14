class_name World
extends Node3D
## The test range: flat ground with a runway, an airfield (tower, terminal,
## hangars), a city to the right of the departure path, farmland and forests,
## a lake and a mountain ridge to the west. Built in code so the APK carries no
## level data: static colliders only, everything drawn by a few shader-driven
## meshes and MultiMeshes (about a dozen draw calls), nothing runs per frame.

const LAYER_WORLD := 1
const RUNWAY_LENGTH := 3400.0
const RUNWAY_WIDTH := 60.0
## The runway runs along -Z from this point; aircraft spawn here facing -Z.
const RUNWAY_START := Vector3(0.0, 0.0, 250.0)

var sun: DirectionalLight3D
var environment: Environment

var _colliders: WorldColliders
var _forests: Array[Vector4] = []
var _lake := Vector3(-1800.0, 0.0, -300.0)
var _lake_r := Vector2(560.0, 380.0)


func _ready() -> void:
	var phys := PhysicsMaterial.new()
	phys.friction = 0.7
	phys.bounce = 0.0
	_colliders = WorldColliders.new(self, phys)
	_build_sky()
	var trees := WorldTrees.new()
	var boxes := WorldBoxes.new()
	_plan_forests()
	_build_ground()
	_build_runway()
	WorldAirport.new().build(self, _colliders, boxes)
	WorldCity.new().build(self, _colliders, boxes, trees)
	_build_lake()
	_build_ridge()
	_scatter_trees(trees)
	boxes.build(self)
	trees.build(self)


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
	environment.fog_density = 0.00007
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


## Forest clusters (x, z, radius, floor strength); the ground shader darkens
## under them and _scatter_trees plants them.
func _plan_forests() -> void:
	var list: Array[Vector4] = [
		Vector4(-900.0, -800.0, 380.0, 1.0), Vector4(-1100.0, -3000.0, 420.0, 1.0),
		Vector4(-1400.0, 1500.0, 350.0, 1.0), Vector4(-700.0, -5200.0, 400.0, 1.0),
		Vector4(1000.0, -300.0, 320.0, 1.0), Vector4(1300.0, -2300.0, 420.0, 1.0),
		Vector4(1000.0, 1600.0, 380.0, 1.0), Vector4(3800.0, -1200.0, 500.0, 1.0),
		Vector4(2500.0, 1500.0, 450.0, 1.0), Vector4(700.0, -8000.0, 500.0, 1.0),
		Vector4(-2600.0, -2400.0, 400.0, 1.0), Vector4(4200.0, -4800.0, 450.0, 1.0),
	]
	_forests = list


func _build_ground() -> void:
	# A thick slab rather than a plane: nothing tunnels through at 250 m/s.
	_colliders.box("Ground", Vector3(0.0, -250.0, 0.0), Vector3(80000.0, 500.0, 80000.0))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80000.0, 80000.0)
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader") as Shader
	var arr := PackedVector4Array()
	for i: int in 16:
		arr.append(_forests[i] if i < _forests.size() else Vector4.ZERO)
	mat.set_shader_parameter(&"forests", arr)
	mat.set_shader_parameter(&"forest_count", _forests.size())
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


func _build_lake() -> void:
	var b := WorldMeshBuilder.new()
	var radii := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for k: int in 40:
		var a := TAU * float(k) / 40.0
		var wob := 1.0 + 0.12 * sin(a * 3.0 + 1.0) + 0.06 * sin(a * 5.0) + rng.randf_range(-0.02, 0.02)
		radii.append(wob)
	# Elliptical lake: scale the unit blob.
	b.blob(Vector3.ZERO, radii, Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = b.build()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world_water.gdshader") as Shader
	mi.material_override = mat
	mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(_lake_r.x, 1.0, _lake_r.y)), _lake + Vector3(0.0, 0.06, 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_ridge() -> void:
	# 14 hills west of x = -3300: one shared cone mesh in a MultiMesh, each with
	# a matching convex collider (the shader only ever pulls the surface inward).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cone := CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 10
	cone.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world_hill.gdshader") as Shader
	cone.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	var count := 14
	mm.instance_count = count
	for i: int in count:
		var radius := rng.randf_range(480.0, 820.0)
		var height := rng.randf_range(280.0, 640.0)
		var cx := minf(-4400.0 + rng.randf_range(-350.0, 350.0), -3350.0 - radius)
		var center := Vector3(cx, 0.0, 2200.0 - float(i) * 620.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(radius, height, radius)),
				center + Vector3(0.0, height * 0.5, 0.0)))
		var points := PackedVector3Array([Vector3(0.0, height, 0.0)])
		for k: int in 10:
			var a := TAU * float(k) / 10.0
			points.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
			points.append(Vector3(cos(a) * radius, -20.0, sin(a) * radius))
		_colliders.hull("Hill%d" % i, center, points)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Hills"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _tree_ok(x: float, z: float) -> bool:
	if absf(x) < 470.0 and z < 4000.0 and z > -9000.0:
		return false
	if x > 140.0 and x < 700.0 and z < 500.0 and z > -3300.0:
		return false
	if x > 850.0 and x < 3400.0 and z < -3750.0 and z > -6800.0:
		return false
	if x < -150.0 and x > -460.0 and z < -820.0 and z > -1020.0:
		return false
	var dx := (x - _lake.x) / (_lake_r.x * 1.2)
	var dz := (z - _lake.z) / (_lake_r.y * 1.2)
	return dx * dx + dz * dz > 1.0


func _scatter_trees(trees: WorldTrees) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for f: Vector4 in _forests:
		for k: int in 380:
			var a := rng.randf() * TAU
			var r := f.z * sqrt(rng.randf()) * 0.95
			var x := f.x + cos(a) * r
			var z := f.y + sin(a) * r
			if not _tree_ok(x, z):
				continue
			var s := rng.randf_range(1.1, 1.8)
			if rng.randf() < 0.6:
				trees.add_conifer(Vector3(x, 0.0, z), s)
			else:
				trees.add_round(Vector3(x, 0.0, z), s)
