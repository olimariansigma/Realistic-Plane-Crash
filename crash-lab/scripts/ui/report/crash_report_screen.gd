class_name CrashReportScreen
extends Control
## Post-crash report overlay with a slim replay-control mode. The owner decides
## when to switch views: REPLAY only emits replay_requested.

signal replay_requested
signal replay_speed_changed(speed: float)   ## one of 0.1, 0.25, 0.5, 1.0
signal replay_seek(fraction: float)         ## 0..1, emitted while the scrub bar is dragged
signal replay_closed
signal restart_requested
signal hangar_requested

const COLOR_GOOD := Color(0.3, 0.8, 0.36)
const COLOR_WARN := Color(0.97, 0.72, 0.2)
const COLOR_BAD := Color(0.9, 0.26, 0.22)
const MS_TO_KT: float = 1.94384
const MS_TO_FPM: float = 196.85
const MARGIN: int = 24
const SPEEDS: Array[float] = [0.1, 0.25, 0.5, 1.0]
const SPEED_TEXT: Array[String] = ["0.1x", "0.25x", "0.5x", "1x"]
const IMPACT_ROWS: Array[String] = [
	"Speed", "Vertical speed", "Flight path", "Pitch", "Roll", "Peak G",
	"Time to rest", "Joints broken", "Skin panels lost", "Fires", "Expected survivors",
]
const PROB_ROWS: Array[String] = ["Deceleration", "Head impact", "Structure", "Fire"]
const LIMB_COUNT: int = 9

var _report: CrashReport
var _selected: int = -1
var _suppress_seek: bool = false
var _named: Array[Node] = []

var _backdrop: ColorRect
var _report_panel: Control
var _replay_bar: Control
var _aircraft_label: Label
var _verdict_label: Label
var _overall_label: Label
var _impact_values: Array[Label] = []
var _seat_map: SeatMap
var _detail_title: Label
var _detail_survival: Label
var _detail_cause: Label
var _detail_g: Label
var _detail_hic: Label
var _detail_intrusion: Label
var _detail_fire: Label
var _prob_bars: Array[ProgressBar] = []
var _prob_values: Array[Label] = []
var _fred_box: VBoxContainer
var _fred_summary: Label
var _fred_flags: Label
var _limb_names: Array[Label] = []
var _limb_values: Array[Label] = []
var _replay_button: Button
var _restart_button: Button
var _hangar_button: Button
var _scrub: HSlider
var _speed_buttons: Array[Button] = []
var _report_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	show_replay_controls(false)


func show_report(report: CrashReport) -> void:
	_report = report
	visible = true
	show_replay_controls(false)
	_aircraft_label.text = report.aircraft_name
	_verdict_label.text = report.verdict
	var pct: int = roundi(report.survival_overall * 100.0)
	_overall_label.text = "%d%%" % pct
	_overall_label.add_theme_color_override("font_color", _survival_color(report.survival_overall))
	_fill_impact(report)
	_seat_map.set_report(report)
	var lowest: int = -1
	var low_value: float = INF
	for i: int in report.seats.size():
		if report.seats[i].survival < low_value:
			low_value = report.seats[i].survival
			lowest = i
	_select(lowest)


func set_replay_progress(fraction: float) -> void:
	_suppress_seek = true
	_scrub.set_value_no_signal(clampf(fraction, 0.0, 1.0))
	_suppress_seek = false


func show_replay_controls(active: bool) -> void:
	_backdrop.visible = not active
	_report_panel.visible = not active
	_replay_bar.visible = active


func _survival_color(value: float) -> Color:
	if value >= 0.75:
		return COLOR_GOOD
	if value >= 0.4:
		return COLOR_WARN
	return COLOR_BAD


# --- Content -------------------------------------------------------------

func _fill_impact(r: CrashReport) -> void:
	var v: Array[String] = [
		"%.1f m/s (%.0f kt)" % [r.impact_speed, r.impact_speed * MS_TO_KT],
		"%.1f m/s (%.0f fpm)" % [r.impact_vertical_speed, r.impact_vertical_speed * MS_TO_FPM],
		"%.1f deg" % r.impact_angle_deg,
		"%.1f deg" % r.impact_pitch_deg,
		"%.1f deg" % r.impact_roll_deg,
		"%.1f g" % r.peak_g,
		"%.1f s" % r.duration,
		"%d / %d" % [r.joints_broken, r.joints_total],
		"%d / %d" % [r.skin_lost, r.skin_total],
		"%d" % r.fires,
		"%.0f of %d" % [r.survivors_expected, r.seat_count()],
	]
	for i: int in v.size():
		_impact_values[i].text = v[i]


