extends SceneTree
## Headless physics smoke test (milestone 1 baseline).
## Run: godot --headless --path . -s res://tests/smoke_physics.gd
## Proves the Jolt backend is active and steps deterministically without a
## display: a 1 m box dropped from 10 m must come to rest on a static floor.
## Later milestones extend this file's sibling tests with the plane drop/break.

const DROP_HEIGHT := 10.0
const MAX_FRAMES := 600

var _box: RigidBody3D
var _frames := 0
var _peak_speed := 0.0


func _initialize() -> void:
	var engine_name := str(ProjectSettings.get_setting("physics/3d/physics_engine"))
	if engine_name != "Jolt Physics":
		_fail("physics engine is '%s', expected 'Jolt Physics'" % engine_name)
		return

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(50.0, 1.0, 50.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)

	_box = RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	_box.add_child(shape)
	_box.mass = 10.0
	_box.position = Vector3(0.0, DROP_HEIGHT, 0.0)
	root.add_child(_box)


func _physics_process(_delta: float) -> bool:
	if _box == null:
		return true
	_frames += 1
	var speed := _box.linear_velocity.length()
	_peak_speed = maxf(_peak_speed, speed)

	var resting := _frames > 30 and speed < 0.05 and absf(_box.position.y - 0.5) < 0.05
	if resting:
		# Free fall from 9.5 m of clearance: v = sqrt(2 g h) ~= 13.65 m/s. Tight
		# tolerance on purpose: it catches hidden default damping (project sets 0).
		var expected := sqrt(2.0 * 9.8 * (DROP_HEIGHT - 0.5))
		if absf(_peak_speed - expected) > 0.3:
			_fail("peak speed %.2f m/s, expected ~%.2f" % [_peak_speed, expected])
		else:
			print("SMOKE PASS: box at rest y=%.3f after %d frames, peak %.2f m/s"
					% [_box.position.y, _frames, _peak_speed])
			quit(0)
		return true
	if _frames >= MAX_FRAMES:
		_fail("box never came to rest (y=%.3f, v=%.3f)" % [_box.position.y, speed])
		return true
	return false


func _fail(msg: String) -> void:
	printerr("SMOKE FAIL: " + msg)
	quit(1)
