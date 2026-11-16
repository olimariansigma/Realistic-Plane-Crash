class_name SeatMap
extends Control
## Top-down seat chart, nose at the left. Seat rects are computed when the
## report or the size changes; _draw only walks the cached arrays.

signal seat_selected(index: int)

const COLOR_FATAL := Color(0.86, 0.2, 0.18)
const COLOR_INJURED := Color(0.96, 0.7, 0.18)
const COLOR_SURVIVED := Color(0.28, 0.76, 0.34)
const MIN_CELL: float = 4.0
const MAX_CELL: float = 56.0

var _report: CrashReport
var _rects: Array[Rect2] = []
var _colors: PackedColorArray = PackedColorArray()
var _selected: int = -1
var _box: StyleBoxFlat = StyleBoxFlat.new()
var _outline: StyleBoxFlat = StyleBoxFlat.new()
var _cell: float = MIN_CELL
## Deck captions as alternating text and position; empty for one deck.
var _deck_labels: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box.anti_aliasing = true
	_outline.anti_aliasing = true
	_outline.draw_center = false
	_outline.border_color = UiStyle.TEXT


## Red -> amber -> green by survival 0..1.
static func survival_color(survival: float) -> Color:
	var s: float = clampf(survival, 0.0, 1.0)
	if s < 0.5:
		return COLOR_FATAL.lerp(COLOR_INJURED, s * 2.0)
	return COLOR_INJURED.lerp(COLOR_SURVIVED, (s - 0.5) * 2.0)


func set_report(report: CrashReport) -> void:
	_report = report
	_selected = -1
	_layout()


func set_selected(index: int) -> void:
	_selected = index
	queue_redraw()


## Centre of a seat in local coordinates (for tests and hit checks).
func seat_center(index: int) -> Vector2:
	if index < 0 or index >= _rects.size():
		return Vector2.ZERO
	return _rects[index].get_center()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	_rects.clear()
	_colors.clear()
	_deck_labels.clear()
	if _report == null or _report.seats.is_empty():
		queue_redraw()
		return
	var seats: Array[SeatResult] = _report.seats
	var n: int = seats.size()
	_rects.resize(n)
	_colors.resize(n)
	# Per deck: first and last row number, widest row, station of the first row.
	var min_row: PackedInt32Array = [1 << 30, 1 << 30]
	var max_row: PackedInt32Array = [-1, -1]
	var cols: PackedInt32Array = [0, 0]
	var first_station: PackedFloat32Array = [INF, INF]
	var last_station: float = 0.0
	for s: SeatResult in seats:
		var d: int = clampi(s.deck, 0, 1)
		min_row[d] = mini(min_row[d], s.row)
		max_row[d] = maxi(max_row[d], s.row)
		cols[d] = maxi(cols[d], s.columns_in_row)
		first_station[d] = minf(first_station[d], s.station)
		if d == 0:
			last_station = maxf(last_station, s.station)
	if max_row[0] < 0:
		# Nothing on the main deck: treat the only deck as the main one.
		min_row[0] = min_row[1]
		max_row[0] = max_row[1]
		cols[0] = cols[1]
		first_station[0] = first_station[1]
		max_row[1] = -1
	var two_decks: bool = max_row[1] >= 0
	var main_rows: int = max_row[0] - min_row[0] + 1
	# The upper deck is drawn above the main deck, lined up along the fuselage:
	# its first row starts as many main-deck rows aft as its station says.
	var shift: int = 0
	var rows: int = main_rows
	if two_decks:
		var pitch: float = (last_station - first_station[0]) / float(maxi(main_rows - 1, 1))
		if pitch > 0.1:
			shift = maxi(roundi((first_station[1] - first_station[0]) / pitch), 0)
		rows = maxi(main_rows, shift + max_row[1] - min_row[1] + 1)
	var label_rows: float = 1.4 if two_decks else 0.0
	var across: float = float(cols[0]) + (float(cols[1]) + 2.0 * label_rows if two_decks else 0.0)
	_cell = clampf(minf(size.x / float(rows), size.y / across), MIN_CELL, MAX_CELL)
	var grid: Vector2 = Vector2(float(rows), across) * _cell
	var origin: Vector2 = ((size - grid) * 0.5).max(Vector2.ZERO)
	var gap: float = _cell * 0.14
	var radius: int = int(_cell * 0.22)
	_box.set_corner_radius_all(radius)
	_outline.set_corner_radius_all(radius)
	_outline.set_border_width_all(2 if _cell >= 10.0 else 1)
	# Strip tops, in cells: [main, upper].
	var top: PackedFloat32Array = [0.0, 0.0]
	if two_decks:
		top[1] = label_rows
		top[0] = label_rows * 2.0 + float(cols[1])
		_deck_labels.append("UPPER DECK")
		_deck_labels.append(origin + Vector2(float(shift), top[1] - 0.35) * _cell)
		_deck_labels.append("MAIN DECK")
		_deck_labels.append(origin + Vector2(0.0, top[0] - 0.35) * _cell)
	for i: int in n:
		var s: SeatResult = seats[i]
		var d: int = clampi(s.deck, 0, 1) if two_decks else 0
		var cx: float = float(s.row - min_row[d]) + (float(shift) if d == 1 else 0.0)
		var cy: float = top[d] + float(s.column) + float(cols[d] - s.columns_in_row) * 0.5
		_rects[i] = Rect2(origin + Vector2(cx, cy) * _cell + Vector2(gap, gap) * 0.5, Vector2(_cell - gap, _cell - gap))
		_colors[i] = survival_color(s.survival)
	queue_redraw()


func _draw() -> void:
	var n: int = _rects.size()
	for i: int in n:
		var r: Rect2 = _rects[i]
		_box.bg_color = _colors[i]
		draw_style_box(_box, r)
		var s: SeatResult = _report.seats[i]
		if s.is_crew:
			draw_style_box(_outline, r)
		if s.has_fred:
			draw_circle(r.get_center(), maxf(1.5, _cell * 0.13), Color(0.05, 0.06, 0.08))
	if _selected >= 0 and _selected < n:
		draw_rect(_rects[_selected].grow(2.0), UiStyle.ACCENT, false, 2.0)
	var font: Font = get_theme_default_font()
	for k: int in range(0, _deck_labels.size(), 2):
		draw_string(font, _deck_labels[k + 1] as Vector2, _deck_labels[k] as String, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var best: int = -1
	var best_d: float = INF
	for i: int in _rects.size():
		var d: float = _rects[i].get_center().distance_squared_to(mb.position)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_selected = best
		queue_redraw()
		seat_selected.emit(best)
		accept_event()
