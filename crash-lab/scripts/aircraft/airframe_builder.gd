class_name AirframeBuilder
extends RefCounted
## Turns an AircraftDef into nodes: rigid bodies, colliders, joints and
## meshes for flight, or meshes only for the hangar showroom.

const LAYER_WORLD := 1
const LAYER_AIRFRAME := 2
## Distance at which an intact part swaps its skin pieces for one merged mesh.
const LOD_DISTANCE := 170.0
const SHADER_PATH := "res://shaders/airframe.gdshader"
const INTERIOR_SHADER_PATH := "res://shaders/interior.gdshader"
const ATLAS_PATH := "res://assets/atlas.png"

## Mesh detail tier (0 low, 1 medium, 2 high): bay length, side count.
static var detail: int = 1

static var _material: ShaderMaterial
static var _interior_material: ShaderMaterial
static var _physics_material: PhysicsMaterial
## PartMeshes keyed by "<aircraft id>/<part name>/<detail>". Filled a slice
## per frame by prebuild_some() during loading; part_meshes() generates
## inline on a miss.
static var _mesh_cache: Dictionary = {}
static var _cache_mutex := Mutex.new()


## Generates every mesh of an aircraft in one go.
static func prebuild_meshes(adef: AircraftDef) -> void:
	for part: PartDef in adef.parts:
		part_meshes(adef, part)


## Generates meshes for parts not built yet until `budget_usec` is spent, and
## returns the fraction of the aircraft now ready (1.0 = done). Call once a
## frame from a loading screen.
static func prebuild_some(adef: AircraftDef, budget_usec: int) -> float:
	var start := Time.get_ticks_usec()
	var total := adef.parts.size()
	var done := 0
	for part: PartDef in adef.parts:
		if _mesh_cache.has("%s/%s/%d" % [adef.id, part.name, detail]):
			done += 1
			continue
		if Time.get_ticks_usec() - start > budget_usec and done > 0:
			break
		part_meshes(adef, part)
		done += 1
		if Time.get_ticks_usec() - start > budget_usec:
			break
	return float(done) / float(maxi(total, 1))


static func part_meshes(adef: AircraftDef, part: PartDef) -> PartMeshes:
	var key := "%s/%s/%d" % [adef.id, part.name, detail]
	_cache_mutex.lock()
	var found: PartMeshes = _mesh_cache.get(key)
	_cache_mutex.unlock()
	if found != null:
		return found
	var built := MeshFactory.build_part(adef, part, detail)
	_cache_mutex.lock()
	_mesh_cache[key] = built
	_cache_mutex.unlock()
	return built


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH) as Shader
		_material.set_shader_parameter(&"atlas", load(ATLAS_PATH))
	return _material


static func interior_material() -> ShaderMaterial:
	if _interior_material == null:
		_interior_material = ShaderMaterial.new()
		_interior_material.shader = load(INTERIOR_SHADER_PATH) as Shader
		_interior_material.set_shader_parameter(&"atlas", load(ATLAS_PATH))
	return _interior_material


## Atlas rectangle for primitive meshes whose UVs span 0..1.
static func tile_rect(tile: Vector2i) -> Vector4:
	return Vector4((float(tile.x) * 256.0 + 6.0) / 1024.0, (float(tile.y) * 256.0 + 6.0) / 1024.0,
			244.0 / 1024.0, 244.0 / 1024.0)


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


## Visual subtree for one part, in the part's local frame:
##   Core   internal structure (hidden while the skin is whole, except engines)
##   Far    merged far-LOD mesh
##   P<n>   skin pieces, in the order of PartMeshes.pieces
## Gear instead has Leg/Strut and Leg/Wheels.
static func build_part_visual(adef: AircraftDef, part: PartDef) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var cut_x := -part.com.x
	var meshes := part_meshes(adef, part)
	if part.kind == PartDef.Kind.GEAR:
		var leg := Node3D.new()
		leg.name = "Leg"
		leg.position = part.p0 - part.com
		root.add_child(leg)
		var strut := _mesh_instance(meshes.strut, cut_x - leg.position.x)
		strut.name = "Strut"
		strut.visibility_range_end = LOD_DISTANCE * 4.0
		leg.add_child(strut)
		var wheels := _mesh_instance(meshes.wheels, cut_x - leg.position.x)
		wheels.name = "Wheels"
		wheels.visibility_range_end = LOD_DISTANCE * 4.0
		leg.add_child(wheels)
		return root
	if meshes.core != null:
		var core := MeshInstance3D.new()
		core.name = "Core"
		core.mesh = meshes.core
		core.material_override = interior_material()
		core.set_instance_shader_parameter(&"cut_plane_x", cut_x)
		core.visible = meshes.core_always_visible
		core.visibility_range_end = LOD_DISTANCE * 3.0
		root.add_child(core)
	if meshes.far != null:
		var far := _mesh_instance(meshes.far, cut_x)
		far.name = "Far"
		far.visibility_range_begin = LOD_DISTANCE
		far.visibility_range_begin_margin = 8.0
		root.add_child(far)
	for i: int in meshes.pieces.size():
		var piece := meshes.pieces[i]
		var mi := _mesh_instance(piece.mesh, cut_x - piece.xform.origin.x)
		mi.name = "P%d" % i
		mi.transform = piece.xform
		mi.visibility_range_end = LOD_DISTANCE
		mi.visibility_range_end_margin = 8.0
		root.add_child(mi)
	_add_lights(adef, part, root)
	var flag := 0.0
	if part.kind == PartDef.Kind.FUSELAGE:
		flag = 1.0
	elif part.kind == PartDef.Kind.FIN:
		flag = 2.0
	if flag > 0.0 and not adef.livery.is_empty():
		# Part-local coordinates to the fuselage frame (station from the nose
		# tip, height above the fuselage centreline); hinged pieces such as the
		# rudder carry their own mesh origin.
		var frame := Vector3(part.com.x, part.com.y - fuselage_axis_y(adef), part.com.z - nose_station_zero(adef))
		for child: Node in root.get_children():
			if child is MeshInstance3D and child.name != &"Core":
				var mi := child as MeshInstance3D
				var f := frame + mi.position
				mi.set_instance_shader_parameter(&"livery_frame", Vector4(f.x, f.y, f.z, flag))
	return root


