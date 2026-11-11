class_name SettingsStore
extends Node
## Player preferences (autoload "Settings"). The class has its own name because
## scripts run with --check-only or -s compile before autoload globals exist;
## they fetch the live node through SettingsStore.instance(). Persisted to user://settings.cfg.
## set_value() never saves on its own so sliders can drag without disk churn;
## the settings panel calls save() when the player presses Done.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
const KEYS: Array[StringName] = [
	&"stick_sensitivity", &"stick_deadzone", &"stick_smoothing", &"invert_pitch",
	&"gyro_enabled", &"gyro_sensitivity", &"auto_trim", &"units_metric",
	&"graphics_quality", &"show_fps",
]
const _DEBRIS: Array[int] = [24, 48, 80]
const _FREDS: Array[int] = [4, 8, 12]

static var _instance: SettingsStore

var stick_sensitivity: float = 1.0
var stick_deadzone: float = 0.08
var stick_smoothing: float = 0.35
var invert_pitch: bool = false
var gyro_enabled: bool = false
var gyro_sensitivity: float = 1.0
var auto_trim: bool = true
## false = knots / feet / fpm, true = km/h / m / m/s.
var units_metric: bool = false
## 0 low, 1 medium, 2 high.
var graphics_quality: int = 1
var show_fps: bool = true


## The autoload node, cached. Falls back to a detached default instance when the
## autoload is absent (e.g. a minimal test scene), so callers never see null.
static func instance() -> SettingsStore:
	if _instance == null or not is_instance_valid(_instance):
		var loop := Engine.get_main_loop() as SceneTree
		if loop != null:
			_instance = loop.root.get_node_or_null("Settings") as SettingsStore
		if _instance == null:
			_instance = SettingsStore.new()
	return _instance


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: StringName in KEYS:
			if cfg.has_section_key(SECTION, key):
				_assign(key, cfg.get_value(SECTION, key))
	_clamp_all()


func save() -> void:
	var cfg := ConfigFile.new()
	for key: StringName in KEYS:
		cfg.set_value(SECTION, key, get(key))
	cfg.save(PATH)


func reset_defaults() -> void:
	stick_sensitivity = 1.0
	stick_deadzone = 0.08
	stick_smoothing = 0.35
	invert_pitch = false
	gyro_enabled = false
	gyro_sensitivity = 1.0
	auto_trim = true
	units_metric = false
	graphics_quality = 1
	show_fps = true
	changed.emit()


func set_value(key: StringName, value: Variant) -> void:
	if not KEYS.has(key):
		push_warning("Settings: unknown key %s" % key)
		return
	_assign(key, value)
	_clamp_all()
	changed.emit()


func max_debris() -> int:
	return _DEBRIS[clampi(graphics_quality, 0, 2)]


func max_freds() -> int:
	return _FREDS[clampi(graphics_quality, 0, 2)]


## Type-safe set: a hand-edited config must not be able to crash a typed property.
func _assign(key: StringName, value: Variant) -> void:
	var current: Variant = get(key)
	match typeof(current):
		TYPE_FLOAT:
			if value is float or value is int:
				set(key, float(value))
		TYPE_INT:
			if value is float or value is int:
				set(key, int(value))
		TYPE_BOOL:
			if value is bool:
				set(key, value)


func _clamp_all() -> void:
	stick_sensitivity = clampf(stick_sensitivity, 0.5, 2.0)
	stick_deadzone = clampf(stick_deadzone, 0.0, 0.4)
	stick_smoothing = clampf(stick_smoothing, 0.0, 0.9)
	gyro_sensitivity = clampf(gyro_sensitivity, 0.5, 2.0)
	graphics_quality = clampi(graphics_quality, 0, 2)
