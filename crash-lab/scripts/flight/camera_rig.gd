class_name CameraRig
extends Node3D
## Flight cameras. Runs in _process and reads the target's interpolated
## transform, so the view is smooth at any display rate.

enum Mode { CHASE, ORBIT, COCKPIT, FLYBY }

const MODE_NAMES: Array[String] = ["CHASE", "ORBIT", "COCKPIT", "FLYBY"]

var camera: Camera3D
var mode: Mode = Mode.CHASE
## Body to follow, and a characteristic size (wing span) to scale distances.
var target: Node3D
var size: float = 30.0
## Cockpit eye point in the target's local frame.
var eye_local := Vector3(0.0, 1.0, -10.0)
## Velocity source for the flyby camera placement.
var target_velocity := Vector3.ZERO

var _yaw: float = 0.0
var _pitch: float = 0.18
var _zoom: float = 1.0
var _flyby_pos := Vector3.ZERO
var _flyby_valid: bool = false
var _pos := Vector3.ZERO
var _initialized: bool = false


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 65.0
	camera.near = 0.4
	camera.far = 40000.0
	camera.top_level = true
	add_child(camera)
	camera.make_current()


func follow(body: Node3D, span: float, eye: Vector3) -> void:
	target = body
	size = span
	eye_local = eye
	_initialized = false
	_flyby_valid = false


func cycle_mode() -> Mode:
	set_mode(((mode as int) + 1) % MODE_NAMES.size() as Mode)
	return mode


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_initialized = false
	_flyby_valid = false
	if mode == Mode.ORBIT:
		_pitch = 0.25
	camera.near = 0.15 if mode == Mode.COCKPIT else 0.4


func mode_name() -> String:
	return MODE_NAMES[mode]


## Finger drag in pixels.
func drag(relative: Vector2) -> void:
	_yaw -= relative.x * 0.006
	_pitch = clampf(_pitch + relative.y * 0.005, -1.3, 1.45)


func zoom(factor: float) -> void:
	_zoom = clampf(_zoom / maxf(factor, 0.01), 0.35, 4.0)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var xf := target.get_global_transform_interpolated()
	var origin := xf.origin
	var fwd := -xf.basis.z
	match mode:
		Mode.CHASE:
			var flat := Vector3(fwd.x, 0.0, fwd.z)
			if flat.length_squared() < 0.001:
				flat = Vector3(xf.basis.y.x, 0.0, xf.basis.y.z)
			flat = flat.normalized().rotated(Vector3.UP, _yaw)
			var dist := size * 1.25 * _zoom
			var want := origin - flat * dist + Vector3.UP * (size * 0.26 + dist * sin(_pitch - 0.18))
			if not _initialized:
				_pos = want
				_initialized = true
			_pos = _pos.lerp(want, 1.0 - exp(-delta * 5.0))
			# Never let the chase camera sink into the ground.
			_pos.y = maxf(_pos.y, 1.5)
			camera.global_position = _pos
			camera.look_at(origin + fwd * (size * 0.25) + Vector3.UP * (size * 0.06), Vector3.UP)
			# Drag offsets relax back so the view re-centres behind the aircraft.
			_yaw = lerpf(_yaw, 0.0, 1.0 - exp(-delta * 0.8))
		Mode.ORBIT:
			var dist := size * 1.5 * _zoom
			var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
			var want := origin + dir * dist
			want.y = maxf(want.y, 1.0)
			camera.global_position = want
			camera.look_at(origin, Vector3.UP)
		Mode.COCKPIT:
			var look := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -(_pitch - 0.18) * 0.6)
			camera.global_transform = Transform3D(xf.basis * look, xf * eye_local)
			_yaw = lerpf(_yaw, 0.0, 1.0 - exp(-delta * 1.5))
		Mode.FLYBY:
			if not _flyby_valid or _flyby_pos.distance_to(origin) > maxf(size * 22.0, 700.0):
				var v := target_velocity
				var ahead := v * 3.5 if v.length() > 5.0 else fwd * size
				var side := ahead.cross(Vector3.UP)
				side = side.normalized() if side.length_squared() > 0.01 else Vector3.RIGHT
				_flyby_pos = origin + ahead + side * (size * 1.6)
				_flyby_pos.y = maxf(origin.y - size * 0.5, 2.0)
				_flyby_valid = true
			camera.global_position = _flyby_pos
			camera.look_at(origin, Vector3.UP)
			camera.fov = clampf(rad_to_deg(2.0 * atan(size * 1.4 / maxf(_flyby_pos.distance_to(origin), 1.0))), 12.0, 65.0)
			return
	camera.fov = 65.0
