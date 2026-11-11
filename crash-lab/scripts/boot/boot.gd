extends Control
## Milestone 1 boot screen: proves the engine, renderer and physics backend
## that actually shipped in the APK, then hands over to the hangar.

@onready var _info: Label = %Info
@onready var _fps: Label = %Fps

var _accum := 0.0
var _launched := false


func _ready() -> void:
	_info.text = "v%s  |  Godot %s  |  %s  |  %s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info().string,
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		RenderingServer.get_current_rendering_method(),
	]


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.5:
		return
	_accum = 0.0
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if not _launched:
		_launched = true
		GameState.instance().goto_hangar()
