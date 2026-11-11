extends SceneTree
## Headless flight-model smoke test.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/smoke_flight.gd [-- <aircraft id>]
##
## Flies the aircraft with a crude test pilot and checks the physics end to end:
##  1. parked on its gear it stays put and level;
##  2. full thrust accelerates it, it rotates and climbs away within the runway;
##  3. in the air, each control axis moves the aircraft the right way;
##  4. trimmed for level flight then released, it holds attitude and height;
##  5. in steady flight total lift is close to weight (the force model adds up);
##  6. no structural joint gets near its break load anywhere in the flight.

enum Phase { SETTLE, TAKEOFF, CLIMB, ROLL_CHECK, RECOVER, YAW_CHECK, TRIM, HANDS_OFF, DONE }

var _aircraft: Aircraft
var _def: AircraftDef
var _phase := Phase.SETTLE
var _t := 0.0
var _phase_t := 0.0
var _started := false
var _settle_pos := Vector3.ZERO
var _liftoff_z := 0.0
var _liftoff_t := 0.0
var _mark := 0.0
var _lift_ratio_sum := 0.0
var _lift_samples := 0
var _pitch_target := 0.0
var _trimmed_t := 0.0
var _release_alt := 0.0
var _trim_found := 0.0
var _throttle_i := 0.3
var _prev_ias := 0.0
var _accel_f := 0.0


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "meridian_220"
	root.add_child(World.new())
	_def = load("res://data/aircraft/%s.tres" % id) as AircraftDef
	_aircraft = Aircraft.new()
	root.add_child(_aircraft)
	_aircraft.global_transform = Transform3D(Basis.IDENTITY,
			World.RUNWAY_START + Vector3(0.0, _def.ground_clearance, 0.0))
	_aircraft.setup(_def)


func _next(phase: Phase) -> void:
	_phase = phase
	_phase_t = 0.0


