class_name CrashRecorder
extends Node
## Flight recorder for the slow-motion replay.
##
## It records for the whole flight, keeping the most recent WINDOW_SECONDS,
## and the replay runs from a few seconds before the final crash began to the
## wreck coming to rest. (An earlier version started at the first contact and
## stopped 14 s later: a tail strike on take-off used up the recording and
## the real crash was never in it.)
##
## Every tracked body has a ring buffer of keyframes, allocated on first use
## and written only on ticks where the body is actually moving, so parked
## debris and sleeping wreckage cost nothing. Skin tearing off, dents and
## fires are stored as timed events.
##
## Playback freezes the simulation (the physics server is switched off) and
## writes interpolated transforms straight onto the bodies.

signal playback_progress(fraction: float)

## Long enough for a high-speed crash and the slide that follows it.
const WINDOW_SECONDS := 45.0
## Seconds of lead-in shown before the final impact when a replay starts.
const LEAD_IN := 3.0
const KEY := 8  # floats per key: frame, position xyz, quaternion xyzw
## Loose bodies (dummy limbs, debris, chunks) are keyed every Nth tick.
const LOOSE_EVERY := 3

enum EventKind { PIECE, DENT, FIRE }

var recording: bool = false
var playing: bool = false
## Playback speed relative to real time.
var speed: float = 0.25
## Physics ticks recorded so far.
var frames: int = 0

var _aircraft: Aircraft
var _director: CrashDirector
var _bodies: Array[RigidBody3D] = []
var _always: PackedByteArray
var _tracks: Array[PackedFloat32Array] = []
var _capacity: PackedInt32Array
var _head: PackedInt32Array
var _count: PackedInt32Array
var _last_frame: PackedInt32Array
var _cursor: PackedInt32Array
var _tick_rate: float = 60.0
var _window_frames: int = 0
# Index ranges of each group in _bodies: [start, end).
var _parts_end: int = 0
var _freds_end: int = 0
var _debris_end: int = 0

var _event_frame: PackedInt32Array
var _event_kind: PackedByteArray
var _event_data: Array = []
var _event_cursor: int = 0
var _event_start: int = 0
var _crash_frame: int = -1
var _stop_frame: int = -1

var _first_frame: int = 0
var _time: float = 0.0
var _hold: float = 0.0


func setup(aircraft: Aircraft, director: CrashDirector) -> void:
	_aircraft = aircraft
	_director = director
	_tick_rate = float(Engine.physics_ticks_per_second)
	_window_frames = int(WINDOW_SECONDS * _tick_rate)
	for part: AircraftPart in aircraft.parts:
		_track(part, true, _window_frames)
	_parts_end = _bodies.size()
	var loose := _window_frames / LOOSE_EVERY + 2
	for fred: Fred in aircraft.cabin.freds:
		for limb: RigidBody3D in fred.limbs:
			_track(limb, false, loose)
	_freds_end = _bodies.size()
	for i: int in director.debris.body_count():
		_track(director.debris.body_at(i), false, loose)
	_debris_end = _bodies.size()
	for i: int in director.chunks.body_count():
		_track(director.chunks.body_at(i), false, loose)
	var total := _bodies.size()
	_head.resize(total)
	_count.resize(total)
	_last_frame.resize(total)
	_cursor.resize(total)
	_last_frame.fill(-1)
	aircraft.piece_shed.connect(_on_piece_shed)
	aircraft.part_dented.connect(_on_part_dented)
	aircraft.fire_started.connect(_on_fire_started)
	aircraft.crashed.connect(_on_crashed)
	aircraft.major_impact.connect(_on_crashed)
	set_physics_process(false)
	set_process(false)
	# Run after the aircraft and pools so each tick's final state is captured.
	process_physics_priority = 100


func _track(body: RigidBody3D, always: bool, capacity: int) -> void:
	_bodies.append(body)
	_always.append(1 if always else 0)
	_tracks.append(PackedFloat32Array())
	_capacity.append(capacity)


func start_recording() -> void:
	if recording or playing:
		return
	recording = true
	set_physics_process(true)


func stop_recording() -> void:
	recording = false
	_stop_frame = -1
	set_physics_process(false)


## Keeps recording for `seconds` more, then stops: the wreck is still creeping
## when it is declared at rest, and the replay should end where it ends up.
func stop_recording_after(seconds: float) -> void:
	if recording:
		_stop_frame = frames + int(seconds * _tick_rate)


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


func _on_crashed() -> void:
	_crash_frame = frames


func _physics_process(_dt: float) -> void:
	if not recording:
		return
	var frame := frames
	frames += 1
	if _stop_frame >= 0 and frame >= _stop_frame:
		stop_recording()
		return
	_record_range(0, _parts_end, frame)
	if frame % LOOSE_EVERY != 0:
		return
	# Loose bodies only exist in the scene once something has happened.
	if _aircraft.cabin.armed:
		_record_range(_parts_end, _freds_end, frame)
	if _director.debris.flying_count > 0:
		_record_range(_freds_end, _debris_end, frame)
	if _director.chunks.flying_count > 0:
		_record_range(_debris_end, _bodies.size(), frame)


