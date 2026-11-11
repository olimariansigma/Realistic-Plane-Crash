class_name CrashRecorder
extends Node
## Records a crash and plays it back in slow motion.
##
## Recording starts when the cabin arms (about 1.2 s before impact) and runs
## at the physics rate for up to MAX_SECONDS. Each tracked body has its own
## keyframe track and only gets a key on ticks where it is actually moving,
## so parked debris and sleeping wreckage cost nothing. Skin tearing off,
## dents and fires are stored as timed events.
##
## Playback freezes the simulation (the physics server is switched off) and
## writes interpolated transforms straight onto the bodies.

signal playback_progress(fraction: float)

const MAX_SECONDS := 14.0
const KEY := 8  # floats per key: frame, position xyz, quaternion xyzw

enum EventKind { PIECE, DENT, FIRE }

var recording: bool = false
var playing: bool = false
## Playback speed relative to real time.
var speed: float = 0.25
var frames: int = 0

var _aircraft: Aircraft
var _director: CrashDirector
var _nodes: Array[Node3D] = []
## Bodies whose "is it moving" test is their sleep/freeze state.
var _bodies: Array[RigidBody3D] = []
var _always: PackedByteArray
var _tracks: Array[PackedFloat32Array] = []
var _last_key: PackedInt32Array
var _cursor: PackedInt32Array
var _tick_rate: float = 60.0
var _max_frames: int = 0

var _event_frame: PackedInt32Array
var _event_kind: PackedByteArray
var _event_data: Array = []
var _event_cursor: int = 0

var _time: float = 0.0
var _hold: float = 0.0


func setup(aircraft: Aircraft, director: CrashDirector) -> void:
	_aircraft = aircraft
	_director = director
	_tick_rate = float(Engine.physics_ticks_per_second)
	_max_frames = int(MAX_SECONDS * _tick_rate)
	for part: AircraftPart in aircraft.parts:
		_track(part, true)
	for fred: Fred in aircraft.cabin.freds:
		for limb: RigidBody3D in fred.limbs:
			_track(limb, false)
	for i: int in director.debris.body_count():
		_track(director.debris.body_at(i), false)
	for i: int in director.chunks.body_count():
		_track(director.chunks.body_at(i), false)
	_last_key.resize(_nodes.size())
	_cursor.resize(_nodes.size())
	_last_key.fill(-1)
	aircraft.piece_shed.connect(_on_piece_shed)
	aircraft.part_dented.connect(_on_part_dented)
	aircraft.fire_started.connect(_on_fire_started)
	set_physics_process(false)
	set_process(false)
	# Run after the aircraft and pools so each tick's final state is captured.
	process_physics_priority = 100


func _track(body: RigidBody3D, always: bool) -> void:
	_nodes.append(body)
	_bodies.append(body)
	_always.append(1 if always else 0)
	_tracks.append(PackedFloat32Array())


func start_recording() -> void:
	if recording or frames > 0:
		return
	recording = true
	set_physics_process(true)


func stop_recording() -> void:
	recording = false
	set_physics_process(false)


func _add_event(kind: EventKind, data: Variant) -> void:
	if not recording:
		return
	_event_frame.append(frames)
	_event_kind.append(kind)
	_event_data.append(data)


func _on_piece_shed(_part: AircraftPart, _piece: SkinPiece, node: MeshInstance3D, _kick: float) -> void:
	_add_event(EventKind.PIECE, node)


func _on_part_dented(part: AircraftPart) -> void:
	_add_event(EventKind.DENT, [part, part.dent_slot(0), part.dent_push(0), part.dent_slot(1), part.dent_push(1)])


func _on_fire_started(source: FireSource) -> void:
	_add_event(EventKind.FIRE, source)


