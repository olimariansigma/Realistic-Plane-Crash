class_name AircraftPart
extends RigidBody3D
## One structural chunk. Besides being a rigid body it keeps the books the
## structure monitor needs: every force the game applies goes through
## push_force/push_torque so the externally applied load is known exactly.

var def: PartDef
var index: int = 0
var parent_index: int = -1
## Joint to the parent part; null for the root or once broken.
var joint: Generic6DOFJoint3D
## Anchor of that joint in this part's local frame.
var anchor_local: Vector3
## Index of the root of the connected assembly this part currently belongs to.
var assembly_root: int = 0

# Per-tick cache, refreshed by begin_tick().
var xf: Transform3D
var lin_vel: Vector3
var ang_vel: Vector3

# Forces applied by game code this tick (world frame; torque about the CoM).
var ext_force: Vector3
var ext_torque: Vector3

# State from the previous tick, for finite-difference accelerations.
var prev_lin_vel: Vector3
var prev_ang_mom: Vector3
var has_prev: bool = false

# Contact summary for the last physics step, filled in _integrate_forces.
var contact_count: int = 0
var contact_impulse: Vector3
var contact_torque_impulse: Vector3
## Largest single contact this step: its world position, impulse, and the
## closing speed along the contact normal. Drives crumple and damage.
var hit_position: Vector3
var hit_impulse: Vector3
var hit_speed: float = 0.0

## Crush energy absorbed so far (J) and the deepest dent (m).
var crush_energy: float = 0.0
var crush_depth: float = 0.0
## Deepest a dent may go on this part (set by the builder from its size).
var crumple_limit: float = 1.0
## Fire intensity 0..1 (0 = not burning) and seconds alight.
var burning: float = 0.0
var burn_time: float = 0.0
## Physics tick of the last impact event raised for this part.
var last_hit_tick: int = -1000
var pending_hit_energy: float = 0.0

# Two dent slots mirrored into the crumple shader: centre, push vector (both
# part-local), radius and depth.
var _dent_a_pos: Vector3
var _dent_a_push: Vector3
var _dent_a_radius: float = 0.0
var _dent_a_depth: float = 0.0
var _dent_b_pos: Vector3
var _dent_b_push: Vector3
var _dent_b_radius: float = 0.0
var _dent_b_depth: float = 0.0

var visual: Node3D
## Skin pieces (shared with every aircraft of this type) and this part's own
## node for each; an entry goes null once that piece has been torn off.
var pieces: Array[SkinPiece] = []
var piece_nodes: Array[MeshInstance3D] = []
var pieces_left: int = 0
var core_node: MeshInstance3D
var far_node: MeshInstance3D
var core_always_visible: bool = false
## True once any skin has been lost.
var stripped: bool = false
## Hidden nodes of pieces already torn off, by piece index (for the replay).
var _released_nodes: Dictionary = {}


func begin_tick() -> void:
	xf = global_transform
	lin_vel = linear_velocity
	ang_vel = angular_velocity


func push_force(force: Vector3, world_pos: Vector3) -> void:
	var r := world_pos - xf.origin
	apply_force(force, r)
	ext_force += force
	ext_torque += r.cross(force)


func push_central_force(force: Vector3) -> void:
	apply_central_force(force)
	ext_force += force


func push_torque(torque: Vector3) -> void:
	apply_torque(torque)
	ext_torque += torque


func velocity_at(world_pos: Vector3) -> Vector3:
	return lin_vel + ang_vel.cross(world_pos - xf.origin)


## Angular momentum about the CoM in the world frame. The body's principal
## axes are its local axes by construction (see AirframeBuilder).
func angular_momentum() -> Vector3:
	var b := xf.basis
	var w_local := b.transposed() * ang_vel
	return b * (w_local * inertia)


## Records a dent of `depth` metres centred at `local_pos`, pushed along
## `local_dir`. Hits near an existing dent deepen it; otherwise the shallower
## of the two slots is reused. Only touches the shader when something changes.
func add_dent(local_pos: Vector3, local_dir: Vector3, depth: float) -> void:
	if pieces.is_empty() or depth < 0.02:
		return
	depth = minf(depth, crumple_limit)
	crush_depth = maxf(crush_depth, depth)
	var radius := clampf(depth * 2.5 + 0.8, 0.8, crumple_limit * 3.5)
	if _dent_a_radius > 0.0 and local_pos.distance_to(_dent_a_pos) < _dent_a_radius * 0.8:
		_dent_a_depth = minf(_dent_a_depth + depth * 0.6, crumple_limit)
		_dent_a_radius = maxf(_dent_a_radius, clampf(_dent_a_depth * 2.5 + 0.8, 0.8, crumple_limit * 3.5))
		_dent_a_push = (_dent_a_push.normalized() + local_dir * 0.5).normalized() * _dent_a_depth
		crush_depth = maxf(crush_depth, _dent_a_depth)
	elif _dent_b_radius > 0.0 and local_pos.distance_to(_dent_b_pos) < _dent_b_radius * 0.8:
		_dent_b_depth = minf(_dent_b_depth + depth * 0.6, crumple_limit)
		_dent_b_radius = maxf(_dent_b_radius, clampf(_dent_b_depth * 2.5 + 0.8, 0.8, crumple_limit * 3.5))
		_dent_b_push = (_dent_b_push.normalized() + local_dir * 0.5).normalized() * _dent_b_depth
		crush_depth = maxf(crush_depth, _dent_b_depth)
	elif _dent_a_radius <= 0.0 or (_dent_b_radius > 0.0 and _dent_a_depth <= _dent_b_depth
			and depth > _dent_a_depth):
		_dent_a_pos = local_pos
		_dent_a_push = local_dir * depth
		_dent_a_radius = radius
		_dent_a_depth = depth
	elif _dent_b_radius <= 0.0 or depth > _dent_b_depth:
		_dent_b_pos = local_pos
		_dent_b_push = local_dir * depth
		_dent_b_radius = radius
		_dent_b_depth = depth
	else:
		return
	_push_dents(far_node)
	for i: int in piece_nodes.size():
		# Hinged pieces have their own mesh frame, so part-local dents do not apply.
		if piece_nodes[i] != null and pieces[i].control == SkinPiece.Surface.NONE:
			_push_dents(piece_nodes[i])


