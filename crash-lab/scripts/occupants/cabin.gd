class_name Cabin
extends RefCounted
## Everything inside the fuselage: seats, the cutaway liner, FRED dummies, and
## the per-seat acceleration log.
##
## Seat tracking and dummies are "armed" just before an impact (see
## Aircraft._update_arming) rather than running all flight: hundreds of seats
## and dozens of ragdoll bodies are only worth simulating when something is
## about to happen to them.

const HIP_HEIGHT := 0.47
const SEAT_LETTERS := "ABCDEFGHJK"
const GRAVITY := 9.80665
## Time constant of the seat-level acceleration filter. A rigid-body impact
## stops in one or two physics ticks; a real airframe crushes over ~0.1-0.2 s.
## With 0.085 s, the 13.4 m/s velocity change of the 14 CFR 25.562 seat test
## reads as its specified 16 g peak.
const SEAT_FILTER_TAU := 0.085

static var _seat_mesh: ArrayMesh
static var _interior_material: ShaderMaterial

var seats: Array[Seat] = []
var freds: Array[Fred] = []
var armed: bool = false
## Aircraft.sim_time when the cabin was armed.
var armed_time: float = -1.0

var _nodes: Array[Node3D] = []
var _visible: bool = false


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


static func _interior_mat() -> ShaderMaterial:
	if _interior_material == null:
		_interior_material = ShaderMaterial.new()
		_interior_material.shader = load("res://shaders/interior.gdshader") as Shader
	return _interior_material


## Liner and seats for one fuselage part, positioned for a parent whose origin
## is the part's centre of mass. Returns the created nodes.
static func _build_part_interior(def: AircraftDef, part_index: int, all_seats: Array[Seat]) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var part := def.parts[part_index]
	var mine: Array[Seat] = []
	var floor_y := 1.0e9
	for seat: Seat in all_seats:
		if seat.part_index == part_index:
			mine.append(seat)
			floor_y = minf(floor_y, seat.def_pos.y - HIP_HEIGHT)
	if mine.is_empty():
		return out
	var liner := MeshInstance3D.new()
	liner.name = "Liner"
	liner.mesh = MeshFactory.interior_mesh(part, floor_y)
	liner.material_override = _interior_mat()
	liner.set_instance_shader_parameter(&"cut_plane_x", -part.com.x)
	liner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	liner.visibility_range_end = 400.0
	out.append(liner)

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
	out.append(mmi)
	return out


## Builds the live cabin onto an aircraft's fuselage parts.
func build(aircraft: Aircraft, max_freds: int) -> void:
	var def := aircraft.def
	seats = list_seats(def)
	for seat: Seat in seats:
		seat.part = aircraft.parts[seat.part_index]
	for i: int in def.parts.size():
		if def.parts[i].kind != PartDef.Kind.FUSELAGE:
			continue
		for node: Node3D in _build_part_interior(def, i, seats):
			node.visible = false
			aircraft.parts[i].add_child(node)
			_nodes.append(node)
	var picks := def.fred_seats
	for k: int in mini(picks.size(), max_freds):
		var index := picks[k]
		if index < 0 or index >= seats.size() or seats[index].fred != null:
			continue
		var fred := Fred.new()
		aircraft.add_child(fred)
		fred.setup(seats[index], seats[index].part)
		freds.append(fred)


## Adds liner, seats and static dummies to a hangar display model.
static func build_display(def: AircraftDef, model: Node3D, max_freds: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var all_seats := list_seats(def)
	for i: int in def.parts.size():
		if def.parts[i].kind != PartDef.Kind.FUSELAGE:
			continue
		var holder := model.get_node_or_null(String(def.parts[i].name)) as Node3D
		if holder == null:
			continue
		for node: Node3D in _build_part_interior(def, i, all_seats):
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


## Shows or hides the cabin interior (cutaway view).
func set_visible(enabled: bool) -> void:
	_visible = enabled
	for node: Node3D in _nodes:
		node.visible = enabled
	for fred: Fred in freds:
		fred.visible = enabled or fred.ejected


## Starts per-seat tracking and wakes the dummies. Idempotent.
func arm(sim_time: float) -> void:
	if armed:
		return
	armed = true
	armed_time = sim_time
	for fred: Fred in freds:
		fred.activate()


func tick(dt: float) -> void:
	if not armed:
		# Dormant dummies only need posing when someone can see them.
		if _visible:
			for fred: Fred in freds:
				fred.sync_pose()
		return
	var alpha := 1.0 - exp(-dt / SEAT_FILTER_TAU)
	var inv_dt := 1.0 / dt
	for i: int in seats.size():
		track_seat(seats[i], alpha, inv_dt)
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
