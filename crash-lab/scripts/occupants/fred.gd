class_name Fred
extends Node3D
## FRED: a nine-body crash-test dummy held together with Jolt 6-DOF joints.
##
## Until an impact is imminent a FRED is dormant: its bodies are frozen and
## carry no joints, so a cabin full of dummies costs the solver nothing in
## normal flight. activate() poses it on its seat, gives every limb the
## seat's velocity, and wires the joints (including the belt to the seat).
## From then on each limb's felt acceleration is tracked every physics tick.

enum Limb { PELVIS, CHEST, HEAD, ARM_L, ARM_R, THIGH_L, THIGH_R, SHIN_L, SHIN_R }

const LIMB_NAMES: Array[String] = ["Pelvis", "Chest", "Head", "Left arm", "Right arm",
		"Left thigh", "Right thigh", "Left shin", "Right shin"]
const LIMB_MASS: Array[float] = [12.0, 28.0, 5.0, 4.5, 4.5, 9.0, 9.0, 5.0, 5.0]
const TOTAL_MASS := 82.0
const LAYER_WORLD := 1
const LAYER_OCCUPANT := 8
const GRAVITY := 9.80665
## Time constant of the per-limb acceleration filter (s). Limbs are loaded
## through belts and joints with some give, so pulses shorter than this are
## solver artefacts rather than something a body would feel.
const LIMB_FILTER_TAU := 0.03
## Seat mount, modelled as a plastic energy absorber between the seat and the
## dummy's pelvis. It stands in for everything that gives in a real crash and
## that rigid bodies lack: underfloor crush, seat stroke, belt stretch.
##   - Natural frequency chosen so an abrupt 13.4 m/s stop (the 14 CFR 25.562
##     longitudinal test) peaks near that test's 16 g: a ~ 0.8 * omega * dv.
##   - Stroke is the owning part's `crush_depth`. Past it the mount bottoms
##     out on a much stiffer stop: the survivable volume is gone.
##   - Plastic: it resists being stretched but does not spring back.
const MOUNT_OMEGA := 14.6
const MOUNT_DAMPING := 300.0
const MOUNT_STOP_FACTOR := 30.0
## Restraint failure: sustained mount load equivalent to this many g on the
## whole dummy (seat attachments are certified to 16 g and fail well above).
const BELT_BREAK_G := 34.0
const YELLOW := Color(0.96, 0.78, 0.1)
const DARK := Color(0.12, 0.12, 0.13)

static var _meshes: Array[Mesh] = []
static var _shapes: Array[Shape3D] = []

var seat: Seat
## The fuselage part the seat is bolted to.
var anchor: AircraftPart
var limbs: Array[RigidBody3D] = []
var active: bool = false
var ejected: bool = false
## Peak felt acceleration per limb, in g.
var peak_g: PackedFloat32Array
## Head injury criterion over windows of up to two physics ticks (~33 ms).
var hic: float = 0.0
## Peak restraint load (N) and the furthest the seat mount stroked (m).
var belt_peak: float = 0.0
var stroke_peak: float = 0.0
## True once the mount used its whole stroke (structure crushed to the seat).
var bottomed: bool = false

var _local: Array[Transform3D] = []
var _prev_vel: PackedVector3Array
var _accel: PackedVector3Array
var _head_prev_g: float = 0.0
var _belt_filtered: float = 0.0
var _joints: Array[Generic6DOFJoint3D] = []
var _joint_a: PackedInt32Array
var _joint_b: PackedInt32Array
var _belts: Array[Generic6DOFJoint3D] = []
var _stroke_limit: float = 0.5
var _mount_set := Vector3.ZERO
var _chest_set := Vector3.ZERO


