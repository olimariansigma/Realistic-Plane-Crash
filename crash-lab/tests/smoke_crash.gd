extends SceneTree
## Headless crash-physics smoke test.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/smoke_crash.gd [-- <aircraft id>]
##
## Three scenarios on one aircraft type:
##  1. Firm landing (touchdown at ~2.5 m/s sink): nothing may break.
##  2. Flat drop from 30 m (~24 m/s): the gear must collapse, the wreck must
##     shed debris within the pool cap and come to rest above ground.
##     (Scenario 3 also checks skin comes off piece by piece.)
##  3. Dive into the ground at cruise speed: most joints must fail, fuel must
##     ignite and the structure must crumple.
## Every scenario also checks that nothing goes non-finite or tunnels.

const DEBRIS_CAP := 48

var _def: AircraftDef
var _world: World
var _aircraft: Aircraft
var _director: CrashDirector
var _scenario := -1
var _t := 0.0
var _wait := 0
var _started := false
var _summary: PackedStringArray = []
var _peak_flying := 0
var _peak_chunks := 0


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "meridian_220"
	_def = load("res://data/aircraft/%s.tres" % id) as AircraftDef
	_world = World.new()
	root.add_child(_world)
	_begin(0)


func _begin(index: int) -> void:
	if _aircraft != null:
		_aircraft.queue_free()
		_director.queue_free()
	_scenario = index
	_t = 0.0
	_peak_flying = 0
	_peak_chunks = 0
	_aircraft = Aircraft.new()
	root.add_child(_aircraft)
	var start := World.RUNWAY_START
	match index:
		0:
			_aircraft.global_transform = Transform3D(Basis.IDENTITY,
					start + Vector3(0.0, _def.ground_clearance + 0.3, 0.0))
			_aircraft.setup(_def)
		1:
			_aircraft.global_transform = Transform3D(Basis.IDENTITY,
					start + Vector3(0.0, _def.ground_clearance + 30.0, -300.0))
			_aircraft.setup(_def)
		2:
			var basis := Basis(Vector3.RIGHT, deg_to_rad(-30.0))
			_aircraft.global_transform = Transform3D(basis, start + Vector3(0.0, 260.0, -600.0))
			_aircraft.setup(_def)
			_aircraft.set_initial_velocity(basis * Vector3(0.0, 0.0, -_def.v_cruise))
			_aircraft.configure_airborne(0.6)
	_director = CrashDirector.new()
	root.add_child(_director)
	_director.setup(_aircraft, 1, DEBRIS_CAP)


