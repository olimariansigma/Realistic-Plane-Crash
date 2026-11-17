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
var _calibration: Dictionary = {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(AIRFOIL_DIR)
	DirAccess.make_dir_recursive_absolute(AIRCRAFT_DIR)
	_load_calibration()
	_make_airfoil("transport", "Supercritical transport", 0.28, 0.105, 17.0, 13.0, 0.0068, 0.0055, 0.8, -0.04, 0.80, 0.085)
	_make_airfoil("tail", "Symmetric tail", 0.0, 0.100, 15.0, 15.0, 0.0060, 0.0060, 0.8, 0.0, 0.84, 0.05)
	_make_airfoil("fighter", "Thin high-alpha", 0.06, 0.092, 24.0, 20.0, 0.0055, 0.0090, 0.35, -0.01, 0.92, 0.022)
	# Start from a clean directory so removed aircraft do not linger.
	for file: String in DirAccess.get_files_at(AIRCRAFT_DIR):
		if file.ends_with(".tres"):
			DirAccess.remove_absolute(AIRCRAFT_DIR + file)
	var fleet: Array[Dictionary] = []
	for spec: Dictionary in _airliner_specs():
		fleet.append(_airliner(spec))
	fleet.append(_fighter())
	for params: Dictionary in fleet:
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


## Cruise trim and throttle per aircraft, measured by tools/calibrate.sh and
## stored in data/aircraft/calibration.json. Missing entries get a neutral
## guess; the in-flight start then takes a few seconds to settle.
func _load_calibration() -> void:
	var path := AIRCRAFT_DIR + "calibration.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_calibration = parsed


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
		stall_neg: float, cd_min: float, k_cd: float, blend: float, cm0: float, mach_crit: float,
		wave_drag: float) -> void:
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
	af.mach_crit = mach_crit
	af.wave_drag = wave_drag
	var path := AIRFOIL_DIR + key + ".tres"
	ResourceSaver.save(af, path)
	_airfoils[key] = load(path)


# ---------------------------------------------------------------- parameter tables

## Real aircraft, by their published dimensions and typical operating
## Tail volume coefficients for the airliners.
const H_VOLUME := 1.15
const V_VOLUME := 0.095

