class_name Autoplay
extends Node
## Scripted play-through for tools/playtest.sh. It plays the real game the way
## a player does - synthetic screen touches on the real widgets, from the
## hangar through a take-off, a crash, the REPORT button, its replay, a restart
## and back to the hangar - and fails loudly at the first step that does not
## respond. Only created when CRASHLAB_AUTOPLAY is set.
##
## CRASHLAB_AUTOPLAY       number of times to tap NEXT in the hangar first
## CRASHLAB_AUTOPLAY_SHOTS directory for a screenshot of each stage (optional)

var _shots: String = ""
var _failed: bool = false
var _patience: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shots = OS.get_environment("CRASHLAB_AUTOPLAY_SHOTS")
	# A software renderer runs the game several times slower than real time.
	if DisplayServer.get_name() != "headless":
		_patience = 6.0
	_run.call_deferred()


func _run() -> void:
	var game := GameState.instance()
	var hangar := await _scene_of(&"Hangar") as Hangar
	if hangar == null:
		return
	if not await _until(func() -> bool: return hangar._def != null and hangar._pending_def == null, 30.0,
			"the hangar never finished loading its first aircraft"):
		return
	var steps := maxi(int(OS.get_environment("CRASHLAB_AUTOPLAY")), 0) % maxi(game.aircraft_ids.size(), 1)
	var wanted := game.aircraft_ids[(maxi(game.aircraft_ids.find(game.selected_id), 0) + steps) % game.aircraft_ids.size()]
	for i: int in steps:
		await _tap(hangar.ui.get_node(^"%NextButton") as Control)
	if not await _until(func() -> bool: return hangar._pending_def == null and hangar._def != null \
			and String(hangar._def.id) == wanted, 60.0, "NEXT did not bring up %s" % wanted):
		return
	await _wait(0.5)
	_shot("1_hangar")
	await _tap(hangar.ui.get_node(^"%LaunchButton") as Control)

	var flight := await _scene_of(&"FlightScene") as FlightScene
	if flight == null:
		return
	if String(flight.def.id) != wanted:
		_fail("launched %s, expected %s" % [flight.def.id, wanted])
		return
	var tel := flight.aircraft.telemetry
	var controls := flight.aircraft.controls
	await _wait(1.0)
	_shot("2_runway")

	# Throttle to the stop with finger 0, then let go: it must stay there.
	var throttle := flight.hud.get_node(^"%ThrottleSlider") as Control
	var rect := throttle.get_global_rect()
	_touch(0, rect.get_center(), true)
	await _frames(2)
	_drag(0, Vector2(rect.get_center().x, rect.position.y + 4.0))
	await _frames(2)
	_touch(0, Vector2(rect.get_center().x, rect.position.y + 4.0), false)
	await _frames(4)
	if controls.throttle < 0.95:
		_fail("throttle slider touch did not reach the controls (throttle %.2f)" % controls.throttle)
		return
	if not await _until(func() -> bool: return tel.ias > flight.def.v_rotate, 150.0,
			"the aircraft did not accelerate to rotation speed (ias %.1f m/s)" % tel.ias):
		return
	_shot("3_takeoff_roll")

	# Pull back with finger 1 until it climbs.
	var stick := flight.hud.get_node(^"%Stick") as Control
	var centre := stick.get_global_rect().get_center()
	var radius := minf(stick.size.x, stick.size.y) * 0.4
	_touch(1, centre, true)
	await _frames(2)
	_drag(1, centre + Vector2(0.0, radius * 0.6))
	await _wait(0.5)
	if controls.pitch <= 0.05:
		_fail("pulling the stick back did not command nose-up (pitch %.2f)" % controls.pitch)
		return
	if not await _until(func() -> bool: return tel.altitude_agl > 50.0, 80.0, "the aircraft did not lift off"):
		return
	_shot("4_climb")

	# Roll over and push: into the ground.
	_drag(1, centre + Vector2(radius * 0.9, -radius * 0.9))
	if not await _until(func() -> bool: return flight.director.settled, 240.0,
			"the wreck never came to rest after flying into the ground"):
		return
	_touch(1, centre, false)
	await _wait(0.5)
	# The report only opens on the REPORT button.
	if flight.report_screen.visible:
		_fail("the report opened by itself; it should wait for the REPORT button")
		return
	var report_button := flight.hud.get_node(^"%ReportButton") as Control
	await _tap(report_button)
	if not await _until(func() -> bool: return flight.report_screen.visible, 5.0,
			"tapping REPORT did not open the crash report"):
		return
	# CLOSE goes back to the wreck; REPORT opens it again.
	await _tap(flight.report_screen.find_child("CloseButton", true, false) as Control)
	await _wait(0.3)
	if flight.report_screen.visible or not report_button.is_visible_in_tree():
		_fail("CLOSE did not return to the flight view")
		return
	await _tap(report_button)
	if not await _until(func() -> bool: return flight.report_screen.visible, 5.0,
			"REPORT did not reopen the crash report"):
		return
	await _wait(0.5)
	_shot("5_report")
	if flight.report == null or flight.report.seats.is_empty():
		_fail("the crash report has no seats in it")
		return

	# The first flight scene is freed by the restart: keep what is reported later.
	var part_count := flight.def.parts.size()
	var seat_count := flight.report.seats.size()
	var wreck_at := flight.aircraft.root_part.global_position
	await _tap(flight.report_screen.find_child("ReplayButton", true, false) as Control)
	await _wait(1.0)
	if not flight.recorder.playing:
		_fail("REPLAY did not start playback")
		return
	_shot("6_replay_start")
	var replay_from := flight.aircraft.root_part.global_position
	var seconds := flight.recorder.duration()
	if seconds < 3.0 or replay_from.distance_to(wreck_at) < 15.0:
		_fail("the replay does not cover the crash (%.1f s, starts %.0f m from the wreck)"
				% [seconds, replay_from.distance_to(wreck_at)])
		return
	flight.recorder.seek(0.45)
	await _wait(0.6)
	_shot("7_replay_mid")
	await _tap(flight.report_screen.find_child("ReportButton", true, false) as Control)
	await _wait(0.4)
	# The wreck may still have been creeping when its position was noted.
	if flight.aircraft.root_part.global_position.distance_to(wreck_at) > 8.0:
		_fail("closing the replay did not put the wreck back")
		return

	await _tap(flight.report_screen.find_child("RestartButton", true, false) as Control)
	var first_id := flight.get_instance_id()
	var second := await _scene_of(&"FlightScene", first_id) as FlightScene
	if second == null:
		return
	await _wait(1.0)
	if second.aircraft.telemetry.integrity < 1.0 or second.aircraft.parts.size() != part_count:
		_fail("the restarted flight did not start with an intact aircraft")
		return
	# The replay switches physics off; the next flight must be live again.
	(second.hud.get_node(^"%ThrottleSlider") as TouchSlider).value = 1.0
	await _wait(3.0)
	if second.aircraft.telemetry.ias < 2.0:
		_fail("after a replay and RESTART the new aircraft is frozen (ias %.1f m/s)" % second.aircraft.telemetry.ias)
		return
	await _tap(second.hud.get_node(^"%PauseButton") as Control)
	await _wait(0.4)
	_shot("8_pause")
	await _tap(second.hud.get_node(^"%HangarButton") as Control)
	var back := await _scene_of(&"Hangar") as Hangar
	if back == null:
		return
	if not await _until(func() -> bool: return back._def != null and back._pending_def == null, 30.0,
			"the hangar did not reload after a flight"):
		return
	print("AUTOPLAY PASS: %s | hangar, launch, take-off, crash, report (%d seats), replay %.1f s, restart, hangar"
			% [wanted, seat_count, seconds])
	get_tree().quit(0)