func _record_range(from: int, to: int, frame: int) -> void:
	for i: int in range(from, to):
		var body := _bodies[i]
		# A frozen body is parked or settled; a sleeping one has not moved
		# since its last key.
		if body.freeze or (body.sleeping and _last_frame[i] >= 0):
			continue
		var track := _tracks[i]
		var capacity := _capacity[i]
		if track.is_empty():
			track.resize(capacity * KEY)
			_tracks[i] = track
		var last := _last_frame[i]
		var gap := 1 if _always[i] == 1 else LOOSE_EVERY
		if last >= 0 and frame - last > gap:
			# Re-waking after a pause: pin the old pose to just before now, so
			# playback holds still across the gap instead of drifting.
			var prev := posmod(_head[i] - 1, capacity) * KEY
			var slot := _head[i] * KEY
			track[slot] = float(frame - gap)
			for k: int in range(1, KEY):
				track[slot + k] = track[prev + k]
			_head[i] = (_head[i] + 1) % capacity
			_count[i] = mini(_count[i] + 1, capacity)
		var xf := body.global_transform
		var q := xf.basis.get_rotation_quaternion()
		var at := _head[i] * KEY
		track[at] = float(frame)
		track[at + 1] = xf.origin.x
		track[at + 2] = xf.origin.y
		track[at + 3] = xf.origin.z
		track[at + 4] = q.x
		track[at + 5] = q.y
		track[at + 6] = q.z
		track[at + 7] = q.w
		_head[i] = (_head[i] + 1) % capacity
		_count[i] = mini(_count[i] + 1, capacity)
		_last_frame[i] = frame


## Length of the replay in seconds (at most WINDOW_SECONDS).
func duration() -> float:
	return float(frames - _first_frame) / _tick_rate


# ---------------------------------------------------------------- playback

## Freezes the simulation and starts the replay just before the final crash.
func play() -> void:
	if frames < 2:
		return
	stop_recording()
	if not playing:
		playing = true
		# From the lead-in to the final crash, or as far back as is kept.
		_first_frame = maxi(frames - _window_frames, 0)
		if _crash_frame >= 0:
			_first_frame = maxi(_first_frame, _crash_frame - int(LEAD_IN * _tick_rate))
		_event_start = 0
		while _event_start < _event_frame.size() and _event_frame[_event_start] < _first_frame:
			_event_start += 1
		PhysicsServer3D.set_active(false)
		_aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		_director.debris.process_mode = Node.PROCESS_MODE_DISABLED
		_director.chunks.process_mode = Node.PROCESS_MODE_DISABLED
		_director.set_physics_process(false)
		for body: RigidBody3D in _bodies:
			# Transforms are written per rendered frame, not per physics tick.
			body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	_apply(float(_first_frame) + _time * _tick_rate)


## Puts the scene into its state at the start of the window: everything that
## happened before it stays done, everything inside it is undone.
func _rewind() -> void:
	_cursor.fill(0)
	_event_cursor = _event_start
	_director.fx.stop_fires()
	for part: AircraftPart in _aircraft.parts:
		part.show_dents(Vector4.ZERO, Vector3.ZERO, Vector4.ZERO, Vector3.ZERO)
	for i: int in _event_frame.size():
		var data: Variant = _event_data[i]
		var before := i < _event_start
		match _event_kind[i]:
			EventKind.PIECE:
				(data as MeshInstance3D).visible = not before
			EventKind.DENT:
				if before:
					var d := data as Array
					(d[0] as AircraftPart).show_dents(d[1], d[2], d[3], d[4])
			EventKind.FIRE:
				if before:
					_director.fx.start_fire(data as FireSource)


func _process(delta: float) -> void:
	var total := duration()
	if _time >= total:
		# Hold the last frame for a moment, then loop.
		_hold += delta
		if _hold > 1.5:
			seek(0.0)
		return
	_time = minf(_time + delta * speed, total)
	_apply(float(_first_frame) + _time * _tick_rate)
	playback_progress.emit(_time / maxf(total, 0.001))


func _apply(frame: float) -> void:
	for i: int in _bodies.size():
		var count := _count[i]
		var body := _bodies[i]
		if count == 0:
			if _always[i] == 0:
				body.visible = false
			continue
		var track := _tracks[i]
		var capacity := _capacity[i]
		var oldest := posmod(_head[i] - count, capacity)
		if frame < track[oldest * KEY]:
			# Not in the scene yet at this point of the recording.
			if _always[i] == 0:
				body.visible = false
			continue
		body.visible = true
		var c := _cursor[i]
		while c + 1 < count and track[((oldest + c + 1) % capacity) * KEY] <= frame:
			c += 1
		_cursor[i] = c
		var a := ((oldest + c) % capacity) * KEY
		var pos := Vector3(track[a + 1], track[a + 2], track[a + 3])
		var rot := Quaternion(track[a + 4], track[a + 5], track[a + 6], track[a + 7])
		if c + 1 < count:
			var b := ((oldest + c + 1) % capacity) * KEY
			var span := track[b] - track[a]
			var t := clampf((frame - track[a]) / span, 0.0, 1.0) if span > 0.0 else 0.0
			pos = pos.lerp(Vector3(track[b + 1], track[b + 2], track[b + 3]), t)
			rot = rot.slerp(Quaternion(track[b + 4], track[b + 5], track[b + 6], track[b + 7]), t)
		body.global_transform = Transform3D(Basis(rot), pos)
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
