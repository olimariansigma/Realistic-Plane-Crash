extends SceneTree
## Headless crash-report UI check: header, seat map selection, detail, replay bar.
## Untyped UI reference on purpose: this script compiles before the screen class.

var _fail: String = ""
var _replay: int = 0
var _restart: int = 0
var _hangar: int = 0
var _closed: int = 0
var _seeks: Array[float] = []
var _speeds: Array[float] = []


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _finish() -> void:
	if _fail.is_empty():
		print("SMOKE PASS: report header, seat map, selection, detail, FRED, replay bar, 1 and 400 seats")
		quit(0)
	else:
		print("SMOKE FAIL: " + _fail)
		quit(1)


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


func _report(rows: int, cols: int) -> CrashReport:
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
	var total: float = 0.0
	var idx: int = 0
	if rows * cols > 3:
		r.seats.append(_seat("CPT", 0, 0, 2, true, 0.9))
		r.seats.append(_seat("FO", 0, 1, 2, true, 0.85))
		r.seats.append(_seat("ENG", 0, 0, 1, true, 0.8))
		r.seats[2].row = 1
	for row: int in rows:
		for c: int in cols:
			var surv: float = fmod(float(idx) * 0.137 + 0.15, 1.0)
			r.seats.append(_seat("%d%s" % [row + 2, char(65 + c)], row + 2, c, cols, false, surv))
			idx += 1
	if rows * cols == 1:
		r.seats.append(_seat("1A", 0, 0, 1, false, 0.5))
	for s: SeatResult in r.seats:
		total += s.survival
		r.peak_g = maxf(r.peak_g, s.peak_g)
	r.survival_overall = total / float(r.seats.size())
	r.survivors_expected = total
	return r


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


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _frames(1)
	root.size = Vector2i(1280, 720)
	await _frames(2)
	var ui := (load("res://scenes/ui/crash_report.tscn") as PackedScene).instantiate() as Control
	root.add_child(ui)
	await _frames(1)
	ui.connect("replay_requested", func() -> void: _replay += 1)
	ui.connect("restart_requested", func() -> void: _restart += 1)
	ui.connect("hangar_requested", func() -> void: _hangar += 1)
	ui.connect("replay_closed", func() -> void: _closed += 1)
	ui.connect("replay_seek", func(f: float) -> void: _seeks.append(f))
	ui.connect("replay_speed_changed", func(s: float) -> void: _speeds.append(s))

	var rep: CrashReport = _report(10, 6)
	var lowest: int = 0
	for i: int in rep.seats.size():
		if rep.seats[i].survival < rep.seats[lowest].survival:
			lowest = i
	var other: int = (lowest + 7) % rep.seats.size()
	rep.freds.append(_fred(rep.seats[lowest].label))
	rep.freds.append(_fred(rep.seats[other].label))
	rep.seats[lowest].has_fred = true
	rep.seats[other].has_fred = true
	ui.call("show_report", rep)
	await _frames(2)

	var overall := ui.get_node("%OverallLabel") as Label
	var want: String = "%d%%" % roundi(rep.survival_overall * 100.0)
	if overall.text != want:
		_fail = "overall '%s' != '%s'" % [overall.text, want]
		_finish()
		return
	var title := ui.get_node("%DetailTitle") as Label
	if not title.text.begins_with(rep.seats[lowest].label):
		_fail = "default detail '%s' not lowest seat %s" % [title.text, rep.seats[lowest].label]
		_finish()
		return
	if not (ui.get_node("%FredBox") as Control).visible:
		_fail = "FRED box hidden for FRED seat"
		_finish()
		return
	var map := ui.get_node("%SeatMap") as Control
	map.emit_signal("seat_selected", other)
	if not title.text.begins_with(rep.seats[other].label):
		_fail = "signal select: '%s' not %s" % [title.text, rep.seats[other].label]
		_finish()
		return
	# Click at a seat centre (a non-FRED seat).
	var target: int = (lowest + 3) % rep.seats.size()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map.call("seat_center", target)
	map.call("_gui_input", click)
	if not title.text.begins_with(rep.seats[target].label):
		_fail = "click select: '%s' not %s" % [title.text, rep.seats[target].label]
		_finish()
		return
	if (ui.get_node("%FredBox") as Control).visible:
		_fail = "FRED box visible for non-FRED seat"
		_finish()
		return

	(ui.get_node("%ReplayButton") as Button).pressed.emit()
	(ui.get_node("%RestartButton") as Button).pressed.emit()
	(ui.get_node("%HangarButton") as Button).pressed.emit()
	if _replay != 1 or _restart != 1 or _hangar != 1:
		_fail = "button signals %d/%d/%d" % [_replay, _restart, _hangar]
		_finish()
		return

	var panel := ui.get_node("%ReportPanel") as Control
	var bar := ui.get_node("%ReplayBar") as Control
	var scrub := ui.get_node("%ScrubBar") as HSlider
	if bar.visible or not panel.visible:
		_fail = "replay bar visible in report view"
		_finish()
		return
	ui.call("show_replay_controls", true)
	await _frames(1)
	if panel.visible or not bar.visible or not scrub.is_visible_in_tree():
		_fail = "replay view wrong visibility"
		_finish()
		return
	if (ui.get_node("%Backdrop") as Control).visible or ui.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail = "replay view blocks input"
		_finish()
		return
	scrub.value = 0.3
	if _seeks.size() != 1 or not is_equal_approx(_seeks[0], 0.3):
		_fail = "scrub did not emit seek: %s" % str(_seeks)
		_finish()
		return
	ui.call("set_replay_progress", 0.5)
	if _seeks.size() != 1 or not is_equal_approx(scrub.value, 0.5):
		_fail = "set_replay_progress emitted or failed: %s %f" % [str(_seeks), scrub.value]
		_finish()
		return
	if not (ui.get_node("%Speed1") as Button).button_pressed:
		_fail = "0.25x not default"
		_finish()
		return
	(ui.get_node("%Speed2") as Button).pressed.emit()
	if _speeds != [0.5]:
		_fail = "speed signal: %s" % str(_speeds)
		_finish()
		return
	(ui.get_node("%ReportButton") as Button).pressed.emit()
	if _closed != 1:
		_fail = "replay_closed not emitted"
		_finish()
		return
	ui.call("show_replay_controls", false)

	for dims: Vector2i in [Vector2i(1, 1), Vector2i(100, 4), Vector2i(0, 0)]:
		var r: CrashReport = _report(dims.x, dims.y)
		ui.call("show_report", r)
		await _frames(2)
		var n: int = r.seats.size()
		if dims.x == 100:
			n = 403
		if r.seats.size() != n:
			_fail = "built %d seats, want %d" % [r.seats.size(), n]
			_finish()
			return
	_finish()
