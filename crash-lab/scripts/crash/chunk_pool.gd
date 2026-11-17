class_name ChunkPool
extends Node3D
## Fixed pool of rigid bodies that carry torn-off skin pieces. A body borrows
## the piece's mesh and a box collider sized to it, flies and tumbles as its
## own object, then is frozen once it has settled.
##
## Nothing ever vanishes: a body is only reused once its chunk has settled,
## and the settled chunk is first replaced by a static copy left lying exactly
## where it came to rest. While every body is still in the air the pool has no
## room, and the aircraft keeps its skin until one lands (see `room()`).

const LAYER_WORLD := 1
const LAYER_DEBRIS := 4
const REST_SPEED_SQ := 0.5
const REST_TIME := 0.7
const PARK := Vector3(0.0, -2000.0, 0.0)

enum State { FREE, FLYING, SETTLED }

## A body took on a new piece: (mesh node, mesh, local transform, parameter
## names, parameter values), for the replay.
signal restyled(node: MeshInstance3D, mesh: Mesh, xform: Transform3D, names: Array, values: Array)
## A settled chunk was replaced by this static copy.
signal left_behind(node: MeshInstance3D)

var capacity: int = 0
var flying_count: int = 0
var spawned_total: int = 0

var _bodies: Array[RigidBody3D] = []
var _meshes: Array[MeshInstance3D] = []
var _shapes: Array[BoxShape3D] = []
var _state: PackedByteArray
var _still: PackedFloat32Array
var _next: int = 0
var _rng := RandomNumberGenerator.new()

const DENT_PARAMS: Array[StringName] = [&"dent_a", &"dent_a_push", &"dent_b", &"dent_b_push", &"scorch",
		&"livery_frame"]


var _left: Node3D


func setup(count: int) -> void:
	capacity = count
	_left = Node3D.new()
	_left.name = "Settled"
	add_child(_left)
	_rng.seed = 4711
	_state.resize(count)
	_still.resize(count)
	var physics := PhysicsMaterial.new()
	physics.friction = 0.6
	physics.bounce = 0.12
	for i: int in count:
		var body := RigidBody3D.new()
		body.name = "Chunk%d" % i
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.physics_material_override = physics
		# Sheet metal in an airstream: a stand-in for the drag that makes torn
		# panels flutter down rather than fly like bricks.
		body.linear_damp = 0.25
		body.angular_damp = 0.7
		body.position = PARK
		body.visible = false
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		var mi := MeshInstance3D.new()
		mi.material_override = AirframeBuilder.material()
		mi.set_instance_shader_parameter(&"cut_plane_x", 1.0e6)
		mi.visibility_range_end = 1200.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		add_child(body)
		_bodies.append(body)
		_meshes.append(mi)
		_shapes.append(shape)
		_state[i] = State.FREE
	set_physics_process(false)


## Launches `piece` as a free chunk. `part_xf` is the transform of the part it
## came off, `source` the mesh node that was showing it (for dents/scorch).
func spawn(piece: SkinPiece, part_xf: Transform3D, velocity: Vector3, kick: float,
		source: MeshInstance3D) -> void:
	if capacity == 0:
		return
	var i := _take_slot()
	if i < 0:
		return
	_state[i] = State.FLYING
	_still[i] = 0.0
	flying_count += 1
	spawned_total += 1
	var body := _bodies[i]
	var mi := _meshes[i]
	mi.mesh = piece.mesh
	mi.transform = Transform3D(piece.xform.basis, piece.xform.origin - piece.center)
	var values: Array = []
	for param: StringName in DENT_PARAMS:
		var value: Variant = source.get_instance_shader_parameter(param) if source != null \
				else mi.get_instance_shader_parameter(param)
		mi.set_instance_shader_parameter(param, value)
		values.append(value)
	restyled.emit(mi, mi.mesh, mi.transform, DENT_PARAMS, values)
	_shapes[i].size = piece.size
	body.mass = piece.mass
	body.freeze = false
	body.collision_layer = LAYER_DEBRIS
	body.collision_mask = LAYER_WORLD
	body.global_transform = part_xf * Transform3D(Basis.IDENTITY, piece.center)
	var away := part_xf.basis * piece.center
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.UP
	body.linear_velocity = velocity + (away + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0.0, 0.6),
			_rng.randf_range(-0.4, 0.4))) * kick
	body.angular_velocity = Vector3(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0),
			_rng.randf_range(-5.0, 5.0))
	body.reset_physics_interpolation()
	body.visible = true
	set_physics_process(true)


func _physics_process(dt: float) -> void:
	if flying_count == 0:
		set_physics_process(false)
		return
	for i: int in capacity:
		if _state[i] != State.FLYING:
			continue
		var body := _bodies[i]
		if body.linear_velocity.length_squared() < REST_SPEED_SQ or body.global_position.y < -50.0:
			_still[i] += dt
			if _still[i] >= REST_TIME:
				body.freeze = true
				body.collision_layer = 0
				body.collision_mask = 0
				_state[i] = State.SETTLED
				flying_count -= 1
		else:
			_still[i] = 0.0


## Bodies that can take a new chunk now: free ones and settled ones (which
## leave a static copy behind when reused).
func room() -> int:
	return capacity - flying_count


## A free body if there is one, else the oldest settled one (its chunk is left
## behind as a static copy), else -1: never a chunk that is still flying.
func _take_slot() -> int:
	for n: int in capacity:
		var i := (_next + n) % capacity
		if _state[i] == State.FREE:
			_next = (i + 1) % capacity
			return i
	for n: int in capacity:
		var i := (_next + n) % capacity
		if _state[i] == State.SETTLED:
			_leave_behind(i)
			_next = (i + 1) % capacity
			return i
	return -1


func _leave_behind(i: int) -> void:
	var src := _meshes[i]
	var copy := MeshInstance3D.new()
	copy.mesh = src.mesh
	copy.material_override = src.material_override
	copy.visibility_range_end = src.visibility_range_end
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.set_instance_shader_parameter(&"cut_plane_x", 1.0e6)
	for param: StringName in DENT_PARAMS:
		copy.set_instance_shader_parameter(param, src.get_instance_shader_parameter(param))
	_left.add_child(copy)
	copy.global_transform = src.global_transform
	left_behind.emit(copy)


func body_count() -> int:
	return capacity


func body_at(index: int) -> RigidBody3D:
	return _bodies[index]
