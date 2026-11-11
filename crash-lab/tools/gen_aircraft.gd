extends SceneTree
## Writes the shipped airfoil and aircraft .tres files from compact parameter
## tables. The game never runs this; it only loads the .tres output, so a plane
## can equally be authored or tweaked by editing a .tres in the Godot editor.
##
## Run: godot --headless --path . -s res://tools/gen_aircraft.gd
##
## Layout assumptions (conventional aircraft): fuselage split into sections
## along Z, a two-panel wing per side, left/right tailplanes, one or two fins,
## podded or buried engines, tricycle gear. Anything else needs a hand-made def.

const G := 9.80665
const AIRFOIL_DIR := "res://data/airfoils/"
const AIRCRAFT_DIR := "res://data/aircraft/"

var _airfoils: Dictionary = {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(AIRFOIL_DIR)
	DirAccess.make_dir_recursive_absolute(AIRCRAFT_DIR)
	_make_airfoil("transport", "Supercritical transport", 0.28, 0.105, 17.0, 13.0, 0.0068, 0.0055, 0.8, -0.04)
	_make_airfoil("tail", "Symmetric tail", 0.0, 0.100, 15.0, 15.0, 0.0060, 0.0060, 0.8, 0.0)
	_make_airfoil("fighter", "Thin high-alpha", 0.06, 0.092, 24.0, 20.0, 0.0055, 0.0090, 0.35, -0.01)
	for params: Dictionary in [_narrow_body(), _wide_body(), _fighter()]:
		var def := _build(params)
		var path := AIRCRAFT_DIR + String(def.id) + ".tres"
		var err := ResourceSaver.save(def, path)
		if err != OK:
			printerr("GEN FAIL: could not save %s (%d)" % [path, err])
			quit(1)
			return
		_report(def, params)
	print("GEN PASS")
	quit(0)


# ---------------------------------------------------------------- airfoils

## Section model: linear lift up to stall, blended into flat-plate behaviour
## (normal-force coefficient 1.8 sin(a)) with a sigmoid of sharpness `blend`.
func _section(aoa_deg: float, cl0: float, slope: float, stall_pos: float, stall_neg: float,
		cd_min: float, k_cd: float, blend: float) -> Vector2:
	var a := deg_to_rad(aoa_deg)
	var ep := exp(-blend * (aoa_deg - stall_pos))
	var en := exp(blend * (aoa_deg + stall_neg))
	var sigma := (1.0 + ep + en) / ((1.0 + ep) * (1.0 + en))
	var cl_lin := cl0 + slope * aoa_deg
	var cl_fp := 1.8 * sin(a) * cos(a)
	var cd_lin := cd_min + k_cd * cl_lin * cl_lin
	var cd_fp := cd_min + 1.8 * sin(a) * sin(a)
	return Vector2(lerpf(cl_lin, cl_fp, sigma), lerpf(cd_lin, cd_fp, sigma))


func _make_airfoil(key: String, title: String, cl0: float, slope: float, stall_pos: float,
		stall_neg: float, cd_min: float, k_cd: float, blend: float, cm0: float) -> void:
	var cl := Curve.new()
	cl.min_value = -3.0
	cl.max_value = 3.0
	var cd := Curve.new()
	cd.min_value = 0.0
	cd.max_value = 3.0
	var aoa := -180.0
	while aoa <= 180.0:
		var s := _section(aoa, cl0, slope, stall_pos, stall_neg, cd_min, k_cd, blend)
		var x := AirfoilDef.aoa_to_x(aoa)
		cl.add_point(Vector2(x, s.x), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		cd.add_point(Vector2(x, s.y), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		aoa += 1.0 if absf(aoa + 0.5) < 40.0 else 5.0
	var af := AirfoilDef.new()
	af.display_name = title
	af.cl_curve = cl
	af.cd_curve = cd
	af.cm0 = cm0
	af.stall_deg = stall_pos
	var path := AIRFOIL_DIR + key + ".tres"
	ResourceSaver.save(af, path)
	_airfoils[key] = load(path)


# ---------------------------------------------------------------- parameter tables

func _narrow_body() -> Dictionary:
	return {
		id = &"meridian_220", name = "Meridian 220", category = "Narrow-body airliner",
		desc = "Twin-engine single-aisle workhorse. 182 seats, forgiving handling, long flaps.",
		paint = Color(0.93, 0.95, 0.97), accent = Color(0.09, 0.32, 0.72),
		# Fuselage: nose tip Z, section cut Zs, radius, cap lengths, masses per section.
		nose_z = -17.2, tail_z = 20.4, fus_r = 1.98, nose_cap = 5.2, tail_cap = 9.5,
		cuts = [-11.5, -5.0, 5.0, 11.5],
		fus_mass = [4500.0, 7000.0, 13500.0, 5500.0, 3000.0],
		fus_break_force = [1.2e6, 1.5e6, 1.7e6, 1.3e6],
		fus_break_torque = [5.0e6, 8.0e6, 9.0e6, 6.0e6],
		fus_crush = 0.75, nose_power = 0.62, nose_droop = 0.28, tail_ratio = 0.14,
		tail_upsweep = 0.72, squash = Vector2(1.0, 1.0),
		# Wing planform measured from the centreline.
		wing = {
			root_c = 6.1, tip_c = 1.6, semi = 17.0, sweep = 25.0, dihedral = 5.0,
			y = -1.15, z_c4 = -3.2, x_in = 1.8, x_kink = 6.8, x_kink2 = 11.8, thick = 0.13,
			winglet = 1.9,
			incidence = 3.0, washout = -2.5, airfoil = "transport",
			mass_in = 5000.0, mass_mid = 2400.0, mass_out = 1100.0,
			fuel_in = 3000.0, fuel_mid = 1400.0, fuel_out = 500.0,
			break_force_in = 2.6e6, break_torque_in = 7.5e6,
			break_force_mid = 2.2e6, break_torque_mid = 4.0e6,
			break_force_out = 8.0e5, break_torque_out = 1.0e6,
			flap_in = 0.85, flap_out = 0.45, aileron_deg = 20.0, e = 0.80,
			cg_mac = 0.24,
		},
		htail = {
			root_c = 3.9, tip_c = 1.4, semi = 6.2, sweep = 28.0, dihedral = 6.0,
			y = 0.55, z_c4 = 17.2, x_in = 0.9, thick = 0.10, incidence = -1.0,
			mass = 520.0, break_force = 5.0e5, break_torque = 1.1e6,
			elevator_deg = 25.0, effectiveness = 0.58, trim_deg = -9.0, e = 0.85,
		},
		fins = [{
			x = 0.0, cant = 0.0, root_c = 5.4, tip_c = 1.9, height = 6.0, sweep = 35.0,
			y = 1.5, z_c4 = 15.4, thick = 0.10, mass = 900.0,
			break_force = 4.5e5, break_torque = 1.3e6, rudder_deg = 25.0, effectiveness = 0.55,
		}],
		engines = [{
			x = 5.75, y = -2.35, z_off = -4.6, length = 4.4, r = 1.12, mass = 3400.0,
			thrust = 120000.0, spool = 3.2, lapse = 0.42, mount = "wing_in",
			break_force = 4.5e5, break_torque = 7.0e5, fuel = 150.0,
		}],
		gear = {
			nose_z = -13.6, nose_y = -1.55, main_x = 3.8, main_z_off = 1.55, main_y = -1.45,
			clearance = 3.45, nose_mass = 420.0, main_mass = 1250.0, mount = "wing_in",
			nose_wheel_r = 0.38, main_wheel_r = 0.58, travel = 0.45, steer = 65.0,
			nose_break_force = 4.2e5, nose_break_torque = 5.0e5,
			main_break_force = 1.25e6, main_break_torque = 1.8e6,
		},
		flaps = [0.0, 5.0, 15.0, 25.0, 40.0], flap_cl = 1.15, flap_cd = 0.075, flap_cm = -0.12,
		flap_time = 12.0, control_rate = 2.2, trim_rate = 0.10,
		cabin = {
			cockpit_z = -14.9, cockpit_x = 0.55, cockpit_floor = -0.35,
			z_start = -12.2, rows = 30, pitch = 0.81, floor = -0.6, first_row = 1,
			abreast = [-1.55, -1.05, -0.55, 0.55, 1.05, 1.55],
		},
		v_rotate = 72.0, v_cruise = 135.0, v_ne = 245.0, cruise_trim = 0.31, cruise_throttle = 0.21,
	}


func _wide_body() -> Dictionary:
	return {
		id = &"atlas_900", name = "Atlas 900", category = "Wide-body airliner",
		desc = "Long-haul twin-aisle heavy. 345 seats and a lot of inertia: plan ahead.",
		paint = Color(0.95, 0.95, 0.93), accent = Color(0.62, 0.10, 0.14),
		nose_z = -30.0, tail_z = 34.0, fus_r = 3.05, nose_cap = 7.5, tail_cap = 15.0,
		cuts = [-21.5, -13.5, -5.5, 5.5, 13.5, 22.5],
		fus_mass = [10000.0, 17000.0, 24000.0, 34000.0, 21000.0, 15000.0, 9000.0],
		fus_break_force = [2.8e6, 3.6e6, 5.2e6, 5.4e6, 3.8e6, 3.0e6],
		fus_break_torque = [2.0e7, 3.0e7, 5.0e7, 5.2e7, 3.2e7, 2.2e7],
		fus_crush = 1.1, nose_power = 0.6, nose_droop = 0.3, tail_ratio = 0.13,
		tail_upsweep = 0.75, squash = Vector2(1.0, 1.0),
		wing = {
			root_c = 12.4, tip_c = 2.6, semi = 30.0, sweep = 31.0, dihedral = 6.0,
			y = -1.7, z_c4 = -6.0, x_in = 2.8, x_kink = 12.0, x_kink2 = 21.0, thick = 0.12,
			winglet = 2.8,
			incidence = 3.0, washout = -3.0, airfoil = "transport",
			mass_in = 19000.0, mass_mid = 8500.0, mass_out = 3500.0,
			fuel_in = 13000.0, fuel_mid = 5000.0, fuel_out = 2000.0,
			break_force_in = 9.5e6, break_torque_in = 5.2e7,
			break_force_mid = 7.0e6, break_torque_mid = 2.6e7,
			break_force_out = 2.5e6, break_torque_out = 6.5e6,
			flap_in = 0.85, flap_out = 0.45, aileron_deg = 20.0, e = 0.82,
			cg_mac = 0.25,
		},
		htail = {
			root_c = 7.0, tip_c = 2.3, semi = 10.5, sweep = 33.0, dihedral = 7.0,
			y = 0.9, z_c4 = 29.5, x_in = 1.4, thick = 0.10, incidence = -1.0,
			mass = 1900.0, break_force = 1.8e6, break_torque = 7.0e6,
			elevator_deg = 25.0, effectiveness = 0.58, trim_deg = -9.0, e = 0.85,
		},
		fins = [{
			x = 0.0, cant = 0.0, root_c = 9.2, tip_c = 3.2, height = 10.0, sweep = 40.0,
			y = 2.5, z_c4 = 26.5, thick = 0.10, mass = 3000.0,
			break_force = 1.6e6, break_torque = 8.0e6, rudder_deg = 25.0, effectiveness = 0.55,
		}],
		engines = [{
			x = 9.6, y = -3.25, z_off = -8.6, length = 7.2, r = 1.7, mass = 9500.0,
			thrust = 400000.0, spool = 4.0, lapse = 0.45, mount = "wing_in",
			break_force = 1.5e6, break_torque = 3.5e6, fuel = 400.0,
		}],
		gear = {
			nose_z = -24.5, nose_y = -2.5, main_x = 5.4, main_z_off = 2.6, main_y = -2.3,
			clearance = 5.4, nose_mass = 1500.0, main_mass = 5200.0, mount = "wing_in",
			nose_wheel_r = 0.55, main_wheel_r = 0.72, travel = 0.6, steer = 65.0,
			nose_break_force = 1.5e6, nose_break_torque = 2.6e6,
			main_break_force = 4.8e6, main_break_torque = 1.0e7,
		},
		flaps = [0.0, 5.0, 15.0, 25.0, 35.0], flap_cl = 1.1, flap_cd = 0.07, flap_cm = -0.11,
		flap_time = 16.0, control_rate = 1.6, trim_rate = 0.08,
		cabin = {
			cockpit_z = -27.0, cockpit_x = 0.62, cockpit_floor = -0.2,
			z_start = -23.0, rows = 38, pitch = 0.86, floor = -0.75, first_row = 1,
			abreast = [-2.5, -2.0, -1.5, -0.5, 0.0, 0.5, 1.5, 2.0, 2.5],
		},
		v_rotate = 84.0, v_cruise = 150.0, v_ne = 260.0, cruise_trim = 0.28, cruise_throttle = 0.31,
	}


func _fighter() -> Dictionary:
	return {
		id = &"kestrel_f7", name = "Kestrel F7", category = "Fighter",
		desc = "Single-seat interceptor. Thrust to spare, 9 g airframe, very little margin for error.",
		paint = Color(0.50, 0.55, 0.60), accent = Color(0.95, 0.72, 0.12),
		nose_z = -8.6, tail_z = 6.9, fus_r = 0.92, nose_cap = 4.6, tail_cap = 1.2,
		cuts = [-3.0, 2.4], fus_mass = [2230.0, 3900.0, 1700.0],
		fus_break_force = [1.5e6, 1.6e6], fus_break_torque = [2.6e6, 2.8e6],
		fus_crush = 0.5, nose_power = 0.95, nose_droop = 0.12, tail_ratio = 0.72,
		tail_upsweep = 0.0, squash = Vector2(1.22, 0.9),
		canopy = { z0 = -6.0, z1 = -3.2, half_width = 0.44, height = 0.62, mass = 70.0 },
		wing = {
			root_c = 5.2, tip_c = 1.1, semi = 4.9, sweep = 38.0, dihedral = 0.0,
			y = 0.0, z_c4 = -0.9, x_in = 1.0, x_kink = 2.6, x_kink2 = 3.8, thick = 0.05,
			winglet = 0.0,
			incidence = 0.5, washout = -1.5, airfoil = "fighter",
			mass_in = 600.0, mass_mid = 280.0, mass_out = 120.0,
			fuel_in = 450.0, fuel_mid = 150.0, fuel_out = 0.0,
			break_force_in = 1.1e6, break_torque_in = 1.5e6,
			break_force_mid = 6.5e5, break_torque_mid = 6.0e5,
			break_force_out = 2.2e5, break_torque_out = 1.5e5,
			flap_in = 0.7, flap_out = 0.3, aileron_deg = 12.0, e = 0.78,
			cg_mac = 0.27,
		},
		htail = {
			root_c = 2.9, tip_c = 0.9, semi = 2.9, sweep = 40.0, dihedral = -2.0,
			y = -0.1, z_c4 = 5.3, x_in = 0.75, thick = 0.045, incidence = 0.0,
			mass = 160.0, break_force = 3.4e5, break_torque = 2.6e5,
			# All-moving tailerons: pitch plus a little roll.
			elevator_deg = 24.0, effectiveness = 1.0, trim_deg = -6.0, e = 0.8,
			roll_mix = 0.12,
		},
		fins = [{
			x = 0.0, cant = 0.0, root_c = 3.3, tip_c = 1.1, height = 3.0, sweep = 45.0,
			y = 0.75, z_c4 = 4.2, thick = 0.05, mass = 190.0,
			break_force = 5.5e5, break_torque = 5.5e5, rudder_deg = 28.0, effectiveness = 0.5,
		}],
		engines = [{
			x = 0.0, y = 0.0, z_off = 0.0, z_abs = 4.9, length = 3.6, r = 0.62, mass = 1700.0,
			thrust = 128000.0, spool = 1.1, lapse = 0.08, mount = "fus_tail",
			break_force = 9.0e5, break_torque = 7.0e5, fuel = 200.0,
		}],
		gear = {
			nose_z = -5.4, nose_y = -0.75, main_x = 1.25, main_z_off = 0.85, main_y = -0.7,
			clearance = 1.95, nose_mass = 110.0, main_mass = 240.0, mount = "fus_mid",
			nose_wheel_r = 0.24, main_wheel_r = 0.34, travel = 0.32, steer = 50.0,
			nose_break_force = 1.5e5, nose_break_torque = 1.1e5,
			main_break_force = 3.6e5, main_break_torque = 2.6e5,
		},
		flaps = [0.0, 10.0, 25.0], flap_cl = 0.75, flap_cd = 0.05, flap_cm = -0.05,
		flap_time = 4.0, control_rate = 5.0, trim_rate = 0.22,
		cabin = {
			cockpit_z = -4.3, cockpit_x = 0.0, cockpit_floor = -0.2,
			rows = 0, z_start = 0.0, pitch = 1.0, floor = 0.0, first_row = 1, abreast = [],
		},
		v_rotate = 78.0, v_cruise = 190.0, v_ne = 420.0, cruise_trim = 0.46, cruise_throttle = 0.10,
	}


# ---------------------------------------------------------------- builder

func _build(p: Dictionary) -> AircraftDef:
	var def := AircraftDef.new()
	def.id = p.id
	def.display_name = p.name
	def.category = p.category
	def.description = p.desc
	def.paint = p.paint
	def.accent = p.accent
	def.flap_steps_deg = PackedFloat32Array(p.flaps)
	def.flap_cl_gain = p.flap_cl
	def.flap_cd_gain = p.flap_cd
	def.flap_cm_gain = p.flap_cm
	def.flap_time = p.flap_time
	def.control_rate = p.control_rate
	def.trim_rate = p.trim_rate
	def.v_rotate = p.v_rotate
	def.v_cruise = p.v_cruise
	def.v_never_exceed = p.v_ne
	def.cruise_trim = p.cruise_trim
	def.cruise_throttle = p.cruise_throttle

	_add_fuselage(def, p)
	# The wing group (wing, wing-mounted engines and gear) slides along Z until
	# the centre of mass sits at the requested fraction of the mean chord.
	var w: Dictionary = p.wing
	var shift := 0.0
	for _i: int in 8:
		var trial := AircraftDef.new()
		trial.parts = def.parts.duplicate()
		_add_wing_group(trial, p, shift, false)
		_add_tail(trial, p, false)
		var mac := _mac(w, shift)
		var target: float = mac.x + (float(w.cg_mac) - 0.25) * mac.y
		shift += trial.center_of_mass().z - target
	_add_wing_group(def, p, shift, true)
	_add_tail(def, p, true)
	_add_canopy(def, p)
	_add_cabin(def, p)

	# Re-origin everything on the centre of mass so "aircraft origin" == CG.
	var cg := def.center_of_mass()
	_translate(def, -cg)
	# `clearance` was the height of the pre-shift origin; the CG sits cg.y above it.
	def.ground_clearance = float(p.gear.clearance) + cg.y
	_size_gear(def)
	def.wing_area = _wing_area(w)
	def.wing_span = float(w.semi) * 2.0
	return def


## Front-most is always fus_nose, aft-most fus_tail, the wing section fus_mid;
## anything between is fus_fwd / fus_fwd2 ... and fus_aft / fus_aft2 ...
func _fus_section_name(i: int, n: int) -> StringName:
	var mid := n / 2
	if i == mid:
		return &"fus_mid"
	if i == 0:
		return &"fus_nose"
	if i == n - 1:
		return &"fus_tail"
	var steps := absi(i - mid)
	var base := "fus_fwd" if i < mid else "fus_aft"
	return StringName(base if steps == 1 else "%s%d" % [base, steps])


func _add_fuselage(def: AircraftDef, p: Dictionary) -> void:
	var cuts: Array = [p.nose_z]
	cuts.append_array(p.cuts)
	cuts.append(p.tail_z)
	var n := cuts.size() - 1
	var mid := n / 2
	var r: float = p.fus_r
	var made: Array[PartDef] = []
	for i: int in n:
		var z0: float = cuts[i]
		var z1: float = cuts[i + 1]
		var part := PartDef.new()
		part.name = _fus_section_name(i, n)
		part.kind = PartDef.Kind.FUSELAGE
		part.mass = p.fus_mass[i]
		part.p0 = Vector3(0.0, 0.0, z0)
		part.p1 = Vector3(0.0, 0.0, z1)
		part.r0 = r
		part.r1 = r
		part.shape_a = float(p.nose_cap) if i == 0 else 0.0
		part.shape_b = float(p.tail_cap) if i == n - 1 else 0.0
		var length := z1 - z0
		# Tapered ends carry less mass at the tip: pull the CoM toward the cabin.
		var com_z := (z0 + z1) * 0.5
		if i == 0:
			com_z += float(p.nose_cap) * 0.16
		if i == n - 1:
			com_z -= float(p.tail_cap) * 0.2
		part.com = Vector3(0.0, -0.12 * r, com_z)
		part.inertia = Vector3(
				part.mass * (3.0 * r * r + length * length) / 12.0,
				part.mass * (3.0 * r * r + length * length) / 12.0,
				part.mass * r * r * 0.72)
		var taper := 1.0
		if i == 0 or i == n - 1:
			taper = 0.8
		# Cross-flow: a cylinder at Cd ~0.7. Axial: skin friction on the wetted
		# area (Cf ~0.003 with form factor), a little more on the tapered ends.
		part.drag_area = Vector3(length * 2.0 * r * 0.7 * taper, length * 2.0 * r * 0.7 * taper,
				0.0033 * TAU * r * length * (1.2 if i == 0 or i == n - 1 else 1.0))
		part.crush_depth = p.fus_crush
		part.nose_power = p.nose_power
		part.nose_droop = p.nose_droop
		part.tail_ratio = p.tail_ratio
		part.tail_upsweep = p.tail_upsweep
		part.squash = p.squash
		made.append(part)
	# Root (mid) first, then outward so parents precede children.
	def.parts.append(made[mid])
	for i: int in range(mid - 1, -1, -1):
		made[i].parent = made[i + 1].name
		made[i].anchor = Vector3(0.0, 0.0, cuts[i + 1])
		made[i].break_force = p.fus_break_force[i]
		made[i].break_torque = p.fus_break_torque[i]
		def.parts.append(made[i])
	for i: int in range(mid + 1, n):
		made[i].parent = made[i - 1].name
		made[i].anchor = Vector3(0.0, 0.0, cuts[i])
		made[i].break_force = p.fus_break_force[i - 1]
		made[i].break_torque = p.fus_break_torque[i - 1]
		def.parts.append(made[i])


## Chord at span station x of a straight-tapered planform.
func _chord(w: Dictionary, x: float) -> float:
	return lerpf(float(w.root_c), float(w.tip_c), x / float(w.semi))


## Quarter-chord point at span station x (right side).
func _c4(w: Dictionary, x: float, shift: float) -> Vector3:
	return Vector3(x, float(w.y) + tan(deg_to_rad(float(w.dihedral))) * x,
			float(w.z_c4) + shift + tan(deg_to_rad(float(w.sweep))) * x)


## Returns (z of the mean-chord quarter point, mean aerodynamic chord).
func _mac(w: Dictionary, shift: float) -> Vector2:
	var lam := float(w.tip_c) / float(w.root_c)
	var mac := 2.0 / 3.0 * float(w.root_c) * (1.0 + lam + lam * lam) / (1.0 + lam)
	var x_mac := float(w.semi) / 3.0 * (1.0 + 2.0 * lam) / (1.0 + lam)
	return Vector2(_c4(w, x_mac, shift).z, mac)


func _wing_area(w: Dictionary) -> float:
	return (float(w.root_c) + float(w.tip_c)) * float(w.semi)


func _panel_part(part_name: StringName, parent: StringName, kind: PartDef.Kind, w: Dictionary,
		x0: float, x1: float, side: float, shift: float, mass: float) -> PartDef:
	var part := PartDef.new()
	part.name = part_name
	part.parent = parent
	part.kind = kind
	part.mass = mass
	var a := _c4(w, x0, shift)
	var b := _c4(w, x1, shift)
	a.x *= side
	b.x *= side
	part.p0 = a
	part.p1 = b
	part.r0 = _chord(w, x0)
	part.r1 = _chord(w, x1)
	part.shape_a = w.thick
	# Area centroid of the trapezoid, pushed aft of the quarter chord to ~40 %.
	var t := (part.r0 + 2.0 * part.r1) / (3.0 * (part.r0 + part.r1))
	var mean_c := lerpf(part.r0, part.r1, t)
	part.com = a.lerp(b, t) + Vector3(0.0, 0.0, 0.15 * mean_c)
	part.anchor = a + Vector3(0.0, 0.0, 0.15 * part.r0)
	var span := (b - a).length()
	var thick := mean_c * float(w.thick)
	part.inertia = Vector3(
			mass * (thick * thick + mean_c * mean_c) / 12.0,
			mass * (span * span + mean_c * mean_c) / 12.0,
			mass * (span * span + thick * thick) / 12.0)
	return part


func _strip(surf_name: StringName, part: StringName, w: Dictionary, x0: float, x1: float,
		side: float, shift: float, incidence_deg: float, airfoil: String, aspect: float,
		full_span: float) -> SurfaceDef:
	var s := SurfaceDef.new()
	s.name = surf_name
	s.part = part
	s.airfoil = _airfoils[airfoil]
	var xm := (x0 + x1) * 0.5
	var pos := _c4(w, xm, shift)
	pos.x *= side
	s.position = pos
	var dih := deg_to_rad(float(w.dihedral))
	var normal := Vector3(-sin(dih) * side, cos(dih), 0.0)
	var inc := deg_to_rad(incidence_deg)
	var chord_dir := Vector3(0.0, sin(inc), -cos(inc))
	chord_dir = (chord_dir - normal * chord_dir.dot(normal)).normalized()
	s.normal = normal
	s.chord_dir = chord_dir
	s.chord = (_chord(w, x0) + _chord(w, x1)) * 0.5
	s.area = s.chord * (x1 - x0)
	s.aspect_ratio = aspect
	s.efficiency = w.e
	s.full_span = full_span
	return s


func _add_wing_group(def: AircraftDef, p: Dictionary, shift: float, with_surfaces: bool) -> void:
	var w: Dictionary = p.wing
	var semi: float = w.semi
	var x_in: float = w.x_in
	var x_kink: float = w.x_kink
	var aspect := 4.0 * semi * semi / _wing_area(w)
	var gear_p: Dictionary = p.gear
	for side_i: int in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var tag := "l" if side_i == 0 else "r"
		var inner := _panel_part(StringName("wing_%s_in" % tag), &"fus_mid", PartDef.Kind.WING,
				w, x_in, x_kink, side, shift, w.mass_in)
		inner.fuel_kg = w.fuel_in
		inner.break_force = w.break_force_in
		inner.break_torque = w.break_torque_in
		var x_kink2: float = w.x_kink2
		var middle := _panel_part(StringName("wing_%s_mid" % tag), inner.name, PartDef.Kind.WING,
				w, x_kink, x_kink2, side, shift, w.mass_mid)
		middle.fuel_kg = w.fuel_mid
		middle.break_force = w.break_force_mid
		middle.break_torque = w.break_torque_mid
		var outer := _panel_part(StringName("wing_%s_out" % tag), middle.name, PartDef.Kind.WING,
				w, x_kink2, semi, side, shift, w.mass_out)
		outer.fuel_kg = w.fuel_out
		outer.break_force = w.break_force_out
		outer.break_torque = w.break_torque_out
		outer.winglet = w.winglet
		def.parts.append(inner)
		def.parts.append(middle)
		def.parts.append(outer)

		if with_surfaces:
			var inc: float = w.incidence
			var wash: float = w.washout
			# Four strips: two on the inner panel, one each on the middle and outer.
			var bounds: Array[float] = [x_in, (x_in + x_kink) * 0.5, x_kink, x_kink2, semi]
			var owners: Array[StringName] = [inner.name, inner.name, middle.name, outer.name]
			for k: int in 4:
				var owner := owners[k]
				var xm := (bounds[k] + bounds[k + 1]) * 0.5
				var s := _strip(StringName("wing_%s_%d" % [tag, k]), owner, w, bounds[k],
						bounds[k + 1], side, shift, inc + wash * xm / semi, w.airfoil, aspect,
						semi * 2.0)
				s.flap_fraction = float(w.flap_in) if k < 2 else (float(w.flap_out) if k == 2 else 0.0)
				s.spoiler_fraction = 0.6 if k == 1 or k == 2 else 0.0
				if k == 3:
					# Roll right (+1) raises lift on the left wing, lowers it on the right.
					s.control_mix = Vector3(0.0, -side, 0.0)
					s.max_deflection_deg = w.aileron_deg
					s.effectiveness = 0.45
				def.surfaces.append(s)

		for e: Dictionary in p.engines:
			if String(e.mount) != "wing_in":
				continue
			var eng := PartDef.new()
			eng.name = StringName("engine_%s" % tag)
			eng.parent = inner.name
			eng.kind = PartDef.Kind.ENGINE
			eng.mass = e.mass
			var wing_at := _c4(w, e.x, shift)
			var zc: float = wing_at.z + float(e.z_off)
			eng.p0 = Vector3(float(e.x) * side, e.y, zc - float(e.length) * 0.5)
			eng.p1 = Vector3(float(e.x) * side, e.y, zc + float(e.length) * 0.5)
			eng.r0 = e.r
			eng.r1 = float(e.r) * 0.72
			eng.com = Vector3(float(e.x) * side, e.y, zc - float(e.length) * 0.08)
			eng.anchor = Vector3(float(e.x) * side, wing_at.y - 0.25, wing_at.z - 0.5)
			var er: float = e.r
			var el: float = e.length
			eng.inertia = Vector3(eng.mass * (3.0 * er * er + el * el) / 12.0,
					eng.mass * (3.0 * er * er + el * el) / 12.0, eng.mass * er * er * 0.5)
			eng.drag_area = Vector3(el * er * 1.4, el * er * 1.4, PI * er * er * 0.06)
			eng.break_force = e.break_force
			eng.break_torque = e.break_torque
			eng.fuel_kg = e.fuel
			eng.skin = 1
			def.parts.append(eng)
			if with_surfaces:
				var ed := EngineDef.new()
				ed.name = eng.name
				ed.part = eng.name
				ed.position = Vector3(float(e.x) * side, e.y, zc)
				ed.direction = Vector3.FORWARD
				ed.max_thrust = e.thrust
				ed.spool_time = e.spool
				ed.mach_lapse = e.lapse
				def.engines.append(ed)

		# Main gear leg.
		var mac := _mac(w, shift)
		var leg := PartDef.new()
		leg.name = StringName("gear_main_%s" % tag)
		leg.kind = PartDef.Kind.GEAR
		leg.mass = gear_p.main_mass
		var mount: String = gear_p.mount
		leg.parent = inner.name if mount == "wing_in" else &"fus_mid"
		var pivot := Vector3(float(gear_p.main_x) * side, gear_p.main_y,
				mac.x + float(gear_p.main_z_off))
		_fill_gear(def, leg, pivot, gear_p, false, with_surfaces, p)
		def.parts.append(leg)

	if with_surfaces:
		# Carry-through: the wing's lift continues across the fuselage.
		var c := _strip(&"wing_center", &"fus_mid", w, 0.0, x_in, 1.0, shift, w.incidence,
				w.airfoil, aspect, semi * 2.0)
		c.position.x = 0.0
		c.normal = Vector3.UP
		c.chord_dir = Vector3(0.0, sin(deg_to_rad(float(w.incidence))),
				-cos(deg_to_rad(float(w.incidence))))
		c.area *= 2.0
		def.surfaces.append(c)


func _fill_gear(def: AircraftDef, leg: PartDef, pivot: Vector3, gear_p: Dictionary,
		is_nose: bool, with_def: bool, p: Dictionary) -> void:
	var wheel_r: float = gear_p.nose_wheel_r if is_nose else gear_p.main_wheel_r
	var travel: float = gear_p.travel
	var clearance: float = gear_p.clearance
	# Static stroke is 55 % of travel; size the strut so the aircraft sits level.
	var static_stroke := travel * 0.55
	var free_length := clearance + pivot.y + static_stroke
	leg.p0 = pivot
	leg.p1 = pivot + Vector3(0.0, -(free_length - wheel_r), 0.0)
	leg.r0 = wheel_r
	leg.r1 = wheel_r * 0.22
	leg.shape_a = 2.0 if is_nose or float(gear_p.main_mass) < 2000.0 else 4.0
	leg.com = pivot.lerp(leg.p1, 0.7)
	leg.anchor = pivot
	var h := free_length
	leg.inertia = Vector3(leg.mass * h * h / 12.0, leg.mass * wheel_r * wheel_r,
			leg.mass * h * h / 12.0)
	leg.break_force = gear_p.nose_break_force if is_nose else gear_p.main_break_force
	leg.break_torque = gear_p.nose_break_torque if is_nose else gear_p.main_break_torque
	leg.skin = 2
	leg.crush_depth = 0.1
	if not with_def:
		return
	var gd := GearDef.new()
	gd.name = leg.name
	gd.part = leg.name
	gd.pivot = pivot
	gd.free_length = free_length
	gd.travel = travel
	gd.wheel_radius = wheel_r
	gd.steer_max_deg = float(gear_p.steer) if is_nose else 0.0
	gd.brake_mu = 0.0 if is_nose else 0.55
	gd.rolling_mu = 0.018
	gd.lateral_mu = 0.75
	gd.drag_area = wheel_r * (1.0 if is_nose else 2.0 * float(leg.shape_a) / 2.0) * 1.3
	def.gear.append(gd)


## Sizes every oleo from the static load it actually carries (moment balance
## about the final centre of mass, which is the origin by now): the spring
## holds that load at 55 % of the stroke and the damper is ~0.5 of critical.
func _size_gear(def: AircraftDef) -> void:
	var weight := def.total_mass() * G
	var nose_z := 0.0
	var main_z := 0.0
	var mains := 0
	for g: GearDef in def.gear:
		if g.steer_max_deg > 0.0:
			nose_z = g.pivot.z
		else:
			main_z = g.pivot.z
			mains += 1
	var nose_load := weight * main_z / (main_z - nose_z)
	for g: GearDef in def.gear:
		var load := nose_load if g.steer_max_deg > 0.0 else (weight - nose_load) / float(mains)
		var static_stroke := g.travel * 0.55
		g.spring_k = load / static_stroke
		g.damper_c = 2.0 * sqrt(g.spring_k * load / G) * (0.55 if g.steer_max_deg > 0.0 else 0.45)


func _add_tail(def: AircraftDef, p: Dictionary, with_surfaces: bool) -> void:
	var h: Dictionary = p.htail
	var aft: StringName = &"fus_tail"
	var h_area := (float(h.root_c) + float(h.tip_c)) * float(h.semi)
	var h_aspect := 4.0 * float(h.semi) * float(h.semi) / h_area
	for side_i: int in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var tag := "l" if side_i == 0 else "r"
		var part := _panel_part(StringName("hstab_%s" % tag), aft, PartDef.Kind.STABILIZER, h,
				h.x_in, h.semi, side, 0.0, h.mass)
		part.break_force = h.break_force
		part.break_torque = h.break_torque
		def.parts.append(part)
		if with_surfaces:
			var s := _strip(StringName("hstab_%s" % tag), part.name, h, h.x_in, h.semi, side, 0.0,
					h.incidence, "tail", h_aspect, float(h.semi) * 2.0)
			# Count the area buried in the fuselage: the tailplane works across it.
			s.area = h_area * 0.5
			# Stick back (+1) must push the tail down: negative lift.
			s.control_mix = Vector3(-1.0, -side * float(h.get("roll_mix", 0.0)), 0.0)
			s.max_deflection_deg = h.elevator_deg
			s.effectiveness = h.effectiveness
			s.trim_deg = h.trim_deg
			def.surfaces.append(s)

	var fins: Array = p.fins
	for i: int in fins.size():
		var f: Dictionary = fins[i]
		var fin := PartDef.new()
		fin.name = StringName("fin" if fins.size() == 1 else "fin_%d" % i)
		fin.parent = aft
		fin.kind = PartDef.Kind.FIN
		fin.mass = f.mass
		var cant := deg_to_rad(float(f.cant))
		var up := Vector3(sin(cant), cos(cant), 0.0)
		var root := Vector3(f.x, f.y, f.z_c4)
		var height: float = f.height
		var tip := root + up * height + Vector3(0.0, 0.0, tan(deg_to_rad(float(f.sweep))) * height)
		fin.p0 = root
		fin.p1 = tip
		fin.r0 = f.root_c
		fin.r1 = f.tip_c
		fin.shape_a = f.thick
		var t := (fin.r0 + 2.0 * fin.r1) / (3.0 * (fin.r0 + fin.r1))
		var mean_c := lerpf(fin.r0, fin.r1, t)
		fin.com = root.lerp(tip, t) + Vector3(0.0, 0.0, 0.15 * mean_c)
		fin.anchor = root + Vector3(0.0, 0.0, 0.15 * fin.r0)
		fin.inertia = Vector3(fin.mass * (height * height + mean_c * mean_c) / 12.0,
				fin.mass * mean_c * mean_c / 12.0, fin.mass * height * height / 12.0)
		fin.break_force = f.break_force
		fin.break_torque = f.break_torque
		fin.skin = 1
		def.parts.append(fin)
		if with_surfaces:
			var area := (fin.r0 + fin.r1) * 0.5 * height
			for k: int in 2:
				var s := SurfaceDef.new()
				s.name = StringName("%s_%d" % [fin.name, k])
				s.part = fin.name
				s.airfoil = _airfoils["tail"]
				var frac := 0.25 + 0.5 * float(k)
				s.position = root.lerp(tip, frac)
				s.normal = Vector3(cos(cant), -sin(cant), 0.0)
				s.chord_dir = Vector3.FORWARD
				s.chord = lerpf(fin.r0, fin.r1, frac)
				s.area = s.chord * height * 0.5
				# The fuselage acts as an end plate: effective AR ~1.6 x geometric.
				s.aspect_ratio = 1.6 * height * height / area
				s.efficiency = 0.8
				s.full_span = height * 2.0
				# Nose right (+1) needs the tail pushed left: negative side lift.
				s.control_mix = Vector3(0.0, 0.0, -1.0)
				s.max_deflection_deg = f.rudder_deg
				s.effectiveness = f.effectiveness
				def.surfaces.append(s)

	# Fuselage-mounted engines and the nose gear ride with the body.
	for e: Dictionary in p.engines:
		if String(e.mount) == "wing_in":
			continue
		var eng := PartDef.new()
		eng.name = &"engine_c"
		eng.parent = StringName(String(e.mount))
		eng.kind = PartDef.Kind.ENGINE
		eng.mass = e.mass
		var zc: float = e.z_abs
		var el: float = e.length
		var er: float = e.r
		eng.p0 = Vector3(e.x, e.y, zc - el * 0.5)
		eng.p1 = Vector3(e.x, e.y, zc + el * 0.5)
		eng.r0 = er
		eng.r1 = er * 0.9
		eng.com = Vector3(e.x, e.y, zc)
		eng.anchor = Vector3(e.x, e.y, zc - el * 0.5)
		eng.inertia = Vector3(eng.mass * (3.0 * er * er + el * el) / 12.0,
				eng.mass * (3.0 * er * er + el * el) / 12.0, eng.mass * er * er * 0.5)
		eng.break_force = e.break_force
		eng.break_torque = e.break_torque
		eng.fuel_kg = e.fuel
		eng.skin = 2
		def.parts.append(eng)
		if with_surfaces:
			var ed := EngineDef.new()
			ed.name = eng.name
			ed.part = eng.name
			ed.position = Vector3(e.x, e.y, zc + el * 0.5)
			ed.max_thrust = e.thrust
			ed.spool_time = e.spool
			ed.mach_lapse = e.lapse
			def.engines.append(ed)

	var gear_p: Dictionary = p.gear
	var nose := PartDef.new()
	nose.name = &"gear_nose"
	nose.kind = PartDef.Kind.GEAR
	nose.mass = gear_p.nose_mass
	nose.parent = def.parts[def.parts.size() - 1].name  # placeholder, fixed below
	var nose_z: float = gear_p.nose_z
	var owner: StringName = &"fus_mid"
	for part: PartDef in def.parts:
		if part.kind == PartDef.Kind.FUSELAGE and nose_z >= part.p0.z and nose_z <= part.p1.z:
			owner = part.name
	nose.parent = owner
	_fill_gear(def, nose, Vector3(0.0, gear_p.nose_y, nose_z), gear_p, true, with_surfaces, p)
	def.parts.append(nose)


## Bubble canopy: its own lightly-attached part, so it can come off.
func _add_canopy(def: AircraftDef, p: Dictionary) -> void:
	if not p.has("canopy"):
		return
	var c: Dictionary = p.canopy
	var z0: float = c.z0
	var z1: float = c.z1
	var owner := _fuselage_part_at(def, (z0 + z1) * 0.5)
	var body := def.parts[def.find_part(owner)]
	var top := float(p.fus_r) * body.squash.y
	var part := PartDef.new()
	part.name = &"canopy"
	part.parent = owner
	part.kind = PartDef.Kind.CANOPY
	part.mass = c.mass
	# Sit the dome on the crown line, which is lower over the nose cap.
	var length := (body.p1 - body.p0).length()
	var y0 := top * 0.55
	var y1 := top * 0.86
	if body.shape_a > 0.0:
		var pr0 := MeshFactory.body_profile(body, clampf(z0 - body.p0.z, 0.0, length), length)
		var pr1 := MeshFactory.body_profile(body, clampf(z1 - body.p0.z, 0.0, length), length)
		y0 = pr0.y + pr0.x * body.squash.y * 0.72
		y1 = pr1.y + pr1.x * body.squash.y * 0.8
	part.p0 = Vector3(0.0, y0, z0)
	part.p1 = Vector3(0.0, y1, z1)
	part.r0 = c.half_width
	part.r1 = c.height
	part.com = (part.p0 + part.p1) * 0.5 + Vector3(0.0, float(c.height) * 0.3, 0.0)
	part.anchor = part.p1
	var span := z1 - z0
	part.inertia = Vector3(part.mass * span * span / 12.0, part.mass * span * span / 12.0,
			part.mass * 0.1)
	part.break_force = 6.0e4
	part.break_torque = 5.0e4
	part.crush_depth = 0.1
	def.parts.append(part)


func _add_cabin(def: AircraftDef, p: Dictionary) -> void:
	var c: Dictionary = p.cabin
	var cockpit := SeatBlockDef.new()
	cockpit.label = "Flight deck"
	cockpit.is_crew = true
	cockpit.rows = 1
	cockpit.first_row = 0
	cockpit.z_start = c.cockpit_z
	cockpit.floor_y = c.cockpit_floor
	var cx: float = c.cockpit_x
	cockpit.abreast = PackedFloat32Array([0.0]) if cx == 0.0 else PackedFloat32Array([-cx, cx])
	cockpit.part = _fuselage_part_at(def, cockpit.z_start)
	def.seat_blocks.append(cockpit)

	# Cabin rows, split wherever they cross a fuselage section boundary so each
	# block is bolted to exactly one structural part.
	var rows: int = c.rows
	var current: SeatBlockDef = null
	for r: int in rows:
		var z: float = float(c.z_start) + float(c.pitch) * float(r)
		var owner := _fuselage_part_at(def, z)
		if current == null or current.part != owner:
			current = SeatBlockDef.new()
			current.label = "Cabin"
			current.part = owner
			current.first_row = int(c.first_row) + r
			current.rows = 0
			current.z_start = z
			current.pitch = c.pitch
			current.floor_y = c.floor
			current.abreast = PackedFloat32Array(c.abreast)
			def.seat_blocks.append(current)
		current.rows += 1

	# FREDs in priority order: captain, then seats spread along the cabin.
	var picks := PackedInt32Array([0])
	var per_row: int = (c.abreast as Array).size()
	if rows > 0 and per_row > 0:
		var first_cabin := cockpit.abreast.size()
		var fractions: Array[float] = [0.5, 0.02, 0.98, 0.25, 0.75, 0.38, 0.62, 0.12, 0.88, 0.45, 0.55]
		for i: int in fractions.size():
			var row := clampi(int(fractions[i] * float(rows)), 0, rows - 1)
			var col := (i * 2) % per_row
			picks.append(first_cabin + row * per_row + col)
	def.fred_seats = picks


func _fuselage_part_at(def: AircraftDef, z: float) -> StringName:
	for part: PartDef in def.parts:
		if part.kind == PartDef.Kind.FUSELAGE and z >= part.p0.z and z < part.p1.z:
			return part.name
	return def.parts[0].name


func _translate(def: AircraftDef, d: Vector3) -> void:
	for part: PartDef in def.parts:
		part.com += d
		part.anchor += d
		part.p0 += d
		part.p1 += d
	for s: SurfaceDef in def.surfaces:
		s.position += d
	for e: EngineDef in def.engines:
		e.position += d
	for g: GearDef in def.gear:
		g.pivot += d
	for b: SeatBlockDef in def.seat_blocks:
		b.z_start += d.z
		b.floor_y += d.y


func _report(def: AircraftDef, p: Dictionary) -> void:
	var inertia := def.total_inertia()
	var w: Dictionary = p.wing
	print("%s: %d parts, %d surfaces, %d seats | mass %.0f kg | S %.1f m2 b %.1f m | T/W %.2f" % [
			def.display_name, def.parts.size(), def.surfaces.size(), def.seat_count(),
			def.total_mass(), def.wing_area, def.wing_span,
			def.total_thrust() / (def.total_mass() * G)])
	print("    inertia pitch %.0f yaw %.0f roll %.0f kg m2 | W/S %.0f kg/m2 | clearance %.2f m | MAC %.2f m" % [
			inertia.x, inertia.y, inertia.z, def.total_mass() / def.wing_area,
			def.ground_clearance, _mac(w, 0.0).y])
