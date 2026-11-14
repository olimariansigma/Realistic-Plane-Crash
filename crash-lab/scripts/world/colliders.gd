class_name WorldColliders
extends RefCounted
## Factory for the world's static collision bodies; keeps a running count so
## the total stays inside the budget.

var count := 0
var _parent: Node3D
var _material: PhysicsMaterial


func _init(parent: Node3D, material: PhysicsMaterial) -> void:
	_parent = parent
	_material = material


func _body(node_name: String, xform: Transform3D, shape: Shape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = World.LAYER_WORLD
	body.collision_mask = 0
	body.physics_material_override = _material
	body.transform = xform
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	_parent.add_child(body)
	count += 1
	return body


## Box collider; `center` is the middle of the box.
func box(node_name: String, center: Vector3, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _body(node_name, Transform3D(Basis(Vector3.UP, yaw), center), shape)


## Box collider standing on the ground at `base` (bottom centre).
func box_on(node_name: String, base: Vector3, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	return box(node_name, base + Vector3(0.0, size.y * 0.5, 0.0), size, yaw)


func hull(node_name: String, center: Vector3, points: PackedVector3Array) -> StaticBody3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return _body(node_name, Transform3D(Basis.IDENTITY, center), shape)
