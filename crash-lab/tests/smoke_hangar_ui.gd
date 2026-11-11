extends SceneTree
## Headless hangar UI check: labels, stats, buttons, loading state, start mode.
## Untyped UI reference on purpose: this script compiles before autoloads exist.

var _fail: String = ""
var _next: int = 0
var _launch: int = 0
var _modes: Array[int] = []
var _drags: int = 0
var _zooms: Array[float] = []


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _finish() -> void:
	if _fail.is_empty():
		print("SMOKE PASS: hangar labels, stats, next/launch, loading, start mode, orbit input")
		quit(0)
	else:
		print("SMOKE FAIL: " + _fail)
		quit(1)


func _event(e: InputEvent) -> void:
	Input.parse_input_event(e)
	await process_frame


func _run() -> void:
	# Headless resets the window size on the first frame, so set it again after.
	root.size = Vector2i(1280, 720)
	await _frames(1)
	root.size = Vector2i(1280, 720)
	await _frames(2)
	var ui := (load("res://scenes/ui/hangar_ui.tscn") as PackedScene).instantiate() as Control
	root.add_child(ui)
	await _frames(1)
	var def := load("res://data/aircraft/meridian_220.tres") as AircraftDef
	if def == null:
		_fail = "meridian_220.tres missing"
		_finish()
		return
	ui.call("show_aircraft", def, 0, 3)
	await _frames(2)

	var name_label := ui.get_node("%NameLabel") as Label
	var mass := ui.get_node("%StatValue0") as Label
	var seats := ui.get_node("%StatValue7") as Label
	if name_label.text != def.display_name:
		_fail = "name '%s' != '%s'" % [name_label.text, def.display_name]
		_finish()
		return
	var want_mass: String = "%.1f t" % (def.total_mass() / 1000.0)
	if mass.text != want_mass:
		_fail = "mass '%s' != '%s'" % [mass.text, want_mass]
		_finish()
		return
	if seats.text != str(def.seat_count()):
		_fail = "seats '%s' != '%d'" % [seats.text, def.seat_count()]
		_finish()
		return
	# Degenerate def must not crash.
	ui.call("show_aircraft", AircraftDef.new(), 0, 1)
	ui.call("show_aircraft", def, 0, 3)

	ui.connect("next_requested", func() -> void: _next += 1)
	ui.connect("launch_requested", func() -> void: _launch += 1)
	ui.connect("start_mode_changed", func(m: int) -> void: _modes.append(m))
	ui.connect("orbit_drag", func(_r: Vector2) -> void: _drags += 1)
	ui.connect("orbit_zoom", func(f: float) -> void: _zooms.append(f))
	var next_button := ui.get_node("%NextButton") as Button
	var launch := ui.get_node("%LaunchButton") as Button
	next_button.pressed.emit()
	if _next != 1:
		_fail = "next_requested not emitted"
		_finish()
		return
	launch.pressed.emit()
	if _launch != 1:
		_fail = "launch_requested not emitted"
		_finish()
		return
	ui.call("set_loading", true)
	if not launch.disabled:
		_fail = "LAUNCH not disabled while loading"
		_finish()
		return
	ui.call("set_loading", false)
	if launch.disabled:
		_fail = "LAUNCH not re-enabled"
		_finish()
		return
	var mode1 := ui.get_node("%StartMode1") as Button
	mode1.pressed.emit()
	if _modes != [1]:
		_fail = "start_mode_changed(1) not emitted: %s" % str(_modes)
		_finish()
		return
	ui.call("set_start_mode", 2)
	if _modes.size() != 1:
		_fail = "set_start_mode emitted"
		_finish()
		return
	if not (ui.get_node("%StartMode2") as Button).button_pressed:
		_fail = "set_start_mode did not select"
		_finish()
		return

	# Orbit: single-finger drag on free centre area, then pinch, then wheel.
	var c := Vector2(640.0, 300.0)
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = c
	t.pressed = true
	await _event(t)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = c + Vector2(10.0, 0.0)
	d.relative = Vector2(10.0, 0.0)
	await _event(d)
	if _drags != 1:
		_fail = "orbit_drag count %d != 1" % _drags
		_finish()
		return
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.position = c + Vector2(100.0, 0.0)
	t2.pressed = true
	await _event(t2)
	var d2 := InputEventScreenDrag.new()
	d2.index = 1
	d2.position = c + Vector2(200.0, 0.0)
	d2.relative = Vector2(100.0, 0.0)
	await _event(d2)
	if _zooms.size() != 1 or _zooms[0] <= 1.0:
		_fail = "pinch zoom wrong: %s" % str(_zooms)
		_finish()
		return
	t.pressed = false
	await _event(t)
	t2.pressed = false
	await _event(t2)
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	w.position = c
	await _event(w)
	if _zooms.size() != 2 or not is_equal_approx(_zooms[1], 1.1):
		_fail = "wheel zoom wrong: %s" % str(_zooms)
		_finish()
		return
	_finish()
