extends SceneTree
## UI layout harness: renders a screen at a real window size and saves a PNG, or
## runs the `touchtest` hit-test check. Run under Xvfb so stretch scaling is real:
##   xvfb-run -a -s "-screen 0 2600x1300x24" godot --path . -s res://tools/ui_shots.gd \
##     -- <w> <h> <hud|hud_pause|hud_settings|hangar|hangar_settings|report|report_replay|touchtest> <out.png>

const BG := Color(0.45, 0.47, 0.5)

var _w: int = 1280
var _h: int = 720
var _screen: String = "hud"
var _out: String = "/tmp/ui_shot.png"
var _started: bool = false
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 3:
		_w = args[0].to_int()
		_h = args[1].to_int()
		_screen = args[2]
	if args.size() >= 4:
		_out = args[3]


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _layer() -> CanvasLayer:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	bg_layer.add_child(bg)
	root.add_child(bg_layer)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	return layer


func _first_def() -> AircraftDef:
	var dir := DirAccess.open("res://data/aircraft")
	var names: PackedStringArray = dir.get_files() if dir != null else PackedStringArray()
	names.sort()
	for n: String in names:
		if n.ends_with(".tres"):
			var d := load("res://data/aircraft/" + n) as AircraftDef
			if d != null:
				return d
	var fallback := AircraftDef.new()
	fallback.display_name = "Mock 100"
	return fallback


func _make_hud(layer: CanvasLayer) -> Array:
	var hud := (load("res://scenes/ui/flight_hud.tscn") as PackedScene).instantiate() as FlightHud
	layer.add_child(hud)
	await _frames(1)
	var controls := ControlState.new()
	var tel := FlightTelemetry.new()
	tel.ias = 72.0
	tel.tas = 75.0
	tel.mach = 0.22
	tel.altitude_agl = 640.0
	tel.vertical_speed = -2.5
	tel.pitch_deg = 6.0
	tel.roll_deg = -14.0
	tel.aoa_deg = 5.2
	tel.g_load = 1.1
	tel.heading_deg = 247.0
	tel.thrust_fraction = 0.64
	tel.flap_ratio = 0.33
	tel.gear_ratio = 1.0
	tel.trim = 0.04
	var def: AircraftDef = _first_def()
	hud.bind(controls, tel, def)
	hud.show_message("Narrow-body - Runway", 30.0)
	await _frames(3)
	return [hud, controls, tel]


func _seat(label: String, row: int, col: int, cols: int, crew: bool, surv: float) -> SeatResult:
	var s := SeatResult.new()
	s.label = label
	s.row = row
	s.column = col
	s.columns_in_row = cols
	s.is_crew = crew
	s.zone = "fus_mid"
	s.survival = surv
	s.peak_g = 8.0 + (1.0 - surv) * 20.0
	s.peak_g_axes = Vector3(2.0, s.peak_g * 0.8, 5.0)
	s.hic = 300.0 + (1.0 - surv) * 900.0
	s.intrusion = 1.0 - surv
	s.fire = 0.1
	s.p_decel = 1.0 - surv
	s.p_head = 0.2
	s.p_intrusion = 0.1
	s.p_fire = 0.05
	s.cause = "Deceleration" if surv < 0.5 else ""
	return s


func _fred(label: String) -> FredResult:
	var f := FredResult.new()
	f.seat_label = label
	f.limb_names = PackedStringArray(["head", "torso", "pelvis", "L arm", "R arm", "L forearm", "R forearm", "L leg", "R leg"])
	f.limb_peak_g = PackedFloat32Array([30.0, 20.0, 18.0, 12.0, 12.0, 9.0, 9.0, 14.0, 14.0])
	f.hic = 640.0
	f.belt_peak_kn = 7.5
	f.stroke_m = 0.18
	f.bottomed = true
	return f


func _make_report() -> CrashReport:
	var r := CrashReport.new()
	r.aircraft_name = "Meridian 220"
	r.impact_speed = 62.0
	r.impact_velocity = Vector3(40.0, -12.0, 45.0)
	r.impact_vertical_speed = -12.0
	r.impact_pitch_deg = -8.0
	r.impact_roll_deg = 15.0
	r.impact_angle_deg = 11.0
	r.duration = 6.4
	r.joints_broken = 7
	r.joints_total = 31
	r.skin_lost = 120
	r.skin_total = 900
	r.fires = 2
	r.verdict = "Survivable with serious injuries"
	r.seats.append(_seat("CPT", 0, 0, 2, true, 0.9))
	r.seats.append(_seat("FO", 0, 1, 2, true, 0.85))
	var idx: int = 0
	for row: int in 30:
		for c: int in 6:
			var surv: float = fmod(float(idx) * 0.137 + 0.15, 1.0)
			r.seats.append(_seat("%d%s" % [row + 2, char(65 + c)], row + 2, c, 6, false, surv))
			idx += 1
	var total: float = 0.0
	for s: SeatResult in r.seats:
		total += s.survival
		r.peak_g = maxf(r.peak_g, s.peak_g)
	r.survival_overall = total / float(r.seats.size())
	r.survivors_expected = total
	var low: int = 2
	for i: int in r.seats.size():
		if r.seats[i].survival < r.seats[low].survival:
			low = i
	r.freds.append(_fred(r.seats[low].label))
	r.freds.append(_fred(r.seats[5].label))
	r.seats[low].has_fred = true
	r.seats[5].has_fred = true
	return r