func _physics_process(dt: float) -> bool:
	if not _started:
		_started = true
		_start()
		return false
	_t += dt
	_phase_t += dt
	var tm := _aircraft.telemetry
	var c := _aircraft.controls
	var pos := _aircraft.root_part.xf.origin
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return _fail("position is not finite at t=%.1f" % _t)
	if tm.integrity < 1.0:
		return _fail("a joint let go in normal flight at t=%.1f (phase %d)" % [_t, _phase])

	match _phase:
		Phase.SETTLE:
			c.brake = 1.0
			if _phase_t > 1.0 and _settle_pos == Vector3.ZERO:
				_settle_pos = pos
			if _phase_t > 4.0:
				if pos.distance_to(_settle_pos) > 0.15 or absf(tm.pitch_deg) > 1.5 or absf(tm.roll_deg) > 0.5:
					return _fail("did not sit still on its gear (moved %.2f m, pitch %.2f, roll %.2f)"
							% [pos.distance_to(_settle_pos), tm.pitch_deg, tm.roll_deg])
				if not tm.on_ground:
					return _fail("gear reports no ground contact while parked")
				c.brake = 0.0
				c.throttle = 1.0
				c.flap_step = mini(2, _def.flap_steps_deg.size() - 1)
				_next(Phase.TAKEOFF)
		Phase.TAKEOFF:
			_wings_level(c, tm)
			if tm.ias > _def.v_rotate:
				c.pitch = clampf((11.0 - tm.pitch_deg) * 0.12, -0.3, 0.8)
			if tm.altitude_agl > 15.0 and not tm.on_ground:
				_liftoff_z = pos.z
				_liftoff_t = _t
				c.gear_down = false
				_next(Phase.CLIMB)
			elif _phase_t > 70.0:
				return _fail("never left the ground (ias %.1f m/s after %.0f s)" % [tm.ias, _phase_t])
		Phase.CLIMB:
			_wings_level(c, tm)
			_hold_pitch(c, tm, 9.0)
			if tm.altitude_agl > 350.0:
				c.flap_step = 0
				c.throttle = 0.6
				_mark = tm.roll_deg
				_next(Phase.ROLL_CHECK)
			elif _phase_t > 60.0:
				return _fail("could not climb to 350 m (alt %.0f m, vs %.1f)" % [tm.altitude_agl, tm.vertical_speed])
		Phase.ROLL_CHECK:
			_hold_pitch(c, tm, 4.0)
			c.roll = 0.5
			if _phase_t > 0.8:
				var rolled := wrapf(tm.roll_deg - _mark, -180.0, 180.0)
				if rolled < 1.5:
					return _fail("right stick did not roll right (%.1f deg in 0.8 s)" % rolled)
				_next(Phase.RECOVER)
		Phase.RECOVER:
			_wings_level(c, tm)
			_hold_pitch(c, tm, 4.0)
			if _phase_t > 8.0:
				if absf(tm.roll_deg) > 6.0:
					return _fail("could not level the wings (roll %.1f deg)" % tm.roll_deg)
				_mark = tm.heading_deg
				_next(Phase.YAW_CHECK)
		Phase.YAW_CHECK:
			_wings_level(c, tm)
			_hold_pitch(c, tm, 4.0)
			c.yaw = 0.6
			if _phase_t > 3.0:
				var turned := wrapf(tm.heading_deg - _mark, -180.0, 180.0)
				if turned < 0.3:
					return _fail("right rudder did not yaw right (%.2f deg)" % turned)
				c.yaw = 0.0
				_pitch_target = tm.pitch_deg
				_next(Phase.TRIM)
		Phase.TRIM:
			# Autopilot: hold level flight at cruise speed and let auto-trim take
			# the stick load, so the release below starts from a trimmed state.
			_wings_level(c, tm)
			_pitch_target = clampf(_pitch_target - tm.vertical_speed * 0.004, -5.0, 12.0)
			_hold_pitch(c, tm, _pitch_target)
			# PI auto-throttle on airspeed.
			var speed_err := _def.v_cruise - tm.ias
			if absf(speed_err) < 8.0:  # anti-windup: integrate only near the target
				_throttle_i = clampf(_throttle_i + speed_err * 0.0001, 0.0, 1.0)
			c.throttle = clampf(_throttle_i + speed_err * 0.03, 0.02, 1.0)
			var accel := (tm.ias - _prev_ias) / dt
			_accel_f = lerpf(_accel_f, accel, 0.05)
			var steady := absf(c.pitch) < 0.02 and absf(tm.vertical_speed) < 0.8 \
					and absf(speed_err) < 3.0 and absf(_accel_f) < 0.15
			_trimmed_t = _trimmed_t + dt if steady else 0.0
			if _trimmed_t > 3.0:
				c.pitch = 0.0
				_release_alt = tm.altitude_msl
				_trim_found = tm.trim
				_next(Phase.HANDS_OFF)
			elif _phase_t > 150.0:
				return _fail("could not trim for level flight (stick %.2f, vs %.1f, ias %.1f, accel %.2f)"
						% [c.pitch, tm.vertical_speed, tm.ias, _accel_f])
		Phase.HANDS_OFF:
			# Wing-leveller only; pitch and throttle are untouched.
			_wings_level(c, tm)
			if _phase_t > 2.0:
				var lift := 0.0
				for s: AeroSurface in _aircraft.surfaces:
					lift += s.lift * (s.part.xf.basis * s.local_normal).y
				_lift_ratio_sum += lift / (_def.total_mass() * Aircraft.GRAVITY)
				_lift_samples += 1
			# A released, trimmed aircraft still has a slow, lightly damped phugoid
			# (about a minute per cycle); the limits allow that but not divergence.
			if absf(tm.pitch_deg - _pitch_target) > 7.0 or absf(tm.altitude_msl - _release_alt) > 250.0:
				return _fail("diverged hands-off (pitch %.1f from %.1f, ias %.1f, height change %.0f m)"
						% [tm.pitch_deg, _pitch_target, tm.ias, tm.altitude_msl - _release_alt])
			if _phase_t > 25.0:
				var ratio := _lift_ratio_sum / float(_lift_samples)
				if absf(ratio - 1.0) > 0.08:
					return _fail("mean lift / weight = %.2f in level flight, expected ~1" % ratio)
				# Structural margin: nothing in a normal flight may come near breaking.
				var worst := 0.0
				var worst_name := ""
				var monitor := _aircraft.structure
				for i: int in range(1, _aircraft.parts.size()):
					if monitor.peak_ratio[i] > worst:
						worst = monitor.peak_ratio[i]
						worst_name = String(_aircraft.parts[i].name)
				if OS.has_environment("CRASHLAB_LOADS"):
					for i: int in range(1, _aircraft.parts.size()):
						print("    %-14s peak load ratio %.2f" % [_aircraft.parts[i].name, monitor.peak_ratio[i]])
				if worst > 0.7:
					return _fail("joint %s reached %.0f %% of its break load in normal flight" % [worst_name, worst * 100.0])
				print("    peak joint load %.0f %% of break (%s)" % [worst * 100.0, worst_name])
				print("SMOKE PASS: %s lifted off at %.0f m in %.0f s, controls respond, holds level hands-off (trim %.2f, throttle %.2f at %.0f m/s), L/W %.2f"
						% [_def.display_name, World.RUNWAY_START.z - _liftoff_z, _liftoff_t - 4.0,
						_trim_found, c.throttle, _def.v_cruise, ratio])
				quit(0)
				return true
	_prev_ias = tm.ias
	if World.RUNWAY_START.z - pos.z > World.RUNWAY_LENGTH and _phase == Phase.TAKEOFF:
		return _fail("ran off the end of the runway at %.1f m/s" % tm.ias)
	return false


func _wings_level(c: ControlState, tm: FlightTelemetry) -> void:
	c.roll = clampf(-tm.roll_deg * 0.06, -1.0, 1.0)


func _hold_pitch(c: ControlState, tm: FlightTelemetry, target_deg: float) -> void:
	c.pitch = clampf((target_deg - tm.pitch_deg) * 0.1, -0.5, 0.6)


func _fail(msg: String) -> bool:
	printerr("SMOKE FAIL: " + msg)
	quit(1)
	return true