func _select(index: int) -> void:
	_selected = index
	_seat_map.set_selected(index)
	if _report == null or index < 0 or index >= _report.seats.size():
		_detail_title.text = "No seats"
		_fred_box.visible = false
		return
	var s: SeatResult = _report.seats[index]
	_detail_title.text = "%s  -  %s" % [s.label, s.zone]
	_detail_survival.text = "Survival %d%%" % roundi(s.survival * 100.0)
	_detail_survival.add_theme_color_override("font_color", _survival_color(s.survival))
	_detail_cause.text = "Cause: %s" % (s.cause if not s.cause.is_empty() else "none")
	_detail_g.text = "Peak %.1f g  (lat %.1f  vert %.1f  fore-aft %.1f)" % [
		s.peak_g, s.peak_g_axes.x, s.peak_g_axes.y, s.peak_g_axes.z]
	_detail_hic.text = "HIC %.0f" % s.hic
	_detail_intrusion.text = "Intrusion %d%%" % roundi(s.intrusion * 100.0)
	_detail_fire.text = "Fire %d%%" % roundi(s.fire * 100.0)
	var probs: Array[float] = [s.p_decel, s.p_head, s.p_intrusion, s.p_fire]
	for i: int in probs.size():
		_prob_bars[i].value = probs[i]
		_prob_values[i].text = "%d%%" % roundi(probs[i] * 100.0)
	var fred: FredResult = null
	if s.has_fred:
		for f: FredResult in _report.freds:
			if f.seat_label == s.label:
				fred = f
				break
	_fred_box.visible = fred != null
	if fred == null:
		return
	for i: int in LIMB_COUNT:
		var has: bool = i < fred.limb_names.size() and i < fred.limb_peak_g.size()
		_limb_names[i].visible = has
		_limb_values[i].visible = has
		if has:
			_limb_names[i].text = fred.limb_names[i]
			_limb_values[i].text = "%.1f g" % fred.limb_peak_g[i]
	_fred_summary.text = "HIC %.0f   Belt %.1f kN   Stroke %.2f m" % [fred.hic, fred.belt_peak_kn, fred.stroke_m]
	var flags: PackedStringArray = PackedStringArray()
	if fred.bottomed:
		flags.append("BOTTOMED OUT")
	if fred.ejected:
		flags.append("EJECTED")
	_fred_flags.text = "  ".join(flags)
	_fred_flags.visible = not flags.is_empty()


# --- Construction --------------------------------------------------------

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.03, 0.05, 0.82)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_add(self, _backdrop, "Backdrop")

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	_add(self, margin, "ReportPanel")
	_report_panel = margin

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	body.add_child(_build_impact())
	body.add_child(_build_map())
	body.add_child(_build_detail())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(buttons)
	_replay_button = _button("REPLAY", buttons, "ReplayButton")
	_restart_button = _button("RESTART", buttons, "RestartButton")
	_hangar_button = _button("HANGAR", buttons, "HangarButton")
	_replay_button.pressed.connect(func() -> void: replay_requested.emit())
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_hangar_button.pressed.connect(func() -> void: hangar_requested.emit())

	_build_replay_bar()
	for n: Node in _named:
		n.owner = self
		n.unique_name_in_owner = true
	_named.clear()


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(_label("CRASH REPORT", 30, UiStyle.ACCENT))
	_aircraft_label = _label("", UiStyle.FONT_SIZE, UiStyle.TEXT)
	_add(col, _aircraft_label, "AircraftLabel")
	_verdict_label = _label("", UiStyle.FONT_SIZE, UiStyle.TEXT)
	_add(col, _verdict_label, "VerdictLabel")
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	_overall_label = _label("0%", 64, COLOR_BAD)
	_overall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_add(right, _overall_label, "OverallLabel")
	var cap := _label("OVERALL SURVIVAL", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(cap)
	return row


## Panel with a title and a scrolling VBox; returns the panel, content via out.
func _panel(title: String, min_width: float, expand: bool) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	panel.custom_minimum_size.x = min_width
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = 2.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	box.add_child(_label(title, UiStyle.FONT_SIZE, UiStyle.ACCENT))
	return [panel, box]


func _build_impact() -> Control:
	var p: Array = _panel("IMPACT", 270.0, false)
	var box := p[1] as VBoxContainer
	for i: int in IMPACT_ROWS.size():
		box.add_child(_label(IMPACT_ROWS[i], UiStyle.SMALL_FONT_SIZE, Color(UiStyle.TEXT, 0.65)))
		var v := _label("-", UiStyle.FONT_SIZE, UiStyle.TEXT)
		_add(box, v, "ImpactValue%d" % i)
		_impact_values.append(v)
	return p[0] as Control


func _build_map() -> Control:
	var p: Array = _panel("SEAT MAP", 300.0, true)
	var box := p[1] as VBoxContainer
	_seat_map = SeatMap.new()
	_seat_map.custom_minimum_size = Vector2(240.0, 200.0)
	_seat_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seat_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add(box, _seat_map, "SeatMap")
	_seat_map.seat_selected.connect(_select)
	var legend := HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 16)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(legend)
	var entries: Array[Array] = [
		[SeatMap.COLOR_FATAL, "Fatal"], [SeatMap.COLOR_INJURED, "Injured"], [SeatMap.COLOR_SURVIVED, "Survived"]]
	for e: Array in entries:
		var sw := ColorRect.new()
		sw.color = e[0] as Color
		sw.custom_minimum_size = Vector2(18.0, 18.0)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		legend.add_child(sw)
		legend.add_child(_label(e[1] as String, UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT))
	return p[0] as Control


