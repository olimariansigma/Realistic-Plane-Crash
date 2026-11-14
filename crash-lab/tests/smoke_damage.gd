extends SceneTree
## Headless damage-aerodynamics test: what the aircraft does after losing
## pieces of itself in cruise.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/smoke_damage.gd [-- <aircraft id>]
##
## A test pilot holds wings level and pitch as hard as the controls allow.
##  1. Outer wing panel torn off: asymmetric but controllable.
##  2. Whole wing torn off at the root: must roll out of control.
##  3. Wing still attached but stripped of its skin: no skin, no lift, so it
##     must roll out of control just the same.
##  4. Both tailplanes torn off: pitch must diverge.
##  5. Elevators torn off (aircraft with hinged elevators): the stick must
##     stop moving the nose.

const SETTLE := 3.0

var _def: AircraftDef
var _aircraft: Aircraft
var _case := 0
var _t := 0.0
var _started := false
var _done_damage := false
var _max_roll := 0.0
var _pitch0 := 0.0
var _max_pitch_dev := 0.0
var _prev_roll := 0.0
var _pitch_at_pull := 0.0
var _summary: PackedStringArray = []


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "abius_a320"
	_def = load("res://data/aircraft/%s.tres" % id) as AircraftDef
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80000.0, 500.0, 80000.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -250.0
	root.add_child(ground)
	_begin(0)


func _begin(index: int) -> void:
	if _aircraft != null:
		_aircraft.queue_free()
	_case = index
	_t = 0.0
	_done_damage = false
	_max_roll = 0.0
	_max_pitch_dev = 0.0
	_aircraft = Aircraft.new()
	_aircraft.max_freds = 0
	root.add_child(_aircraft)
	_aircraft.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2500.0, 0.0))
	_aircraft.setup(_def)
	_aircraft.set_initial_velocity(Vector3(0.0, 0.0, -_def.v_cruise))
	_aircraft.configure_airborne(_def.cruise_throttle)
	# This test is about aerodynamics: do not let secondary overloads muddy it.
	_aircraft.structure.enabled = false


func _part(part_name: StringName) -> AircraftPart:
	var index := _def.find_part(part_name)
	return _aircraft.parts[index] if index >= 0 else null


func _strip(part: AircraftPart, only_controls: bool) -> void:
	for i: int in part.pieces.size():
		if part.piece_nodes[i] == null:
			continue
		if only_controls and part.pieces[i].control == SkinPiece.Surface.NONE:
			continue
		part.release_piece(i)


func _physics_process(dt: float) -> bool:
	if not _started:
		_started = true
		_start()
		return false
	_t += dt
	var tm := _aircraft.telemetry
	var c := _aircraft.controls
	# Pilot: wings level (PD), hold the starting pitch.
	var rate := (tm.roll_deg - _prev_roll) / dt
	if absf(rate) > 2000.0:
		rate = 0.0  # wrapped through +/-180
	_prev_roll = tm.roll_deg
	c.roll = clampf(-tm.roll_deg * 0.08 - rate * 0.012, -1.0, 1.0)
	if _t < SETTLE:
		_pitch0 = tm.pitch_deg
	if not (_case == 4 and _t > SETTLE + 1.0):
		c.pitch = clampf((_pitch0 - tm.pitch_deg) * 0.12, -1.0, 1.0)

	if _t >= SETTLE and not _done_damage:
		_done_damage = true
		match _case:
			0:
				_aircraft.detach(_def.find_part(&"wing_l_out"), 1.0)
			1:
				_aircraft.detach(_def.find_part(&"wing_l_in"), 1.0)
			2:
				for part_name: StringName in [&"wing_l_in", &"wing_l_mid", &"wing_l_out"]:
					_strip(_part(part_name), false)
			3:
				_aircraft.detach(_def.find_part(&"hstab_l"), 1.0)
				_aircraft.detach(_def.find_part(&"hstab_r"), 1.0)
			4:
				_strip(_part(&"hstab_l"), true)
				_strip(_part(&"hstab_r"), true)
	if _t > SETTLE:
		_max_roll = maxf(_max_roll, absf(tm.roll_deg))
		_max_pitch_dev = maxf(_max_pitch_dev, absf(tm.pitch_deg - _pitch0))

	match _case:
		0:
			if _t > SETTLE + 8.0:
				if _max_roll > 40.0:
					return _fail("losing only the outer panel rolled the aircraft %.0f deg; it should be controllable" % _max_roll)
				_summary.append("outer panel off: held within %.0f deg of level" % _max_roll)
				_begin(1)
		1:
			if _t > SETTLE + 5.0:
				if _max_roll < 60.0:
					return _fail("with a whole wing gone the aircraft only rolled %.0f deg in 5 s" % _max_roll)
				_summary.append("wing off: rolled %.0f deg" % _max_roll)
				_begin(2)
		2:
			if _t > SETTLE + 6.0:
				if _max_roll < 45.0:
					return _fail("with a wing stripped of its skin the aircraft only rolled %.0f deg in 6 s" % _max_roll)
				_summary.append("wing stripped: rolled %.0f deg" % _max_roll)
				_begin(3)
		3:
			if _t > SETTLE + 8.0:
				if _max_pitch_dev < 20.0:
					return _fail("with both tailplanes gone pitch only moved %.0f deg in 8 s" % _max_pitch_dev)
				_summary.append("tailplanes off: pitch ran away %.0f deg" % _max_pitch_dev)
				_begin(4)
		4:
			var hinged := false
			for piece: SkinPiece in _part(&"hstab_l").pieces:
				if piece.control != SkinPiece.Surface.NONE:
					hinged = true
			if not hinged:
				_summary.append("all-moving tail: no separate elevators to lose")
				return _pass()
			if _t > SETTLE + 1.0 and _t < SETTLE + 1.0 + dt * 1.5:
				_pitch_at_pull = tm.pitch_deg
				_aircraft.auto_trim = false
			if _t > SETTLE + 1.0:
				c.pitch = 1.0
			if _t > SETTLE + 4.0:
				var gained := tm.pitch_deg - _pitch_at_pull
				if gained > 3.0:
					return _fail("with the elevators torn off, full back stick still raised the nose %.1f deg" % gained)
				_summary.append("elevators off: full stick moved the nose %.1f deg" % gained)
				return _pass()
	return false


func _pass() -> bool:
	print("SMOKE PASS: %s | %s" % [_def.display_name, " | ".join(_summary)])
	quit(0)
	return true


func _fail(msg: String) -> bool:
	printerr("SMOKE FAIL: " + msg)
	quit(1)
	return true
