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
			paint = abius, accent = Color("#1E6F8C").srgb_to_linear(), nose_power = 0.58,
			length = 37.57, width = 3.95, mass = 66000.0, span = 34.1, area = 122.6, sweep = 25.0,
			taper = 0.24, winglet = 2.4, winglet_style = 0,
			engines = [0.34], thrust = 120000.0, engine_d = 2.2, engine_len = 4.4, engine_mass = 3400.0,
			rows = 30, groups = [3, 3], wheels = 2,
			# Measured from the Airbus A320 airport-planning drawings (AC, 2017):
			# nose section (station, crown, keel, half-width), windows, doors and
			# windscreen, all from the nose tip and the fuselage mid-height.
			height = 4.14, nose_cap_m = 6.0,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[27.0, 2.07, -2.07, 1.975], [28.0, 2.07, -1.85, 1.93], [30.0, 2.07, -1.45, 1.7], [32.0, 2.07, -1.0, 1.38], [34.0, 2.0, -0.55, 1.0], [36.0, 1.85, -0.05, 0.72], [37.0, 1.6, 0.3, 0.4], [37.57, 1.2, 0.8, 0.12]],
			nose_table = [[0.0, -0.5, -0.93, 0.1], [0.25, -0.2, -1.26, 0.45], [0.5, 0.0, -1.42, 0.69],
				[1.0, 0.27, -1.62, 0.99], [1.5, 0.61, -1.78, 1.21], [2.0, 1.11, -1.89, 1.39],
				[3.0, 1.58, -2.03, 1.68], [4.0, 1.87, -2.07, 1.86], [5.0, 2.03, -2.07, 1.95],
				[6.0, 2.07, -2.07, 1.975]],
			win_w = 0.23, win_h = 0.32, win_pitch = 0.533, win_z = 0.67, win_first = 6.1, win_last = 27.6,
			doors = [[5.04, 0.81, 1.85, -0.12], [14.43, 0.5, 0.9, 0.05], [15.28, 0.5, 0.9, 0.05],
				[29.53, 0.81, 1.79, -0.12]],
			windscreen = { s0 = 1.6, s1 = 3.5, sill0 = 0.32, sill1 = 0.15, top0 = 0.72, top1 = 0.9,
				splits = [2.3, 2.92] },
			# Original fictional airline "Vennari Air": eurowhite, teal cheatline sweeping up the tail.
			scheme = { base = "#F4F5F2", belly = "#5C6570", belly_z = -0.45, belly_sweep = 0.7, belly_end = -0.1,
				cheats = [["#1E6F8C", 0.45, -0.3, 0.82, 0.8], ["#E8A33D", 0.08, -0.6, 0.85, -0.2]],
				texts = [["VENNARI", "#1E6F8C", 0.55, 0.36, 0.45], ["XN-VNA", "#3A424C", 0.32, 0.8, -0.9]],
				radome = "#2B2F36", radome_len = 1.3, cowl = "#1E6F8C", lip = "#C9CED6",
				fin_shapes = [[1, 0.42, 0.7, 0.2, "#F4F5F2"], [5, 0.42, 0.7, 0.09, "#E8A33D"],
					[3, 0.5, 0.075, 0.03, "#F4F5F2"]] },
			v_rotate = 74.0, v_cruise = 128.6, v_ne = 196.0,
		},
		{
			id = &"abius_a330", name = "Abius A330-300", category = "Wide-body twin",
			desc = "Medium-to-long-haul twin-aisle. 296 seats on a long, slender wing.",
			paint = abius, accent = Color("#14213D").srgb_to_linear(), nose_power = 0.58,
			length = 63.69, width = 5.64, mass = 195000.0, span = 60.3, area = 361.6, sweep = 30.0,
			taper = 0.25, winglet = 2.7, winglet_style = 0,
			engines = [0.31], thrust = 316000.0, engine_d = 3.1, engine_len = 6.2, engine_mass = 7800.0,
			rows = 37, groups = [2, 4, 2], wheels = 4,
			# Measured from the Airbus A330 airport-planning drawings (AC, 2013).
			nose_cap_m = 9.0,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[44.0, 2.82, -2.82, 2.82], [46.0, 2.82, -2.6, 2.65], [48.0, 2.82, -2.2, 2.56], [50.0, 2.82, -1.7, 2.38], [52.0, 2.82, -1.2, 2.13], [54.0, 2.82, -0.7, 1.84], [56.0, 2.82, -0.1, 1.55], [58.0, 2.8, 0.6, 1.25], [60.0, 2.75, 1.2, 0.95], [62.0, 2.68, 1.8, 0.5], [63.69, 2.6, 2.2, 0.1]],
			nose_table = [[0.0, -0.18, -0.67, 0.2], [0.25, 0.1, -0.96, 0.5], [0.5, 0.28, -1.14, 0.65],
				[1.0, 0.53, -1.42, 0.92], [1.5, 0.96, -1.63, 1.19], [2.0, 1.38, -1.81, 1.37],
				[3.0, 1.85, -2.1, 1.75], [4.0, 2.13, -2.35, 2.04], [5.0, 2.35, -2.52, 2.29],
				[6.0, 2.52, -2.65, 2.49], [8.0, 2.7, -2.8, 2.74], [10.0, 2.82, -2.82, 2.82]],
			win_w = 0.25, win_h = 0.36, win_pitch = 0.533, win_z = 1.13, win_first = 6.9, win_last = 49.6,
			doors = [[5.3, 1.07, 1.93, -0.045], [17.74, 1.07, 1.93, -0.045], [35.96, 1.07, 1.66, -0.05],
				[50.96, 1.07, 1.93, -0.045]],
			windscreen = { s0 = 1.45, s1 = 3.2, sill0 = 0.38, sill1 = 0.35, top0 = 0.85, top1 = 0.95,
				splits = [1.95, 2.62] },
			# Original fictional airline "Solmara Airways": navy sill line with a gold pinstripe.
			scheme = { base = "#F7F7F4", belly = "#3A3F47", belly_z = -0.4, belly_sweep = 0.75, belly_end = -0.05,
				cheats = [["#14213D", 0.8, -0.55, 0.78, 0.9], ["#C9A227", 0.1, -0.05, 0.78, 1.3]],
				texts = [["SOLMARA", "#14213D", 0.75, 0.4, 0.55], ["XN-SLM", "#14213D", 0.4, 0.8, -1.2]],
				radome = "#14213D", radome_len = 1.8, cowl = "#F7F7F4", lip = "#14213D",
				fin_shapes = [[1, 0.5, 0.75, 0.2, "#C9A227"], [3, 0.5, 0.3, 0.025, "#F7F7F4"],
					[3, 0.5, 0.36, 0.025, "#F7F7F4"], [3, 0.5, 0.42, 0.025, "#F7F7F4"]] },
			v_rotate = 80.0, v_cruise = 128.6, v_ne = 185.0,
		},
		{
			id = &"abius_a350", name = "Abius A350-900", category = "Wide-body twin",
			desc = "Composite long-hauler with curved wingtips. 315 seats, a lot of wing for its weight.",
			paint = abius, accent = Color("#0F3D4C").srgb_to_linear(), nose_power = 0.6,
			length = 66.8, width = 5.96, mass = 230000.0, span = 64.75, area = 443.0, sweep = 32.0,
			taper = 0.22, winglet = 3.0, winglet_style = 0,
			engines = [0.3], thrust = 374000.0, engine_d = 3.6, engine_len = 6.8, engine_mass = 9300.0,
			rows = 35, groups = [3, 3, 3], wheels = 4,
			# Measured from the Airbus A350-900 airport-planning drawings (AC, 2012).
			height = 6.09, nose_cap_m = 9.5,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[48.0, 3.045, -3.045, 2.98], [50.0, 2.95, -2.45, 2.96], [52.0, 2.85, -2.35, 2.78], [54.0, 2.8, -1.95, 2.5], [56.0, 2.65, -1.55, 2.06], [58.0, 2.45, -1.1, 1.62], [60.0, 2.25, -0.55, 1.22], [62.0, 2.1, -0.1, 1.05], [64.0, 2.0, 0.45, 0.85], [65.3, 2.0, 0.8, 0.44], [66.8, 1.9, 1.0, 0.08]],
			nose_table = [[0.0, -1.4, -1.85, 0.15], [0.25, -1.09, -2.06, 0.5], [0.5, -0.85, -2.23, 0.7],
				[1.0, -0.4, -2.48, 1.0], [1.5, 0.0, -2.6, 1.22], [2.0, 0.4, -2.74, 1.38],
				[3.0, 1.35, -2.92, 1.74], [4.0, 1.9, -3.0, 2.02], [5.0, 2.25, -3.045, 2.26],
				[6.0, 2.5, -3.045, 2.5], [8.0, 2.85, -3.045, 2.82], [9.5, 3.045, -3.045, 2.98]],
			win_w = 0.28, win_h = 0.4, win_pitch = 0.59, win_z = 0.65, win_first = 8.4, win_last = 51.2,
			doors = [[6.85, 1.1, 2.1, -0.45], [18.85, 1.1, 2.1, -0.45], [37.93, 0.8, 1.3, 0.1],
				[52.55, 1.1, 2.1, -0.45]],
			windscreen = { s0 = 1.95, s1 = 3.65, sill0 = 0.45, sill1 = 0.4, top0 = 1.05, top1 = 1.1,
				splits = [2.5, 3.12], mask = 0.18 },
			# Original fictional airline "Halvera Airways": a teal wave band.
			scheme = { base = "#FAFAF8", belly = "#B9C1CA", belly_z = -0.5, belly_sweep = 0.8, belly_end = -0.1,
				cheats = [["#1F7F86", 0.6, -0.35, 0.75, 1.0], ["#0F3D4C", 0.05, -0.65, 1.0, -0.65]],
				texts = [["HALVERA", "#0F3D4C", 0.7, 0.3, 0.55], ["XN-HLV", "#0F3D4C", 0.4, 0.8, -1.3]],
				radome = "#2B2F36", radome_len = 1.8, cowl = "#0F3D4C", lip = "#FAFAF8",
				fin_shapes = [[3, 0.5, 0.62, 0.06, "#2AB3A6"], [3, 0.5, 0.54, 0.06, "#2AB3A6"],
					[3, 0.5, 0.46, 0.06, "#2AB3A6"]] },
			v_rotate = 79.0, v_cruise = 128.6, v_ne = 190.0,
		},
		{
			id = &"abius_a380", name = "Abius A380-800", category = "Double-deck four-engine",
			desc = "The largest airliner built. Two full decks, 536 seats, four engines, 80 m of wing.",
			paint = abius, accent = Color("#2B2D33").srgb_to_linear(), nose_power = 0.48, nose_droop = 0.1,
			length = 72.72, width = 7.14, height = 8.41, mass = 480000.0, span = 79.75, area = 845.0,
			sweep = 33.5, taper = 0.22, winglet = 2.3, winglet_style = 2, double_deck = true,
			engines = [0.33, 0.61], thrust = 311000.0, engine_d = 3.5, engine_len = 6.0, engine_mass = 8200.0,
			rows = 36, groups = [3, 4, 3], upper_rows = 22, upper_groups = [2, 4, 2], wheels = 6,
			# Measured from the Airbus A380 airport-planning drawings (AC, 2012).
			nose_cap_m = 10.3,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[50.0, 4.205, -4.205, 3.57], [55.0, 4.1, -2.75, 3.15], [58.0, 3.85, -2.1, 2.57], [60.0, 3.7, -1.6, 2.2], [62.0, 3.5, -1.1, 1.85], [64.0, 3.35, -0.6, 1.5], [66.0, 3.2, -0.15, 1.2], [68.0, 2.9, 0.4, 0.86], [70.3, 2.6, 1.0, 0.3], [72.72, 2.4, 2.0, 0.08]],
			nose_table = [[0.0, -1.34, -2.08, 0.4], [0.25, -0.88, -2.43, 0.78], [0.5, -0.55, -2.65, 1.05],
				[1.0, -0.09, -2.97, 1.38], [1.5, 0.26, -3.18, 1.65], [2.0, 0.65, -3.36, 1.87],
				[3.0, 1.54, -3.57, 2.2], [4.0, 2.26, -3.75, 2.5], [5.0, 2.79, -3.86, 2.71],
				[6.0, 3.22, -3.96, 2.9], [8.0, 3.68, -4.07, 3.21], [10.3, 4.12, -4.205, 3.57]],
			win_w = 0.25, win_h = 0.35, win_pitch = 0.635, win_z = -0.4, win_first = 7.96, win_last = 51.9,
			win2 = [2.5, 13.03, 53.05],
			doors = [[6.32, 1.07, 2.13, -1.55], [16.5, 1.07, 2.13, -1.55], [32.68, 0.9, 1.7, -1.4],
				[44.74, 1.07, 2.13, -1.55], [53.63, 1.07, 2.13, -1.55],
				[20.94, 1.07, 1.9, 1.3], [40.3, 1.07, 1.9, 1.3], [49.19, 1.07, 1.9, 1.3]],
			windscreen = { s0 = 1.65, s1 = 3.6, sill0 = 0.25, sill1 = 0.2, top0 = 0.8, top1 = 0.75,
				splits = [2.4, 3.02] },
			# Original fictional airline "Norvance Airlines": charcoal sill and a bronze ring.
			scheme = { base = "#F8F7F3", belly = "#2B2D33", belly_z = -0.45, belly_sweep = 0.7, belly_end = -0.05,
				cheats = [["#2B2D33", 1.0, -0.6, 0.72, 1.2], ["#B07D3A", 0.12, -0.02, 0.72, 1.5]],
				texts = [["NORVANCE", "#2B2D33", 0.95, 0.4, 0.9], ["XN-NRV", "#2B2D33", 0.45, 0.8, -1.5]],
				radome = "#2B2F36", radome_len = 2.0, cowl = "#C9CDD2", lip = "#2B2D33",
				fin_shapes = [[2, 0.5, 0.74, 0.22, "#B07D3A", 0.015], [1, 0.5, 0.74, 0.07, "#B07D3A"]] },
			v_rotate = 82.0, v_cruise = 128.6, v_ne = 190.0,
		},
		{
			id = &"bing_737", name = "Bing 737-800", category = "Narrow-body twin",
			desc = "The best-selling jetliner. 186 seats, low-slung engines, blended winglets.",
			paint = bing, accent = Color("#1B3A5C").srgb_to_linear(), nose_power = 0.7,
			length = 39.5, width = 3.76, mass = 66000.0, span = 34.3, area = 124.6, sweep = 25.0,
			taper = 0.22, winglet = 2.5, winglet_style = 0,
			engines = [0.33], thrust = 121000.0, engine_d = 2.05, engine_len = 4.2, engine_mass = 3300.0,
			# CFM56 tucked right up against the wing; big dorsal fin; steep tail.
			engine_drop = 0.03, dorsal = 0.45, tail_upsweep = 0.85, nose_droop = 0.18, engine_flat = 0.28,
			rows = 31, groups = [3, 3], wheels = 2,
			win_w = 0.25, win_h = 0.36, win_pitch = 0.51,
			# Measured from Boeing's 737NG airport-planning drawings (D6-58325-7):
			# nose section (station, crown, keel, half-width), windows, doors and
			# windscreen, from the nose tip and the fuselage mid-height.
			height = 4.01, nose_cap_m = 7.9,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[26.0, 2.005, -2.005, 1.88], [28.0, 2.04, -1.83, 1.88], [30.0, 2.04, -1.56, 1.85], [32.0, 2.04, -1.19, 1.72], [34.0, 2.04, -0.71, 1.15], [36.0, 2.0, -0.12, 0.58], [37.0, 1.9, 0.23, 0.4], [38.0, 1.6, 0.73, 0.18], [39.5, 1.3, 1.0, 0.06]],
			nose_table = [[0.0, -0.31, -0.65, 0.09], [0.25, 0.01, -1.0, 0.37], [0.5, 0.17, -1.19, 0.56],
				[1.0, 0.47, -1.43, 0.75], [1.5, 0.81, -1.64, 0.92], [2.0, 1.16, -1.8, 1.08],
				[3.0, 1.53, -1.99, 1.37], [4.0, 1.72, -2.04, 1.6], [5.0, 1.83, -2.04, 1.77],
				[6.0, 1.93, -2.02, 1.85], [7.9, 2.005, -2.005, 1.88]],
			win_z = 0.45, win_first = 6.15, win_last = 30.9,
			doors = [[5.03, 0.86, 1.83, -0.45], [16.75, 0.5, 0.9, -0.1], [17.85, 0.5, 0.9, -0.1],
				[31.88, 0.76, 1.83, -0.41]],
			windscreen = { s0 = 1.5, s1 = 3.05, sill0 = 0.3, sill1 = 0.3, top0 = 0.66, top1 = 1.0,
				splits = [1.85, 2.35] },
			# Original fictional airline "Norvelle Air": dark-blue belly, blue cheatline.
			scheme = { base = "#F4F5F2", belly = "#1B3A5C", belly_z = -0.4, belly_sweep = 0.8, belly_end = -0.15,
				cheats = [["#2E7DBE", 0.35, -0.3, 0.82, 1.6]],
				texts = [["NORVELLE AIR", "#1B3A5C", 0.5, 0.38, 0.6], ["NV-5173", "#1B3A5C", 0.32, 0.8, -1.0]],
				radome = "#2B2F36", radome_len = 1.2, cowl = "#F4F5F2", lip = "#1B3A5C",
				fin_shapes = [[1, 0.45, 0.78, 0.22, "#F4F5F2"], [4, 0.45, 0.6, 0.1, "#2E7DBE"],
					[4, 0.45, 0.5, 0.1, "#2E7DBE"]] },
			v_rotate = 75.0, v_cruise = 128.6, v_ne = 190.0,
		},
		{
			id = &"bing_747", name = "Bing 747-400", category = "Four-engine jumbo",
			desc = "The original jumbo, hump and all. 388 seats, four engines, a heavily swept wing.",
			paint = bing, accent = Color("#0E2A4F").srgb_to_linear(), nose_power = 0.66,
			length = 70.66, width = 6.5, mass = 330000.0, span = 64.4, area = 541.0, sweep = 37.5,
			taper = 0.25, winglet = 1.8, winglet_style = 0, hump = 1.25, nose_droop = 0.08,
			engines = [0.36, 0.63], thrust = 282000.0, engine_d = 2.8, engine_len = 5.6, engine_mass = 5800.0,
			rows = 34, groups = [3, 4, 3], upper_rows = 8, upper_groups = [3, 3], wheels = 4,
			win_w = 0.25, win_h = 0.36, win_pitch = 0.51,
			# Measured from Boeing's 747-400 airport-planning drawings (D6-58326-1).
			# The upper deck stands about 0.9 m above the main crown.
			height = 7.04, nose_cap_m = 10.0,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[45.0, 3.52, -3.52, 3.25], [48.0, 3.52, -3.08, 3.05], [52.0, 3.52, -2.21, 2.7], [54.0, 3.52, -1.77, 2.5], [56.0, 3.52, -1.34, 2.2], [58.0, 3.52, -0.9, 2.0], [60.0, 3.52, -0.47, 1.5], [62.0, 3.55, -0.03, 1.2], [64.0, 3.6, 0.4, 1.0], [66.0, 3.65, 0.78, 0.6], [68.0, 3.6, 1.28, 0.25], [70.66, 3.2, 2.0, 0.06]],
			nose_table = [[0.0, -0.28, -0.47, 0.05], [0.25, 0.22, -0.97, 0.53], [0.5, 0.46, -1.15, 0.84],
				[1.0, 0.78, -1.53, 1.18], [1.5, 1.09, -1.78, 1.34], [2.0, 1.34, -1.96, 1.53],
				[3.0, 1.9, -2.34, 1.77], [4.0, 2.39, -2.65, 2.02], [5.0, 3.14, -2.9, 2.24],
				[6.0, 3.76, -3.08, 2.46], [8.0, 4.14, -3.4, 2.77], [10.0, 4.33, -3.52, 3.1]],
			win_z = 0.19, win_first = 6.0, win_last = 62.3, win2 = [2.77, 9.59, 21.54],
			doors = [[9.5, 1.07, 1.93, -0.84], [18.8, 1.07, 1.93, -0.84], [30.61, 1.07, 1.93, -0.84],
				[40.74, 1.07, 1.93, -0.84], [55.14, 1.07, 1.93, -0.84], [15.45, 0.7, 1.3, 2.15]],
			windscreen = { s0 = 4.55, s1 = 6.3, sill0 = 2.8, sill1 = 2.8, top0 = 3.25, top1 = 3.31,
				splits = [4.95, 5.4] },
			# Original fictional airline "Teshka Airways": navy and gold double cheatline.
			scheme = { base = "#F0F1F3", belly = "#8C939B", belly_z = -0.3, belly_sweep = 0.8, belly_end = -0.1,
				cheats = [["#0E2A4F", 0.7, -0.55, 0.86, 1.6], ["#D4A62A", 0.16, -0.12, 0.86, 2.1]],
				texts = [["TESHKA", "#0E2A4F", 1.2, 0.33, 0.75], ["TK-7410", "#0E2A4F", 0.45, 0.82, -1.4]],
				radome = "#2B2F36", radome_len = 1.6, cowl = "#0E2A4F", lip = "#D4A62A",
				fin_shapes = [[3, 0.5, 0.62, 0.06, "#D4A62A"], [3, 0.5, 0.55, 0.06, "#D4A62A"],
					[5, 0.3, 0.82, 0.18, "#D4A62A"]] },
			v_rotate = 84.0, v_cruise = 128.6, v_ne = 203.0,
		},
		{
			id = &"bing_777", name = "Bing 777-300ER", category = "Wide-body twin",
			desc = "The big twin: 370 seats and the largest engines ever fitted to an airliner.",
			paint = bing, accent = Color("#14213D").srgb_to_linear(), nose_power = 0.68,
			length = 73.86, width = 6.2, mass = 300000.0, span = 64.8, area = 436.8, sweep = 31.6,
			taper = 0.15, winglet = 2.0, winglet_style = 1,
			engines = [0.31], thrust = 513000.0, engine_d = 3.9, engine_len = 7.3, engine_mass = 10500.0,
			rows = 37, groups = [3, 4, 3], wheels = 6,
			win_w = 0.27, win_h = 0.4, win_pitch = 0.57,
			# Measured from Boeing's 777-300ER airport-planning drawings (D6-58329-2).
			height = 6.28, nose_cap_m = 10.0,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[54.0, 3.14, -3.14, 3.1], [56.0, 3.14, -3.08, 3.03], [58.0, 3.14, -2.8, 2.91], [60.0, 3.14, -2.4, 2.68], [62.0, 2.94, -1.94, 2.4], [64.0, 2.83, -1.45, 2.14], [66.0, 2.6, -1.0, 1.7], [68.0, 2.34, -0.55, 1.3], [70.0, 2.1, -0.15, 0.95], [72.0, 2.14, 0.35, 0.45], [73.86, 2.0, 0.9, 0.05]],
			nose_table = [[0.0, -0.51, -0.69, 0.37], [0.25, -0.06, -1.2, 0.6], [0.5, 0.23, -1.37, 0.83],
				[1.0, 0.51, -1.66, 1.14], [1.5, 0.91, -1.89, 1.34], [2.0, 1.37, -2.06, 1.63],
				[3.0, 1.83, -2.34, 1.97], [4.0, 2.23, -2.63, 2.31], [5.0, 2.51, -2.8, 2.6],
				[6.0, 2.68, -2.95, 2.8], [8.0, 3.03, -3.14, 3.08], [10.0, 3.14, -3.14, 3.1]],
			win_z = 0.43, win_first = 8.0, win_last = 58.7,
			doors = [[6.74, 1.07, 1.88, -0.55], [17.07, 1.07, 1.88, -0.55], [32.92, 1.07, 1.88, -0.55],
				[46.46, 1.07, 1.88, -0.55], [59.67, 1.07, 1.88, -0.55]],
			windscreen = { s0 = 1.5, s1 = 3.14, sill0 = 0.34, sill1 = 0.34, top0 = 0.8, top1 = 0.97,
				splits = [1.95, 2.5] },
			# Original fictional airline "Aurion": navy belly, gold ring on the tail.
			scheme = { base = "#FAFAF8", belly = "#14213D", belly_z = -0.35, belly_sweep = 0.8, belly_end = -0.3,
				cheats = [["#C8A24A", 0.16, -0.32, 0.86, -0.32]],
				texts = [["AURION", "#14213D", 0.85, 0.4, 0.62], ["AU-3071", "#14213D", 0.4, 0.82, -1.2]],
				radome = "#2B2F36", radome_len = 1.8, cowl = "#14213D", lip = "#C8A24A",
				fin_shapes = [[2, 0.5, 0.72, 0.34, "#C8A24A", 0.05], [1, 0.5, 0.72, 0.1, "#FAFAF8"],
					[3, 0.5, 0.08, 0.02, "#C8A24A"]] },
			v_rotate = 86.0, v_cruise = 128.6, v_ne = 185.0,
		},
		{
			id = &"bing_787", name = "Bing 787-9", category = "Wide-body twin",
			desc = "Composite long-range twin with raked wingtips. 288 seats, very efficient wing.",
			paint = bing, accent = Color("#E8ECEE").srgb_to_linear(), nose_power = 0.74,
			length = 62.81, width = 5.77, mass = 210000.0, span = 60.12, area = 360.5, sweep = 32.2,
			taper = 0.18, winglet = 2.5, winglet_style = 1,
			engines = [0.31], thrust = 320000.0, engine_d = 3.4, engine_len = 6.0, engine_mass = 8000.0,
			rows = 32, groups = [3, 3, 3], wheels = 4,
			# 787: the largest airliner windows (about 0.27 x 0.47 m).
			win_w = 0.27, win_h = 0.47,
			# Measured from Boeing's 787 airport-planning drawings (D6-58333): the
			# smooth nose, four-pane windscreen and the big, high-set windows.
			height = 5.94, nose_cap_m = 8.97,
			# Measured tail cone (station, crown, keel, half-width).
			tail_table = [[44.0, 2.97, -2.96, 2.885], [46.0, 2.96, -2.9, 2.8], [48.0, 2.92, -2.61, 2.55], [50.0, 2.8, -2.29, 2.25], [52.0, 2.67, -1.9, 2.02], [54.0, 2.43, -1.48, 1.6], [56.0, 2.13, -1.01, 1.3], [58.0, 1.85, -0.51, 0.95], [60.0, 1.6, 0.1, 0.6], [62.81, 1.3, 0.8, 0.04]],
			nose_table = [[0.0, -0.75, -1.1, 0.2], [0.25, -0.57, -1.78, 0.59], [0.5, -0.32, -1.94, 0.75],
				[1.0, 0.16, -2.19, 1.11], [1.5, 0.57, -2.31, 1.36], [2.0, 1.01, -2.43, 1.56],
				[3.0, 1.7, -2.63, 1.92], [4.0, 2.11, -2.76, 2.19], [5.0, 2.39, -2.86, 2.41],
				[6.0, 2.63, -2.92, 2.61], [8.0, 2.88, -2.97, 2.86], [8.97, 2.97, -2.97, 2.885]],
			win_z = 0.77, win_first = 8.0, win_last = 48.9, win_pitch = 0.61,
			doors = [[6.3, 1.07, 1.88, -0.38], [18.36, 1.07, 1.88, -0.38], [35.43, 1.07, 1.88, -0.38],
				[49.66, 1.07, 1.88, -0.38]],
			windscreen = { s0 = 1.85, s1 = 3.4, sill0 = 0.3, sill1 = 0.3, top0 = 0.85, top1 = 1.0,
				splits = [2.35] },
			# Original fictional airline "Kestrava": pale grey, teal belly, split tail.
			scheme = { base = "#E8ECEE", belly = "#0F7C7A", belly_z = -0.32, belly_sweep = 1.0, belly_end = -0.32,
				cheats = [["#0F7C7A", 0.15, -0.36, 1.0, -0.36]],
				texts = [["KESTRAVA", "#0F7C7A", 0.72, 0.42, 0.55], ["KV-9044", "#0F7C7A", 0.36, 0.8, -1.1]],
				radome = "#2B2F36", radome_len = 1.6, cowl = "#E8ECEE", lip = "#0F7C7A",
				fin_shapes = [[6, 0.55, 0.5, 1.0, "#0F7C7A"], [7, 0.2, 0.5, 0.2, "#0F7C7A", 0.07],
					[7, 0.3, 0.5, 0.3, "#0F7C7A", 0.07], [7, 0.4, 0.5, 0.4, "#0F7C7A", 0.07],
					[1, 0.78, 0.78, 0.08, "#E8ECEE"]] },
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
	var nose_cap: float = spec.get("nose_cap_m", 1.35 * width)
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
			fuel = 0.045 * engine_mass, flat_bottom = spec.get("engine_flat", 0.0),
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
	var livery := _airliner_livery(spec, cabin, nose_z, nose_cap, r, squash_y, big, wing_le_hint(spec, nose_z, length))
	return {
		livery = livery,
		nose_table = spec.get("nose_table", []), tail_table = spec.get("tail_table", []),
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


## Measured section rows for the fuselage section spanning stations s0..s1
## (from the nose tip), re-based to the section's own start. Sections untouched
## by the nose or tail tables get none and keep the plain constant section.
## A spec may instead give `section_tables`, one explicit list per section.
func _section_rows(p: Dictionary, index: int, s0: float, s1: float) -> PackedVector4Array:
	var rows := PackedVector4Array()
	var explicit: Array = p.get("section_tables", [])
	if index < explicit.size():
		for v: Variant in explicit[index]:
			var a := v as Array
			rows.append(Vector4(a[0], a[1], a[2], a[3]))
		return rows
	var nose: Array = p.get("nose_table", [])
	var tail: Array = p.get("tail_table", [])
	var nose_end := float((nose.back() as Array)[0]) if not nose.is_empty() else -1.0
	var tail_start := float((tail[0] as Array)[0]) if not tail.is_empty() else INF
	var touches_nose := not nose.is_empty() and s0 < nose_end - 0.01
	var touches_tail := not tail.is_empty() and s1 > tail_start + 0.01
	if not touches_nose and not touches_tail:
		return rows
	var stations: Array[float] = [s0]
	for v: Variant in nose + tail:
		var st := float((v as Array)[0])
		if st > s0 + 0.01 and st < s1 - 0.01:
			stations.append(st)
	stations.append(s1)
	for st: float in stations:
		var a := _sample_body(p, nose, tail, st)
		rows.append(Vector4(st - s0, a.x, a.y, a.z))
	return rows


## Crown, keel and half-width at station `st`, from the measured nose and
## tail tables, or the constant section between them.
func _sample_body(p: Dictionary, nose: Array, tail: Array, st: float) -> Vector3:
	for table: Array in [nose, tail]:
		if table.is_empty():
			continue
		var first := table[0] as Array
		var last := table.back() as Array
		if st < float(first[0]) - 0.001 or st > float(last[0]) + 0.001:
			continue
		for k: int in range(1, table.size()):
			var a := table[k - 1] as Array
			var b := table[k] as Array
			if st <= float(b[0]) + 0.001:
				var t := clampf((st - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
				return Vector3(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t))
	var r := float(p.fus_r)
	var sq: Vector2 = p.squash
	return Vector3(r * sq.y, -r * sq.y, r * sq.x)


## Rough station of the wing-root leading edge (for overwing exits); the
## wing is slid later, so this is only used to place markings.
func wing_le_hint(spec: Dictionary, nose_z: float, length: float) -> float:
	return float(spec.get("wing_le_station", length * 0.40))


## Window rows, doors and windscreen in the fuselage frame (station aft of the
## nose tip, height above the centreline). Spec keys override any value:
## win_w, win_h, win_pitch, win_h_above_floor, doors (Array of
## [station, width, height]), windscreen = {s0, s1, sill0, sill1, top0, top1,
## splits, mask}.
func _airliner_livery(spec: Dictionary, cabin: Dictionary, nose_z: float, nose_cap: float, r: float,
		squash_y: float, big: bool, wing_le: float) -> Dictionary:
	var floor_h: float = cabin.floor
	var first := float(cabin.z_start) - nose_z
	var last := first + float(cabin.rows) * float(cabin.pitch)
	var win_w: float = spec.get("win_w", 0.24)
	var win_h: float = spec.get("win_h", 0.34)
	var pitch: float = spec.get("win_pitch", 0.53)
	var row_h := floor_h + float(spec.get("win_h_above_floor", 1.05))
	if spec.has("win_z"):
		row_h = spec.win_z
		first = float(spec.win_first) - 0.3
		last = float(spec.win_last) + 0.4
	var livery := {
		win_size = Vector4(win_w, win_h, minf(win_w, win_h) * 0.38, pitch),
		win_row0 = Vector4(row_h, first + 0.3, last - 0.4, 1.0),
		win_row1 = Vector4.ZERO,
		panel_lines = Vector4(2.4, 0.01, 0.2, 0.0),
	}
	if cabin.has("upper"):
		var u: Dictionary = cabin.upper
		var u_first := float(u.z_start) - nose_z
		livery.win_row1 = Vector4(float(u.floor) + 0.95, u_first + 0.2,
				u_first + float(u.rows) * float(u.pitch) - 0.3, 1.0)
	if spec.has("win2"):
		var w2: Array = spec.win2
		livery.win_row1 = Vector4(w2[0], w2[1], w2[2], 1.0)
	# Doors: [station, width, height]; sill on the cabin floor.
	var doors: Array = spec.get("doors", [])
	if doors.is_empty():
		var door_h := 1.85 if not big else 1.93
		var door_w := 0.81 if not big else 1.07
		doors = [[first - 1.1, door_w, door_h], [last + 0.8, door_w, door_h]]
		if big:
			doors.append([lerpf(first, last, 0.3), door_w, door_h])
			doors.append([lerpf(first, last, 0.68), door_w, door_h])
		else:
			doors.append([wing_le + 1.0, 0.51, 1.0])
			doors.append([wing_le + 1.95, 0.51, 1.0])
	var list: Array = []
	for d: Variant in doors:
		var a := d as Array
		var w := float(a[1])
		var h := float(a[2])
		# Small doors (overwing exits) sit higher, at window level.
		var sill := floor_h + (0.45 if h < 1.3 else 0.02)
		if a.size() > 3:
			sill = float(a[3])
		list.append(Vector4(float(a[0]), w, h, sill))
	livery.doors = list
	# Windscreen on the nose cap.
	var ws: Dictionary = spec.get("windscreen", {})
	var s0: float = ws.get("s0", nose_cap * 0.33)
	var s1: float = ws.get("s1", nose_cap * 0.6)
	livery.cockpit_a = Vector4(s0, s1, ws.get("sill0", r * squash_y * 0.12), ws.get("sill1", r * squash_y * 0.36))
	livery.cockpit_b = Vector4(ws.get("top0", r * squash_y * 0.5), ws.get("top1", r * squash_y * 0.62), 0.07,
			ws.get("mask", 0.0))
	var splits: Array = ws.get("splits", [lerpf(s0, s1, 0.34), lerpf(s0, s1, 0.68)])
	var sv := Vector4.ZERO
	for i: int in mini(splits.size(), 4):
		sv[i] = float(splits[i])
	livery.cockpit_splits = sv
	if spec.has("scheme"):
		livery.paint = _paint(spec.scheme, row_h, r * squash_y, float(spec.length), spec)
	return livery


## Livery colours and art in shader units. Spec fractions: belly heights in
## fuselage half-heights, stations as fractions of the length, other heights
## in metres from the cabin window line.
## A livery colour written as an sRGB hex code, in the linear space the
## shader and vertex colours work in (raw hex values come out washed out).
func _lin(hex: Variant) -> Color:
	return Color(String(hex)).srgb_to_linear()


func _paint(pp: Dictionary, win_z: float, half_h: float, length: float, spec: Dictionary) -> Dictionary:
	var out := {}
	out.base = _lin(pp.base)
	out.belly = _lin(pp.get("belly", pp.base))
	var bz := float(pp.get("belly_z", -0.45)) * half_h
	var b_start := float(pp.get("belly_sweep", 0.72)) * length
	var b_end := float(pp.get("belly_end", -0.1)) * half_h
	out.belly_line = Vector4(bz, b_start, (b_end - bz) / maxf(length - b_start, 1.0), 0.03)
	var cheats: Array = []
	for c: Variant in pp.get("cheats", []):
		var a := c as Array
		# [colour, width, offset from window line, sweep start (fraction), offset at the tail]
		var start := float(a[3]) * length
		var rise := (float(a[4]) - float(a[2])) / maxf(length - start, 1.0)
		cheats.append([_lin(a[0]), Vector4(float(a[2]), float(a[1]), start, rise)])
	out.cheats = cheats
	var texts: Array = []
	for t: Variant in pp.get("texts", []):
		var a := t as Array
		# [text, colour, cap height, centre (fraction of length), baseline above the window line]
		texts.append([a[0], _lin(a[1]), Vector4(float(a[3]) * length, win_z + float(a[4]), float(a[2]), 0.21)])
	out.texts = texts
	if pp.has("radome"):
		out.radome = _lin(pp.radome)
		out.radome_len = float(pp.get("radome_len", 1.4))
	out.cowl = _lin(pp.get("cowl", pp.base))
	out.lip = _lin(pp.get("lip", "#c9ced6"))
	var shapes: Array = []
	for f: Variant in pp.get("fin_shapes", []):
		var a := f as Array
		shapes.append([a[0], a[1], a[2], a[3], _lin(a[4]), a[5] if a.size() > 5 else 0.0])
	out.fin_shapes = shapes
	return out


## The single-engine fighter is hand-specified: a 9 g airframe does not follow
## the airliner scaling rules.
func _fighter() -> Dictionary:
	var cal: Dictionary = _calibration.get("lockhid_f16", {})
	return {
		id = &"lockhid_f16", name = "Lockhid F-16C", category = "Single-engine fighter",
		desc = "Lightweight fighter: bubble canopy, afterburner, 9 g airframe. Supersonic at low level.",
		paint = Color("#5F6568").srgb_to_linear(), accent = Color("#5F6568").srgb_to_linear(),
		nose_z = -8.3, tail_z = 6.76, fus_r = 0.9, nose_cap = 3.6, tail_cap = 1.2,
		cuts = [-3.0, 2.4], fus_mass = [2000.0, 3500.0, 1500.0],
		fus_break_force = [1.5e6, 1.6e6], fus_break_torque = [2.6e6, 2.8e6],
		fus_crush = 0.5, nose_power = 0.95, nose_droop = 0.12, tail_ratio = 0.72,
		tail_upsweep = 0.0, squash = Vector2(1.1, 0.82),
		canopy = { z0 = -5.4, z1 = -2.2, half_width = 0.52, height = 0.6, mass = 70.0 },
		# Cross-sections every 0.5 m from the F-16C three-view (crown, keel,
		# half-width above the engine axis): the wide flat wing-body, not a tube.
		section_tables = [
			[[0.0, 0.02, -0.12, 0.05], [0.5, 0.18, -0.28, 0.22], [1.0, 0.3, -0.38, 0.36], [1.5, 0.4, -0.46, 0.46],
				[2.0, 0.48, -0.52, 0.54], [2.5, 0.55, -0.55, 0.6], [3.0, 0.62, -0.58, 0.66], [3.5, 0.66, -0.6, 0.7],
				[4.0, 0.67, -0.62, 0.74], [4.5, 0.68, -0.62, 0.78], [5.0, 0.68, -0.64, 0.84], [5.31, 0.68, -0.64, 0.87]],
			[[0.0, 0.68, -0.64, 0.87], [0.7, 0.69, -0.64, 0.92], [1.2, 0.7, -0.64, 0.96], [1.7, 0.71, -0.64, 1.0],
				[2.7, 0.72, -0.64, 1.0], [3.2, 0.72, -0.64, 0.99], [3.7, 0.71, -0.64, 0.96], [4.2, 0.7, -0.62, 0.92],
				[4.7, 0.68, -0.6, 0.88], [5.2, 0.66, -0.6, 0.82], [5.41, 0.65, -0.6, 0.78]],
			[[0.0, 0.65, -0.6, 0.78], [0.3, 0.64, -0.6, 0.76], [0.8, 0.62, -0.6, 0.7], [1.3, 0.6, -0.6, 0.66],
				[1.8, 0.58, -0.6, 0.64], [2.3, 0.58, -0.58, 0.63], [2.8, 0.57, -0.57, 0.62], [3.3, 0.56, -0.56, 0.6],
				[3.8, 0.55, -0.55, 0.58], [4.37, 0.55, -0.55, 0.56]],
		],
		# The F-16's look: chin intake under the cockpit, root strakes running
		# forward to the canopy, and ventral fins under the engine.
		extras = [
			{ part = &"fus_mid", type = "intake", z0 = -0.65, z1 = 2.7, y_top = -0.45,
				height = 0.62, half_width = 0.58 },
			{ part = &"fus_mid", type = "strake", z0 = -1.7, to_wing_le = true, y = 0.0,
				x_root = 0.7, x_tip = 1.75 },
			{ part = &"fus_tail", type = "ventral", z0 = 1.1, z1 = 2.7, y = -0.55, x = 0.5,
				height = 0.55, cant_deg = 15.0 },
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
		# Two-tone air-superiority grey with invented unit markings only.
		livery = { paint = _paint({ base = "#5F6568", belly = "#A9B1B3", belly_z = 0.15, belly_sweep = 1.0,
			belly_end = 0.15, radome = "#7C848A", radome_len = 1.6, cowl = "#5F6568", lip = "#4A4F53",
			texts = [["LK 88-0412", "#1E2226", 0.16, 0.78, -0.25]],
			fin_shapes = [[3, 0.5, 0.5, 0.12, "#D8C26A"], [1, 0.55, 0.78, 0.18, "#1E2226"]] },
			0.0, 0.74, 15.06, {}) },
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
	def.livery = p.get("livery", {})
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
	_fin_paint_geometry(def)

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
		part.nose_table = _section_rows(p, i, z0 - float(p.nose_z), z1 - float(p.nose_z))
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
			eng.flat_bottom = float(e.get("flat_bottom", 0.0))
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
		# Flap-track fairings: one under the inner panel, two under the mid.
		for side: String in ["l", "r"]:
			var inner := def.find_part(StringName("wing_%s_in" % side))
			var middle := def.find_part(StringName("wing_%s_mid" % side))
			if inner >= 0:
				def.parts[inner].extras.append({ type = "canoes", at = [0.62] })
			if middle >= 0:
				def.parts[middle].extras.append({ type = "canoes", at = [0.3, 0.78] })
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


## Fin outline in the fuselage frame, for the tail art.
func _fin_paint_geometry(def: AircraftDef) -> void:
	var fin_index := def.find_part(&"fin")
	if fin_index < 0 or not def.livery.has("paint"):
		return
	var fin := def.parts[fin_index]
	var nose := INF
	var axis_y := 0.0
	for part: PartDef in def.parts:
		if part.kind == PartDef.Kind.FUSELAGE:
			nose = minf(nose, part.p0.z)
			axis_y = part.p0.y
	var height := fin.p1.y - fin.p0.y
	var le0 := fin.p0.z - 0.25 * fin.r0
	var le1 := fin.p1.z - 0.25 * fin.r1
	var paint: Dictionary = def.livery.paint
	paint.fin_geo = Vector4(le0 - nose, fin.p0.y - axis_y, (le1 - le0) / maxf(height, 0.1), fin.r0)
	paint.fin_geo2 = Vector4(fin.r1, height, 0.0, 0.0)


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