func _physics_process(_dt: float) -> void:
	if not recording:
		return
	var frame := frames
	for i: int in _nodes.size():
		var body := _bodies[i]
		# Parts always get their first key; after that, like everything else,
		# only while awake and unfrozen.
		if body.freeze or (body.sleeping and _last_key[i] >= 0):
			continue
		if _always[i] == 0 and not body.visible and _last_key[i] < 0:
			continue
		var xf := body.global_transform
		var track := _tracks[i]
		var last := _last_key[i]
		if last >= 0 and frame - last > 1:
			# Re-waking after a pause: pin the old pose to the previous frame so
			# playback holds still across the gap instead of drifting.
			var n := track.size()
			track.append(float(frame - 1))
			for k: int in range(1, KEY):
				track.append(track[n - KEY + k])
		var q := xf.basis.get_rotation_quaternion()
		track.append(float(frame))
		track.append(xf.origin.x)
		track.append(xf.origin.y)
		track.append(xf.origin.z)
		track.append(q.x)
		track.append(q.y)
		track.append(q.z)
		track.append(q.w)
		_last_key[i] = frame
	frames += 1
	if frames >= _max_frames:
		stop_recording()


func duration() -> float:
	return float(frames) / _tick_rate


# ---------------------------------------------------------------- playback

## Freezes the simulation and starts playing from the beginning.
func play() -> void:
	if frames < 2:
		return
	stop_recording()
	if not playing:
		playing = true
		PhysicsServer3D.set_active(false)
		_aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		_director.debris.process_mode = Node.PROCESS_MODE_DISABLED
		_director.chunks.process_mode = Node.PROCESS_MODE_DISABLED
		_director.set_physics_process(false)
		for node: Node3D in _nodes:
			# Transforms are written per rendered frame, not per physics tick.
			node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	seek(0.0)
	set_process(true)


## Leaves replay on its final frame (the wreck as it came to rest).
func stop() -> void:
	if not playing:
		return
	seek(1.0)
	set_process(false)


func seek(fraction: float) -> void:
	_time = clampf(fraction, 0.0, 1.0) * duration()
	_hold = 0.0
	_rewind()
	_apply(_time * _tick_rate)


func _rewind() -> void:
	_cursor.fill(0)
	_event_cursor = 0
	for i: int in _event_frame.size():
		match _event_kind[i]:
			EventKind.PIECE:
				(_event_data[i] as MeshInstance3D).visible = true
	for part: AircraftPart in _aircraft.parts:
		part.show_dents(Vector4.ZERO, Vector3.ZERO, Vector4.ZERO, Vector3.ZERO)
	_director.fx.stop_fires()


func _process(delta: float) -> void:
	var total := duration()
	if _time >= total:
		# Hold the last frame for a moment, then loop.
		_hold += delta
		if _hold > 1.5:
			seek(0.0)
		return
	_time = minf(_time + delta * speed, total)
	_apply(_time * _tick_rate)
	playback_progress.emit(_time / total)


func _apply(frame: float) -> void:
	for i: int in _nodes.size():
		var track := _tracks[i]
		var size := track.size()
		var node := _nodes[i]
		if size == 0 or frame < track[0]:
			# Not in the scene yet at this point of the recording.
			if _always[i] == 0:
				node.visible = false
			continue
		node.visible = true
		var c := _cursor[i]
		while c + KEY < size and track[c + KEY] <= frame:
			c += KEY
		_cursor[i] = c
		var pos := Vector3(track[c + 1], track[c + 2], track[c + 3])
		var rot := Quaternion(track[c + 4], track[c + 5], track[c + 6], track[c + 7])
		if c + KEY < size:
			var n := c + KEY
			var span := track[n] - track[c]
			var t := clampf((frame - track[c]) / span, 0.0, 1.0) if span > 0.0 else 0.0
			pos = pos.lerp(Vector3(track[n + 1], track[n + 2], track[n + 3]), t)
			rot = rot.slerp(Quaternion(track[n + 4], track[n + 5], track[n + 6], track[n + 7]), t)
		node.global_transform = Transform3D(Basis(rot), pos)
	while _event_cursor < _event_frame.size() and float(_event_frame[_event_cursor]) <= frame:
		var data: Variant = _event_data[_event_cursor]
		match _event_kind[_event_cursor]:
			EventKind.PIECE:
				(data as MeshInstance3D).visible = false
			EventKind.DENT:
				var d := data as Array
				(d[0] as AircraftPart).show_dents(d[1], d[2], d[3], d[4])
			EventKind.FIRE:
				_director.fx.start_fire(data as FireSource)
		_event_cursor += 1