## Capsule/box/sphere dimensions per limb: (radius or half-width, length).
static func _ensure_shared() -> void:
	if not _meshes.is_empty():
		return
	var dims: Array[Vector3] = [
		Vector3(0.34, 0.2, 0.24), Vector3(0.36, 0.42, 0.22), Vector3(0.105, 0.0, 0.0),
		Vector3(0.045, 0.55, 0.0), Vector3(0.045, 0.55, 0.0), Vector3(0.07, 0.44, 0.0),
		Vector3(0.07, 0.44, 0.0), Vector3(0.05, 0.46, 0.0), Vector3(0.05, 0.46, 0.0),
	]
	for i: int in dims.size():
		var d := dims[i]
		if i <= Limb.CHEST:
			var box := BoxMesh.new()
			box.size = d
			_meshes.append(box)
			var shape := BoxShape3D.new()
			shape.size = d
			_shapes.append(shape)
		elif i == Limb.HEAD:
			var sphere := SphereMesh.new()
			sphere.radius = d.x
			sphere.height = d.x * 2.0
			sphere.radial_segments = 10
			sphere.rings = 5
			_meshes.append(sphere)
			var shape := SphereShape3D.new()
			shape.radius = d.x
			_shapes.append(shape)
		else:
			var capsule := CapsuleMesh.new()
			capsule.radius = d.x
			capsule.height = d.y
			capsule.radial_segments = 6
			capsule.rings = 2
			_meshes.append(capsule)
			var shape := CapsuleShape3D.new()
			shape.radius = d.x
			shape.height = d.y
			_shapes.append(shape)


## Limb poses relative to the hip point, seated and facing -Z.
static func seated_pose() -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	pose.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, 0.0)))
	pose.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.36, 0.03)))
	pose.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.72, 0.02)))
	for side: float in [-1.0, 1.0]:
		pose.append(_segment(Vector3(side * 0.24, 0.52, 0.03), Vector3(side * 0.22, 0.1, -0.28)))
	for side: float in [-1.0, 1.0]:
		pose.append(_segment(Vector3(side * 0.1, 0.0, -0.04), Vector3(side * 0.1, 0.02, -0.46)))
	for side: float in [-1.0, 1.0]:
		pose.append(_segment(Vector3(side * 0.1, 0.02, -0.48), Vector3(side * 0.1, -0.42, -0.5)))
	return pose


## Transform whose Y axis runs from `a` to `b`, centred between them.
static func _segment(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.BACK)
	x = Vector3.RIGHT if x.length_squared() < 0.001 else x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)