func _build_detail() -> Control:
	var p: Array = _panel("SEAT DETAIL", 330.0, false)
	var box := p[1] as VBoxContainer
	_detail_title = _label("-", 26, UiStyle.TEXT)
	_add(box, _detail_title, "DetailTitle")
	_detail_survival = _label("", UiStyle.FONT_SIZE, UiStyle.TEXT)
	_add(box, _detail_survival, "DetailSurvival")
	_detail_cause = _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	_add(box, _detail_cause, "DetailCause")
	_detail_g = _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	_detail_g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add(box, _detail_g, "DetailG")
	_detail_hic = _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	_add(box, _detail_hic, "DetailHic")
	_detail_intrusion = _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	_add(box, _detail_intrusion, "DetailIntrusion")
	_detail_fire = _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	_add(box, _detail_fire, "DetailFire")
	box.add_child(_label("Fatal injury probability", UiStyle.SMALL_FONT_SIZE, Color(UiStyle.TEXT, 0.65)))
	for name: String in PROB_ROWS:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var l := _label(name, UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
		l.custom_minimum_size.x = 110.0
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(80.0, 14.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		var val := _label("0%", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
		val.custom_minimum_size.x = 44.0
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		_prob_bars.append(bar)
		_prob_values.append(val)
	_fred_box = VBoxContainer.new()
	_fred_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fred_box.visible = false
	_add(box, _fred_box, "FredBox")
	_fred_box.add_child(_label("FRED DUMMY", UiStyle.SMALL_FONT_SIZE, UiStyle.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fred_box.add_child(grid)
	for i: int in LIMB_COUNT:
		var n := _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(n)
		grid.add_child(v)
		_limb_names.append(n)
		_limb_values.append(v)
	_fred_summary = _label("", UiStyle.SMALL_FONT_SIZE, UiStyle.TEXT)
	_fred_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fred_box.add_child(_fred_summary)
	_fred_flags = _label("", UiStyle.SMALL_FONT_SIZE, COLOR_BAD)
	_fred_box.add_child(_fred_flags)
	return p[0] as Control


func _build_replay_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	_add(self, margin, "ReplayBar")
	_replay_bar = margin
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	margin.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.001
	_scrub.custom_minimum_size = Vector2(200.0, 56.0)
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrub.value_changed.connect(func(v: float) -> void:
		if not _suppress_seek:
			replay_seek.emit(v))
	_add(row, _scrub, "ScrubBar")
	var group := ButtonGroup.new()
	for i: int in SPEEDS.size():
		var b := Button.new()
		b.text = SPEED_TEXT[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(84.0, 56.0)
		b.add_theme_font_size_override("font_size", UiStyle.FONT_SIZE)
		var speed: float = SPEEDS[i]
		b.pressed.connect(func() -> void: replay_speed_changed.emit(speed))
		_add(row, b, "Speed%d" % i)
		_speed_buttons.append(b)
	_speed_buttons[1].set_pressed_no_signal(true)
	_report_button = Button.new()
	_report_button.text = "REPORT"
	_report_button.custom_minimum_size = Vector2(130.0, 56.0)
	_report_button.add_theme_font_size_override("font_size", UiStyle.FONT_SIZE)
	_report_button.pressed.connect(func() -> void: replay_closed.emit())
	_add(row, _report_button, "ReportButton")


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, parent: Node, node_name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200.0, 72.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 26)
	_add(parent, b, node_name)
	return b


## Adds a child; its unique name is registered at the end of _build, once the
## whole subtree is in the tree (owner must be an ancestor).
func _add(parent: Node, node: Node, node_name: String) -> void:
	node.name = node_name
	parent.add_child(node)
	_named.append(node)
