class_name FlightHud
extends Control
## Touch flight HUD: writes the pilot's ControlState, reads FlightTelemetry.
## Root ignores the mouse so 3D input is never blocked; unconsumed touches
## become camera drag / pinch. Runs while paused so the pause menu works.

signal camera_cycle_requested
## Finger dragged on free screen area, in px.
signal camera_drag(relative: Vector2)
## Pinch: > 1 zooms in.
signal camera_zoom(factor: float)
signal cutaway_toggled(enabled: bool)
signal restart_requested
signal hangar_requested
signal pause_changed(paused: bool)

const EXPO: float = 1.6
## Seconds per unit of _settings.stick_smoothing.
const SMOOTH_TIME_SCALE: float = 0.25
const TELEMETRY_PERIOD: float = 0.1
const MS_TO_KT: float = 1.94384
const MS_TO_KMH: float = 3.6
const M_TO_FT: float = 3.28084
const MS_TO_FPM: float = 196.85
## sin(30 deg): gravity-vector change that equals full gyro deflection.
const GYRO_FULL_SCALE: float = 0.5

var _controls: ControlState
var _telemetry: FlightTelemetry
var _def: AircraftDef

var _flap: int = 0
var _flap_max: int = 0
var _roll_out: float = 0.0
var _pitch_out: float = 0.0
var _yaw_out: float = 0.0
var _tel_accum: float = 0.0
var _toast_left: float = 0.0
var _stall_phase: float = 0.0
var _gyro_neutral: Vector3 = Vector3.ZERO
var _gyro_have_neutral: bool = false
var _gyro_was_enabled: bool = false
## Free-area touches (camera): two slots, no per-event allocation.
var _cam_index: PackedInt32Array = PackedInt32Array([-1, -1])
var _cam_pos: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])

var _settings: SettingsStore = SettingsStore.instance()

@onready var _flight_layer: Control = %FlightLayer
@onready var _stick: VirtualStick = %Stick
@onready var _rudder: TouchSlider = %RudderSlider
@onready var _throttle: TouchSlider = %ThrottleSlider
@onready var _flap_up: TouchButton = %FlapUpButton
@onready var _flap_down: TouchButton = %FlapDownButton
@onready var _flap_label: Label = %FlapLabel
@onready var _gear: TouchButton = %GearButton
@onready var _brake: TouchButton = %BrakeButton
@onready var _spoilers: TouchButton = %SpoilerButton
@onready var _cam_button: TouchButton = %CamButton
@onready var _cut_button: TouchButton = %CutButton
@onready var _pause_button: TouchButton = %PauseButton
@onready var _telemetry_label: Label = %TelemetryLabel
@onready var _attitude: AttitudeIndicator = %AttitudeIndicator
@onready var _stall_label: Label = %StallLabel
@onready var _fps_label: Label = %FpsLabel
@onready var _toast_label: Label = %ToastLabel
@onready var _overlay: Control = %PauseOverlay
@onready var _settings_panel: SettingsPanel = %SettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flight_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	for label: Label in [_telemetry_label, _toast_label]:
		label.add_theme_stylebox_override(&"normal", UiStyle.panel_box())
	for label: Label in [_telemetry_label, _toast_label, _flap_label, _fps_label]:
		label.add_theme_color_override(&"font_color", UiStyle.TEXT)
	_stall_label.add_theme_color_override(&"font_color", Color(1.0, 0.15, 0.1))
	_toast_label.hide()
	_stall_label.hide()
	_overlay.hide()
	_settings_panel.hide()
	_gear.pressed = true
	_cam_button.tapped.connect(camera_cycle_requested.emit)
	_cut_button.pressed_changed.connect(cutaway_toggled.emit)
	_pause_button.tapped.connect(_set_paused.bind(true))
	_flap_up.tapped.connect(_step_flap.bind(1))
	_flap_down.tapped.connect(_step_flap.bind(-1))
	%ResumeButton.pressed.connect(_set_paused.bind(false))
	%RestartButton.pressed.connect(_on_restart_pressed)
	%SettingsButton.pressed.connect(_settings_panel.show)
	%HangarButton.pressed.connect(_on_hangar_pressed)
	_update_flap_label()
	_refresh_telemetry()