static func _limb_mesh(index: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[index]
	mi.material_override = AirframeBuilder.material()
	mi.set_instance_shader_parameter(&"cut_plane_x", 1.0e6)
	mi.set_instance_shader_parameter(&"tint",
			DARK if index == Limb.PELVIS or index >= Limb.SHIN_L else YELLOW)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 220.0
	return mi


## Physics-free seated dummy for the hangar, origin at the hip point.
static func build_static() -> Node3D:
	_ensure_shared()
	var root := Node3D.new()
	root.name = "FredStatic"
	var pose := seated_pose()
	for i: int in pose.size():
		var mi := _limb_mesh(i)
		mi.transform = pose[i]
		root.add_child(mi)
	return root


func setup(target_seat: Seat, anchor_part: AircraftPart) -> void:
	_ensure_shared()
	seat = target_seat
	anchor = anchor_part
	seat.fred = self
	name = "Fred_%s" % seat.label.replace("/", "")
	var pose := seated_pose()
	var count := pose.size()
	peak_g.resize(count)
	_prev_vel.resize(count)
	_accel.resize(count)
	for i: int in count:
		var body := RigidBody3D.new()
		body.name = LIMB_NAMES[i].replace(" ", "")
		body.mass = LIMB_MASS[i]
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.can_sleep = true
		var collider := CollisionShape3D.new()
		collider.shape = _shapes[i]
		body.add_child(collider)
		body.add_child(_limb_mesh(i))
		add_child(body)
		limbs.append(body)
		_local.append(Transform3D(Basis.IDENTITY, seat.local_pos) * pose[i])
	# Joint nodes exist from the start but stay unwired (and so inactive)
	# until activate(): a joint from a frozen limb to the moving fuselage
	# would pin the aircraft in place.
	_add_joint(Limb.PELVIS, Limb.CHEST, Vector3(0.0, 0.14, 0.02), Vector3(-70.0, 12.0, 15.0), Vector3(15.0, 12.0, 15.0))
	_add_joint(Limb.CHEST, Limb.HEAD, Vector3(0.0, 0.6, 0.02), Vector3(-60.0, 40.0, 30.0), Vector3(45.0, 40.0, 30.0))
	_add_joint(Limb.CHEST, Limb.ARM_L, Vector3(-0.24, 0.52, 0.03), Vector3(-120.0, 40.0, 60.0), Vector3(50.0, 40.0, 20.0))
	_add_joint(Limb.CHEST, Limb.ARM_R, Vector3(0.24, 0.52, 0.03), Vector3(-120.0, 40.0, 20.0), Vector3(50.0, 40.0, 60.0))
	_add_joint(Limb.PELVIS, Limb.THIGH_L, Vector3(-0.1, 0.0, -0.04), Vector3(-40.0, 15.0, 15.0), Vector3(30.0, 15.0, 15.0))
	_add_joint(Limb.PELVIS, Limb.THIGH_R, Vector3(0.1, 0.0, -0.04), Vector3(-40.0, 15.0, 15.0), Vector3(30.0, 15.0, 15.0))
	_add_joint(Limb.THIGH_L, Limb.SHIN_L, Vector3(-0.1, 0.02, -0.47), Vector3(-60.0, 3.0, 3.0), Vector3(70.0, 3.0, 3.0))
	_add_joint(Limb.THIGH_R, Limb.SHIN_R, Vector3(0.1, 0.02, -0.47), Vector3(-60.0, 3.0, 3.0), Vector3(70.0, 3.0, 3.0))
	# The belt joint only keeps the pelvis square to the seat; the mount force
	# in tick() carries the load. Translation is free.
	var belt := _make_joint("Belt", Vector3(0.0, 0.0, 0.05), Vector3(-12.0, 8.0, 8.0), Vector3(12.0, 8.0, 8.0))
	for axis: String in ["x", "y", "z"]:
		belt.set("linear_limit_%s/enabled" % axis, false)
	_belts.append(belt)
	_stroke_limit = maxf(anchor.def.crush_depth, 0.1) if anchor.def != null else 0.5
	sync_pose()
	visible = false


## `lower` / `upper` are angular limits in degrees about the aircraft X
## (flexion), Y (twist) and Z (side bend) axes.
func _make_joint(joint_name: String, hip_offset: Vector3, lower: Vector3, upper: Vector3) -> Generic6DOFJoint3D:
	var joint := Generic6DOFJoint3D.new()
	joint.name = joint_name
	joint.exclude_nodes_from_collision = true
	joint.set(&"angular_limit_x/lower_angle", deg_to_rad(lower.x))
	joint.set(&"angular_limit_x/upper_angle", deg_to_rad(upper.x))
	joint.set(&"angular_limit_y/lower_angle", deg_to_rad(-lower.y))
	joint.set(&"angular_limit_y/upper_angle", deg_to_rad(upper.y))
	joint.set(&"angular_limit_z/lower_angle", deg_to_rad(-lower.z))
	joint.set(&"angular_limit_z/upper_angle", deg_to_rad(upper.z))
	joint.set_meta(&"hip_offset", hip_offset)
	add_child(joint)
	return joint


func _add_joint(a: Limb, b: Limb, hip_offset: Vector3, lower: Vector3, upper: Vector3) -> void:
	_joints.append(_make_joint("%s_%s" % [limbs[a].name, limbs[b].name], hip_offset, lower, upper))
	_joint_a.append(a)
	_joint_b.append(b)


## Puts every limb back on the seat in the rest pose (dormant dummies only).
func sync_pose() -> void:
	var base := anchor.global_transform
	for i: int in limbs.size():
		limbs[i].global_transform = base * _local[i]


## Wakes the dummy: pose, velocities, joints, collisions.
func activate() -> void:
	if active:
		return
	active = true
	var base := anchor.global_transform
	var v := anchor.linear_velocity
	var w := anchor.angular_velocity
	for i: int in limbs.size():
		var body := limbs[i]
		var xf := base * _local[i]
		body.global_transform = xf
		body.freeze = false
		body.collision_layer = LAYER_OCCUPANT
		body.collision_mask = LAYER_WORLD
		var vel := v + w.cross(xf.origin - base.origin)
		body.linear_velocity = vel
		body.angular_velocity = w
		body.reset_physics_interpolation()
		_prev_vel[i] = vel
		_accel[i] = Vector3.ZERO
	var hip := base * Transform3D(Basis.IDENTITY, seat.local_pos)
	for k: int in _joints.size():
		var joint := _joints[k]
		joint.global_transform = hip * Transform3D(Basis.IDENTITY, joint.get_meta(&"hip_offset") as Vector3)
		joint.node_a = joint.get_path_to(limbs[_joint_a[k]])
		joint.node_b = joint.get_path_to(limbs[_joint_b[k]])
	for belt: Generic6DOFJoint3D in _belts:
		belt.global_transform = hip * Transform3D(Basis.IDENTITY, belt.get_meta(&"hip_offset") as Vector3)
		belt.node_a = belt.get_path_to(anchor)
		belt.node_b = belt.get_path_to(limbs[Limb.PELVIS])


## Per-tick tracking for an active dummy.
func tick(dt: float) -> void:
	if not active:
		return
	var alpha := 1.0 - exp(-dt / LIMB_FILTER_TAU)
	var inv_dt := 1.0 / dt
	var net := Vector3.ZERO
	for i: int in limbs.size():
		var v := limbs[i].linear_velocity
		# Felt acceleration: what an accelerometer on the limb would read.
		var felt := (v - _prev_vel[i]) * inv_dt + Vector3(0.0, GRAVITY, 0.0)
		_prev_vel[i] = v
		net += felt * LIMB_MASS[i]
		var a := _accel[i].lerp(felt, alpha)
		_accel[i] = a
		var g := a.length() / GRAVITY
		if g > peak_g[i]:
			peak_g[i] = g
		if i == Limb.HEAD:
			# HIC = max over windows of (mean g)^2.5 * duration.
			var one := pow(g, 2.5) * dt
			var two := pow((g + _head_prev_g) * 0.5, 2.5) * (dt * 2.0)
			hic = maxf(hic, maxf(one, two))
			_head_prev_g = g
	if ejected:
		return
	var load := _mount_force(Limb.PELVIS, TOTAL_MASS, true, dt)
	if seat.is_crew:
		# Shoulder harness: a second, lighter mount holding the chest.
		load += _mount_force(Limb.CHEST, LIMB_MASS[Limb.CHEST] + LIMB_MASS[Limb.HEAD], false, dt)
	_belt_filtered = lerpf(_belt_filtered, load, alpha)
	belt_peak = maxf(belt_peak, _belt_filtered)
	if _belt_filtered > BELT_BREAK_G * GRAVITY * TOTAL_MASS:
		eject()


## Applies the seat-mount force to one limb (and its reaction to the seat's
## part, so the structure monitor sees it). Returns the force magnitude.
func _mount_force(limb: int, carried_mass: float, is_pelvis: bool, dt: float) -> float:
	var body := limbs[limb]
	var rest := anchor.xf * _local[limb].origin
	var pos := body.global_position
	var offset := pos - rest
	var rel_vel := body.linear_velocity - anchor.velocity_at(rest)
	var set_point := _mount_set if is_pelvis else _chest_set
	var stretch := offset - set_point
	if stretch.dot(rel_vel) < 0.0:
		# Unloading: the crushed structure stays crushed.
		set_point += stretch * minf(dt * 25.0, 1.0)
		stretch = offset - set_point
	var k := carried_mass * MOUNT_OMEGA * MOUNT_OMEGA
	var force := stretch * -k - rel_vel * (MOUNT_DAMPING * carried_mass / TOTAL_MASS)
	var travel := offset.length()
	if is_pelvis:
		stroke_peak = maxf(stroke_peak, travel)
		_mount_set = set_point
	else:
		_chest_set = set_point
	if travel > _stroke_limit:
		bottomed = true
		force -= offset * ((travel - _stroke_limit) / travel * k * MOUNT_STOP_FACTOR)
	body.apply_central_force(force)
	anchor.push_force(-force, rest)
	return force.length()


## Restraint failure: the dummy is thrown clear.
func eject() -> void:
	if ejected:
		return
	ejected = true
	for belt: Generic6DOFJoint3D in _belts:
		belt.queue_free()
	_belts.clear()
	visible = true


func worst_limb() -> int:
	var best := 0
	for i: int in peak_g.size():
		if peak_g[i] > peak_g[best]:
			best = i
	return best