## weights (not maximum take-off weight). Maker names are the game's own.
func _airliner_specs() -> Array[Dictionary]:
	var abius := Color(0.94, 0.95, 0.97)
	var bing := Color(0.95, 0.95, 0.93)
	return [
		{
			id = &"abius_a320", name = "Abius A320-200", category = "Narrow-body twin",
			desc = "The single-aisle workhorse. 180 seats, fly-by-wire, forgiving low-speed handling.",
			paint = abius, accent = Color(0.06, 0.2, 0.52), nose_power = 0.58,
			length = 37.57, width = 3.95, mass = 66000.0, span = 34.1, area = 122.6, sweep = 25.0,
			taper = 0.24, winglet = 2.4, winglet_style = 0,
			engines = [0.34], thrust = 120000.0, engine_d = 2.2, engine_len = 4.4, engine_mass = 3400.0,
			rows = 30, groups = [3, 3], wheels = 2,
			v_rotate = 74.0, v_cruise = 128.6, v_ne = 196.0,
		},
		{
			id = &"abius_a330", name = "Abius A330-300", category = "Wide-body twin",
			desc = "Medium-to-long-haul twin-aisle. 296 seats on a long, slender wing.",
			paint = abius, accent = Color(0.07, 0.24, 0.5), nose_power = 0.58,
			length = 63.69, width = 5.64, mass = 195000.0, span = 60.3, area = 361.6, sweep = 30.0,
			taper = 0.25, winglet = 2.7, winglet_style = 0,
			engines = [0.31], thrust = 316000.0, engine_d = 3.1, engine_len = 6.2, engine_mass = 7800.0,
			rows = 37, groups = [2, 4, 2], wheels = 4,
			v_rotate = 80.0, v_cruise = 128.6, v_ne = 185.0,
		},
		{
			id = &"abius_a350", name = "Abius A350-900", category = "Wide-body twin",
			desc = "Composite long-hauler with curved wingtips. 315 seats, a lot of wing for its weight.",
			paint = abius, accent = Color(0.1, 0.12, 0.16), nose_power = 0.6,
			length = 66.8, width = 5.96, mass = 230000.0, span = 64.75, area = 443.0, sweep = 32.0,
			taper = 0.22, winglet = 3.0, winglet_style = 0,
			engines = [0.3], thrust = 374000.0, engine_d = 3.6, engine_len = 6.8, engine_mass = 9300.0,
			rows = 35, groups = [3, 3, 3], wheels = 4,
			v_rotate = 79.0, v_cruise = 128.6, v_ne = 190.0,
		},
		{
			id = &"abius_a380", name = "Abius A380-800", category = "Double-deck four-engine",
			desc = "The largest airliner built. Two full decks, 536 seats, four engines, 80 m of wing.",
			paint = abius, accent = Color(0.05, 0.16, 0.45), nose_power = 0.48, nose_droop = 0.1,
			length = 72.72, width = 7.14, height = 8.41, mass = 480000.0, span = 79.75, area = 845.0,
			sweep = 33.5, taper = 0.22, winglet = 2.3, winglet_style = 2, double_deck = true,
			engines = [0.33, 0.61], thrust = 311000.0, engine_d = 3.5, engine_len = 6.0, engine_mass = 8200.0,
			rows = 36, groups = [3, 4, 3], upper_rows = 22, upper_groups = [2, 4, 2], wheels = 6,
			v_rotate = 82.0, v_cruise = 128.6, v_ne = 190.0,
		},
		{
			id = &"bing_737", name = "Bing 737-800", category = "Narrow-body twin",
			desc = "The best-selling jetliner. 186 seats, low-slung engines, blended winglets.",
			paint = bing, accent = Color(0.0, 0.33, 0.55), nose_power = 0.7,
			length = 39.5, width = 3.76, mass = 66000.0, span = 34.3, area = 124.6, sweep = 25.0,
			taper = 0.22, winglet = 2.5, winglet_style = 0,
			engines = [0.33], thrust = 121000.0, engine_d = 2.05, engine_len = 4.2, engine_mass = 3300.0,
			# CFM56 tucked right up against the wing; big dorsal fin; steep tail.
			engine_drop = 0.03, dorsal = 0.45, tail_upsweep = 0.85, nose_droop = 0.18,
			rows = 31, groups = [3, 3], wheels = 2,
			v_rotate = 75.0, v_cruise = 128.6, v_ne = 190.0,
		},
		{
			id = &"bing_747", name = "Bing 747-400", category = "Four-engine jumbo",
			desc = "The original jumbo, hump and all. 388 seats, four engines, a heavily swept wing.",
			paint = bing, accent = Color(0.02, 0.2, 0.42), nose_power = 0.66,
			length = 70.66, width = 6.5, mass = 330000.0, span = 64.4, area = 541.0, sweep = 37.5,
			taper = 0.25, winglet = 1.8, winglet_style = 0, hump = 1.55, nose_droop = 0.08,
			engines = [0.36, 0.63], thrust = 282000.0, engine_d = 2.8, engine_len = 5.6, engine_mass = 5800.0,
			rows = 34, groups = [3, 4, 3], upper_rows = 8, upper_groups = [3, 3], wheels = 4,
			v_rotate = 84.0, v_cruise = 128.6, v_ne = 203.0,
		},
		{
			id = &"bing_777", name = "Bing 777-300ER", category = "Wide-body twin",
			desc = "The big twin: 370 seats and the largest engines ever fitted to an airliner.",
			paint = bing, accent = Color(0.0, 0.27, 0.5), nose_power = 0.68,
			length = 73.86, width = 6.2, mass = 300000.0, span = 64.8, area = 436.8, sweep = 31.6,
			taper = 0.15, winglet = 2.0, winglet_style = 1,
			engines = [0.31], thrust = 513000.0, engine_d = 3.9, engine_len = 7.3, engine_mass = 10500.0,
			rows = 37, groups = [3, 4, 3], wheels = 6,
			v_rotate = 86.0, v_cruise = 128.6, v_ne = 185.0,
		},
		{
			id = &"bing_787", name = "Bing 787-9", category = "Wide-body twin",
			desc = "Composite long-range twin with raked wingtips. 288 seats, very efficient wing.",
			paint = bing, accent = Color(0.03, 0.3, 0.6), nose_power = 0.74,
			length = 62.81, width = 5.77, mass = 210000.0, span = 60.12, area = 360.5, sweep = 32.2,
			taper = 0.18, winglet = 2.5, winglet_style = 1,
			engines = [0.31], thrust = 320000.0, engine_d = 3.4, engine_len = 6.0, engine_mass = 8000.0,
			rows = 32, groups = [3, 3, 3], wheels = 4,
			v_rotate = 80.0, v_cruise = 128.6, v_ne = 196.0,
		},
	]