## Height of the fuselage centreline (the fuselage parts share it).
static func fuselage_axis_y(adef: AircraftDef) -> float:
	for part: PartDef in adef.parts:
		if part.kind == PartDef.Kind.FUSELAGE:
			return part.p0.y
	return 0.0


## Z of the nose tip: stations in the livery are measured aft of it.
static func nose_station_zero(adef: AircraftDef) -> float:
	var z := INF
	for part: PartDef in adef.parts:
		if part.kind == PartDef.Kind.FUSELAGE:
			z = minf(z, part.p0.z)
	return z


## Puts the aircraft's window rows, doors and windscreen on the shared
## airframe material (one aircraft is shown at a time).
static func apply_livery(adef: AircraftDef) -> void:
	var mat := material()
	var l := adef.livery
	for key: String in ["win_size", "win_row0", "win_row1", "cockpit_a", "cockpit_b", "cockpit_splits",
			"panel_lines"]:
		mat.set_shader_parameter(StringName(key), l.get(key, Vector4.ZERO))
	var doors := PackedVector4Array()
	doors.resize(12)
	var list: Array = l.get("doors", [])
	for i: int in mini(list.size(), 12):
		doors[i] = list[i]
	mat.set_shader_parameter(&"doors", doors)
	_apply_paint(adef, mat)


## The airline livery: fuselage colours, cheatlines, titles and the fin art.
static func _apply_paint(adef: AircraftDef, mat: ShaderMaterial) -> void:
	var p: Dictionary = adef.livery.get("paint", {})
	if p.is_empty():
		mat.set_shader_parameter(&"fus_base", Vector4(0.95, 0.95, 0.94, 0.0))
		mat.set_shader_parameter(&"fin_geo2", Vector4.ZERO)
		return
	var base: Color = p.get("base", Color(0.95, 0.95, 0.94))
	mat.set_shader_parameter(&"fus_base", Vector4(base.r, base.g, base.b, 1.0))
	var belly: Color = p.get("belly", base)
	mat.set_shader_parameter(&"belly_col", Vector4(belly.r, belly.g, belly.b, 1.0))
	mat.set_shader_parameter(&"belly_line", p.get("belly_line", Vector4(-100.0, 1000.0, 0.0, 0.04)))
	var radome: Color = p.get("radome", base)
	mat.set_shader_parameter(&"radome", Vector4(radome.r, radome.g, radome.b, float(p.get("radome_len", 0.0))))
	var cheats := PackedVector4Array()
	var cheat_cols := PackedVector4Array()
	cheats.resize(3)
	cheat_cols.resize(3)
	var list: Array = p.get("cheats", [])
	for i: int in mini(list.size(), 3):
		var c: Array = list[i]
		cheats[i] = c[1]
		var col: Color = c[0]
		cheat_cols[i] = Vector4(col.r, col.g, col.b, 1.0)
	mat.set_shader_parameter(&"cheat", cheats)
	mat.set_shader_parameter(&"cheat_col", cheat_cols)
	# Titles: up to two strings, stroked from StrokeFont segments.
	var segs := PackedVector4Array()
	var boxes := PackedVector4Array()
	var cols := PackedVector4Array()
	boxes.resize(2)
	cols.resize(2)
	var ranges := Vector4.ZERO
	var texts: Array = p.get("texts", [])
	for i: int in mini(texts.size(), 2):
		var t: Array = texts[i]
		var first := segs.size()
		var width := StrokeFont.segments(String(t[0]), segs)
		boxes[i] = t[2]
		var col: Color = t[1]
		cols[i] = Vector4(col.r, col.g, col.b, width)
		if i == 0:
			ranges.x = first
			ranges.y = segs.size()
		else:
			ranges.z = first
			ranges.w = segs.size()
	segs.resize(96)
	mat.set_shader_parameter(&"text_segs", segs)
	mat.set_shader_parameter(&"text_box", boxes)
	mat.set_shader_parameter(&"text_col", cols)
	mat.set_shader_parameter(&"text_range", ranges)
	# Fin art in fin coordinates.
	mat.set_shader_parameter(&"fin_geo", p.get("fin_geo", Vector4.ZERO))
	mat.set_shader_parameter(&"fin_geo2", p.get("fin_geo2", Vector4.ZERO))
	var shapes := PackedVector4Array()
	var shape_cols := PackedVector4Array()
	shapes.resize(6)
	shape_cols.resize(6)
	var fs: Array = p.get("fin_shapes", [])
	for i: int in mini(fs.size(), 6):
		var f: Array = fs[i]
		shapes[i] = Vector4(f[0], f[1], f[2], f[3])
		var col: Color = f[4]
		shape_cols[i] = Vector4(col.r, col.g, col.b, f[5] if f.size() > 5 else 0.0)
	mat.set_shader_parameter(&"fin_shape", shapes)
	mat.set_shader_parameter(&"fin_shape_col", shape_cols)


