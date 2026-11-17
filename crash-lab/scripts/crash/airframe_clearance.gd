class_name AirframeClearance
extends RefCounted
## Loose pieces (torn skin, shards) start inside or against the airframe they
## came off: a belly panel can ride along under a sliding hull for seconds.
## They collide with the ground and each other at once, but with the airframe
## only once they are clear of every part of it. Turned on while still
## buried, the contact shoves the piece out through the structure and
## disturbs the airframe around it (it threw a pilot out of a belly-landed
## F-16), even though in Godot's Jolt the airframe's own mask leaves loose
## pieces out.

var _query := PhysicsShapeQueryParameters3D.new()


func _init() -> void:
	_query.collision_mask = AirframeBuilder.LAYER_AIRFRAME
	_query.margin = 0.05


## True if `shape`, placed at `body`'s transform, touches no airframe part.
func is_clear(body: RigidBody3D, shape: Shape3D) -> bool:
	_query.shape = shape
	_query.transform = body.global_transform
	return body.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()
