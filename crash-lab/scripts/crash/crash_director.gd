class_name CrashDirector
extends Node3D
## Turns the aircraft's structural events into flying skin chunks, debris
## shards and effects, and
## decides when a crash has started and when the wreck has come to rest.

signal crash_started
signal crash_settled
## The aircraft flew away from a minor contact: the crash state is cleared.
signal crash_cancelled

## The wreck is at rest once it has visibly stopped: the main wreck, every
## part that carries seats, and all but STRAGGLER_SHARE of the airframe's mass
## slower than REST_SPEED (m/s) for REST_TIME seconds. Light pieces still
## moving (a wheel, a fin toppling over) do not hold the report up; Aircraft
## keeps braking them after rest().
const REST_TIME := 1.0
const REST_SPEED := 1.2
const STRAGGLER_SHARE := 0.05
## Seconds the main wreck alone must be still, if loose parts keep moving.
const ROOT_REST_TIME := 10.0
## Intact, off the ground and faster than this (m/s) for RECOVERY_TIME: the
## contact was an incident, not a crash.
const FLYING_SPEED := 30.0
const RECOVERY_TIME := 4.0
## Chunk spawn queue length and how many are released per physics tick.
const QUEUE_SIZE := 256
const SPAWNS_PER_TICK := 6

var aircraft: Aircraft
var debris: DebrisPool
var chunks: ChunkPool
var fx: FxPool
var crash_active: bool = false
var settled: bool = false
## Seconds since the crash began.
var crash_clock: float = 0.0
var breaks: int = 0

var _still_time: float = 0.0
var _root_still_time: float = 0.0
var _flying_time: float = 0.0
## 1 for each part that carries seats: the report is about the occupants, and
## the cabin stops logging at rest, so those parts must have stopped too.
var _occupied: PackedByteArray = PackedByteArray()
var _q_piece: Array[SkinPiece] = []
var _q_node: Array[MeshInstance3D] = []
var _q_xf: Array[Transform3D] = []
var _q_vel: PackedVector3Array
var _q_kick: PackedFloat32Array
var _queued: int = 0
var _ticks_fx: int = 0
var _released: int = 0


func setup(target: Aircraft, quality: int, max_debris: int) -> void:
	aircraft = target
	aircraft.shed_room = shed_room
	chunks = ChunkPool.new()
	chunks.name = "Chunks"
	add_child(chunks)
	chunks.setup([120, 240, 320][clampi(quality, 0, 2)])
	_q_piece.resize(QUEUE_SIZE)
	_q_node.resize(QUEUE_SIZE)
	_q_xf.resize(QUEUE_SIZE)
	_q_vel.resize(QUEUE_SIZE)
	_q_kick.resize(QUEUE_SIZE)
	aircraft.piece_shed.connect(_on_piece_shed)
	debris = DebrisPool.new()
	debris.name = "Debris"
	add_child(debris)
	debris.setup(max_debris)
	fx = FxPool.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(quality)
	aircraft.part_detached.connect(_on_part_detached)
	aircraft.part_impacted.connect(_on_part_impacted)
	aircraft.part_cracked.connect(_on_part_cracked)
	aircraft.tyre_burst.connect(_on_tyre_burst)
	aircraft.fire_started.connect(_on_fire_started)
	aircraft.crashed.connect(_on_crashed)
	_occupied.resize(aircraft.parts.size())
	_occupied.fill(0)
	for seat: Seat in aircraft.cabin.seats:
		_occupied[seat.part_index] = 1


func _on_crashed() -> void:
	crash_active = true
	crash_clock = 0.0
	_flying_time = 0.0
	crash_started.emit()


func _on_part_detached(part: AircraftPart, _parent: AircraftPart, load_ratio: float) -> void:
	breaks += 1
	var pos := part.xf * part.anchor_local
	# Bigger parts and harder overloads shed more fragments.
	var count := clampi(int(2.0 + part.mass / 2500.0 + load_ratio), 2, 9)
	debris.spawn_burst(pos, part.lin_vel, 5.0 + minf(load_ratio * 2.0, 10.0), count, aircraft.def.paint)
	if pos.y - aircraft.ground_y < 6.0:
		fx.burst_dust(Vector3(pos.x, aircraft.ground_y + 0.5, pos.z), 2.0)


## A tyre blow-out: shreds of rubber and a puff of smoke and dust.
func _on_tyre_burst(gear: GearUnit, world_pos: Vector3) -> void:
	debris.spawn_burst(world_pos + Vector3(0.0, 0.4, 0.0), gear.part.lin_vel, 7.0, 3, MeshFactory.TYRE.darkened(0.5))
	fx.burst_dust(world_pos + Vector3(0.0, 0.3, 0.0), 1.5)


func _on_part_cracked(part: AircraftPart) -> void:
	var pos := part.xf * part.anchor_local
	debris.spawn_burst(pos, part.lin_vel, 4.0, 2, aircraft.def.paint)
	if pos.y - aircraft.ground_y < 6.0:
		fx.burst_dust(Vector3(pos.x, aircraft.ground_y + 0.5, pos.z), 1.2)


func _on_part_impacted(part: AircraftPart, world_pos: Vector3, _impulse: Vector3, energy: float) -> void:
	# About one fragment per 300 kJ, on top of a floor for any real hit.
	if energy > 4.0e4:
		var count := clampi(int(energy / 3.0e5) + 1, 1, 6)
		debris.spawn_burst(world_pos, part.lin_vel, 4.0 + minf(part.hit_speed * 0.25, 9.0), count,
				aircraft.def.paint)
	fx.burst_dust(world_pos, 0.8 + sqrt(energy) / 900.0)


