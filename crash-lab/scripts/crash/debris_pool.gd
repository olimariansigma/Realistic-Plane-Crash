class_name DebrisPool
extends Node3D
## Fixed pool of small rigid-body fragments thrown out by breaks and impacts.
##
## Every body is created once. Spawning recycles the oldest fragment when the
## pool is full, so the active body count never exceeds `capacity`. Fragments
## collide with the world only, and are frozen (static, no collision) as soon
## as they have been still for a moment, so settled wreckage costs nothing.

const LAYER_WORLD := 1
const LAYER_DEBRIS := 4
const REST_SPEED_SQ := 0.36
const REST_TIME := 0.6
const PARK := Vector3(0.0, -2000.0, 0.0)

enum State { FREE, FLYING, SETTLED }

var capacity: int = 0
## Fragments currently simulated by the physics engine.
var flying_count: int = 0
## Total fragments ever spawned (for tests and the report).
var spawned_total: int = 0

var _bodies: Array[RigidBody3D] = []
var _meshes: Array[MeshInstance3D] = []
var _state: PackedByteArray
var _still: PackedFloat32Array
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func setup(count: int) -> void:
	capacity = count
	_rng.seed = 90210
	_state.resize(count)
	_still.resize(count)
	var shapes: Array[BoxShape3D] = []
	var meshes: Array[BoxMesh] = []
	# Panel shard, spar/strut, compact chunk.
	for size: Vector3 in [Vector3(1.3, 0.07, 0.9), Vector3(0.18, 0.18, 1.9), Vector3(0.6, 0.45, 0.7)]:
		var shape := BoxShape3D.new()
		shape.size = size
		shapes.append(shape)
		var mesh := BoxMesh.new()
		mesh.size = size
		meshes.append(mesh)
	var physics := PhysicsMaterial.new()
	physics.friction = 0.6
	physics.bounce = 0.15
	for i: int in count:
		var variant := i % 3
		var body := RigidBody3D.new()
		body.name = "Debris%d" % i
		body.mass = [14.0, 9.0, 30.0][variant]
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.physics_material_override = physics
		body.position = PARK
		body.visible = false
		var collider := CollisionShape3D.new()
		collider.shape = shapes[variant]
		body.add_child(collider)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[variant]
		mi.material_override = AirframeBuilder.material()
		# Debris has no centreline: keep it out of the cutaway clip.
		mi.set_instance_shader_parameter(&"cut_plane_x", 1.0e6)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 900.0
		body.add_child(mi)
		add_child(body)
		_bodies.append(body)
		_meshes.append(mi)
		_state[i] = State.FREE
	set_physics_process(false)


## Throws `count` fragments from `pos`. `base_velocity` is the velocity of the
## structure they came from; `spread` (m/s) is the random scatter added to it.
func spawn_burst(pos: Vector3, base_velocity: Vector3, spread: float, count: int, color: Color) -> void:
	if capacity == 0:
		return
	for _n: int in mini(count, capacity):
		var i := _next
		_next = (_next + 1) % capacity
		var body := _bodies[i]
		if _state[i] == State.FLYING:
			flying_count -= 1
		_state[i] = State.FLYING
		_still[i] = 0.0
		flying_count += 1
		spawned_total += 1
		var offset := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.2, 1.2), _rng.randf_range(-1.0, 1.0))
		body.freeze = false
		body.collision_layer = LAYER_DEBRIS
		body.collision_mask = LAYER_WORLD
		body.global_transform = Transform3D(
				Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)),
				pos + offset)
		body.linear_velocity = base_velocity * _rng.randf_range(0.45, 0.95) + offset.normalized() * spread * _rng.randf_range(0.3, 1.0)
		body.angular_velocity = Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0))
		body.reset_physics_interpolation()
		body.visible = true
		var mi := _meshes[i]
		var s := _rng.randf_range(0.55, 1.5)
		mi.scale = Vector3(s, s, s)
		mi.set_instance_shader_parameter(&"tint", color.darkened(_rng.randf_range(0.0, 0.45)))
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
				# Settled: leave it lying there, but take it out of the simulation.
				body.freeze = true
				body.collision_layer = 0
				body.collision_mask = 0
				_state[i] = State.SETTLED
				flying_count -= 1
		else:
			_still[i] = 0.0


## Transforms of every visible fragment, for the replay recorder.
func body_count() -> int:
	return capacity


func body_at(index: int) -> RigidBody3D:
	return _bodies[index]
