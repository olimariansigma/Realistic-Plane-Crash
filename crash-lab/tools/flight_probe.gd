extends SceneTree
## Developer probe: flies a scripted profile headless and prints a time series.
## Run: godot --headless --path . --fixed-fps 60 -s res://tools/flight_probe.gd -- <id> <mode>
## mode: takeoff | cruise

var _aircraft: Aircraft
var _t := 0.0
var _mode := "takeoff"
var _next_print := 0.0
var _started := false


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "meridian_220"
	_mode = args[1] if args.size() > 1 else "takeoff"
	var world := World.new()
	root.add_child(world)
	var def := load("res://data/aircraft/%s.tres" % id) as AircraftDef
	_aircraft = Aircraft.new()
	root.add_child(_aircraft)
	if _mode == "cruise":
		_aircraft.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 800.0, 0.0))
		_aircraft.setup(def)
		_aircraft.set_initial_velocity(Vector3(0.0, 0.0, -def.v_cruise))
		_aircraft.configure_airborne(0.45)
	else:
		_aircraft.global_transform = Transform3D(Basis.IDENTITY,
				World.RUNWAY_START + Vector3(0.0, def.ground_clearance + 0.05, 0.0))
		_aircraft.setup(def)
	print("mass %.0f  parts %d  surfaces %d" % [def.total_mass(), _aircraft.parts.size(), _aircraft.surfaces.size()])


func _physics_process(dt: float) -> bool:
	if not _started:
		_started = true
		_start()
		return false
	_t += dt
	var a := _aircraft
	var tm := a.telemetry
	var c := a.controls
	if _mode == "takeoff":
		if _t > 3.0:
			c.throttle = 1.0
			c.flap_step = 2
		if tm.ias > a.def.v_rotate and tm.altitude_agl < 300.0:
			c.pitch = clampf((12.0 - tm.pitch_deg) * 0.12, -0.3, 0.8)
		elif tm.altitude_agl >= 300.0:
			c.pitch = clampf((5.0 - tm.pitch_deg) * 0.1, -0.5, 0.5)
		if tm.altitude_agl > 30.0:
			c.gear_down = false
		c.roll = clampf(-tm.roll_deg * 0.05, -1.0, 1.0)
	else:
		# Hands-off after 20 s: tests natural stability.
		if _t < 20.0:
			c.pitch = clampf((2.5 - tm.pitch_deg) * 0.1 - tm.vertical_speed * 0.02, -0.5, 0.5)
			c.roll = clampf(-tm.roll_deg * 0.05, -1.0, 1.0)
		else:
			c.pitch = 0.0
			c.roll = 0.0
	if _t >= _next_print:
		_next_print += 2.0
		var nose := a.gears[a.gears.size() - 1]
		var main := a.gears[0]
		print("t=%5.1f ias=%6.1f alt=%7.1f vs=%6.1f pitch=%6.2f roll=%6.2f aoa=%5.2f g=%5.2f trim=%5.2f thr=%4.2f gear=%4.2f flap=%4.2f nose=%6.0f main=%6.0f z=%8.0f x=%6.1f hdg=%6.2f slip=%5.2f" % [
				_t, tm.ias, tm.altitude_agl, tm.vertical_speed, tm.pitch_deg, tm.roll_deg, tm.aoa_deg,
				tm.g_load, tm.trim, tm.thrust_fraction, tm.gear_ratio, tm.flap_ratio,
				nose.load / 1000.0, main.load / 1000.0, a.root_part.xf.origin.z, a.root_part.xf.origin.x, tm.heading_deg, tm.sideslip_deg])
	if _t > (60.0 if _mode == "takeoff" else 70.0):
		quit(0)
		return true
	return false