static var _light_mats: Dictionary = {}


static func _light_material(col: Color) -> StandardMaterial3D:
	if not _light_mats.has(col):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 4.0
		_light_mats[col] = m
	return _light_mats[col]


## Navigation lights (red left tip, green right tip, white tail), white
## wingtip and tail strobes, and red beacons on the crown and belly. Strobes
## and beacons start dark; Aircraft flashes them in flight.
static func _add_lights(adef: AircraftDef, part: PartDef, root: Node3D) -> void:
	var size := clampf(adef.wing_span * 0.0045, 0.06, 0.2)
	var at: Array[Vector3] = []
	var cols: Array[Color] = []
	var kinds: Array[String] = []
	if part.kind == PartDef.Kind.WING and String(part.name).ends_with("_out"):
		var tip := part.p1 - part.com
		var outward := Vector3(signf(tip.x + part.com.x), 0.0, 0.0)
		at.append(tip + outward * 0.15 - Vector3(0.0, 0.0, 0.2 * part.r1))
		cols.append(Color(1.0, 0.08, 0.05) if outward.x < 0.0 else Color(0.1, 1.0, 0.25))
		kinds.append("Nav")
		at.append(tip + outward * 0.15 + Vector3(0.0, 0.0, 0.35 * part.r1))
		cols.append(Color(1.0, 1.0, 1.0))
		kinds.append("Strobe")
	elif part.kind == PartDef.Kind.FUSELAGE:
		var length := (part.p1 - part.p0).length()
		if part.shape_b > 0.0:
			var pr := MeshFactory.body_profile(part, length, length)
			var tail := part.p1 - part.com + Vector3(0.0, pr.y, 0.0) + Vector3(0.0, 0.0, 0.05)
			at.append(tail)
			cols.append(Color(1.0, 0.98, 0.92))
			kinds.append("Nav")
		elif String(part.name) == "fus_mid":
			var c := (part.p0 + part.p1) * 0.5 - part.com
			var ry := part.r0 * part.squash.y
			at.append(c + Vector3(0.0, ry + size * 0.5, 0.0))
			cols.append(Color(1.0, 0.05, 0.02))
			kinds.append("Beacon")
			at.append(c - Vector3(0.0, ry + size * 0.5, -1.5))
			cols.append(Color(1.0, 0.05, 0.02))
			kinds.append("Beacon")
	if at.is_empty():
		return
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	for i: int in at.size():
		var mi := MeshInstance3D.new()
		mi.name = "%s%d" % [kinds[i], i]
		mi.mesh = mesh
		mi.material_override = _light_material(cols[i])
		mi.position = at[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = kinds[i] == "Nav"
		root.add_child(mi)


## Static display model (no physics) with the aircraft origin at the node
## origin. Gear is drawn at its static stroke so the wheels sit on the floor
## when the model is placed `ground_clearance` above it.
static func build_display_model(adef: AircraftDef) -> Node3D:
	apply_livery(adef)
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
		PartDef.Kind.GEAR, PartDef.Kind.CANOPY:
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
	var meshes := part_meshes(adef, part)
	body.pieces = meshes.pieces
	body.core_node = body.visual.get_node_or_null("Core") as MeshInstance3D
	body.far_node = body.visual.get_node_or_null("Far") as MeshInstance3D
	body.core_always_visible = meshes.core_always_visible
	for i: int in meshes.pieces.size():
		body.piece_nodes.append(body.visual.get_node("P%d" % i) as MeshInstance3D)
	body.pieces_left = meshes.pieces.size()
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
