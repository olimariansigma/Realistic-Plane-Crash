extends SceneTree
## Frame-time benchmark for the simulation side of the game.
## Run: godot --headless --path . --fixed-fps 60 -s res://tools/bench.gd [-- <aircraft id>]
##
## Measures, per physics tick and without a renderer:
##   script   everything the game's GDScript does in a tick (flight model,
##            structure monitor, cabin, pools, recorder), timed directly;
##   step     the Jolt physics step, timed as (whole tick) - (script).
## across three phases: cruise, the crash itself, and the settled wreck.
## It also reports body counts and checks that steady-state ticks allocate
## no objects. Numbers are for this machine; scale for the target device.

const WARMUP_TICKS := 120
const CRUISE_TICKS := 600

var _aircraft: Aircraft
var _director: CrashDirector
var _recorder: CrashRecorder
var _def: AircraftDef
var _phase := 0
var _tick := 0
var _started := false
var _last_usec := 0
var _script_usec := 0
var _samples: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _script_samples: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _objects_before := 0
var _crash_ticks := 0
var _peak_bodies := 0


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "atlas_900"
	_def = load("res://data/aircraft/%s.tres" % id) as AircraftDef
	root.add_child(World.new())
	_aircraft = Aircraft.new()
	_aircraft.max_freds = 8
	root.add_child(_aircraft)
	_aircraft.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 700.0, 2000.0))
	_aircraft.setup(_def)
	_aircraft.set_initial_velocity(Vector3(0.0, 0.0, -_def.v_cruise))
	_aircraft.configure_airborne(_def.cruise_throttle)
	_director = CrashDirector.new()
	root.add_child(_director)
	_director.setup(_aircraft, 1, 48)
	_recorder = CrashRecorder.new()
	root.add_child(_recorder)
	_recorder.setup(_aircraft, _director)
	# Wrap the aircraft's tick so its script time can be measured on its own.
	_aircraft.set_physics_process(false)


func _physics_process(dt: float) -> bool:
	if not _started:
		_started = true
		_start()
		_last_usec = Time.get_ticks_usec()
		return false
	var now := Time.get_ticks_usec()
	var whole := float(now - _last_usec) / 1000.0
	_last_usec = now
	_tick += 1

	var t0 := Time.get_ticks_usec()
	_aircraft._physics_process(dt)
	if _aircraft.cabin.armed and not _recorder.recording and _recorder.frames == 0:
		_recorder.start_recording()
	var script_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	if _tick > WARMUP_TICKS:
		_samples[_phase].append(whole)
		_script_samples[_phase].append(script_ms)
	_peak_bodies = maxi(_peak_bodies, _director.debris.flying_count + _director.chunks.flying_count)

	match _phase:
		0:
			var tm := _aircraft.telemetry
			_aircraft.controls.pitch = clampf((2.0 - tm.pitch_deg) * 0.1 - tm.vertical_speed * 0.02, -0.5, 0.5)
			_aircraft.controls.roll = clampf(-tm.roll_deg * 0.05, -1.0, 1.0)
			if _tick == WARMUP_TICKS + 60:
				_objects_before = int(Performance.get_monitor(Performance.OBJECT_COUNT))
			if _tick == WARMUP_TICKS + CRUISE_TICKS:
				var grown := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - _objects_before
				print("cruise: object count changed by %d over %d ticks" % [grown, CRUISE_TICKS - 60])
				# Put it into the ground: 20 degree dive from 150 m.
				var basis := Basis(Vector3.RIGHT, deg_to_rad(-20.0))
				_aircraft.teleport(Transform3D(basis, Vector3(0.0, 150.0, 0.0)), basis * Vector3(0.0, 0.0, -_def.v_cruise * 0.8))
				_phase = 1
		1:
			_crash_ticks += 1
			if _director.settled or _crash_ticks > 2400:
				_phase = 2
				_crash_ticks = 0
		2:
			_crash_ticks += 1
			if _crash_ticks > 300:
				_report()
				quit(0)
				return true
	return false


func _stats(samples: PackedFloat32Array) -> Vector3:
	if samples.is_empty():
		return Vector3.ZERO
	var sorted := samples.duplicate()
	sorted.sort()
	var sum := 0.0
	for v: float in sorted:
		sum += v
	return Vector3(sum / float(sorted.size()), sorted[int(float(sorted.size()) * 0.99)], sorted[sorted.size() - 1])


func _report() -> void:
	var names: Array[String] = ["cruise", "crash", "wreck at rest"]
	var bodies := _aircraft.parts.size()
	for fred: Fred in _aircraft.cabin.freds:
		bodies += fred.limbs.size()
	print("BENCH %s: %d parts, %d surfaces, %d seats, %d FREDs, %d airframe+dummy bodies, peak %d loose bodies" % [
			_def.display_name, _aircraft.parts.size(), _aircraft.surfaces.size(), _aircraft.cabin.seats.size(),
			_aircraft.cabin.freds.size(), bodies, _peak_bodies])
	print("  %-14s  %-28s  %-28s" % ["phase", "whole tick ms (avg/p99/max)", "game script ms (avg/p99/max)"])
	for i: int in 3:
		var w := _stats(_samples[i])
		var s := _stats(_script_samples[i])
		print("  %-14s  %6.2f / %6.2f / %6.2f      %6.2f / %6.2f / %6.2f   (%d ticks)" % [
				names[i], w.x, w.y, w.z, s.x, s.y, s.z, _samples[i].size()])
	print("  budget: 16.67 ms per frame at 60 FPS, rendering not included")