## Dent slot 0 or 1 as (centre x, y, z, radius); radius 0 means unused.
func dent_slot(slot: int) -> Vector4:
	if slot == 0:
		return Vector4(_dent_a_pos.x, _dent_a_pos.y, _dent_a_pos.z, _dent_a_radius)
	return Vector4(_dent_b_pos.x, _dent_b_pos.y, _dent_b_pos.z, _dent_b_radius)


func dent_push(slot: int) -> Vector3:
	return _dent_a_push if slot == 0 else _dent_b_push


## Shows the given dent state on the meshes without touching the recorded
## damage. Used by the replay to rewind and re-apply crumpling.
func show_dents(a: Vector4, a_push: Vector3, b: Vector4, b_push: Vector3) -> void:
	_show_dents_on(far_node, a, a_push, b, b_push)
	for i: int in piece_nodes.size():
		var node := piece_nodes[i] if piece_nodes[i] != null else _released_nodes.get(i) as MeshInstance3D
		if node != null and pieces[i].control == SkinPiece.Surface.NONE:
			_show_dents_on(node, a, a_push, b, b_push)


func _show_dents_on(mesh: MeshInstance3D, a: Vector4, a_push: Vector3, b: Vector4, b_push: Vector3) -> void:
	if mesh == null:
		return
	mesh.set_instance_shader_parameter(&"dent_a", a)
	mesh.set_instance_shader_parameter(&"dent_a_push", a_push)
	mesh.set_instance_shader_parameter(&"dent_b", b)
	mesh.set_instance_shader_parameter(&"dent_b_push", b_push)


func _push_dents(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	mesh.set_instance_shader_parameter(&"dent_a",
			Vector4(_dent_a_pos.x, _dent_a_pos.y, _dent_a_pos.z, _dent_a_radius))
	mesh.set_instance_shader_parameter(&"dent_a_push", _dent_a_push)
	mesh.set_instance_shader_parameter(&"dent_b",
			Vector4(_dent_b_pos.x, _dent_b_pos.y, _dent_b_pos.z, _dent_b_radius))
	mesh.set_instance_shader_parameter(&"dent_b_push", _dent_b_push)


func set_scorch(amount: float) -> void:
	if far_node != null:
		far_node.set_instance_shader_parameter(&"scorch", amount)
	for node: MeshInstance3D in piece_nodes:
		if node != null:
			node.set_instance_shader_parameter(&"scorch", amount)


## Index of the attached skin piece nearest to `local_pos`, or -1 if none lies
## within `max_distance`.
func nearest_piece(local_pos: Vector3, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance * max_distance
	for i: int in pieces.size():
		if piece_nodes[i] == null:
			continue
		var d := pieces[i].center.distance_squared_to(local_pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## Tears skin piece `index` off this part. Returns the node that was showing
## it (now hidden), so its dents and scorch can be copied onto the flying
## chunk; the caller owns spawning that chunk.
func release_piece(index: int) -> MeshInstance3D:
	var node := piece_nodes[index]
	if node == null:
		return null
	piece_nodes[index] = null
	_released_nodes[index] = node
	pieces_left -= 1
	node.visible = false
	mass = maxf(mass - pieces[index].mass, def.mass * 0.4)
	if not stripped:
		stripped = true
		# From now on the part is drawn piece by piece at any distance, over
		# its exposed structure.
		if far_node != null:
			far_node.visible = false
		if core_node != null:
			core_node.visible = true
			core_node.visibility_range_end = 0.0
		for other: MeshInstance3D in piece_nodes:
			if other != null:
				other.visibility_range_end = 0.0
	return node


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var n := state.get_contact_count()
	contact_count = n
	contact_impulse = Vector3.ZERO
	contact_torque_impulse = Vector3.ZERO
	hit_speed = 0.0
	hit_impulse = Vector3.ZERO
	if n == 0:
		return
	var origin := state.transform.origin
	var best := 0.0
	for i: int in n:
		var j := state.get_contact_impulse(i)
		var pos := state.get_contact_collider_position(i)
		contact_impulse += j
		contact_torque_impulse += (pos - origin).cross(j)
		var mag := j.length_squared()
		if mag > best:
			best = mag
			hit_position = pos
			hit_impulse = j
			var normal := state.get_contact_local_normal(i)
			var rel := state.get_contact_local_velocity_at_position(i) \
					- state.get_contact_collider_velocity_at_position(i)
			hit_speed = maxf(-rel.dot(normal), 0.0)
