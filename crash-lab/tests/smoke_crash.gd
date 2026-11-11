extends SceneTree
## Headless crash-physics smoke test.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/smoke_crash.gd [-- <aircraft id>]
##
## Four scenarios on one aircraft type, from harmless to hopeless:
##  1. Firm landing (touchdown at ~2.5 m/s sink): nothing may break and the
##     survival report must read 100 %.
##  2. Gear-up belly landing at approach speed: the aircraft slides to a stop
##     and most occupants must survive.
##  3. Flat drop from 30 m (~24 m/s): the gear must collapse, the wreck must
##     shed debris within the pool cap and come to rest above ground.
##  4. Dive into the ground at cruise speed: most joints must fail, fuel must
##     ignite, the structure must crumple and come apart piece by piece, the
##     report must call it unsurvivable, and the replay must play back.
## Survival must fall from each scenario to the next.
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
var _recorder: CrashRecorder
var _survival: Array[float] = []
var _replay_frames := -1


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
			# Two metres up, gear retracted, a little above stall, sinking gently.
			var speed := _def.v_rotate * 1.05
			_aircraft.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(3.0)),
					start + Vector3(0.0, _def.ground_clearance + 2.0, -100.0))
			_aircraft.setup(_def)
			_aircraft.set_initial_velocity(Vector3(0.0, -1.5, -speed))
			_aircraft.configure_airborne(0.0, false, _def.flap_steps_deg.size() - 1)
		2:
			_aircraft.global_transform = Transform3D(Basis.IDENTITY,
					start + Vector3(0.0, _def.ground_clearance + 30.0, -300.0))
			_aircraft.setup(_def)
		3:
			var basis := Basis(Vector3.RIGHT, deg_to_rad(-30.0))
			_aircraft.global_transform = Transform3D(basis, start + Vector3(0.0, 260.0, -600.0))
			_aircraft.setup(_def)
			_aircraft.set_initial_velocity(basis * Vector3(0.0, 0.0, -_def.v_cruise))
			_aircraft.configure_airborne(0.6)
	_director = CrashDirector.new()
	root.add_child(_director)
	_director.setup(_aircraft, 1, DEBRIS_CAP)
	if _recorder != null:
		_recorder.queue_free()
	_recorder = CrashRecorder.new()
	root.add_child(_recorder)
	_recorder.setup(_aircraft, _director)


