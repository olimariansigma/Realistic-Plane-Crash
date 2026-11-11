class_name GameState
extends Node
## Session state and scene flow (autoload "Game"). Scripts reach it through
## GameState.instance() for the same reason as SettingsStore: autoload globals
## are not visible to --check-only.
##
## Scene changes are asynchronous: the next scene and the selected aircraft
## load on the resource loader's threads and the aircraft's meshes are
## generated on a worker thread, all behind a loading overlay.

enum StartMode { RUNWAY, AIRBORNE, APPROACH }

const AIRCRAFT_DIR := "res://data/aircraft/"
const FLIGHT_SCENE := "res://scenes/flight/flight.tscn"
const HANGAR_SCENE := "res://scenes/hangar/hangar.tscn"
const START_MODE_NAMES: Array[String] = ["Runway", "In flight", "Final approach"]

static var _instance: GameState

## Aircraft ids found in AIRCRAFT_DIR, sorted. Adding a .tres adds a plane.
var aircraft_ids: PackedStringArray
var selected_id: String = ""
var start_mode: StartMode = StartMode.RUNWAY
## Result of the most recent crash, for the report screen.
var last_report: RefCounted

## Script classes referenced by the resources that load on background threads.
## Holding them here compiles them once on the main thread at startup; left to
## the loader threads, two resources that share a script race to compile it
## and one of the loads fails.
var _warm_scripts: Array[Script] = [
	AircraftDef, PartDef, SurfaceDef, AirfoilDef, EngineDef, GearDef, SeatBlockDef,
]

var _pending_scene: String = ""
var _pending_def: String = ""
var _mesh_task: int = -1
var _scene_requested: bool = false
var _overlay: CanvasLayer
var _bar: ProgressBar
var _label: Label
var _progress: Array = []


static func instance() -> GameState:
	if _instance == null or not is_instance_valid(_instance):
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			_instance = tree.root.get_node_or_null(^"Game") as GameState
		if _instance == null:
			_instance = GameState.new()
			_instance._scan_aircraft()
	return _instance


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_instance = self
	_scan_aircraft()
	_build_overlay()
	set_process(false)
	var settings := SettingsStore.instance()
	settings.changed.connect(apply_quality)
	apply_quality()


## Applies the graphics quality tier to everything that is not scene-specific:
## mesh detail for the next aircraft build, and the 3D render scale.
func apply_quality() -> void:
	var quality := SettingsStore.instance().graphics_quality
	AirframeBuilder.detail = quality
	get_viewport().scaling_3d_scale = [0.7, 0.85, 1.0][clampi(quality, 0, 2)]


func _scan_aircraft() -> void:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(AIRCRAFT_DIR):
		# Exported builds list "name.tres.remap".
		var clean := file.trim_suffix(".remap")
		if clean.ends_with(".tres") or clean.ends_with(".res"):
			found.append(clean.get_basename())
	found.sort()
	aircraft_ids = PackedStringArray(found)
	if selected_id == "" and not found.is_empty():
		selected_id = "meridian_220" if found.has("meridian_220") else found[0]


func aircraft_path(id: String = "") -> String:
	return AIRCRAFT_DIR + (selected_id if id == "" else id) + ".tres"


func load_selected() -> AircraftDef:
	return load(aircraft_path()) as AircraftDef


## Loads `scene_path` (and, for the flight scene, the selected aircraft) in
## the background, then switches to it. The two loads run one after the other:
## both compile GDScript classes the other depends on, and Godot 4.4 fails
## such loads intermittently when they race on separate loader threads.
func change_scene_async(scene_path: String) -> void:
	if _pending_scene != "":
		return
	get_tree().paused = false
	_pending_scene = scene_path
	_pending_def = aircraft_path() if scene_path == FLIGHT_SCENE else ""
	_mesh_task = -1
	_scene_requested = false
	_label.text = "LOADING"
	_bar.value = 0.0
	_overlay.visible = true
	if _pending_def != "":
		ResourceLoader.load_threaded_request(_pending_def)
	else:
		ResourceLoader.load_threaded_request(scene_path)
		_scene_requested = true
	set_process(true)


func goto_flight() -> void:
	change_scene_async(FLIGHT_SCENE)


func goto_hangar() -> void:
	change_scene_async(HANGAR_SCENE)


func _process(_delta: float) -> void:
	if _pending_scene == "":
		return
	if not _scene_requested:
		# Stage 1: the aircraft definition, then its meshes on a worker thread.
		var def_status := ResourceLoader.load_threaded_get_status(_pending_def, _progress)
		_bar.value = (_progress[0] as float) * 30.0 if _progress.size() > 0 else 0.0
		if def_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if def_status == ResourceLoader.THREAD_LOAD_LOADED:
			var def := ResourceLoader.load_threaded_get(_pending_def) as AircraftDef
			_mesh_task = WorkerThreadPool.add_task(AirframeBuilder.prebuild_meshes.bind(def))
		else:
			push_error("Failed to load %s" % _pending_def)
		ResourceLoader.load_threaded_request(_pending_scene)
		_scene_requested = true
		return
	# Stage 2: the scene itself, while the mesh task finishes.
	var status := ResourceLoader.load_threaded_get_status(_pending_scene, _progress)
	var fraction: float = _progress[0] if _progress.size() > 0 else 0.0
	_bar.value = 30.0 + fraction * 50.0 if _pending_def != "" else fraction * 100.0
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("Failed to load %s" % _pending_scene)
		_finish_loading()
		return
	if _mesh_task != -1:
		if not WorkerThreadPool.is_task_completed(_mesh_task):
			return
		WorkerThreadPool.wait_for_task_completion(_mesh_task)
	_bar.value = 100.0
	var packed := ResourceLoader.load_threaded_get(_pending_scene) as PackedScene
	get_tree().change_scene_to_packed(packed)
	_finish_loading()


func _finish_loading() -> void:
	_pending_scene = ""
	_pending_def = ""
	_mesh_task = -1
	set_process(false)
	# Leave the overlay up for two frames so the new scene's first heavy frame
	# is hidden behind it.
	await get_tree().process_frame
	await get_tree().process_frame
	_overlay.visible = false


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "LoadingOverlay"
	_overlay.layer = 100
	_overlay.visible = false
	add_child(_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.086, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420.0, 0.0)
	box.position = Vector2(-210.0, -40.0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 28)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420.0, 14.0)
	_bar.show_percentage = false
	box.add_child(_bar)