func bind(controls: ControlState, telemetry: FlightTelemetry, def: AircraftDef) -> void:
	_controls = controls
	_telemetry = telemetry
	_def = def
	_flap_max = 0
	if def != null:
		_flap_max = maxi(def.flap_steps_deg.size() - 1, 0)
	if controls != null:
		_flap = clampi(controls.flap_step, 0, _flap_max)
		_gear.pressed = controls.gear_down
		_spoilers.pressed = controls.spoilers
		_throttle.value = controls.throttle
	_update_flap_label()
	_refresh_telemetry()


func set_camera_mode_name(mode_name: String) -> void:
	_cam_button.text = mode_name


func show_message(text: String, seconds: float = 2.5) -> void:
	_toast_label.text = text
	_toast_label.show()
	_toast_left = seconds


## Hides every flight widget and the telemetry (crash report view).
func set_controls_visible(enabled: bool) -> void:
	_flight_layer.visible = enabled


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_overlay.visible = paused
	if paused:
		_release_all_touches()
	else:
		_settings_panel.hide()
		_gyro_have_neutral = false
	pause_changed.emit(paused)


func _on_restart_pressed() -> void:
	_set_paused(false)
	restart_requested.emit()


func _on_hangar_pressed() -> void:
	_set_paused(false)
	hangar_requested.emit()


func _release_all_touches() -> void:
	_stick.cancel_touch()
	_rudder.cancel_touch()
	_throttle.cancel_touch()
	for b: TouchButton in [_flap_up, _flap_down, _brake, _cam_button, _pause_button]:
		b.cancel_touch()
	_cam_index[0] = -1
	_cam_index[1] = -1


func _step_flap(direction: int) -> void:
	_flap = clampi(_flap + direction, 0, _flap_max)
	_update_flap_label()


func _update_flap_label() -> void:
	_flap_label.text = "FLAPS %d/%d" % [_flap, _flap_max]


# --- Per-frame: input shaping --------------------------------------------

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast_label.hide()
	if _telemetry != null:
		_attitude.set_attitude(_telemetry.pitch_deg, _telemetry.roll_deg)
		if _telemetry.stall_warning:
			_stall_phase += delta
			_stall_label.visible = fmod(_stall_phase, 0.5) < 0.3
		else:
			_stall_phase = 0.0
			_stall_label.visible = false
	_tel_accum += delta
	if _tel_accum >= TELEMETRY_PERIOD:
		_tel_accum = 0.0
		_refresh_telemetry()
	if _controls != null:
		_write_controls(delta)


func _write_controls(delta: float) -> void:
	var dz: float = _settings.stick_deadzone
	var sens: float = _settings.stick_sensitivity
	var stick: Vector2 = _stick.value
	var stick_len: float = stick.length()
	if stick_len <= dz:
		stick = Vector2.ZERO
	else:
		stick *= ((stick_len - dz) / maxf(1.0 - dz, 0.0001)) / stick_len
	var yaw: float = _rudder.value
	var yaw_abs: float = absf(yaw)
	yaw = 0.0 if yaw_abs <= dz else signf(yaw) * (yaw_abs - dz) / maxf(1.0 - dz, 0.0001)

	var roll_t: float = signf(stick.x) * pow(absf(stick.x), EXPO) * sens
	var pitch_t: float = signf(stick.y) * pow(absf(stick.y), EXPO) * sens
	var yaw_t: float = signf(yaw) * pow(absf(yaw), EXPO) * sens
	var gyro: Vector2 = _read_gyro()
	roll_t = clampf(roll_t + gyro.x, -1.0, 1.0)
	pitch_t = clampf(pitch_t + gyro.y, -1.0, 1.0)
	yaw_t = clampf(yaw_t, -1.0, 1.0)
	if _settings.invert_pitch:
		pitch_t = -pitch_t

	var tau: float = _settings.stick_smoothing * SMOOTH_TIME_SCALE
	var alpha: float = 1.0 if tau <= 0.0001 else 1.0 - exp(-delta / tau)
	_roll_out = lerpf(_roll_out, roll_t, alpha)
	_pitch_out = lerpf(_pitch_out, pitch_t, alpha)
	_yaw_out = lerpf(_yaw_out, yaw_t, alpha)
	_controls.roll = _roll_out
	_controls.pitch = _pitch_out
	_controls.yaw = _yaw_out
	_controls.throttle = _throttle.value
	_controls.flap_step = _flap
	_controls.gear_down = _gear.pressed
	_controls.brake = 1.0 if _brake.pressed else 0.0
	_controls.spoilers = _spoilers.pressed


