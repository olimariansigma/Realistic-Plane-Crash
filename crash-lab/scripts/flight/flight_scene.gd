class_name FlightScene
extends Node3D
## The playable scene: world, one aircraft, cameras and the HUD.

const HUD_SCENE_PATH := "res://scenes/ui/flight_hud.tscn"
const REPORT_SCENE_PATH := "res://scenes/ui/crash_report.tscn"
## Seconds the recorder keeps running after the wreck is declared at rest.
const RECORD_TAIL := 4.0

var world: World
var aircraft: Aircraft
var camera_rig: CameraRig
var hud: FlightHud
var director: CrashDirector
var recorder: CrashRecorder
var report_screen: CrashReportScreen
var report: CrashReport
var def: AircraftDef

var _game: GameState
var _settings: SettingsStore
var _cutaway: float = 0.0
var _cutaway_target: float = 0.0
var _wreck_view: bool = false


func _ready() -> void:
	_game = GameState.instance()
	_settings = SettingsStore.instance()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.apply_quality(_settings.graphics_quality)

	def = _game.load_selected()
	aircraft = Aircraft.new()
	aircraft.name = "Aircraft"
	add_child(aircraft)
	aircraft.max_freds = _settings.max_freds()
	aircraft.auto_trim = _settings.auto_trim
	_spawn(_game.start_mode)

	director = CrashDirector.new()
	director.name = "CrashDirector"
	add_child(director)
	director.setup(aircraft, _settings.graphics_quality, _settings.max_debris())
	director.crash_started.connect(_on_crash_started)
	director.crash_settled.connect(_on_crash_settled)
	director.crash_cancelled.connect(_on_crash_cancelled)

	recorder = CrashRecorder.new()
	recorder.name = "CrashRecorder"
	add_child(recorder)
	recorder.setup(aircraft, director)
	# Records all flight; only the last CrashRecorder.WINDOW_SECONDS are kept.
	recorder.start_recording()

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.follow(aircraft.root_part, def.wing_span, _eye_point())

	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as FlightHud
	layer.add_child(hud)
	hud.bind(aircraft.controls, aircraft.telemetry, def)
	hud.set_camera_mode_name(camera_rig.mode_name())
	hud.camera_cycle_requested.connect(_on_camera_cycle)
	hud.camera_drag.connect(camera_rig.drag)
	hud.camera_zoom.connect(camera_rig.zoom)
	hud.cutaway_toggled.connect(_on_cutaway_toggled)
	hud.restart_requested.connect(_on_restart)
	hud.hangar_requested.connect(_on_hangar)
	_settings.changed.connect(_on_settings_changed)

	report_screen = (load(REPORT_SCENE_PATH) as PackedScene).instantiate() as CrashReportScreen
	report_screen.visible = false
	layer.add_child(report_screen)
	report_screen.replay_requested.connect(_on_replay_requested)
	report_screen.replay_speed_changed.connect(_on_replay_speed)
	report_screen.replay_seek.connect(recorder.seek)
	report_screen.replay_closed.connect(_on_replay_closed)
	report_screen.restart_requested.connect(_on_restart)
	report_screen.hangar_requested.connect(_on_hangar)
	recorder.playback_progress.connect(report_screen.set_replay_progress)
	hud.show_message("%s  -  %s" % [def.display_name, GameState.START_MODE_NAMES[_game.start_mode]], 3.0)
	print("Flight ready: %s, %d parts, %d surfaces" % [def.id, aircraft.parts.size(), aircraft.surfaces.size()])


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"cutaway_amount", 0.0)
	AirframeBuilder.set_cutaway_shader(false)
	PhysicsServer3D.set_active(true)


func _notification(what: int) -> void:
	# Leaving the app mid-flight pauses it, so the player comes back to the
	# pause menu instead of a crash that happened while they were away.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if hud != null and not report_screen.visible and not get_tree().paused:
			hud.pause()