## Spawning a chunk swaps a mesh and copies shader parameters; a hard hit can
## shed dozens at once, so they are queued and released a few per tick.
## Skin pieces that can still be torn off now: a chunk body must be free for
## each, counting the ones already queued. Wired into Aircraft.shed_room.
func shed_room() -> int:
	return mini(chunks.room() - (_queued - _released), QUEUE_SIZE - (_queued - _released))


func _on_piece_shed(part: AircraftPart, piece: SkinPiece, node: MeshInstance3D, kick: float) -> void:
	if _queued - _released >= QUEUE_SIZE:
		return
	var slot := _queued % QUEUE_SIZE
	_q_piece[slot] = piece
	_q_node[slot] = node
	_q_xf[slot] = part.xf
	_q_vel[slot] = part.velocity_at(part.xf * piece.center)
	_q_kick[slot] = kick
	_queued += 1


func _release_chunks() -> void:
	var budget := SPAWNS_PER_TICK
	while _released < _queued and budget > 0:
		var slot := _released % QUEUE_SIZE
		# A chunk released a few ticks late starts where its part has moved on from.
		chunks.spawn(_q_piece[slot], _q_xf[slot], _q_vel[slot], _q_kick[slot], _q_node[slot])
		if _q_piece[slot].structure:
			# Torn-out frames and spars leave a spray of clips, brackets and
			# fasteners behind.
			var at := _q_xf[slot] * _q_piece[slot].center
			debris.spawn_burst(at, _q_vel[slot], 3.0 + _q_kick[slot] * 0.5, 2, MeshFactory.PRIMER)
		_q_piece[slot] = null
		_q_node[slot] = null
		_released += 1
		budget -= 1


## Picks up to FxPool.SCRAPE_SLOTS metal-on-ground scrapes (parts sliding in
## contact, gears running on burst rims) for the sparks and soil spray.
func _sample_scrapes() -> void:
	var slot := 0
	for part: AircraftPart in aircraft.parts:
		if slot >= FxPool.SCRAPE_SLOTS:
			break
		if part.contact_count == 0 or part.sleeping or (part.def.kind == PartDef.Kind.GEAR and part.joint != null):
			continue
		var v := part.velocity_at(part.hit_position)
		v.y = 0.0
		var slide := v.length()
		if slide < 6.0:
			continue
		fx.set_scrape(slot, part.hit_position, v, clampf(slide / 50.0, 0.25, 1.0))
		slot += 1
	for gear: GearUnit in aircraft.gears:
		if slot >= FxPool.SCRAPE_SLOTS:
			break
		if gear.burst and gear.on_ground and gear.ground_speed > 6.0:
			var v := gear.part.lin_vel
			v.y = 0.0
			fx.set_scrape(slot, gear.contact, v, clampf(gear.ground_speed / 60.0, 0.2, 0.8))
			slot += 1


func _on_fire_started(source: FireSource) -> void:
	fx.start_fire(source)


func _physics_process(dt: float) -> void:
	_release_chunks()
	if not aircraft.resting and _ticks_fx % 3 == 0:
		_sample_scrapes()
	_ticks_fx += 1
	# An intact aircraft with the throttle open is being driven, not wrecked:
	# it never counts as at rest, and one declared at rest wakes up again (a
	# nacelle scraping the runway on burst tyres is an incident, not a crash).
	var driven := aircraft.controls.throttle > 0.2 and aircraft.is_intact()
	if settled and driven:
		settled = false
		crash_active = false
		_still_time = 0.0
		_root_still_time = 0.0
		aircraft.wake()
		aircraft.clear_incident()
		crash_cancelled.emit()
		return
	if not crash_active or settled:
		return
	crash_clock += dt
	var total_mass := 0.0
	var moving_mass := 0.0
	var occupants_moving := false
	for i: int in aircraft.parts.size():
		var part := aircraft.parts[i]
		total_mass += part.mass
		if not part.sleeping and part.lin_vel.length_squared() >= REST_SPEED * REST_SPEED:
			moving_mass += part.mass
			occupants_moving = occupants_moving or _occupied[i] == 1
	var root_speed := aircraft.root_part.lin_vel.length()

	# An incident, not a crash: nothing structural failed and the aircraft is
	# flying again. Stand down so the flight simply carries on.
	var intact := aircraft.joints_alive == aircraft.parts.size() - 1
	if intact and root_speed > FLYING_SPEED and not aircraft.body_contact \
			and not aircraft.telemetry.on_ground:
		_flying_time += dt
		if _flying_time >= RECOVERY_TIME:
			crash_active = false
			_flying_time = 0.0
			_still_time = 0.0
			aircraft.clear_incident()
			crash_cancelled.emit()
			return
	else:
		_flying_time = 0.0

	# Settled: the heavy wreckage still, or the main wreck still for a long
	# while with only stragglers moving. There is no time limit while it moves.
	var still := not driven and root_speed < REST_SPEED and not occupants_moving \
			and moving_mass <= total_mass * STRAGGLER_SHARE
	_still_time = _still_time + dt if still else 0.0
	_root_still_time = _root_still_time + dt if root_speed < REST_SPEED and not driven else 0.0
	if _still_time >= REST_TIME or _root_still_time >= ROOT_REST_TIME:
		settled = true
		aircraft.rest()
		crash_settled.emit()
