class_name SettingsPanel
extends Control
## Settings editor over the pause menu. Edits apply live; Done persists them.

signal closed

var _settings: SettingsStore = SettingsStore.instance()

@onready var _stick_sens: HSlider = %StickSensitivity
@onready var _deadzone: HSlider = %StickDeadzone
@onready var _smoothing: HSlider = %StickSmoothing
@onready var _invert: CheckButton = %InvertPitch
@onready var _gyro: CheckButton = %GyroEnabled
@onready var _gyro_sens: HSlider = %GyroSensitivity
@onready var _auto_trim: CheckButton = %AutoTrim
@onready var _metric: CheckButton = %UnitsMetric
@onready var _quality: OptionButton = %Quality
@onready var _fps: CheckButton = %ShowFps


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stick_sens.value_changed.connect(_on_float.bind(&"stick_sensitivity"))
	_deadzone.value_changed.connect(_on_float.bind(&"stick_deadzone"))
	_smoothing.value_changed.connect(_on_float.bind(&"stick_smoothing"))
	_gyro_sens.value_changed.connect(_on_float.bind(&"gyro_sensitivity"))
	_invert.toggled.connect(_on_bool.bind(&"invert_pitch"))
	_gyro.toggled.connect(_on_bool.bind(&"gyro_enabled"))
	_auto_trim.toggled.connect(_on_bool.bind(&"auto_trim"))
	_metric.toggled.connect(_on_bool.bind(&"units_metric"))
	_fps.toggled.connect(_on_bool.bind(&"show_fps"))
	_quality.item_selected.connect(_on_quality)
	%ResetButton.pressed.connect(_on_reset)
	%DoneButton.pressed.connect(_on_done)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _refresh() -> void:
	_stick_sens.set_value_no_signal(_settings.stick_sensitivity)
	_deadzone.set_value_no_signal(_settings.stick_deadzone)
	_smoothing.set_value_no_signal(_settings.stick_smoothing)
	_gyro_sens.set_value_no_signal(_settings.gyro_sensitivity)
	_invert.set_pressed_no_signal(_settings.invert_pitch)
	_gyro.set_pressed_no_signal(_settings.gyro_enabled)
	_auto_trim.set_pressed_no_signal(_settings.auto_trim)
	_metric.set_pressed_no_signal(_settings.units_metric)
	_fps.set_pressed_no_signal(_settings.show_fps)
	_quality.select(_settings.graphics_quality)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


func _on_float(v: float, key: StringName) -> void:
	_settings.set_value(key, v)


func _on_bool(v: bool, key: StringName) -> void:
	_settings.set_value(key, v)


func _on_quality(index: int) -> void:
	_settings.set_value(&"graphics_quality", index)


func _on_reset() -> void:
	_settings.reset_defaults()
	_refresh()


func _on_done() -> void:
	_settings.save()
	hide()
	closed.emit()
