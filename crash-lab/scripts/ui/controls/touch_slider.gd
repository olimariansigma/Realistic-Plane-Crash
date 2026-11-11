class_name TouchSlider
extends Control
## Single-finger slider that sets its value from the absolute finger position.
## Own touch handling (see VirtualStick) so it works alongside other fingers.

signal value_changed(value: float)

@export var vertical: bool = true
@export var min_value: float = 0.0
@export var max_value: float = 1.0
## Springs back to rest_value on release (rudder).
@export var spring_return: bool = false
@export var rest_value: float = 0.0
## When > 1, the value snaps to this many evenly spaced steps.
@export var detents: int = 0
@export var label: String = ""

var value: float = 0.0:
	set = _set_value
var touch_index: int = -1

const _END_PAD := 20.0
var _handle_box: StyleBoxFlat
var _track_box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_handle_box = UiStyle.panel_box(UiStyle.ACTIVE_BG, UiStyle.TEXT)
	_handle_box.set_content_margin_all(0.0)
	_track_box = UiStyle.panel_box(UiStyle.PANEL_BG, UiStyle.OUTLINE)
	_track_box.set_content_margin_all(0.0)
	if spring_return:
		value = rest_value


func is_pressed() -> bool:
	return touch_index != -1


func cancel_touch() -> void:
	if touch_index != -1:
		touch_index = -1
		if spring_return:
			value = rest_value
		queue_redraw()


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
				_track(touch.position)
				queue_redraw()
				get_viewport().set_input_as_handled()
		elif touch.index == touch_index:
			cancel_touch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == touch_index:
			_track(drag.position)
			get_viewport().set_input_as_handled()


func _start_pad() -> float:
	return _END_PAD + (12.0 if not label.is_empty() and vertical else 0.0)


## Normalised position along the track, 0 = min end, 1 = max end.
func _track(global_pos: Vector2) -> void:
	var rect: Rect2 = get_global_rect()
	var t: float
	if vertical:
		var start: float = rect.position.y + _start_pad()
		t = 1.0 - (global_pos.y - start) / maxf(rect.size.y - _start_pad() - _END_PAD, 1.0)
	else:
		var start_x: float = rect.position.x + _END_PAD
		t = (global_pos.x - start_x) / maxf(rect.size.x - 2.0 * _END_PAD, 1.0)
	t = clampf(t, 0.0, 1.0)
	if detents > 1:
		t = roundf(t * (detents - 1)) / float(detents - 1)
	value = lerpf(min_value, max_value, t)


func _set_value(v: float) -> void:
	var clamped: float = clampf(v, minf(min_value, max_value), maxf(min_value, max_value))
	if is_equal_approx(clamped, value):
		return
	value = clamped
	queue_redraw()
	value_changed.emit(value)


func _draw() -> void:
	var span: float = max_value - min_value
	var t: float = 0.0 if is_zero_approx(span) else clampf((value - min_value) / span, 0.0, 1.0)
	var font: Font = get_theme_default_font()
	var handle_color: Color = UiStyle.ACCENT if touch_index != -1 else UiStyle.TEXT
	_handle_box.border_color = handle_color
	if vertical:
		var top: float = _start_pad()
		var length: float = size.y - top - _END_PAD
		var cx: float = size.x * 0.5
		draw_style_box(_track_box, Rect2(cx - 8.0, top, 16.0, length))
		var hy: float = top + (1.0 - t) * length
		draw_style_box(_handle_box, Rect2(4.0, hy - 18.0, size.x - 8.0, 36.0))
		if not label.is_empty():
			draw_string(font, Vector2(0.0, 22.0), label, HORIZONTAL_ALIGNMENT_CENTER,
					size.x, UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	else:
		var cy: float = size.y * (0.62 if not label.is_empty() else 0.5)
		var length_h: float = size.x - 2.0 * _END_PAD
		draw_style_box(_track_box, Rect2(_END_PAD, cy - 8.0, length_h, 16.0))
		var hx: float = _END_PAD + t * length_h
		draw_style_box(_handle_box, Rect2(hx - 18.0, cy - 22.0, 36.0, 44.0))
		if not label.is_empty():
			draw_string(font, Vector2(0.0, 16.0), label, HORIZONTAL_ALIGNMENT_CENTER,
					size.x, UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
