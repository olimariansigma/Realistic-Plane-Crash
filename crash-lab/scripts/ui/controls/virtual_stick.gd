class_name VirtualStick
extends Control
## Analog stick. Reads touches itself in _input because Control GUI events only
## carry the first finger, and flight needs stick + throttle held together.

## x: -1 left .. +1 right. y: -1 up .. +1 down (finger toward screen bottom).
var value: Vector2 = Vector2.ZERO
var touch_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_pressed() -> bool:
	return touch_index != -1


## Drops the captured finger (pause, hidden HUD) so the stick cannot stay stuck.
func cancel_touch() -> void:
	touch_index = -1
	_set_value(Vector2.ZERO)


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
				get_viewport().set_input_as_handled()
		elif touch.index == touch_index:
			cancel_touch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == touch_index:
			_track(drag.position)
			get_viewport().set_input_as_handled()


func _track(global_pos: Vector2) -> void:
	var radius: float = minf(size.x, size.y) * 0.4
	var offset: Vector2 = global_pos - get_global_rect().get_center()
	_set_value((offset / radius).limit_length(1.0))


func _set_value(v: Vector2) -> void:
	if v != value:
		value = v
		queue_redraw()


func _draw() -> void:
	var half: float = minf(size.x, size.y) * 0.5
	var center: Vector2 = size * 0.5
	var travel: float = half * 0.8
	draw_circle(center, half - 2.0, UiStyle.PANEL_BG)
	draw_arc(center, half - 2.0, 0.0, TAU, 48, UiStyle.OUTLINE, UiStyle.OUTLINE_WIDTH, true)
	draw_arc(center, travel, 0.0, TAU, 48, Color(UiStyle.OUTLINE, 0.18), 1.0, true)
	var knob_color: Color = UiStyle.ACCENT if touch_index != -1 else UiStyle.ACTIVE_BG
	var knob_pos: Vector2 = center + value * travel
	draw_circle(knob_pos, half * 0.3, Color(knob_color, 0.85))
	draw_arc(knob_pos, half * 0.3, 0.0, TAU, 32, UiStyle.TEXT, UiStyle.OUTLINE_WIDTH, true)
