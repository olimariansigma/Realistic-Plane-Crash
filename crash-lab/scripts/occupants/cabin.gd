class_name Cabin
extends RefCounted
## Everything inside the fuselage: seats, FRED dummies, and
## the per-seat acceleration log.
##
## Seat tracking and dummies are "armed" just before an impact (see
## Aircraft._update_arming) rather than running all flight: hundreds of seats
## and dozens of ragdoll bodies are only worth simulating when something is
## about to happen to them.

const HIP_HEIGHT := 0.47
const SEAT_LETTERS := "ABCDEFGHJK"
const GRAVITY := 9.80665
## Dummies woken per physics tick once the cabin is armed.
const WAKE_PER_TICK := 2
## Seat-level acceleration is low-passed, because a rigid-body impact stops in
## one or two physics ticks where a real airframe crushes for ~0.1 s. The
## time constant matches the response of the seat mount on the same part,
## tau = 1 / (0.8 * omega) (see Fred.mount_omega): 0.085 s for 0.75 m of
## crush, so the 13.4 m/s stop of the 14 CFR 25.562 seat test reads near its
## 16 g. Stiffer structure (less crush room) gives a shorter tau and more g.
static func filter_tau(crush_depth: float) -> float:
	return 1.0 / (0.8 * Fred.mount_omega(crush_depth))


static var _seat_mesh: ArrayMesh

var seats: Array[Seat] = []
var freds: Array[Fred] = []
var armed: bool = false
## Aircraft.sim_time when the cabin was armed.
var armed_time: float = -1.0

var _seat_nodes: Array[MultiMeshInstance3D] = []
var _parts: Array[AircraftPart] = []
var _visible: bool = false
var _wake_next: int = 1 << 30
var _finished: bool = false


## Flattens the def's seat blocks into seats (aircraft-frame positions only).
static func list_seats(def: AircraftDef) -> Array[Seat]:
	var out: Array[Seat] = []
	for block: SeatBlockDef in def.seat_blocks:
		var part_index := def.find_part(block.part)
		for r: int in block.rows:
			for c: int in block.abreast.size():
				var seat := Seat.new()
				seat.index = out.size()
				seat.is_crew = block.is_crew
				seat.row = block.first_row + r
				seat.column = c
				seat.part_index = maxi(part_index, 0)
				seat.def_pos = Vector3(block.abreast[c], block.floor_y + HIP_HEIGHT,
						block.z_start + block.pitch * float(r))
				seat.local_pos = seat.def_pos - def.parts[seat.part_index].com
				if block.is_crew:
					seat.label = ["CPT", "F/O", "JMP"][mini(c, 2)] if block.abreast.size() > 1 else "PLT"
				else:
					seat.label = "%d%s" % [seat.row, SEAT_LETTERS[mini(c, SEAT_LETTERS.length() - 1)]]
				out.append(seat)
	return out


## Seat rows for one fuselage part, positioned for a parent whose origin is
## the part's centre of mass. Returns null when the part has no seats.
static func _build_part_seats(def: AircraftDef, part_index: int, all_seats: Array[Seat]) -> MultiMeshInstance3D:
	var mine: Array[Seat] = []
	for seat: Seat in all_seats:
		if seat.part_index == part_index:
			mine.append(seat)
	if mine.is_empty():
		return null
	if _seat_mesh == null:
		_seat_mesh = MeshFactory.seat_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _seat_mesh
	mm.instance_count = mine.size()
	for i: int in mine.size():
		var seat := mine[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				seat.local_pos - Vector3(0.0, HIP_HEIGHT, 0.0)))
		mm.set_instance_color(i, Color(0.2, 0.22, 0.26) if seat.is_crew else def.accent.lerp(Color(0.25, 0.27, 0.32), 0.45))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Seats"
	mmi.multimesh = mm
	mmi.material_override = AirframeBuilder.material()
	mmi.set_instance_shader_parameter(&"cut_plane_x", 1.0e6)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 300.0
	return mmi


## Builds the live cabin onto an aircraft's fuselage parts.
func build(aircraft: Aircraft, max_freds: int) -> void:
	var def := aircraft.def
	_parts = aircraft.parts
	seats = list_seats(def)
	for seat: Seat in seats:
		seat.part = aircraft.parts[seat.part_index]
	_seat_nodes.resize(def.parts.size())
	for i: int in def.parts.size():
		if def.parts[i].kind != PartDef.Kind.FUSELAGE:
			continue
		var node := _build_part_seats(def, i, seats)
		if node != null:
			node.visible = false
			aircraft.parts[i].add_child(node)
			_seat_nodes[i] = node
	var picks := def.fred_seats
	for k: int in mini(picks.size(), max_freds):
		var index := picks[k]
		if index < 0 or index >= seats.size() or seats[index].fred != null:
			continue
		var fred := Fred.new()
		aircraft.add_child(fred)
		fred.setup(seats[index], seats[index].part)
		freds.append(fred)


