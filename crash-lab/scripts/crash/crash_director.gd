class_name CrashDirector
extends Node3D
## Turns the aircraft's structural events into flying skin chunks, debris
## shards and effects, and
## decides when a crash has started and when the wreck has come to rest.

signal crash_started
signal crash_settled

## Seconds the wreck must be still before the crash counts as settled, and the
## longest a crash may run before it is called settled anyway.
const REST_TIME := 2.5
const REST_SPEED := 1.2
const MAX_CRASH_TIME := 30.0

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


func setup(target: Aircraft, quality: int, max_debris: int) -> void:
	aircraft = target
	chunks = ChunkPool.new()
	chunks.name = "Chunks"
	add_child(chunks)
	chunks.setup([70, 120, 180][clampi(quality, 0, 2)])
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
	aircraft.fire_started.connect(_on_fire_started)
	aircraft.crashed.connect(_on_crashed)


func _on_crashed() -> void:
	crash_active = true
	crash_clock = 0.0
	crash_started.emit()


func _on_part_detached(part: AircraftPart, _parent: AircraftPart, load_ratio: float) -> void:
	breaks += 1
	var pos := part.xf * part.anchor_local
	# Bigger parts and harder overloads shed more fragments.
	var count := clampi(int(2.0 + part.mass / 2500.0 + load_ratio), 2, 9)
	debris.spawn_burst(pos, part.lin_vel, 5.0 + minf(load_ratio * 2.0, 10.0), count, aircraft.def.paint)
	if pos.y - aircraft.ground_y < 6.0:
		fx.burst_dust(Vector3(pos.x, aircraft.ground_y + 0.5, pos.z), 2.0)


func _on_part_impacted(part: AircraftPart, world_pos: Vector3, _impulse: Vector3, energy: float) -> void:
	# About one fragment per 300 kJ, on top of a floor for any real hit.
	if energy > 4.0e4:
		var count := clampi(int(energy / 3.0e5) + 1, 1, 6)
		debris.spawn_burst(world_pos, part.lin_vel, 4.0 + minf(part.hit_speed * 0.25, 9.0), count,
				aircraft.def.paint)
	fx.burst_dust(world_pos, 0.8 + sqrt(energy) / 900.0)


func _on_piece_shed(part: AircraftPart, piece: SkinPiece, node: MeshInstance3D, kick: float) -> void:
	chunks.spawn(piece, part.xf, part.velocity_at(part.xf * piece.center), kick, node)


func _on_fire_started(source: FireSource) -> void:
	fx.start_fire(source)


func _physics_process(dt: float) -> void:
	if not crash_active or settled:
		return
	crash_clock += dt
	var fastest := 0.0
	for part: AircraftPart in aircraft.parts:
		if not part.sleeping:
			fastest = maxf(fastest, part.lin_vel.length_squared())
	_still_time = _still_time + dt if fastest < REST_SPEED * REST_SPEED else 0.0
	if _still_time >= REST_TIME or crash_clock >= MAX_CRASH_TIME:
		settled = true
		crash_settled.emit()
