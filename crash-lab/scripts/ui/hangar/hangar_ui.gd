class_name HangarUi
extends Control
## Hangar overlay: aircraft name, stats, previous/next/launch and showroom options.
## Pure 2D; leaves the screen centre free. Empty-area drag and pinch are re-emitted
## as orbit signals for the showroom camera.

signal previous_requested
signal next_requested
signal launch_requested
signal cutaway_toggled(enabled: bool)
signal start_mode_changed(mode: int)
## Drag on free screen area (px).
signal orbit_drag(relative: Vector2)
## Pinch or wheel zoom factor, > 1 zooms in.
signal orbit_zoom(factor: float)

const WHEEL_STEP: float = 1.1
const KT_PER_MS: float = 1.94384
const G: float = 9.80665
const MIN_PINCH_DIST: float = 1.0

## Stat rows: [label, format, maximum].
const STAT_ROWS: Array[Array] = [
	["Mass", "%.1f t", 250.0],
	["Wingspan", "%.1f m", 65.0],
	["Wing loading", "%d kg/m2", 700.0],
	["Thrust", "%d kN", 850.0],
	["Thrust / weight", "%.2f", 1.2],
	["Rotate speed", "%d kt", 200.0],
	["Never exceed", "%d kt", 850.0],
	["Seats", "%d", 350.0],
	["Structural parts", "%d", 20.0],
]

var _value_labels: Array[Label] = []
var _bars: Array[ProgressBar] = []
var _start_buttons: Array[Button] = []
var _launch_enabled_by_loading: bool = false
var _accent: Color = UiStyle.ACCENT
var _touch_id: Array[int] = [-1, -1]
var _touch_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]

@onready var _game_title: Label = %GameTitle
@onready var _name_label: Label = %NameLabel
@onready var _category_label: Label = %CategoryLabel
@onready var _index_label: Label = %IndexLabel
@onready var _loading_label: Label = %LoadingLabel
@onready var _description: Label = %DescriptionLabel
@onready var _stats_box: VBoxContainer = %StatsBox
@onready var _launch: Button = %LaunchButton
@onready var _cutaway: Button = %CutawayButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	%LeftPanel.add_theme_stylebox_override(&"panel", UiStyle.panel_box())
	%RightPanel.add_theme_stylebox_override(&"panel", UiStyle.panel_box())
	for label: Label in [_game_title, _name_label, _category_label, _index_label,
			_loading_label, _description]:
		label.add_theme_color_override(&"font_color", UiStyle.TEXT)
	_game_title.add_theme_color_override(&"font_color", _accent)
	_loading_label.add_theme_color_override(&"font_color", _accent)
	for label: Label in [_name_label, _category_label, _index_label, _loading_label,
			_game_title]:
		label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
		label.add_theme_constant_override(&"shadow_offset_x", 1)
		label.add_theme_constant_override(&"shadow_offset_y", 1)
	_build_stats()
	_build_start_buttons()
	%PrevButton.pressed.connect(previous_requested.emit)
	%NextButton.pressed.connect(next_requested.emit)
	_launch.pressed.connect(launch_requested.emit)
	_cutaway.toggled.connect(cutaway_toggled.emit)
	%SettingsButton.pressed.connect(_settings_panel.show)
	_settings_panel.closed.connect(_settings_panel.hide)
	_settings_panel.hide()
	_apply_accent(_accent)


func _build_stats() -> void:
	for i: int in STAT_ROWS.size():
		var row := VBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 1)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := Label.new()
		name_label.text = STAT_ROWS[i][0] as String
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override(&"font_size", UiStyle.SMALL_FONT_SIZE)
		name_label.add_theme_color_override(&"font_color", UiStyle.TEXT.darkened(0.2))
		var value := Label.new()
		value.name = "StatValue%d" % i
		value.unique_name_in_owner = true
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override(&"font_size", UiStyle.SMALL_FONT_SIZE)
		value.add_theme_color_override(&"font_color", UiStyle.TEXT)
		line.add_child(name_label)
		line.add_child(value)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = STAT_ROWS[i][2] as float
		bar.custom_minimum_size = Vector2(0, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1.0, 1.0, 1.0, 0.12)
		bar.add_theme_stylebox_override(&"background", bg)
		bar.add_theme_stylebox_override(&"fill", StyleBoxFlat.new())
		row.add_child(line)
		row.add_child(bar)
		_stats_box.add_child(row)
		# Owner must be set after parenting for the %Unique lookup to resolve.
		value.owner = self
		_value_labels.append(value)
		_bars.append(bar)


