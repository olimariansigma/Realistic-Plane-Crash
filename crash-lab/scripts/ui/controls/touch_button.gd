class_name TouchButton
extends Control
## Multi-touch-safe button. A Control GUI press only sees the first finger,
## so this reads screen touches directly (see VirtualStick).

signal pressed_changed(pressed: bool)
## Emitted when the capturing finger lifts.
signal tapped

@export var text: String = "":
	set(v):
		text = v
		queue_redraw()
@export var toggle_mode: bool = false
@export var accent: bool = false

## Toggle mode: flips on each touch-down. Otherwise true while held.
var pressed: bool = false:
	set = _set_pressed
var touch_index: int = -1

var _normal_box: StyleBoxFlat
var _pressed_box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border: Color = UiStyle.ACCENT if accent else UiStyle.OUTLINE
	_normal_box = UiStyle.panel_box(UiStyle.PANEL_BG, border)
	_pressed_box = UiStyle.panel_box(
			Color(UiStyle.ACCENT, 0.85) if accent else UiStyle.ACTIVE_BG, UiStyle.TEXT)


func cancel_touch() -> void:
	if touch_index != -1:
		touch_index = -1
		if not toggle_mode:
			pressed = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_touch()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if touch_index == -1 and is_visible_in_tree() \
					and get_global_rect().has_point(touch.position):
				touch_index = touch.index
				pressed = not pressed if toggle_mode else true
				get_viewport().set_input_as_handled()
		elif touch.index == touch_index:
			touch_index = -1
			if not toggle_mode:
				pressed = false
			tapped.emit()
			get_viewport().set_input_as_handled()


func _set_pressed(v: bool) -> void:
	if v == pressed:
		return
	pressed = v
	queue_redraw()
	pressed_changed.emit(pressed)


func _draw() -> void:
	var box: StyleBoxFlat = _pressed_box if (pressed or touch_index != -1) else _normal_box
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	if text.is_empty():
		return
	var font: Font = get_theme_default_font()
	var baseline: float = (size.y + font.get_ascent(UiStyle.FONT_SIZE)
			- font.get_descent(UiStyle.FONT_SIZE)) * 0.5
	draw_string(font, Vector2(0.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, UiStyle.FONT_SIZE, UiStyle.TEXT)