## Tilt input in stick units (x roll, y pitch). Zero when the sensor is silent.
func _read_gyro() -> Vector2:
	if not _settings.gyro_enabled:
		_gyro_was_enabled = false
		return Vector2.ZERO
	var g: Vector3 = Input.get_gravity()
	if g.is_zero_approx():
		g = Input.get_accelerometer()
	if g.is_zero_approx():
		return Vector2.ZERO
	g = g.normalized()
	if not _gyro_was_enabled:
		_gyro_was_enabled = true
		_gyro_have_neutral = false
	if not _gyro_have_neutral:
		_gyro_neutral = g
		_gyro_have_neutral = true
		return Vector2.ZERO
	var scale: float = _settings.gyro_sensitivity / GYRO_FULL_SCALE
	return Vector2((g.y - _gyro_neutral.y) * scale, (g.z - _gyro_neutral.z) * scale)


# --- 10 Hz: text -------------------------------------------------------------

func _refresh_telemetry() -> void:
	_fps_label.visible = _settings.show_fps
	if _settings.show_fps:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _telemetry == null:
		_telemetry_label.text = "NO DATA"
		return
	var t: FlightTelemetry = _telemetry
	var metric: bool = _settings.units_metric
	var spd: float = t.ias * (MS_TO_KMH if metric else MS_TO_KT)
	var alt: float = t.altitude_agl * (1.0 if metric else M_TO_FT)
	var vs: float = t.vertical_speed * (1.0 if metric else MS_TO_FPM)
	var gear_text: String = "DOWN" if t.gear_ratio > 0.99 \
			else ("UP" if t.gear_ratio < 0.01 else "MOVING")
	var title: String = _def.display_name if _def != null else ""
	_telemetry_label.text = (
		"%s\nSPD  %d %s\nALT  %d %s\nV/S  %+.1f %s\nAoA  %.1f deg\nG  %.1f\nHDG  %03d\n"
		+ "THR  %d%%\nFLAPS  %d%%\nGEAR  %s\nTRIM  %+.2f") % [
			title,
			roundi(spd), "km/h" if metric else "kt",
			roundi(alt), "m" if metric else "ft",
			vs if metric else float(roundi(vs)), "m/s" if metric else "fpm",
			t.aoa_deg, t.g_load, posmod(roundi(t.heading_deg), 360),
			roundi(t.thrust_fraction * 100.0), roundi(t.flap_ratio * 100.0),
			gear_text, t.trim,
		]


# --- Camera touches (anything no widget claimed) -----------------------------

func _input(event: InputEvent) -> void:
	if get_tree().paused or _overlay.visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var slot: int = 0 if _cam_index[0] == -1 else (1 if _cam_index[1] == -1 else -1)
			if slot >= 0:
				_cam_index[slot] = touch.index
				_cam_pos[slot] = touch.position
		else:
			for i: int in 2:
				if _cam_index[i] == touch.index:
					_cam_index[i] = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var slot_d: int = 0 if _cam_index[0] == drag.index else (1 if _cam_index[1] == drag.index else -1)
		if slot_d < 0:
			return
		if _cam_index[1 - slot_d] != -1:
			var old_dist: float = _cam_pos[0].distance_to(_cam_pos[1])
			_cam_pos[slot_d] = drag.position
			var new_dist: float = _cam_pos[0].distance_to(_cam_pos[1])
			if old_dist > 1.0:
				camera_zoom.emit(new_dist / old_dist)
		else:
			_cam_pos[slot_d] = drag.position
			camera_drag.emit(drag.relative)