func _save(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	print("saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _run() -> void:
	root.size = Vector2i(_w, _h)
	await _frames(3)
	root.size = Vector2i(_w, _h)
	await _frames(2)
	var layer: CanvasLayer = _layer()
	match _screen:
		"hud", "hud_pause", "hud_settings":
			var made: Array = await _make_hud(layer)
			var hud := made[0] as FlightHud
			if _screen != "hud":
				(hud.get_node("%PauseButton") as TouchButton).tapped.emit()
				await _frames(2)
			if _screen == "hud_settings":
				(hud.get_node("%SettingsButton") as Button).pressed.emit()
				await _frames(2)
		"hangar", "hangar_settings":
			var ui := (load("res://scenes/ui/hangar_ui.tscn") as PackedScene).instantiate() as HangarUi
			layer.add_child(ui)
			await _frames(1)
			ui.show_aircraft(_first_def(), 1, 3)
			if _screen == "hangar_settings":
				(ui.get_node("%SettingsButton") as Button).pressed.emit()
			await _frames(3)
		"report", "report_replay":
			var rs := (load("res://scenes/ui/crash_report.tscn") as PackedScene).instantiate() as CrashReportScreen
			layer.add_child(rs)
			await _frames(1)
			rs.show_report(_make_report())
			if _screen == "report_replay":
				rs.show_replay_controls(true)
			await _frames(3)
		"touchtest":
			await _touchtest(layer)
			return
		_:
			print("unknown screen " + _screen)
			quit(2)
			return
	await _frames(2)
	_save(_out)
	quit(0)


# --- Touch hit-testing -------------------------------------------------------

var _tid: int = 0


func _scale() -> Vector2:
	return root.get_final_transform().get_scale()


## Canvas-space point -> window pixels, where a real finger would land.
func _px(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _touch(index: int, canvas_pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _px(canvas_pos)
	e.pressed = pressed
	Input.parse_input_event(e)
	await process_frame
	await process_frame


func _drag(index: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _px(to)
	e.relative = _px(to) - _px(from)
	Input.parse_input_event(e)
	await process_frame
	await process_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _touchtest(layer: CanvasLayer) -> void:
	var made: Array = await _make_hud(layer)
	var hud := made[0] as FlightHud
	var controls := made[1] as ControlState
	var sc: Vector2 = _scale()
	print("window %dx%d canvas scale %s canvas %s" % [_w, _h, str(sc), str(root.get_visible_rect().size)])
	hud.show_message("", 0.0)
	var st := hud.get_node("%Stick") as VirtualStick
	var thr := hud.get_node("%ThrottleSlider") as TouchSlider
	var flap_up := hud.get_node("%FlapUpButton") as TouchButton
	var gear := hud.get_node("%GearButton") as TouchButton
	var brake := hud.get_node("%BrakeButton") as TouchButton
	var cam := hud.get_node("%CamButton") as TouchButton
	var pause := hud.get_node("%PauseButton") as TouchButton
	var cams: Array[int] = [0]
	hud.camera_cycle_requested.connect(func() -> void: cams[0] += 1)

	# Stick: press centre, drag right/down, expect roll > 0 and pitch > 0.
	var c: Vector2 = _center(st)
	await _touch(1, c, true)
	await _drag(1, c, c + Vector2(st.size.x * 0.4, st.size.y * 0.4))
	await _frames(20)
	_expect(controls.roll > 0.2, "stick roll %.2f" % controls.roll)
	_expect(controls.pitch > 0.2, "stick pitch %.2f" % controls.pitch)
	# Throttle while stick still held.
	var tr: Rect2 = thr.get_global_rect()
	var tbottom: Vector2 = Vector2(tr.get_center().x, tr.position.y + tr.size.y - 24.0)
	var ttop: Vector2 = Vector2(tr.get_center().x, tr.position.y + 60.0)
	await _touch(2, tbottom, true)
	await _drag(2, tbottom, ttop)
	await _frames(5)
	_expect(controls.throttle > 0.8, "throttle %.2f" % controls.throttle)
	await _touch(2, ttop, false)
	await _touch(1, c, false)
	await _frames(30)
	_expect(absf(controls.roll) < 0.1, "stick release roll %.2f" % controls.roll)

	# FLAP+ tap.
	var before: int = controls.flap_step
	await _touch(3, _center(flap_up), true)
	await _touch(3, _center(flap_up), false)
	await _frames(3)
	_expect(controls.flap_step == before + 1, "flap %d -> %d" % [before, controls.flap_step])
	# GEAR toggle.
	var gear_before: bool = controls.gear_down
	await _touch(4, _center(gear), true)
	await _touch(4, _center(gear), false)
	await _frames(3)
	_expect(controls.gear_down != gear_before, "gear did not toggle")
	# BRAKE held.
	await _touch(5, _center(brake), true)
	await _frames(3)
	_expect(controls.brake > 0.5, "brake not held")
	await _touch(5, _center(brake), false)
	await _frames(3)
	_expect(controls.brake < 0.5, "brake not released")
	# CAM.
	await _touch(6, _center(cam), true)
	await _touch(6, _center(cam), false)
	_expect(cams[0] == 1, "camera_cycle count %d" % cams[0])
	# PAUSE then Resume via mouse click at window pixels.
	await _touch(7, _center(pause), true)
	await _touch(7, _center(pause), false)
	await _frames(2)
	var overlay := hud.get_node("%PauseOverlay") as Control
	_expect(overlay.visible, "pause overlay not shown")
	var resume := hud.get_node("%ResumeButton") as Button
	var pos: Vector2 = _px(_center(resume))
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = pos
	down.global_position = pos
	down.pressed = true
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = pos
	up.global_position = pos
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)
	_expect(not overlay.visible, "Resume click did not close overlay")
	_expect(not paused, "tree still paused")
	if _failures.is_empty():
		print("TOUCH PASS: stick, throttle, flap, gear, brake, cam, pause/resume at %dx%d (scale %.2f)" % [_w, _h, sc.x])
		quit(0)
	else:
		print("TOUCH FAIL: " + "; ".join(_failures))
		quit(1)
