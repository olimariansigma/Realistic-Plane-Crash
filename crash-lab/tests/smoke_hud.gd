extends SceneTree
## Headless HUD check: multi-touch stick + throttle + flap button, then release.
## Untyped HUD reference on purpose: this script compiles before autoloads exist.

var _fail: String = ""


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)
	await process_frame


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)
	await process_frame


func _finish() -> void:
	if _fail.is_empty():
		print("SMOKE PASS: stick roll/pitch, throttle while stick held, flap tap, release decay")
		quit(0)
	else:
		print("SMOKE FAIL: " + _fail)
		quit(1)


func _run() -> void:
	# Headless resets the window size on the first frame, so set it again after.
	root.size = Vector2i(1280, 720)
	await _frames(1)
	root.size = Vector2i(1280, 720)
	await _frames(2)
	var hud := (load("res://scenes/ui/flight_hud.tscn") as PackedScene).instantiate() as Control
	root.add_child(hud)
	# Root is not ready inside _initialize; let _ready run before bind().
	await _frames(1)
	var controls := ControlState.new()
	var telemetry := FlightTelemetry.new()
	var def := AircraftDef.new()
	def.flap_steps_deg = PackedFloat32Array([0.0, 10.0, 20.0, 30.0])
	hud.call("bind", controls, telemetry, def)
	await _frames(2)

	var stick := hud.get_node("%Stick") as Control
	var throttle := hud.get_node("%ThrottleSlider") as Control
	var flap_up := hud.get_node("%FlapUpButton") as Control
	if stick == null or throttle == null or flap_up == null:
		_fail = "widgets missing"
		_finish()
		return
	var sc: Vector2 = stick.get_global_rect().get_center()

	# (a) finger 0: full right, then full down.
	await _touch(0, sc, true)
	await _drag(0, sc + Vector2(400.0, 0.0), Vector2(400.0, 0.0))
	await _frames(30)
	if controls.roll <= 0.8:
		_fail = "roll %.2f <= 0.8 after full right drag" % controls.roll
		_finish()
		return
	await _drag(0, sc + Vector2(0.0, 400.0), Vector2(-400.0, 400.0))
	await _frames(30)
	if controls.pitch <= 0.8:
		_fail = "pitch %.2f <= 0.8 after full down drag" % controls.pitch
		_finish()
		return

	# (b) finger 1 on the throttle while finger 0 is still held.
	var tr: Rect2 = throttle.get_global_rect()
	await _touch(1, tr.position + Vector2(tr.size.x * 0.5, 30.0), true)
	await _frames(30)
	if controls.throttle <= 0.8:
		_fail = "throttle %.2f <= 0.8" % controls.throttle
		_finish()
		return
	if not (stick.get("touch_index") == 0):
		_fail = "stick lost its finger when second finger landed"
		_finish()
		return

	# (c) finger 2 taps FLAP +.
	var fc: Vector2 = flap_up.get_global_rect().get_center()
	await _touch(2, fc, true)
	await _touch(2, fc, false)
	await _frames(2)
	if controls.flap_step != 1:
		_fail = "flap_step %d != 1" % controls.flap_step
		_finish()
		return

	# (d) release the stick finger: outputs decay.
	await _touch(0, sc + Vector2(0.0, 400.0), false)
	await _frames(60)
	if absf(controls.roll) >= 0.05 or absf(controls.pitch) >= 0.05:
		_fail = "no decay: roll %.3f pitch %.3f" % [controls.roll, controls.pitch]
		_finish()
		return
	_finish()