func _physics_process(dt: float) -> bool:
	if not _started:
		_started = true
		_start()
		return false
	_t += dt
	if _replay_frames >= 0:
		return _check_replay()
	if _aircraft.cabin.armed and not _recorder.recording and _recorder.frames == 0:
		_recorder.start_recording()
	for part: AircraftPart in _aircraft.parts:
		var p := part.xf.origin
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return _fail("%s went non-finite in scenario %d" % [part.name, _scenario])
		# Parts dragged down by the rest of the airframe may dig in briefly; going
		# deeper than this means a collider has genuinely tunnelled.
		if p.y < -8.0:
			return _fail("%s tunnelled through the ground in scenario %d (y=%.1f)" % [part.name, _scenario, p.y])
		# A retracted leg still bolted on has no collider and its body stays at
		# the extended position, below the belly: not a tunnelling fault.
		var stowed := part.def.kind == PartDef.Kind.GEAR and part.joint != null
		if _director != null and _director.settled and p.y < -1.5 and not stowed:
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
				var firm := InjuryModel.build_report(_aircraft, _director)
				if firm.survival_overall < 0.99:
					return _fail("a firm landing reported %.0f %% survival" % (firm.survival_overall * 100.0))
				_survival.append(firm.survival_overall)
				_summary.append("firm landing ok (peak load %.0f %%)" % (worst * 100.0))
				_begin(1)
		1:
			# Read the body directly: the aircraft stops refreshing its cached
			# state once the director has stood it down.
			var stopped := _t > 8.0 and _aircraft.root_part.linear_velocity.length() < 0.5
			if stopped or _t > 70.0:
				if not stopped:
					return _fail("belly landing never stopped (%.1f m/s)" % _aircraft.root_part.linear_velocity.length())
				var belly := InjuryModel.build_report(_aircraft, _director)
				if OS.has_environment("CRASHLAB_LOADS"):
					for r: SeatResult in belly.seats:
						print("    %s g=%.1f axes=%s hic=%.0f intr=%.2f fire=%.2f ej=%s pd=%.2f ph=%.2f pi=%.2f pf=%.2f surv=%.2f" % [
								r.label, r.peak_g, r.peak_g_axes, r.hic, r.intrusion, r.fire, r.ejected,
								r.p_decel, r.p_head, r.p_intrusion, r.p_fire, r.survival])
					for f: FredResult in belly.freds:
						print("    fred %s limbs=%s belt=%.1f kN stroke=%.2f bottomed=%s" % [f.seat_label, f.limb_peak_g, f.belt_peak_kn, f.stroke_m, f.bottomed])
				if belly.survival_overall < 0.8:
					return _fail("a gentle belly landing reported only %.0f %% survival (peak %.0f g, %d/%d joints)" % [
							belly.survival_overall * 100.0, belly.peak_g, belly.joints_broken, belly.joints_total])
				_survival.append(belly.survival_overall)
				_summary.append("belly landing: %.0f %% survive, peak %.1f g, %d/%d joints, %d skin pieces off" % [
						belly.survival_overall * 100.0, belly.peak_g, belly.joints_broken, belly.joints_total, belly.skin_lost])
				_begin(2)
		2:
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
				var drop := InjuryModel.build_report(_aircraft, _director)
				if OS.has_environment("CRASHLAB_LOADS"):
					for k: int in mini(drop.seats.size(), 3):
						var r := drop.seats[k]
						print("    drop %s g=%.1f axes=%s hic=%.0f intr=%.2f ej=%s pd=%.2f ph=%.2f pi=%.2f pf=%.2f surv=%.2f" % [
								r.label, r.peak_g, r.peak_g_axes, r.hic, r.intrusion, r.ejected, r.p_decel, r.p_head, r.p_intrusion, r.p_fire, r.survival])
					for f: FredResult in drop.freds:
						print("    drop fred %s pelvis=%.0f head=%.0f belt=%.1f kN stroke=%.2f bottomed=%s ejected=%s" % [f.seat_label, f.limb_peak_g[0], f.limb_peak_g[2], f.belt_peak_kn, f.stroke_m, f.bottomed, f.ejected])
				_survival.append(drop.survival_overall)
				_summary.append("%.0f %% survive" % (drop.survival_overall * 100.0))
				_begin(3)
		3:
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
				var report := InjuryModel.build_report(_aircraft, _director)
				_survival.append(report.survival_overall)
				if report.survival_overall > 0.1:
					return _fail("a cruise-speed dive reported %.0f %% survival" % (report.survival_overall * 100.0))
				if report.impact_speed < _def.v_cruise * 0.8 or report.impact_angle_deg < 15.0:
					return _fail("impact recorded as %.0f m/s at %.0f deg, expected ~%.0f m/s at ~30 deg" % [
							report.impact_speed, report.impact_angle_deg, _def.v_cruise])
				for i: int in range(1, _survival.size()):
					if _survival[i] > _survival[i - 1] + 0.02:
						return _fail("survival rose from scenario %d to %d (%s)" % [i, i + 1, str(_survival)])
				_summary.append("report: %.0f m/s at %.0f deg, %.0f %% survive (%s)" % [
						report.impact_speed, report.impact_angle_deg, report.survival_overall * 100.0, report.verdict])
				if _recorder.frames < 120:
					return _fail("recorder captured only %d frames" % _recorder.frames)
				_recorder.speed = 1.0
				_recorder.play()
				_replay_frames = 0
				return false

	return false


## Lets the replay run for a moment, scrubs it, and checks nothing breaks.
func _check_replay() -> bool:
	_replay_frames += 1
	if _replay_frames == 40:
		_recorder.seek(0.5)
	if _replay_frames == 60:
		_recorder.seek(0.0)
		var nose := _aircraft.root_part.global_position
		# Rewound to the start, the aircraft is back in the air, not in the wreck.
		if nose.y < 20.0:
			return _fail("replay rewind left the aircraft at y=%.1f" % nose.y)
	if _replay_frames < 80:
		return false
	for part: AircraftPart in _aircraft.parts:
		var p := part.global_position
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return _fail("replay put %s at a non-finite position" % part.name)
	_recorder.stop()
	_summary.append("replay %d frames ok" % _recorder.frames)
	print("SMOKE PASS: %s | %s" % [_def.display_name, " | ".join(_summary)])
	quit(0)
	return true


func _fail(msg: String) -> bool:
	printerr("SMOKE FAIL: " + msg)
	quit(1)
	return true