## Adds seats and static dummies to a hangar display model. Returns the nodes
## the cutaway toggle should show and hide (including each part's structure).
static func build_display(def: AircraftDef, model: Node3D, max_freds: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var all_seats := list_seats(def)
	for i: int in def.parts.size():
		if def.parts[i].kind != PartDef.Kind.FUSELAGE:
			continue
		var holder := model.get_node_or_null(String(def.parts[i].name)) as Node3D
		if holder == null:
			continue
		var core := holder.get_node_or_null("Visual/Core") as Node3D
		if core != null:
			out.append(core)
		var node := _build_part_seats(def, i, all_seats)
		if node != null:
			node.visible = false
			holder.add_child(node)
			out.append(node)
	var picks := def.fred_seats
	for k: int in mini(picks.size(), max_freds):
		var index := picks[k]
		if index < 0 or index >= all_seats.size():
			continue
		var dummy := Fred.build_static()
		dummy.position = all_seats[index].def_pos
		dummy.visible = false
		model.add_child(dummy)
		out.append(dummy)
	return out


## Shows or hides the cabin interior (cutaway view). Parts that have lost
## skin keep theirs visible regardless.
func set_visible(enabled: bool) -> void:
	_visible = enabled
	for i: int in _seat_nodes.size():
		var part := _parts[i]
		var show := enabled or part.stripped
		if _seat_nodes[i] != null:
			_seat_nodes[i].visible = show
		if part.def.kind == PartDef.Kind.FUSELAGE and part.core_node != null:
			part.core_node.visible = show
	for fred: Fred in freds:
		fred.visible = enabled or fred.ejected or fred.anchor.stripped


## Called when a part first loses skin: its seats and dummies are now in view.
func reveal_part(part_index: int) -> void:
	if part_index < _seat_nodes.size() and _seat_nodes[part_index] != null:
		_seat_nodes[part_index].visible = true
	for fred: Fred in freds:
		if fred.anchor.index == part_index:
			fred.visible = true


## Starts per-seat tracking and queues the dummies to wake. Idempotent.
func arm(sim_time: float) -> void:
	if armed:
		return
	armed = true
	armed_time = sim_time
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for seat: Seat in seats:
		seat.filter_alpha = 1.0 - exp(-dt / filter_tau(seat.part.def.crush_depth))
	_wake_next = 0


## Stops all tracking once the wreck has come to rest.
func stand_down() -> void:
	_finished = true


func tick(dt: float) -> void:
	if not armed:
		# Dormant dummies only need posing when someone can see them.
		if _visible:
			for fred: Fred in freds:
				fred.sync_pose()
		return
	if _finished:
		return
	# Waking a dummy unfreezes nine bodies and wires nine joints; doing them
	# all on one tick is a visible hitch, so they wake a few per tick.
	var woken := 0
	while _wake_next < freds.size() and woken < WAKE_PER_TICK:
		freds[_wake_next].activate()
		_wake_next += 1
		woken += 1
	var inv_dt := 1.0 / dt
	for i: int in seats.size():
		track_seat(seats[i], seats[i].filter_alpha, inv_dt)
	for fred: Fred in freds:
		fred.tick(dt)


## Advances one seat's acceleration log by a tick.
static func track_seat(seat: Seat, alpha: float, inv_dt: float) -> void:
	var part := seat.part
	var basis := part.xf.basis
	var v := part.lin_vel + part.ang_vel.cross(basis * seat.local_pos)
	if not seat.has_prev:
		seat.prev_vel = v
		seat.has_prev = true
		return
	var a := seat.accel.lerp((v - seat.prev_vel) * inv_dt + Vector3(0.0, GRAVITY, 0.0), alpha)
	seat.prev_vel = v
	seat.accel = a
	var g := a.length() / GRAVITY
	if g > seat.peak_g:
		seat.peak_g = g
	var local := (a * basis) / GRAVITY
	var peak := seat.peak_axes
	if absf(local.x) > peak.x:
		peak.x = absf(local.x)
	if absf(local.y) > peak.y:
		peak.y = absf(local.y)
	if absf(local.z) > peak.z:
		peak.z = absf(local.z)
	seat.peak_axes = peak