func _spawn(mode: GameState.StartMode) -> void:
	var start := World.RUNWAY_START
	match mode:
		GameState.StartMode.AIRBORNE:
			aircraft.global_transform = Transform3D(Basis.IDENTITY, start + Vector3(0.0, 900.0, 2600.0))
			aircraft.setup(def)
			aircraft.set_initial_velocity(Vector3(0.0, 0.0, -def.v_cruise))
			aircraft.configure_airborne(def.cruise_throttle)
		GameState.StartMode.APPROACH:
			# Three-degree glide path to the threshold, landing configuration.
			var dist := 3800.0
			var speed := def.v_rotate * 1.08
			var basis := Basis(Vector3.RIGHT, deg_to_rad(2.0))
			aircraft.global_transform = Transform3D(basis,
					start + Vector3(0.0, dist * tan(deg_to_rad(3.0)) + def.ground_clearance, dist))
			aircraft.setup(def)
			aircraft.set_initial_velocity(Vector3(0.0, -speed * sin(deg_to_rad(3.0)),
					-speed * cos(deg_to_rad(3.0))))
			aircraft.configure_airborne(0.42, true, def.flap_steps_deg.size() - 1)
		_:
			aircraft.global_transform = Transform3D(Basis.IDENTITY,
					start + Vector3(0.0, def.ground_clearance, 0.0))
			aircraft.setup(def)


## Pilot's eye in the root part's frame: the captain's seat plus sitting height.
func _eye_point() -> Vector3:
	var root_com := def.parts[0].com
	for block: SeatBlockDef in def.seat_blocks:
		if block.is_crew and block.abreast.size() > 0:
			return Vector3(block.abreast[0], block.floor_y + 1.15, block.z_start - 0.25) - root_com
	return Vector3(0.0, 1.0, -def.wing_span * 0.3)


func _process(delta: float) -> void:
	camera_rig.target_velocity = aircraft.root_part.lin_vel
	if _cutaway != _cutaway_target:
		_cutaway = move_toward(_cutaway, _cutaway_target, delta * 1.6)
		RenderingServer.global_shader_parameter_set(&"cutaway_amount", _cutaway)
		AirframeBuilder.set_cutaway_shader(_cutaway > 0.0)
		if _cutaway == 0.0:
			aircraft.cabin.set_visible(false)


func _on_crash_started() -> void:
	hud.show_message("IMPACT", 2.0)


func _on_crash_cancelled() -> void:
	hud.show_message("DAMAGED - STILL FLYING", 2.5)


func _on_crash_settled() -> void:
	recorder.stop_recording_after(RECORD_TAIL)
	report = InjuryModel.build_report(aircraft, director)
	_game.last_report = report
	hud.show_message("WRECK AT REST", 1.5)
	# A callback, not an await: if the player leaves in the meantime the
	# connection dies with this node.
	get_tree().create_timer(1.5, false).timeout.connect(_show_report, CONNECT_ONE_SHOT)


func _show_report() -> void:
	hud.set_controls_visible(false)
	report_screen.show_report(report)
	report_screen.visible = true


func _on_replay_requested() -> void:
	report_screen.show_replay_controls(true)
	camera_rig.set_mode(CameraRig.Mode.ORBIT)
	recorder.play()


func _on_replay_speed(speed: float) -> void:
	recorder.speed = speed


func _on_replay_closed() -> void:
	recorder.stop()
	report_screen.show_replay_controls(false)


func _physics_process(_delta: float) -> void:
	# Chase and cockpit views are useless on a tumbling or stationary wreck, but
	# a scrape the aircraft flies away from should not take the view away.
	if director.crash_active and not _wreck_view and camera_rig.mode != CameraRig.Mode.FLYBY \
			and (aircraft.telemetry.integrity < 0.9 or aircraft.root_part.lin_vel.length() < 25.0):
		_wreck_view = true
		camera_rig.set_mode(CameraRig.Mode.ORBIT)
		hud.set_camera_mode_name(camera_rig.mode_name())


func _on_camera_cycle() -> void:
	camera_rig.cycle_mode()
	hud.set_camera_mode_name(camera_rig.mode_name())


func _on_cutaway_toggled(enabled: bool) -> void:
	_cutaway_target = 1.0 if enabled else 0.0
	if enabled:
		aircraft.cabin.set_visible(true)


func _on_settings_changed() -> void:
	aircraft.auto_trim = _settings.auto_trim
	world.apply_quality(_settings.graphics_quality)


func _on_restart() -> void:
	_game.goto_flight()


func _on_hangar() -> void:
	_game.goto_hangar()