func _build_start_buttons() -> void:
	var group := ButtonGroup.new()
	var box: VBoxContainer = %StartModes
	for i: int in GameState.START_MODE_NAMES.size():
		var b := Button.new()
		b.name = "StartMode%d" % i
		b.unique_name_in_owner = true
		b.text = GameState.START_MODE_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 64)
		b.button_pressed = i == 0
		b.pressed.connect(_on_start_pressed.bind(i))
		box.add_child(b)
		b.owner = self
		_start_buttons.append(b)


func _on_start_pressed(mode: int) -> void:
	start_mode_changed.emit(mode)


func _apply_accent(c: Color) -> void:
	_accent = c
	for bar: ProgressBar in _bars:
		var fill := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
		fill.bg_color = c
	var normal := UiStyle.panel_box(c.darkened(0.15), c.lightened(0.3))
	var hover := UiStyle.panel_box(c, c.lightened(0.4))
	var pressed := UiStyle.panel_box(c.darkened(0.35), c.lightened(0.3))
	var disabled := UiStyle.panel_box(c.darkened(0.6), UiStyle.OUTLINE)
	_launch.add_theme_stylebox_override(&"normal", normal)
	_launch.add_theme_stylebox_override(&"hover", hover)
	_launch.add_theme_stylebox_override(&"pressed", pressed)
	_launch.add_theme_stylebox_override(&"disabled", disabled)
	_launch.add_theme_color_override(&"font_color", Color.WHITE)
	_launch.add_theme_color_override(&"font_hover_color", Color.WHITE)
	_launch.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	_launch.add_theme_color_override(&"font_disabled_color", Color(1.0, 1.0, 1.0, 0.45))
	_launch.add_theme_constant_override(&"outline_size", 3)
	_launch.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	_game_title.add_theme_color_override(&"font_color", c)
	_loading_label.add_theme_color_override(&"font_color", c)


## Fills every label and stat. `index` is 0-based.
func show_aircraft(def: AircraftDef, index: int, count: int) -> void:
	_apply_accent(def.accent)
	_name_label.text = def.display_name
	_category_label.text = def.category
	_index_label.text = "%d / %d" % [index + 1, count]
	_description.text = def.description
	_description.visible = not def.description.is_empty()
	var mass_kg: float = def.total_mass()
	var thrust_n: float = def.total_thrust()
	var values: Array[float] = [
		mass_kg / 1000.0,
		def.wing_span,
		mass_kg / def.wing_area if def.wing_area > 0.0 else 0.0,
		thrust_n / 1000.0,
		thrust_n / (mass_kg * G) if mass_kg > 0.0 else 0.0,
		def.v_rotate * KT_PER_MS,
		def.v_never_exceed * KT_PER_MS,
		float(def.seat_count()),
		float(def.parts.size()),
	]
	for i: int in values.size():
		var fmt: String = STAT_ROWS[i][1] as String
		var v: float = values[i]
		# Integer formats need an int argument.
		_value_labels[i].text = fmt % (int(v) if fmt.begins_with("%d") else v)
		_bars[i].value = v


## True shows a small LOADING tag and disables LAUNCH.
func set_loading(loading: bool) -> void:
	_loading_label.visible = loading
	_launch.disabled = loading


## Updates the start-mode selector without emitting.
func set_start_mode(mode: int) -> void:
	if mode >= 0 and mode < _start_buttons.size():
		_start_buttons[mode].set_pressed_no_signal(true)


## Updates the cutaway toggle without emitting.
func set_cutaway(enabled: bool) -> void:
	_cutaway.set_pressed_no_signal(enabled)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var slot: int = -1
			if _touch_id[0] == -1:
				slot = 0
			elif _touch_id[1] == -1:
				slot = 1
			if slot >= 0:
				_touch_id[slot] = t.index
				_touch_pos[slot] = t.position
		else:
			for s: int in 2:
				if _touch_id[s] == t.index:
					_touch_id[s] = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touch_id[0] != -1 and _touch_id[1] != -1:
			var old_dist: float = _touch_pos[0].distance_to(_touch_pos[1])
			for s: int in 2:
				if _touch_id[s] == d.index:
					_touch_pos[s] = d.position
			var new_dist: float = _touch_pos[0].distance_to(_touch_pos[1])
			if old_dist > MIN_PINCH_DIST and new_dist > MIN_PINCH_DIST:
				orbit_zoom.emit(new_dist / old_dist)
		elif _touch_id[0] == d.index or _touch_id[1] == d.index:
			orbit_drag.emit(d.relative)
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.pressed:
			if m.button_index == MOUSE_BUTTON_WHEEL_UP:
				orbit_zoom.emit(WHEEL_STEP)
			elif m.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				orbit_zoom.emit(1.0 / WHEEL_STEP)
