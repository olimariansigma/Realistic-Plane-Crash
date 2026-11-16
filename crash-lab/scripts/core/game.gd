class_name GameState
extends Node
## Session state and scene flow (autoload "Game"). Scripts reach it through
## GameState.instance() for the same reason as SettingsStore: autoload globals
## are not visible to --check-only.
##
## Loading is deliberately single-threaded. Aircraft definitions are small and
## load synchronously (and stay cached); their meshes are generated a few
## milliseconds per frame behind the loading overlay. An earlier version used
## ResourceLoader threads and a WorkerThreadPool task: it worked on desktop
## and failed to load aircraft on phones, and its races were not reproducible
## enough to fix with confidence.

enum StartMode { RUNWAY, AIRBORNE, APPROACH }

const AIRCRAFT_DIR := "res://data/aircraft/"
const FLIGHT_SCENE := "res://scenes/flight/flight.tscn"
const HANGAR_SCENE := "res://scenes/hangar/hangar.tscn"
const START_MODE_NAMES: Array[String] = ["Runway", "In flight", "Final approach"]
## Mesh generation time per frame while loading (microseconds).
const MESH_BUDGET_USEC := 7000

static var _instance: GameState

## Aircraft ids found in AIRCRAFT_DIR, sorted. Adding a .tres adds a plane.
var aircraft_ids: PackedStringArray
var selected_id: String = ""
var start_mode: StartMode = StartMode.RUNWAY
## Result of the most recent crash, for the report screen.
var last_report: RefCounted

var _defs: Dictionary = {}
var _busy: bool = false
var _overlay: CanvasLayer
var _bar: ProgressBar
var _label: Label


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
	var settings := SettingsStore.instance()
	settings.changed.connect(apply_quality)
	apply_quality()
	if OS.has_environment("CRASHLAB_AUTOPLAY"):
		var autoplay := Autoplay.new()
		autoplay.name = "Autoplay"
		add_child(autoplay)


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
	if (selected_id == "" or not found.has(selected_id)) and not found.is_empty():
		selected_id = found[0]


func aircraft_path(id: String = "") -> String:
	return AIRCRAFT_DIR + (selected_id if id == "" else id) + ".tres"


## The definition of aircraft `id` (default: the selected one), loaded once
## and kept. Returns null, with an error logged, if the file is unusable.
func get_def(id: String = "") -> AircraftDef:
	var key := selected_id if id == "" else id
	var cached: AircraftDef = _defs.get(key)
	if cached != null:
		return cached
	var path := aircraft_path(key)
	if not ResourceLoader.exists(path):
		push_error("Aircraft definition missing: %s" % path)
		return null
	var def := load(path) as AircraftDef
	if def == null or def.parts.is_empty():
		push_error("Aircraft definition unreadable: %s" % path)
		return null
	_defs[key] = def
	return def


func load_selected() -> AircraftDef:
	return get_def()


func goto_flight() -> void:
	change_scene_async(FLIGHT_SCENE)


func goto_hangar() -> void:
	change_scene_async(HANGAR_SCENE)


## Switches to `scene_path` behind the loading overlay. For the flight scene
## the selected aircraft's meshes are generated first, a slice per frame, so
## the progress bar moves and the frame never stalls for long.
func change_scene_async(scene_path: String) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	_label.text = "LOADING"
	_bar.value = 0.0
	_overlay.visible = true
	# Two frames so the overlay is actually on screen before any heavy work.
	await get_tree().process_frame
	await get_tree().process_frame
	if scene_path == FLIGHT_SCENE:
		var def := get_def()
		if def == null:
			await _fail("COULD NOT LOAD AIRCRAFT")
			return
		while true:
			var progress := AirframeBuilder.prebuild_some(def, MESH_BUDGET_USEC)
			_bar.value = progress * 80.0
			if progress >= 1.0:
				break
			await get_tree().process_frame
	var packed := load(scene_path) as PackedScene
	if packed == null:
		await _fail("COULD NOT LOAD SCENE")
		return
	_bar.value = 90.0
	await get_tree().process_frame
	get_tree().change_scene_to_packed(packed)
	# Keep the overlay up while the new scene builds itself on its first frames.
	for _i: int in 3:
		await get_tree().process_frame
	_bar.value = 100.0
	_overlay.visible = false
	_busy = false


## Shows `message` on the overlay for a moment, then gives control back.
func _fail(message: String) -> void:
	_label.text = message
	await get_tree().create_timer(2.0, true).timeout
	_overlay.visible = false
	_busy = false


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
	# A CenterContainer keeps the box centred at any aspect ratio.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420.0, 0.0)
	box.add_theme_constant_override(&"separation", 14)
	center.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 28)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420.0, 14.0)
	_bar.show_percentage = false
	box.add_child(_bar)