## Seat X positions for seat groups separated by aisles, e.g. [3, 4, 3].
func _abreast(groups: Array, seat_width: float, aisle: float) -> Array:
	var xs: Array = []
	var x := 0.0
	for g: int in groups.size():
		for _k: int in int(groups[g]):
			xs.append(x)
			x += seat_width
		x += aisle
	var width: float = xs[xs.size() - 1]
	for i: int in xs.size():
		xs[i] = float(xs[i]) - width * 0.5
	return xs


## Expands an airliner spec into the full parameter set _build() consumes.
## Everything not in the spec follows from scaling rules: tail size from
## volume coefficients, structure thresholds from weight and span, gear from
## geometry. The rules were fitted to the hand-tuned prototypes.
func _airliner(spec: Dictionary) -> Dictionary:
	var length: float = spec.length
	var width: float = spec.width
	var r := width * 0.5
	var height: float = spec.get("height", width)
	var squash_y := height / width
	var mass: float = spec.mass
	var weight := mass * G
	var span: float = spec.span
	var semi := span * 0.5
	var area: float = spec.area
	var taper: float = spec.taper
	var sweep: float = spec.sweep
	var root_c := 2.0 * area / (span * (1.0 + taper))
	var tip_c := root_c * taper
	var mac := 2.0 / 3.0 * root_c * (1.0 + taper + taper * taper) / (1.0 + taper)
	var x_mac := semi / 3.0 * (1.0 + 2.0 * taper) / (1.0 + taper)
	var big := mass > 120000.0
	var huge := mass > 400000.0
	var sections := 7 if length > 50.0 else 5
	var mid := sections / 2

	# Fuselage stations. Z = 0 is where the wing's mean quarter chord starts out.
	var nose_z := -0.44 * length
	var tail_z := nose_z + length
	var nose_cap := 1.35 * width
	var tail_cap := 2.5 * width
	var mid_len := length * (0.26 if sections == 5 else 0.17)
	var nose_end := nose_z + nose_cap + length * 0.03
	var tail_start := tail_z - tail_cap - 0.5
	var per_side := (sections - 3) / 2
	var cuts: Array = []
	for k: int in per_side + 1:
		cuts.append(lerpf(nose_end, -mid_len * 0.5, float(k) / float(per_side)))
	for k: int in per_side + 1:
		cuts.append(lerpf(mid_len * 0.5, tail_start, float(k) / float(per_side)))

	# Mass budget.
	var engine_fracs: Array = spec.engines
	var engine_count := engine_fracs.size() * 2
	var engine_mass: float = spec.engine_mass
	var wing_half := 0.13 * mass
	var htail_mass := 0.0085 * mass
	var fin_mass := 0.0145 * mass
	var nose_gear_mass := 0.0068 * mass
	var main_gear_mass := 0.02 * mass
	var fus_total := mass - wing_half * 2.0 - engine_mass * float(engine_count) - htail_mass * 2.0 \
			- fin_mass - nose_gear_mass - main_gear_mass * 2.0
	var bounds: Array = [nose_z]
	bounds.append_array(cuts)
	bounds.append(tail_z)
	var weights: Array[float] = []
	var weight_sum := 0.0
	for i: int in sections:
		var w := float(bounds[i + 1]) - float(bounds[i])
		w *= 0.75 if i == 0 else (0.5 if i == sections - 1 else (1.5 if i == mid else 1.0))
		weights.append(w)
		weight_sum += w
	var fus_mass: Array = []
	for i: int in sections:
		fus_mass.append(fus_total * weights[i] / weight_sum)

	# Fuselage joints: strongest next to the wing box, weaker toward the ends.
	var fus_break_force: Array = []
	var fus_break_torque: Array = []
	for j: int in sections - 1:
		var steps := (mid - j) if j < mid else (j - mid + 1)
		var f_k: float = [2.4, 1.8, 1.4][clampi(steps - 1, 0, 2)]
		var t_k: float = [0.37, 0.24, 0.15][clampi(steps - 1, 0, 2)]
		fus_break_force.append(f_k * weight)
		fus_break_torque.append(t_k * weight * length)

	# Per-section crown scale (the 747's hump) and window rows.
	var fus_top: Array = []
	var fus_windows: Array = []
	var hump: float = spec.get("hump", 1.0)
	var double_deck: bool = spec.get("double_deck", false)
	for i: int in sections:
		var top := Vector2.ONE
		if hump > 1.0:
			if i < mid - 1:
				top = Vector2(hump, hump)
			elif i == mid - 1:
				top = Vector2(hump, 1.0)
		fus_top.append(top)
		var window_rows := 1
		if double_deck and i < sections - 1:
			window_rows = 2
		elif hump > 1.0 and i < mid - 1:
			window_rows = 2
		fus_windows.append(window_rows)

	# Wing.
	var dihedral := 5.5
	var wing_y := -0.58 * r
	var x_in := 0.92 * r
	var x_kink := 0.40 * semi
	var x_kink2 := 0.69 * semi
	var wing := {
		root_c = root_c, tip_c = tip_c, semi = semi, sweep = sweep, dihedral = dihedral,
		y = wing_y, z_c4 = -tan(deg_to_rad(sweep)) * x_mac, x_in = x_in, x_kink = x_kink,
		x_kink2 = x_kink2, thick = 0.125, winglet = spec.winglet, winglet_style = spec.winglet_style,
		incidence = 3.0, washout = -3.0 if big else -2.5, airfoil = "transport",
		mass_in = wing_half * 0.6, mass_mid = wing_half * 0.28, mass_out = wing_half * 0.12,
		fuel_in = wing_half * 0.36, fuel_mid = wing_half * 0.16, fuel_out = wing_half * 0.05,
		break_force_in = 4.25 * weight, break_torque_in = 0.75 * weight * semi,
		break_force_mid = 3.4 * weight, break_torque_mid = 0.39 * weight * semi,
		break_force_out = 1.25 * weight, break_torque_out = 0.095 * weight * semi,
		flap_in = 0.85, flap_out = 0.45, aileron_deg = 20.0, e = 0.81, cg_mac = 0.25,
	}

	# Engines, per side, slung under the wing ahead of the leading edge.
	var engines: Array = []
	var engine_d: float = spec.engine_d
	var engine_len: float = spec.engine_len
	var lowest := -r * squash_y - (0.25 * width + 0.45)
	for frac: float in engine_fracs:
		var ex := frac * semi
		var chord_x := lerpf(root_c, tip_c, frac)
		var wing_under := wing_y + tan(deg_to_rad(dihedral)) * ex - 0.044 * chord_x
		var ey := wing_under - float(spec.get("engine_drop", 0.12)) * engine_d - engine_d * 0.5
		lowest = minf(lowest, ey - engine_d * 0.5 - 0.55)
		engines.append({
			x = ex, y = ey, z_off = -(0.25 * chord_x + 0.25 * engine_len), length = engine_len,
			r = engine_d * 0.5, mass = engine_mass, thrust = spec.thrust,
			spool = 3.2 if not big else (4.0 if not huge else 4.5), lapse = 0.62,
			mount = "wing_in" if ex < x_kink else "wing_mid",
			break_force = 15.0 * engine_mass * G, break_torque = 15.0 * engine_mass * G * 0.33 * engine_len,
			fuel = 0.045 * engine_mass,
		})
	# Height of the fuselage centreline above the ground: enough for the belly,
	# or more if the nacelles need it.
	var clearance := -lowest

	# Tail, sized by volume coefficients (tailplane 1.15, fin 0.095: the real
	# A320 / 737 tails are 31-33 m2 and 21-26 m2).
	var h_sweep := sweep + 4.0
	var h_z := tail_z - 0.40 * tail_cap
	var h_area := H_VOLUME * area * mac / h_z
	var h_span := sqrt(4.6 * h_area)
	h_area = H_VOLUME * area * mac / (h_z + tan(deg_to_rad(h_sweep)) * h_span * 0.21)
	h_span = sqrt(4.6 * h_area)
	var h_semi := h_span * 0.5
	var h_root := 2.0 * h_area / (h_span * 1.35)
	var htail := {
		root_c = h_root, tip_c = h_root * 0.35, semi = h_semi, sweep = h_sweep, dihedral = 6.0,
		y = 0.3 * r, z_c4 = h_z, x_in = 0.45 * r, thick = 0.10, incidence = -0.5,
		mass = htail_mass, break_force = 0.8 * weight, break_torque = 0.29 * weight * h_semi,
		elevator_deg = 25.0, effectiveness = 0.58, trim_deg = -9.0, e = 0.85,
	}
	var v_z := tail_z - 0.55 * tail_cap
	var v_area := V_VOLUME * area * span / (v_z * 1.05)
	var v_height := sqrt(1.75 * v_area)
	var v_root := 2.0 * v_area / (v_height * 1.35)
	var fins: Array = [{
		x = 0.0, cant = 0.0, root_c = v_root, tip_c = v_root * 0.35, height = v_height, sweep = 38.0,
		y = 0.75 * r * squash_y, z_c4 = v_z, thick = 0.10, mass = fin_mass,
		break_force = 0.72 * weight, break_torque = 0.36 * weight * v_height,
		rudder_deg = 25.0, effectiveness = 0.55,
	}]

	# Landing gear.
	var nose_y := -0.78 * r * squash_y
	var main_y := -0.73 * r
	var gear := {
		nose_z = nose_z + 0.10 * length, nose_y = nose_y, main_x = 0.92 * width,
		main_z_off = 0.37 * mac, main_y = main_y, clearance = clearance,
		nose_mass = nose_gear_mass, main_mass = main_gear_mass, mount = "wing_in",
		nose_wheel_r = 0.38 if not big else (0.5 if not huge else 0.6),
		main_wheel_r = 0.58 if not big else 0.7, main_wheels = spec.wheels,
		travel = 0.45 if not big else (0.6 if not huge else 0.7), steer = 65.0,
		nose_break_force = 0.68 * weight, nose_break_torque = 0.43 * weight * (clearance + nose_y),
		main_break_force = 2.1 * weight, main_break_torque = 1.45 * weight * (clearance + main_y),
	}

	# Cabin.
	var floor_y := (-0.52 if double_deck else -0.30) * r * squash_y
	var z_start := nose_z + nose_cap * 0.85 + 1.0
	var rows: int = spec.rows
	var available := (tail_z - tail_cap * 0.72) - z_start
	var pitch := minf(0.81, available / float(rows))
	var upper_floor := floor_y + 2.55
	var cabin := {
		cockpit_z = nose_z + nose_cap * 0.44, cockpit_x = 0.55 if not big else 0.62,
		cockpit_floor = (upper_floor if hump > 1.0 else floor_y) + 0.25,
		z_start = z_start, rows = rows, pitch = pitch, floor = floor_y, first_row = 1,
		abreast = _abreast(spec.groups, 0.5, 0.52),
	}
	if spec.has("upper_rows"):
		cabin["upper"] = {
			rows = spec.upper_rows, z_start = z_start + (0.5 if hump > 1.0 else 3.0),
			pitch = pitch, floor = upper_floor, abreast = _abreast(spec.upper_groups, 0.5, 0.52),
		}

	var cal: Dictionary = _calibration.get(String(spec.id), {})
	return {
		id = spec.id, name = spec.name, category = spec.category, desc = spec.desc,
		paint = spec.paint, accent = spec.accent,
		nose_z = nose_z, tail_z = tail_z, fus_r = r, nose_cap = nose_cap, tail_cap = tail_cap,
		cuts = cuts, fus_mass = fus_mass,
		fus_break_force = fus_break_force, fus_break_torque = fus_break_torque,
		fus_top = fus_top, fus_windows = fus_windows,
		fus_crush = 0.75 if not big else (1.1 if not huge else 1.3),
		nose_power = spec.nose_power, nose_droop = spec.get("nose_droop", 0.22),
		tail_ratio = spec.get("tail_ratio", 0.22), tail_upsweep = spec.get("tail_upsweep", 0.72),
		dorsal = spec.get("dorsal", 0.2),
		squash = Vector2(1.0, squash_y),
		wing = wing, htail = htail, fins = fins, engines = engines, gear = gear,
		flaps = [0.0, 5.0, 15.0, 25.0, 40.0] if not big else [0.0, 5.0, 15.0, 25.0, 35.0],
		flap_cl = 1.15, flap_cd = 0.075, flap_cm = -0.12,
		flap_time = 12.0 if not big else (16.0 if not huge else 20.0),
		control_rate = 2.2 if not big else (1.6 if not huge else 1.3),
		trim_rate = 0.10 if not big else (0.08 if not huge else 0.07),
		cabin = cabin, body_wave_drag = 1.5, fairing = true,
		# Abius airliners fly a normal law like the real ones: +2.5 / -1 g,
		# 15 deg/s roll rate, bank and angle-of-attack protection. Bing jets
		# are flown direct, as the real ones are in the pitch axis.
		fbw_max_g = 2.5 if String(spec.id).begins_with("abius") else 0.0,
		fbw_min_g = -1.0, fbw_roll_rate_deg = 15.0 if String(spec.id).begins_with("abius") else 0.0,
		fbw_aoa_deg = 13.0,
		v_rotate = spec.v_rotate, v_cruise = spec.v_cruise, v_ne = spec.v_ne,
		cruise_trim = cal.get("trim", 0.3), cruise_throttle = cal.get("throttle", 0.3),
	}


