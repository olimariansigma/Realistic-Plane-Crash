class_name ChunkPool
extends Node3D
## Fixed pool of rigid bodies that carry torn-off skin pieces. A body borrows
## the piece's mesh and a box collider sized to it, flies and tumbles as its
## own object, then is frozen once it has settled. The oldest chunk is
## recycled when the pool is full, so the body count is capped.

const LAYER_WORLD := 1
const LAYER_DEBRIS := 4
const REST_SPEED_SQ := 0.5
const REST_TIME := 0.7
const PARK := Vector3(0.0, -2000.0, 0.0)

enum State { FREE, FLYING, SETTLED }

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

const DENT_PARAMS: Array[StringName] = [&"dent_a", &"dent_a_push", &"dent_b", &"dent_b_push", &"scorch"]


func setup(count: int) -> void:
	capacity = count
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
	var i := _next
	_next = (_next + 1) % capacity
	if _state[i] == State.FLYING:
		flying_count -= 1
	_state[i] = State.FLYING
	_still[i] = 0.0
	flying_count += 1
	spawned_total += 1
	var body := _bodies[i]
	var mi := _meshes[i]
	mi.mesh = piece.mesh
	mi.transform = Transform3D(piece.xform.basis, piece.xform.origin - piece.center)
	if source != null:
		for param: StringName in DENT_PARAMS:
			mi.set_instance_shader_parameter(param, source.get_instance_shader_parameter(param))
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


func body_count() -> int:
	return capacity


func body_at(index: int) -> RigidBody3D:
	return _bodies[index]
