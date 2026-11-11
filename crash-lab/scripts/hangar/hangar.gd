class_name Hangar
extends Node3D
## Showroom: a turntable with the selected aircraft, an orbit camera and the
## select/launch UI. Aircraft definitions and their meshes load in the
## background, so flicking through the fleet never stalls the frame.

const UI_SCENE_PATH := "res://scenes/ui/hangar_ui.tscn"
const TURN_RATE := 0.22

var ui: HangarUi
var _game: GameState
var _index: int = 0
var _turntable: Node3D
var _model: Node3D
var _camera: Camera3D
var _def: AircraftDef

var _yaw: float = 2.5
var _pitch: float = 0.22
var _zoom: float = 1.0
var _span: float = 34.0
var _focus_y: float = 3.0
var _drag_cooldown: float = 0.0
var _cutaway: float = 0.0
var _cutaway_target: float = 0.0
var _cabin_nodes: Array[Node3D] = []

# Background loading state.
var _loading_path: String = ""
var _mesh_task: int = -1
var _loaded_def: AircraftDef
var _autolaunch: bool = false


func _ready() -> void:
	_game = GameState.instance()
	_autolaunch = OS.has_environment("CRASHLAB_AUTOLAUNCH")
	_build_room()
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	add_child(_turntable)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 50.0
	_camera.near = 0.3
	_camera.far = 600.0
	add_child(_camera)
	_camera.make_current()

	var layer := CanvasLayer.new()
	layer.name = "UiLayer"
	add_child(layer)
	ui = (load(UI_SCENE_PATH) as PackedScene).instantiate() as HangarUi
	layer.add_child(ui)
	ui.previous_requested.connect(_step.bind(-1))
	ui.next_requested.connect(_step.bind(1))
	ui.launch_requested.connect(_launch)
	ui.cutaway_toggled.connect(_on_cutaway_toggled)
	ui.start_mode_changed.connect(_on_start_mode_changed)
	ui.orbit_drag.connect(_on_orbit_drag)
	ui.orbit_zoom.connect(_on_orbit_zoom)
	ui.set_start_mode(_game.start_mode)

	_index = maxi(_game.aircraft_ids.find(_game.selected_id), 0)
	_request(_index)
	print("Hangar ready: %d aircraft" % _game.aircraft_ids.size())


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"cutaway_amount", 0.0)


func _build_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	key.light_energy = 0.85
	key.shadow_enabled = SettingsStore.instance().graphics_quality >= 1
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 160.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	fill.light_energy = 0.22
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

	var shader := load("res://shaders/hangar_wall.gdshader") as Shader
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = shader
	floor_mat.set_shader_parameter(&"is_floor", 1.0)
	floor_mat.set_shader_parameter(&"size_m", Vector2(240.0, 240.0))
	floor_mat.set_shader_parameter(&"base_color", Color(0.2, 0.21, 0.23))
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(240.0, 240.0)
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Floor"
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = floor_mat
	add_child(floor_mi)

	# Four walls; the camera always stays inside them.
	for i: int in 4:
		var wall_mat := ShaderMaterial.new()
		wall_mat.shader = shader
		wall_mat.set_shader_parameter(&"size_m", Vector2(240.0, 46.0))
		var wall_mesh := QuadMesh.new()
		wall_mesh.size = Vector2(240.0, 46.0)
		var wall := MeshInstance3D.new()
		wall.name = "Wall%d" % i
		wall.mesh = wall_mesh
		wall.material_override = wall_mat
		var angle := float(i) * PI * 0.5
		wall.transform = Transform3D(Basis(Vector3.UP, angle),
				Vector3(sin(angle) * -120.0, 23.0, cos(angle) * -120.0))
		add_child(wall)


func _step(direction: int) -> void:
	var count := _game.aircraft_ids.size()
	if count == 0:
		return
	_index = posmod(_index + direction, count)
	_request(_index)


