class_name FailurePanel
extends PanelContainer
## The FAIL menu: triggers a failure on any component of the aircraft while it
## flies (or sits) - engine flame-out, engine fire, an engine, wing, tail or
## fuselage section breaking off or cracking, tyres bursting, gear
## collapsing, the flight controls jamming. Built in code from the aircraft,
## so every type gets the list that matches its parts.

signal closed
## A failure was triggered: the component and the action, for the warning.
signal triggered(component: String, action: String)

const ROW_HEIGHT := 50.0

var _aircraft: Aircraft
## Each button and the (kind, index) it triggers.
var _buttons: Array[Button] = []
var _kinds: PackedInt32Array = PackedInt32Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _list: VBoxContainer


func setup(aircraft: Aircraft) -> void:
	_aircraft = aircraft
	add_theme_stylebox_override(&"panel", UiStyle.panel_box(Color(0.06, 0.075, 0.1, 0.95)))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "FAILURES"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", UiStyle.FONT_SIZE)
	title.add_theme_color_override("font_color", UiStyle.TEXT)
	header.add_child(title)
	var close := _make_button("CLOSE")
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_row("Flight controls", [["JAM", Aircraft.Failure.CONTROLS_JAM, 0]])
	for i: int in aircraft.engines.size():
		var part_index := aircraft.engines[i].part.index
		_row(pretty_name(aircraft.engines[i].part.name), [
				["FLAME-OUT", Aircraft.Failure.FLAME_OUT, i],
				["FIRE", Aircraft.Failure.ENGINE_FIRE, i],
				["SEPARATE", Aircraft.Failure.BREAK_OFF, part_index]])
	for part: AircraftPart in aircraft.parts:
		var kind := part.def.kind
		if part.parent_index < 0 or kind == PartDef.Kind.ENGINE or kind == PartDef.Kind.GEAR:
			continue
		var actions: Array = []
		if kind != PartDef.Kind.CANOPY:
			actions.append(["CRACK", Aircraft.Failure.CRACK, part.index])
		actions.append(["BREAK OFF", Aircraft.Failure.BREAK_OFF, part.index])
		_row(pretty_name(part.name), actions)
	for g: int in aircraft.gears.size():
		var gear := aircraft.gears[g]
		_row(pretty_name(gear.part.name), [
				["BURST TYRES", Aircraft.Failure.TYRES, g],
				["COLLAPSE", Aircraft.Failure.BREAK_OFF, gear.part.index]])
	refresh()


## Greys out every failure that no longer applies.
func refresh() -> void:
	for k: int in _buttons.size():
		_buttons[k].disabled = not _aircraft.failure_available(_kinds[k] as Aircraft.Failure, _indices[k])


## "wing_l_out" -> "Left wing outer", "engine_r2" -> "Engine R2", ...
static func pretty_name(part_name: StringName) -> String:
	var raw := String(part_name)
	if raw.begins_with("engine_"):
		return "Engine " + raw.trim_prefix("engine_").to_upper()
	var named := {
		"fus_nose": "Nose section", "fus_fwd": "Forward fuselage", "fus_fwd2": "Forward fuselage 2",
		"fus_fwd3": "Forward fuselage 3", "fus_mid": "Centre fuselage", "fus_mid_aft": "Centre fuselage (aft)",
		"fus_aft": "Aft fuselage", "fus_aft2": "Aft fuselage 2", "fus_aft3": "Aft fuselage 3",
		"fus_tail": "Tail section", "fin": "Fin", "canopy": "Canopy", "gear_nose": "Nose gear",
	}
	if named.has(raw):
		return named[raw]
	var side := ""
	if raw.ends_with("_l") or raw.contains("_l_"):
		side = "Left "
	elif raw.ends_with("_r") or raw.contains("_r_"):
		side = "Right "
	var what := raw
	for pair: Array in [["gear_main", "main gear"], ["hstab", "stabiliser"], ["wing", "wing"]]:
		if raw.begins_with(pair[0]):
			what = pair[1]
	if raw.ends_with("_in"):
		what += " inner"
	elif raw.ends_with("_mid"):
		what += " middle"
	elif raw.ends_with("_out"):
		what += " outer"
	var text := side + what
	return text.substr(0, 1).to_upper() + text.substr(1)


func _row(label_text: String, actions: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190.0, ROW_HEIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UiStyle.TEXT)
	row.add_child(label)
	for a: Array in actions:
		var b := _make_button(String(a[0]))
		var kind := int(a[1])
		var index := int(a[2])
		var action := String(a[0])
		b.pressed.connect(func() -> void:
			if _aircraft.trigger_failure(kind as Aircraft.Failure, index):
				triggered.emit(label_text, action)
			refresh())
		row.add_child(b)
		_buttons.append(b)
		_kinds.append(kind)
		_indices.append(index)
	_list.add_child(row)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	b.add_theme_font_size_override("font_size", 17)
	b.focus_mode = Control.FOCUS_NONE
	UiStyle.style_button(b)
	return b
