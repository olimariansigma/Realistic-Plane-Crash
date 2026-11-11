extends SceneTree
## Headless FRED dummy test: a sled, one seat, one dummy.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/smoke_fred.gd
##
## The sled is a heavy body flying level with gravity off; it is stopped dead
## in one tick, which is how a rigid fuselage section meets the ground.
##  1. 13.4 m/s stop (the 14 CFR 25.562 longitudinal velocity change): the
##     seat log must read near that test's 16 g, the dummy must stay belted
##     with its mount inside its stroke, and its torso must fold forward, not
##     back (checks the joint limit directions).
##  2. 32 m/s stop: the mount must bottom out or the restraint must fail.

const STOP_TICK := 30

var _sled: AircraftPart
var _seat: Seat
var _fred: Fred
var _case := 0
var _tick := 0
var _started := false
var _speed := 13.4
var _min_chest_pitch := 0.0
var _max_chest_pitch := 0.0
var _summary: PackedStringArray = []


func _begin(speed: float) -> void:
	if _sled != null:
		_fred.queue_free()
		_sled.queue_free()
	_speed = speed
	_tick = 0
	_min_chest_pitch = 0.0
	_max_chest_pitch = 0.0
	var part_def := PartDef.new()
	part_def.crush_depth = 0.75
	_sled = AircraftPart.new()
	_sled.def = part_def
	_sled.mass = 20000.0
	_sled.gravity_scale = 0.0
	_sled.collision_layer = 0
	_sled.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	_sled.add_child(shape)
	root.add_child(_sled)
	_sled.global_position = Vector3(0.0, 50.0, 0.0)
	_sled.linear_velocity = Vector3(0.0, 0.0, -speed)
	_seat = Seat.new()
	_seat.label = "1A"
	_seat.part = _sled
	_seat.local_pos = Vector3(0.0, 0.5, 0.0)
	_fred = Fred.new()
	root.add_child(_fred)
	_sled.begin_tick()
	_fred.setup(_seat, _sled)
	_fred.activate()


func _physics_process(dt: float) -> bool:
	if not _started:
		_started = true
		_begin(13.4)
		return false
	_tick += 1
	_sled.begin_tick()
	_sled.ext_force = Vector3.ZERO
	_sled.ext_torque = Vector3.ZERO
	if _tick == STOP_TICK:
		_sled.linear_velocity = Vector3.ZERO
		_sled.lin_vel = Vector3.ZERO
	# The sled is weightless; cancel gravity on the dummy's seat too by holding
	# the sled exactly (a 20 t sled barely notices an 82 kg dummy anyway).
	Cabin.track_seat(_seat, 1.0 - exp(-dt / Cabin.SEAT_FILTER_TAU), 1.0 / dt)
	_fred.tick(dt)
	for limb: RigidBody3D in _fred.limbs:
		var p := limb.global_position
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return _fail("limb %s went non-finite" % limb.name)
	if _tick > STOP_TICK and not _fred.ejected:
		# Chest pitch relative to the sled: negative = folded forward (toward -Z).
		var chest_up := _fred.limbs[Fred.Limb.CHEST].global_transform.basis.y
		var pitch := rad_to_deg(atan2(chest_up.z, chest_up.y))
		_min_chest_pitch = minf(_min_chest_pitch, pitch)
		_max_chest_pitch = maxf(_max_chest_pitch, pitch)
	if _tick < STOP_TICK + 120:
		return false

	var head := _fred.peak_g[Fred.Limb.HEAD]
	var chest := _fred.peak_g[Fred.Limb.CHEST]
	var pelvis := _fred.peak_g[Fred.Limb.PELVIS]
	if _case == 0:
		# The seat log includes the 1 g it reads at rest, hence the upper margin.
		if _seat.peak_g < 13.0 or _seat.peak_g > 19.5:
			return _fail("seat log read %.1f g for a 13.4 m/s stop, expected ~16" % _seat.peak_g)
		if _fred.ejected:
			return _fail("dummy was thrown out of a certification-level stop")
		if _fred.bottomed:
			return _fail("seat mount bottomed out (stroke %.2f m) in a certification-level stop" % _fred.stroke_peak)
		if pelvis < 8.0 or pelvis > 30.0:
			return _fail("pelvis peak %.1f g, expected 8-30" % pelvis)
		if _min_chest_pitch > -20.0:
			return _fail("torso did not fold forward (min chest pitch %.1f deg)" % _min_chest_pitch)
		if _max_chest_pitch > 30.0:
			return _fail("torso bent backwards over the seat (%.1f deg)" % _max_chest_pitch)
		if head < pelvis * 0.5:
			return _fail("head peak %.1f g is implausibly low next to pelvis %.1f g" % [head, pelvis])
		_summary.append("13.4 m/s: seat %.1f g, pelvis %.1f g, chest %.1f g, head %.1f g, HIC %.0f, stroke %.2f m, torso %.0f deg" % [
				_seat.peak_g, pelvis, chest, head, _fred.hic, _fred.stroke_peak, _min_chest_pitch])
		_case = 1
		_begin(32.0)
		return false
	if not (_fred.bottomed or _fred.ejected):
		return _fail("a 32 m/s stop neither bottomed the mount nor broke the restraint (stroke %.2f m)" % _fred.stroke_peak)
	if _seat.peak_g < 30.0:
		return _fail("seat log read only %.1f g for a 32 m/s stop" % _seat.peak_g)
	_summary.append("32 m/s: seat %.1f g, pelvis %.1f g, head %.1f g, HIC %.0f, %s" % [
			_seat.peak_g, pelvis, head, _fred.hic, "ejected" if _fred.ejected else "bottomed out"])
	print("SMOKE PASS: FRED sled | " + " | ".join(_summary))
	quit(0)
	return true


func _fail(msg: String) -> bool:
	printerr("SMOKE FAIL: " + msg)
	quit(1)
	return true
