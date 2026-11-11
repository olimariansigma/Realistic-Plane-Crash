class_name AttitudeIndicator
extends Control
## Artificial horizon. Sky is a circle/half-plane polygon computed analytically,
## so the "clip" to the round bezel needs no stencil or shader.

const ARC_SEGMENTS: int = 36
## Degrees of pitch visible from the centre to the bezel.
const VISIBLE_PITCH_DEG := 32.0
const REDRAW_THRESHOLD_DEG := 0.2

var _pitch_deg: float = 0.0
var _roll_deg: float = 0.0
## Reused every redraw so drawing never allocates.
var _sky: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_sky.resize(ARC_SEGMENTS + 1)


func set_attitude(pitch_deg: float, roll_deg: float) -> void:
	if absf(pitch_deg - _pitch_deg) > REDRAW_THRESHOLD_DEG \
			or absf(roll_deg - _roll_deg) > REDRAW_THRESHOLD_DEG:
		_pitch_deg = pitch_deg
		_roll_deg = roll_deg
		queue_redraw()


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - UiStyle.OUTLINE_WIDTH
	var c: Vector2 = size * 0.5
	var px_per_deg: float = radius / VISIBLE_PITCH_DEG
	# Horizon appears to rotate opposite to the aircraft's roll.
	var up: Vector2 = Vector2(0.0, -1.0).rotated(-deg_to_rad(_roll_deg))
	var right: Vector2 = Vector2(up.y * -1.0, up.x)
	# Nose up moves the horizon down: it sits at distance d along `up` (d < 0).
	var d: float = -_pitch_deg * px_per_deg

	draw_circle(c, radius, UiStyle.GROUND)
	if d <= -radius:
		draw_circle(c, radius, UiStyle.SKY)
	elif d < radius:
		var half_angle: float = acos(d / radius)
		var base_angle: float = up.angle()
		for i: int in ARC_SEGMENTS + 1:
			var a: float = base_angle - half_angle + 2.0 * half_angle * i / ARC_SEGMENTS
			_sky[i] = c + Vector2.from_angle(a) * radius
		draw_colored_polygon(_sky, UiStyle.SKY)
		var chord: float = sqrt(radius * radius - d * d)
		var mid: Vector2 = c + up * d
		draw_line(mid - right * chord, mid + right * chord, UiStyle.TEXT, 2.0, true)

	# Pitch ladder every 10 degrees; only rungs fully inside the bezel are drawn.
	for k: int in range(-8, 9):
		if k == 0:
			continue
		var dist: float = (k * 10.0 - _pitch_deg) * px_per_deg
		var half: float = 26.0 if k % 2 == 0 else 14.0
		if sqrt(dist * dist + half * half) > radius * 0.95:
			continue
		var p: Vector2 = c + up * dist
		draw_line(p - right * half, p + right * half, Color(UiStyle.TEXT, 0.85), 2.0, true)

	# Fixed aircraft symbol.
	draw_line(c + Vector2(-46.0, 0.0), c + Vector2(-14.0, 0.0), UiStyle.ACCENT, 4.0, true)
	draw_line(c + Vector2(14.0, 0.0), c + Vector2(46.0, 0.0), UiStyle.ACCENT, 4.0, true)
	draw_line(c + Vector2(-14.0, 0.0), c + Vector2(-14.0, 8.0), UiStyle.ACCENT, 4.0, true)
	draw_line(c + Vector2(14.0, 0.0), c + Vector2(14.0, 8.0), UiStyle.ACCENT, 4.0, true)
	draw_circle(c, 3.5, UiStyle.ACCENT)
	draw_arc(c, radius, 0.0, TAU, 64, UiStyle.OUTLINE, UiStyle.OUTLINE_WIDTH, true)