## The single-engine fighter is hand-specified: a 9 g airframe does not follow
## the airliner scaling rules.
func _fighter() -> Dictionary:
	var cal: Dictionary = _calibration.get("lockhid_f16", {})
	return {
		id = &"lockhid_f16", name = "Lockhid F-16C", category = "Single-engine fighter",
		desc = "Lightweight fighter: bubble canopy, afterburner, 9 g airframe. Supersonic at low level.",
		paint = Color(0.52, 0.56, 0.6), accent = Color(0.36, 0.4, 0.45),
		nose_z = -8.3, tail_z = 6.76, fus_r = 0.9, nose_cap = 3.6, tail_cap = 1.2,
		cuts = [-3.0, 2.4], fus_mass = [2000.0, 3500.0, 1500.0],
		fus_break_force = [1.5e6, 1.6e6], fus_break_torque = [2.6e6, 2.8e6],
		fus_crush = 0.5, nose_power = 0.95, nose_droop = 0.12, tail_ratio = 0.72,
		tail_upsweep = 0.0, squash = Vector2(1.1, 0.82),
		canopy = { z0 = -6.0, z1 = -2.9, half_width = 0.47, height = 0.68, mass = 70.0 },
		# The F-16's look: chin intake under the cockpit, root strakes running
		# forward to the canopy, and ventral fins under the engine.
		extras = [
			{ part = &"fus_mid", type = "intake", z0 = -0.7, z1 = 4.2, y_top = -0.42,
				height = 0.85, half_width = 0.5 },
			{ part = &"fus_mid", type = "strake", z0 = -3.0, to_wing_le = true, y = 0.0,
				x_root = 0.9, x_tip = 1.75 },
			{ part = &"fus_tail", type = "ventral", z0 = 1.1, z1 = 2.6, y = -0.62, x = 0.55,
				height = 0.62, cant_deg = 18.0 },
		],
		wing = {
			root_c = 5.0, tip_c = 1.0, semi = 4.73, sweep = 32.0, dihedral = 0.0,
			y = 0.0, z_c4 = -0.9, x_in = 1.0, x_kink = 2.5, x_kink2 = 3.7, thick = 0.045,
			winglet = 0.0, winglet_style = 0, roll_spoiler = 0.0,
			incidence = 0.5, washout = -1.5, airfoil = "fighter",
			mass_in = 560.0, mass_mid = 260.0, mass_out = 110.0,
			fuel_in = 420.0, fuel_mid = 140.0, fuel_out = 0.0,
			break_force_in = 1.1e6, break_torque_in = 1.5e6,
			break_force_mid = 6.5e5, break_torque_mid = 6.0e5,
			break_force_out = 2.2e5, break_torque_out = 1.5e5,
			flap_in = 0.7, flap_out = 0.3, aileron_deg = 12.0, e = 0.78,
			cg_mac = 0.2,
		},
		htail = {
			root_c = 2.9, tip_c = 0.9, semi = 2.8, sweep = 40.0, dihedral = -6.0,
			y = -0.1, z_c4 = 5.2, x_in = 0.75, thick = 0.045, incidence = 0.0,
			mass = 150.0, break_force = 3.4e5, break_torque = 2.6e5,
			# All-moving tailerons: pitch plus a little roll.
			elevator_deg = 24.0, effectiveness = 1.0, trim_deg = -6.0, e = 0.8,
			roll_mix = 0.12, downwash = 0.55,
		},
		fins = [{
			x = 0.0, cant = 0.0, root_c = 3.3, tip_c = 1.1, height = 3.0, sweep = 45.0,
			y = 0.75, z_c4 = 4.2, thick = 0.05, mass = 180.0,
			break_force = 5.5e5, break_torque = 5.5e5, rudder_deg = 28.0, effectiveness = 0.5,
		}],
		engines = [{
			x = 0.0, y = 0.0, z_off = 0.0, z_abs = 4.9, length = 3.6, r = 0.6, mass = 1750.0,
			thrust = 76300.0, afterburner = 129000.0, spool = 1.1, lapse = 0.05, mount = "fus_tail",
			break_force = 9.0e5, break_torque = 7.0e5, fuel = 200.0,
		}],
		gear = {
			nose_z = -5.2, nose_y = -0.75, main_x = 1.2, main_z_off = 0.85, main_y = -0.7,
			clearance = 1.95, nose_mass = 100.0, main_mass = 230.0, mount = "fus_mid",
			nose_wheel_r = 0.24, main_wheel_r = 0.34, main_wheels = 2, travel = 0.32, steer = 50.0,
			nose_break_force = 1.5e5, nose_break_torque = 1.1e5,
			main_break_force = 3.6e5, main_break_torque = 2.6e5,
		},
		flaps = [0.0, 10.0, 25.0], flap_cl = 0.75, flap_cd = 0.05, flap_cm = -0.05,
		flap_time = 4.0, control_rate = 5.0, trim_rate = 0.22,
		cabin = {
			cockpit_z = -4.3, cockpit_x = 0.0, cockpit_floor = -0.2,
			rows = 0, z_start = 0.0, pitch = 1.0, floor = 0.0, first_row = 1, abreast = [],
		},
		body_wave_drag = 1.2, yaw_damper = 3.0,
		# Relaxed-stability fighter: the flight computer limits 9 g / -3 g,
		# 25 deg angle of attack and 180 deg/s of roll rate, as on the real jet.
		fbw_max_g = 9.0, fbw_min_g = -3.0, fbw_roll_rate_deg = 180.0, fbw_aoa_deg = 25.0,
		v_rotate = 77.0, v_cruise = 200.0, v_ne = 410.0,
		cruise_trim = cal.get("trim", 0.45), cruise_throttle = cal.get("throttle", 0.2),
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
	def.body_wave_drag = p.get("body_wave_drag", 1.5)
	def.yaw_damper = p.get("yaw_damper", 1.5)
	def.fbw_max_g = p.get("fbw_max_g", 0.0)
	def.fbw_min_g = p.get("fbw_min_g", -1.0)
	def.fbw_roll_rate_deg = p.get("fbw_roll_rate_deg", 0.0)
	def.fbw_aoa_limit_deg = p.get("fbw_aoa_deg", 15.0)

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
	_add_extras(def, p)

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
		if p.has("fus_top"):
			var top: Vector2 = p.fus_top[i]
			part.top_scale0 = top.x
			part.top_scale1 = top.y
		part.window_rows = int(p.fus_windows[i]) if p.has("fus_windows") else (1 if int(p.cabin.rows) > 0 else 0)
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
		outer.winglet_style = w.winglet_style
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
				s.roll_spoiler = float(w.get("roll_spoiler", 0.6)) if k == 1 or k == 2 else 0.0
				s.downwash_source = k == 0
				if k == 3:
					# Roll right (+1) raises lift on the left wing, lowers it on the right.
					s.control_mix = Vector3(0.0, -side, 0.0)
					s.max_deflection_deg = w.aileron_deg
					s.effectiveness = 0.45
				def.surfaces.append(s)

		var pod := 0
		var pods := 0
		for e: Dictionary in p.engines:
			if String(e.mount).begins_with("wing_"):
				pods += 1
		for e: Dictionary in p.engines:
			if not String(e.mount).begins_with("wing_"):
				continue
			pod += 1
			var eng := PartDef.new()
			eng.name = StringName("engine_%s" % tag if pods == 1 else "engine_%s%d" % [tag, pod])
			eng.parent = inner.name if String(e.mount) == "wing_in" else middle.name
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
				ed.afterburner_thrust = e.get("afterburner", 0.0)
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
		c.downwash_source = true
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
	leg.shape_a = 2.0 if is_nose else float(gear_p.get("main_wheels", 2))
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
			# Twice the induced angle overstates downwash behind a low-aspect
			# wing; such designs give their own factor.
			s.downwash = h.get("downwash", 1.0)
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
		if String(e.mount).begins_with("wing_"):
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
			ed.afterburner_thrust = e.get("afterburner", 0.0)
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

	# Upper deck (double-deckers, the 747's hump): same rule, its own floor.
	if c.has("upper"):
		var u: Dictionary = c.upper
		current = null
		for r: int in int(u.rows):
			var z: float = float(u.z_start) + float(u.pitch) * float(r)
			var owner := _fuselage_part_at(def, z)
			if current == null or current.part != owner:
				current = SeatBlockDef.new()
				current.label = "Upper deck"
				current.part = owner
				current.first_row = 70 + r
				current.rows = 0
				current.z_start = z
				current.pitch = u.pitch
				current.floor_y = u.floor
				current.abreast = PackedFloat32Array(u.abreast)
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


## Shape details (see PartDef.extras), placed against the wing root once
## the wing has been slid to its final position. `p.fairing` adds the airliner
## belly fairing; `p.extras` lists explicit ones by part, where `to_wing_le`
## ends a strake at the wing-root leading edge.
func _add_extras(def: AircraftDef, p: Dictionary) -> void:
	var root_index := def.find_part(&"wing_l_in")
	if root_index < 0:
		return
	var root := def.parts[root_index]
	var le := root.p0.z - 0.25 * root.r0
	var te := root.p0.z + 0.75 * root.r0
	if p.get("fairing", false):
		var mid := def.parts[def.find_part(_fuselage_part_at(def, (le + te) * 0.5))]
		var r := mid.r0
		mid.extras.append({
			type = "fairing", z0 = le - 0.25 * root.r0 - mid.p0.z, z1 = te + 0.55 * root.r0 - mid.p0.z,
			half_width = 1.03 * r * mid.squash.x, y = -0.32 * r * mid.squash.y, depth = 0.8 * r * mid.squash.y,
		})
	# Dorsal fillet: a low blade running forward from the fin root.
	var fin_index := def.find_part(&"fin")
	if float(p.get("dorsal", 0.0)) > 0.0 and fin_index >= 0:
		var fin := def.parts[fin_index]
		var body := def.parts[def.find_part(fin.parent)]
		var fin_le := fin.p0.z - 0.25 * fin.r0
		var fin_h := (fin.p1 - fin.p0).length()
		body.extras.append({
			type = "dorsal", z0 = fin_le - float(p.dorsal) * 1.4 * fin.r0 - body.p0.z,
			z1 = fin_le + 0.3 * fin.r0 - body.p0.z, y = fin.p0.y - body.p0.y - 0.15,
			height = float(p.dorsal) * 0.5 * fin_h, half_width = 0.05 * fin.r0 + 0.08,
		})
	for item: Variant in p.get("extras", []):
		var e := (item as Dictionary).duplicate()
		var part := def.parts[def.find_part(StringName(e.part))]
		e.erase("part")
		if e.get("to_wing_le", false):
			e.erase("to_wing_le")
			e.z1 = le - part.p0.z
		part.extras.append(e)


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