func _request(index: int) -> void:
	if _game.aircraft_ids.is_empty():
		return
	_game.selected_id = _game.aircraft_ids[index]
	_loading_path = _game.aircraft_path()
	_mesh_task = -1
	_loaded_def = null
	ui.set_loading(true)
	ResourceLoader.load_threaded_request(_loading_path)


func _poll_loading() -> void:
	if _loading_path == "":
		return
	if _loaded_def == null:
		var status := ResourceLoader.load_threaded_get_status(_loading_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_error("Failed to load %s" % _loading_path)
			_loading_path = ""
			ui.set_loading(false)
			return
		_loaded_def = ResourceLoader.load_threaded_get(_loading_path) as AircraftDef
		_mesh_task = WorkerThreadPool.add_task(AirframeBuilder.prebuild_meshes.bind(_loaded_def))
		return
	if not WorkerThreadPool.is_task_completed(_mesh_task):
		return
	WorkerThreadPool.wait_for_task_completion(_mesh_task)
	_loading_path = ""
	_show(_loaded_def)


func _show(def: AircraftDef) -> void:
	_def = def
	if _model != null:
		_model.queue_free()
	_model = AirframeBuilder.build_display_model(def)
	_model.position.y = def.ground_clearance
	_turntable.add_child(_model)
	_cabin_nodes = Cabin.build_display(def, _model, 12)
	_set_cabin_visible(_cutaway > 0.0 or _cutaway_target > 0.0)
	_model.scale = Vector3.ONE * 0.85
	create_tween().tween_property(_model, ^"scale", Vector3.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Frame the larger of span and length so slender aircraft still fit.
	var z_min := 0.0
	var z_max := 0.0
	for part: PartDef in def.parts:
		z_min = minf(z_min, minf(part.p0.z, part.p1.z))
		z_max = maxf(z_max, maxf(part.p0.z, part.p1.z))
	_span = maxf(def.wing_span, z_max - z_min)
	_focus_y = def.ground_clearance * 0.9
	ui.show_aircraft(def, _index, _game.aircraft_ids.size())
	ui.set_loading(false)
	if _autolaunch:
		_autolaunch = false
		_launch.call_deferred()


func _launch() -> void:
	if _def == null:
		return
	_game.goto_flight()


func _on_cutaway_toggled(enabled: bool) -> void:
	_cutaway_target = 1.0 if enabled else 0.0
	if enabled:
		_set_cabin_visible(true)


func _set_cabin_visible(enabled: bool) -> void:
	for node: Node3D in _cabin_nodes:
		if is_instance_valid(node):
			node.visible = enabled


func _on_start_mode_changed(mode: int) -> void:
	_game.start_mode = mode as GameState.StartMode


func _on_orbit_drag(relative: Vector2) -> void:
	_yaw -= relative.x * 0.006
	_pitch = clampf(_pitch + relative.y * 0.004, 0.03, 1.2)
	_drag_cooldown = 2.5


func _on_orbit_zoom(factor: float) -> void:
	_zoom = clampf(_zoom / maxf(factor, 0.01), 0.45, 1.8)


func _process(delta: float) -> void:
	_poll_loading()
	# The turntable pauses while the player is orbiting by hand.
	_drag_cooldown = maxf(_drag_cooldown - delta, 0.0)
	if _drag_cooldown <= 0.0:
		_turntable.rotation.y += TURN_RATE * delta
	if _cutaway != _cutaway_target:
		_cutaway = move_toward(_cutaway, _cutaway_target, delta * 1.6)
		RenderingServer.global_shader_parameter_set(&"cutaway_amount", _cutaway)
		if _cutaway == 0.0:
			_set_cabin_visible(false)
	var dist := clampf(_span * 1.45 * _zoom, 8.0, 105.0)
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	var focus := Vector3(0.0, _focus_y, 0.0)
	_camera.global_position = focus + dir * dist
	_camera.look_at(focus, Vector3.UP)
