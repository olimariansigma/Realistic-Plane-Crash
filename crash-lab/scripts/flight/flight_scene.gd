class_name FlightScene
extends Node3D
## The playable scene: world, one aircraft, cameras and the HUD.

const HUD_SCENE_PATH := "res://scenes/ui/flight_hud.tscn"

var world: World
var aircraft: Aircraft
var camera_rig: CameraRig
var hud: FlightHud
var def: AircraftDef

var _game: GameState
var _settings: SettingsStore


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
	_spawn(_game.start_mode)
	aircraft.auto_trim = _settings.auto_trim

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
	hud.show_message("%s  -  %s" % [def.display_name, GameState.START_MODE_NAMES[_game.start_mode]], 3.0)
	print("Flight ready: %s, %d parts, %d surfaces" % [def.id, aircraft.parts.size(), aircraft.surfaces.size()])


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"cutaway_amount", 0.0)


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


func _process(_delta: float) -> void:
	camera_rig.target_velocity = aircraft.root_part.lin_vel


func _on_camera_cycle() -> void:
	camera_rig.cycle_mode()
	hud.set_camera_mode_name(camera_rig.mode_name())


func _on_cutaway_toggled(enabled: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"cutaway_amount", 1.0 if enabled else 0.0)


func _on_settings_changed() -> void:
	aircraft.auto_trim = _settings.auto_trim
	world.apply_quality(_settings.graphics_quality)


func _on_restart() -> void:
	_game.goto_flight()


func _on_hangar() -> void:
	_game.goto_hangar()