func _physics_process(dt: float) -> bool:
	if not _started:
		_started = true
		_start()
		return false
	_t += dt
	for part: AircraftPart in _aircraft.parts:
		var p := part.xf.origin
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return _fail("%s went non-finite in scenario %d" % [part.name, _scenario])
		# Parts dragged down by the rest of the airframe may dig in briefly; going
		# deeper than this means a collider has genuinely tunnelled.
		if p.y < -8.0:
			return _fail("%s tunnelled through the ground in scenario %d (y=%.1f)" % [part.name, _scenario, p.y])
		if _director != null and _director.settled and p.y < -1.5:
			return _fail("%s came to rest under the ground in scenario %d (y=%.1f)" % [part.name, _scenario, p.y])
	_peak_flying = maxi(_peak_flying, _director.debris.flying_count)
	_peak_chunks = maxi(_peak_chunks, _director.chunks.flying_count)
	if _director.chunks.flying_count > _director.chunks.capacity:
		return _fail("chunk pool exceeded its cap (%d)" % _director.chunks.flying_count)
	if _director.debris.flying_count > DEBRIS_CAP:
		return _fail("debris pool exceeded its cap (%d)" % _director.debris.flying_count)

	var joints := _aircraft.parts.size() - 1
	var broken := joints - _aircraft.joints_alive
	match _scenario:
		0:
			if _t > 6.0:
				if broken > 0 or _aircraft.telemetry.crashed:
					return _fail("a firm landing broke %d joint(s)" % broken)
				for part: AircraftPart in _aircraft.parts:
					if part.stripped:
						return _fail("a firm landing tore skin off %s" % part.name)
				var worst := 0.0
				for i: int in range(1, _aircraft.parts.size()):
					worst = maxf(worst, _aircraft.structure.peak_ratio[i])
				_summary.append("firm landing ok (peak load %.0f %%)" % (worst * 100.0))
				_begin(1)
		1:
			if _director.settled or _t > 45.0:
				if not _director.settled:
					return _fail("30 m drop never came to rest")
				var gear_broken := 0
				for part: AircraftPart in _aircraft.parts:
					if part.def.kind == PartDef.Kind.GEAR and part.joint == null:
						gear_broken += 1
				if gear_broken < 2:
					return _fail("30 m drop collapsed only %d gear leg(s)" % gear_broken)
				if _director.debris.spawned_total == 0:
					return _fail("30 m drop spawned no debris")
				var drop_total := 0
				var drop_left := 0
				for part: AircraftPart in _aircraft.parts:
					drop_total += part.pieces.size()
					drop_left += part.pieces_left
				# A flat drop is a hard belly landing, not a disintegration.
				if drop_left * 2 < drop_total:
					return _fail("30 m drop stripped %d of %d skin pieces" % [drop_total - drop_left, drop_total])
				_summary.append("30 m drop: %d/%d joints, %d gear, %d/%d skin pieces off, %d debris, rest in %.1f s" % [
						broken, joints, gear_broken, drop_total - drop_left, drop_total,
						_director.debris.spawned_total, _director.crash_clock])
				_begin(2)
		2:
			if _director.settled or _t > 80.0:
				if not _director.settled:
					return _fail("dive crash never came to rest")
				if float(broken) < float(joints) * 0.5:
					return _fail("dive crash broke only %d of %d joints" % [broken, joints])
				if _aircraft.fires.is_empty():
					return _fail("dive crash started no fire")
				var deepest := 0.0
				for part: AircraftPart in _aircraft.parts:
					deepest = maxf(deepest, part.crush_depth)
				if deepest < 0.3:
					return _fail("dive crash crumpled only %.2f m" % deepest)
				# Occupants: the cabin must have been armed before the first
				# impact, every seat must have logged it, and the dummies must
				# have come through with finite, non-trivial readings.
				var cabin := _aircraft.cabin
				if not cabin.armed or cabin.armed_time > _aircraft.crash_time:
					return _fail("cabin armed at %.2f s, after the crash began at %.2f s" % [cabin.armed_time, _aircraft.crash_time])
				var seat_peak := 0.0
				for seat: Seat in cabin.seats:
					seat_peak = maxf(seat_peak, seat.peak_g)
				if seat_peak < 8.0:
					return _fail("seats logged only %.1f g in a dive crash" % seat_peak)
				var fred_peak := 0.0
				for fred: Fred in cabin.freds:
					for limb: RigidBody3D in fred.limbs:
						var lp := limb.global_position
						if not (is_finite(lp.x) and is_finite(lp.y) and is_finite(lp.z)) or lp.y < -8.0:
							return _fail("%s limb %s ended at %s" % [fred.name, limb.name, lp])
					fred_peak = maxf(fred_peak, fred.peak_g[fred.worst_limb()])
				if cabin.freds.size() > 0 and fred_peak < 8.0:
					return _fail("dummies logged only %.1f g in a dive crash" % fred_peak)
				_summary.append("%d seats peak %.0f g, %d FREDs peak %.0f g" % [
						cabin.seats.size(), seat_peak, cabin.freds.size(), fred_peak])
				# Piece by piece: skin must have come off as separate chunks, and
				# the wreck must not be left fully skinned or fully bare.
				var skin_total := 0
				var skin_left := 0
				for part: AircraftPart in _aircraft.parts:
					skin_total += part.pieces.size()
					skin_left += part.pieces_left
				var shed := skin_total - skin_left
				if shed < 12 or _director.chunks.spawned_total < shed:
					return _fail("dive crash tore off only %d of %d skin pieces (%d chunks)" % [shed, skin_total, _director.chunks.spawned_total])
				_summary.append("%d/%d skin pieces torn off, peak %d chunks flying" % [shed, skin_total, _peak_chunks])
				_summary.append("dive: %d/%d joints, %d fires, crumple %.1f m, peak %d flying debris, rest in %.1f s" % [
						broken, joints, _aircraft.fires.size(), deepest, _peak_flying, _director.crash_clock])
				print("SMOKE PASS: %s | %s" % [_def.display_name, " | ".join(_summary)])
				quit(0)
				return true
	return false


func _fail(msg: String) -> bool:
	printerr("SMOKE FAIL: " + msg)
	quit(1)
	return true