# ------------------------------------------------------------------ helpers

func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_shot("fail")
	print("AUTOPLAY FAIL: " + message)
	get_tree().quit(1)


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## Polls `test` until it is true; fails the run with `message` after `timeout`.
func _until(test: Callable, timeout: float, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0 * _patience)
	while not test.call():
		if _failed:
			return false
		if Time.get_ticks_msec() > deadline:
			_fail(message)
			return false
		await get_tree().process_frame
	return true


## Waits for the current scene to be a `type` other than the instance
## `previous_id` (which may have been freed by then).
func _scene_of(type: StringName, previous_id: int = 0) -> Node:
	var deadline := Time.get_ticks_msec() + int(90000.0 * _patience)
	while true:
		var scene := get_tree().current_scene
		if scene != null and scene.get_instance_id() != previous_id and scene.is_node_ready() \
				and (scene.get_script() as Script).get_global_name() == type:
			# Let the loading overlay clear before touching anything.
			await _wait(0.5)
			return scene
		if Time.get_ticks_msec() > deadline:
			_fail("the %s scene never appeared" % type)
			return null
		await get_tree().process_frame
	return null


## Canvas position to the window position a real touch would arrive with.
func _to_window(canvas_pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * canvas_pos


func _touch(index: int, canvas_pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = _to_window(canvas_pos)
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(index: int, canvas_pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = _to_window(canvas_pos)
	Input.parse_input_event(event)


func _tap(control: Control) -> void:
	if control == null or not control.is_visible_in_tree():
		_fail("a button the player needs is missing or hidden (%s)" % (control.name if control != null else &"null"))
		return
	var at := control.get_global_rect().get_center()
	_touch(5, at, true)
	await _frames(3)
	_touch(5, at, false)
	await _frames(3)


func _shot(label: String) -> void:
	print("AUTOPLAY stage: " + label)
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(_shots.path_join(label + ".png"))
