class_name AirframeBuilder
extends RefCounted
## Turns an AircraftDef into nodes: rigid bodies, colliders, joints and
## meshes for flight, or meshes only for the hangar showroom.

const LAYER_WORLD := 1
const LAYER_AIRFRAME := 2
## Distance at which parts swap to their low-detail mesh.
const LOD_DISTANCE := 260.0
const SHADER_PATH := "res://shaders/airframe.gdshader"

static var _material: ShaderMaterial
static var _physics_material: PhysicsMaterial
## Meshes keyed by "<aircraft id>/<part name>/<slot>". Filled off the main
## thread by prebuild_meshes() during loading; build_part_visual() falls back
## to generating inline on a miss.
static var _mesh_cache: Dictionary = {}
static var _cache_mutex := Mutex.new()


## Generates every mesh of an aircraft. Safe to call from a worker thread.
static func prebuild_meshes(adef: AircraftDef) -> void:
	for part: PartDef in adef.parts:
		if part.kind == PartDef.Kind.GEAR:
			_cached(adef, part, 2)
			_cached(adef, part, 3)
		else:
			_cached(adef, part, 0)
			_cached(adef, part, 1)


## Slots: 0 near LOD, 1 far LOD, 2 gear strut, 3 gear wheels.
static func _cached(adef: AircraftDef, part: PartDef, slot: int) -> Mesh:
	var key := "%s/%s/%d" % [adef.id, part.name, slot]
	_cache_mutex.lock()
	var found: Mesh = _mesh_cache.get(key)
	_cache_mutex.unlock()
	if found != null:
		return found
	var mesh: Mesh
	match slot:
		2:
			mesh = MeshFactory.gear_strut_mesh(part)
		3:
			mesh = MeshFactory.gear_wheel_mesh(part)
		_:
			mesh = MeshFactory.part_mesh(adef, part, slot)
	_cache_mutex.lock()
	_mesh_cache[key] = mesh
	_cache_mutex.unlock()
	return mesh


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH) as Shader
	return _material


static func physics_material() -> PhysicsMaterial:
	if _physics_material == null:
		_physics_material = PhysicsMaterial.new()
		_physics_material.friction = 0.5
		_physics_material.bounce = 0.02
	return _physics_material


static func _mesh_instance(mesh: Mesh, cut_x: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material()
	mi.set_instance_shader_parameter(&"cut_plane_x", cut_x)
	return mi


## Visual subtree for one part, in the part's local frame. Returns the root;
## near/far LOD meshes are children "Near" and "Far" (gear: "Strut"/"Wheels").
static func build_part_visual(adef: AircraftDef, part: PartDef) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var cut_x := -part.com.x
	if part.kind == PartDef.Kind.GEAR:
		var leg := Node3D.new()
		leg.name = "Leg"
		leg.position = part.p0 - part.com
		root.add_child(leg)
		var strut := _mesh_instance(_cached(adef, part, 2), cut_x - leg.position.x)
		strut.name = "Strut"
		strut.visibility_range_end = LOD_DISTANCE * 3.0
		leg.add_child(strut)
		var wheels := _mesh_instance(_cached(adef, part, 3), cut_x - leg.position.x)
		wheels.name = "Wheels"
		wheels.visibility_range_end = LOD_DISTANCE * 3.0
		leg.add_child(wheels)
		return root
	var near := _mesh_instance(_cached(adef, part, 0), cut_x)
	near.name = "Near"
	near.visibility_range_end = LOD_DISTANCE
	near.visibility_range_end_margin = 10.0
	root.add_child(near)
	var far := _mesh_instance(_cached(adef, part, 1), cut_x)
	far.name = "Far"
	far.visibility_range_begin = LOD_DISTANCE
	far.visibility_range_begin_margin = 10.0
	root.add_child(far)
	return root


## Static display model (no physics) with the aircraft origin at the node
## origin. Gear is drawn at its static stroke so the wheels sit on the floor
## when the model is placed `ground_clearance` above it.
static func build_display_model(adef: AircraftDef) -> Node3D:
	var model := Node3D.new()
	model.name = "DisplayModel"
	for part: PartDef in adef.parts:
		var holder := Node3D.new()
		holder.name = String(part.name)
		holder.position = part.com
		var visual := build_part_visual(adef, part)
		holder.add_child(visual)
		model.add_child(holder)
		if part.kind == PartDef.Kind.GEAR:
			var wheels := visual.get_node_or_null("Leg/Wheels") as Node3D
			for g: GearDef in adef.gear:
				if g.part == part.name and wheels != null:
					wheels.position.y = g.travel * 0.55
	return model


static func build_part(adef: AircraftDef, part: PartDef, index: int) -> AircraftPart:
	var body := AircraftPart.new()
	body.name = String(part.name)
	body.def = part
	body.index = index
	body.parent_index = adef.find_part(part.parent) if part.parent != &"" else -1
	body.position = part.com
	body.mass = part.mass
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.ZERO
	body.inertia = part.inertia
	body.collision_layer = LAYER_AIRFRAME
	body.collision_mask = LAYER_WORLD
	body.contact_monitor = true
	body.max_contacts_reported = 6
	body.can_sleep = false
	body.continuous_cd = true
	body.physics_material_override = physics_material()
	body.anchor_local = part.anchor - part.com
	match part.kind:
		PartDef.Kind.FUSELAGE, PartDef.Kind.ENGINE:
			body.crumple_limit = maxf(part.r0, part.r1) * 0.85
		PartDef.Kind.GEAR:
			body.crumple_limit = 0.0
		_:
			body.crumple_limit = (part.r0 + part.r1) * 0.5 * 0.3

	var shape := CollisionShape3D.new()
	shape.name = "Collider"
	if part.kind == PartDef.Kind.GEAR:
		# Bump stop: a wheel-sized sphere that only reaches the ground once the
		# oleo has used all of its travel.
		var sphere := SphereShape3D.new()
		sphere.radius = part.r0
		shape.shape = sphere
		var travel := 0.45
		for g: GearDef in adef.gear:
			if g.part == part.name:
				travel = g.travel
		shape.position = part.p1 - part.com + Vector3(0.0, travel + 0.04, 0.0)
	else:
		var hull := ConvexPolygonShape3D.new()
		hull.points = MeshFactory.part_hull(part)
		shape.shape = hull
	body.add_child(shape)

	body.visual = build_part_visual(adef, part)
	body.add_child(body.visual)
	body.mesh_near = body.visual.get_node_or_null("Near") as MeshInstance3D
	body.mesh_far = body.visual.get_node_or_null("Far") as MeshInstance3D
	return body


## Rigid 6-DOF joint (all axes locked) between a part and its parent.
static func build_joint(holder: Node3D, parent: AircraftPart, child: AircraftPart) -> Generic6DOFJoint3D:
	var joint := Generic6DOFJoint3D.new()
	joint.name = "Joint_%s" % child.name
	holder.add_child(joint)
	joint.position = child.def.anchor
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(child)
	joint.exclude_nodes_from_collision = true
	return joint
