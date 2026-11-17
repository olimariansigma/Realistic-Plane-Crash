class_name Aircraft
extends Node3D
## A flyable, breakable aircraft built from an AircraftDef.
##
## Each physics tick: read every part's state, let the structure monitor judge
## last step's joint loads, then apply this tick's aerodynamic, thrust and
## gear forces. Nothing here ever sets a transform or a velocity; motion is
## whatever Jolt integrates from the forces.

signal part_detached(part: AircraftPart, parent: AircraftPart, load_ratio: float)
## A hard contact: where, the contact impulse (N s), and the energy absorbed (J).
signal part_impacted(part: AircraftPart, world_pos: Vector3, impulse: Vector3, energy: float)
signal fire_started(source: FireSource)
## A part's dent state changed.
signal part_dented(part: AircraftPart)
## A skin piece has been torn off `part` (already hidden there). `node` is the
## mesh node that showed it; `kick` is the speed (m/s) to throw it clear at.
signal piece_shed(part: AircraftPart, piece: SkinPiece, node: MeshInstance3D, kick: float)
## Raised once per crash, on the first structural failure or hard impact.
signal crashed
## A fresh hard impact after time in the air, while already crashed (for
## example the ground, after a mid-air break-up).
signal major_impact

const GRAVITY := 9.80665
const RHO0 := 1.225
## Closing speed (m/s) below which a contact is a scrape, not an impact.
const IMPACT_MIN_SPEED := 2.5
## Structure crushes at about this many g: depth = energy / (m g N_CRUSH).
const N_CRUSH := 12.0
## Rolling (1/s on angular momentum) and ploughing (1/s on velocity) losses of
## detached wreckage in ground contact.
const WRECK_ROLL_DRAG := 2.5
const WRECK_SLIDE_DRAG := 0.35
## Sliding faster than this (m/s) on the ground scrapes skin off, and loose
## wreckage above this dynamic pressure (Pa) sheds panels into the airstream.
const SCRAPE_SPEED := 12.0
const STRIP_DYN_PRESSURE := 2200.0
## Seconds of fuselage/wing/engine ground contact that make a belly landing a crash.
const BODY_CONTACT_CRASH_TIME := 0.8
## Time constant of the yaw damper's washout filter (s).
## Fly-by-wire loop gains at cruise speed (stick units per g, per g-second,
## per rad/s of pitch rate; per unit roll-rate error at full rate).
const FBW_PITCH_KP := 0.04
const FBW_PITCH_KI := 0.25
const FBW_PITCH_KQ := 0.35
const FBW_ROLL_KP := 2.5
## Released stick: banks steeper than this roll back towards it.
const FBW_BANK_HOLD_DEG := 33.0
const YAW_WASHOUT_TIME := 2.0
## The cabin is armed this many seconds before a predicted impact.
const ARM_LEAD_TIME := 1.2
## Minimum ticks between impact events from one part.
const IMPACT_EVENT_TICKS := 6

var def: AircraftDef
var controls := ControlState.new()
var telemetry := FlightTelemetry.new()

var parts: Array[AircraftPart] = []
var joints_alive: int = 0
var surfaces: Array[AeroSurface] = []
var engines: Array[EngineUnit] = []
var gears: Array[GearUnit] = []
var root_part: AircraftPart
var structure: StructureMonitor
var cabin: Cabin
## How many FRED dummies to seat (set before setup()).
var max_freds: int = 8
## Estimated seconds until the aircraft hits something (large when none).
var impact_eta: float = 999.0
## Active fires, oldest first. Read by FX and by the survival model.
var fires: Array[FireSource] = []
## Simulation time since setup (s) and the time of the first crash event.
var sim_time: float = 0.0
var crash_time: float = -1.0
## True once the wreck has settled and simulation of it has stopped.
var resting: bool = false
## True while any part other than the gear is touching something.
var body_contact: bool = false
## Root-part state on the last tick before the crash began.
var impact_velocity := Vector3.ZERO
var impact_pitch_deg: float = 0.0
var impact_roll_deg: float = 0.0

var auto_trim: bool = true
var trim: float = 0.0
var flap_ratio: float = 0.0
var gear_ratio: float = 1.0
var spoiler_ratio: float = 0.0
## Height of the terrain under the root part (world Y).
var ground_y: float = 0.0
var air_density: float = RHO0
## Local speed of sound (m/s).
var sound_speed: float = 340.3

var _act := Vector3.ZERO
var _agl_ray: RayCast3D
var _ahead_ray: RayCast3D
var _prev_root_vel := Vector3.ZERO
var _has_prev_vel: bool = false
var _g_filtered := Vector3(0.0, 1.0, 0.0)
var _gear_colliders_on: bool = true
var _ticks: int = 0
var _airborne_time: float = 0.0
var _fbw_pitch_i: float = 0.0
## How many skin pieces can be torn off right now (set by CrashDirector): a
## piece is only released when a chunk body can carry it, so none vanish.
var shed_room: Callable
var _strobes: Array[Node3D] = []
## Last deflection written to each hinged piece (skips unchanged writes).
var _hinged_last: PackedFloat32Array = PackedFloat32Array()
var _beacons: Array[Node3D] = []
var _light_time: float = 0.0
var _fbw_active: bool = false
var _fbw_out: float = 0.0
## Seconds left of the weight-on-wheels hold: a bounce must not retract the gear.
var _wow_hold: float = 0.0
var _fbw_offset: float = 0.0
var _yaw_rate_slow: float = 0.0
var _downwash_sources: Array[AeroSurface] = []
var _body_contact_time: float = 0.0
var _vel_history: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _attitude_before := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _hinged_nodes: Array[MeshInstance3D] = []
var _hinged_pieces: Array[SkinPiece] = []
var _hinged_parts: Array[AircraftPart] = []
var _ahead_hit: bool = false
var _ahead_dist: float = 0.0


## Builds the airframe at this node's current transform. Call once, in-tree.
func setup(aircraft_def: AircraftDef) -> void:
	def = aircraft_def
	AirframeBuilder.apply_livery(def)
	for i: int in def.parts.size():
		var body := AirframeBuilder.build_part(def, def.parts[i], i)
		add_child(body)
		parts.append(body)
	root_part = parts[0]
	for part: AircraftPart in parts:
		if part.parent_index >= 0:
			part.joint = AirframeBuilder.build_joint(self, parts[part.parent_index], part)
			joints_alive += 1
	for s: SurfaceDef in def.surfaces:
		var surface := AeroSurface.new()
		surface.setup(s, parts[def.find_part(s.part)])
		surfaces.append(surface)
		if s.downwash_source:
			_downwash_sources.append(surface)
	for e: EngineDef in def.engines:
		var engine := EngineUnit.new()
		engine.setup(e, parts[def.find_part(e.part)])
		engines.append(engine)
	for g: GearDef in def.gear:
		var gear := GearUnit.new()
		var owner_part := parts[def.find_part(g.part)]
		gear.setup(g, owner_part)
		gear.leg_visual = owner_part.visual.get_node_or_null("Leg") as Node3D
		if gear.leg_visual != null:
			gear.wheel_visual = gear.leg_visual.get_node_or_null("Wheels") as Node3D
		gears.append(gear)

	_rng.seed = 1903
	for part: AircraftPart in parts:
		for i: int in part.pieces.size():
			if part.pieces[i].control != SkinPiece.Surface.NONE:
				_hinged_nodes.append(part.piece_nodes[i])
				_hinged_pieces.append(part.pieces[i])
				_hinged_parts.append(part)
	for part: AircraftPart in parts:
		var visual := part.get_node_or_null(^"Visual")
		if visual == null:
			continue
		for child: Node in visual.get_children():
			var light_name := String(child.name)
			if light_name.begins_with("Strobe"):
				_strobes.append(child as Node3D)
			elif light_name.begins_with("Beacon"):
				_beacons.append(child as Node3D)
	_hinged_last.resize(_hinged_nodes.size())
	_hinged_last.fill(1.0e9)
	structure = StructureMonitor.new()
	structure.setup(parts)
	cabin = Cabin.new()
	cabin.build(self, max_freds)

	_ahead_ray = RayCast3D.new()
	_ahead_ray.name = "AheadRay"
	_ahead_ray.enabled = false
	_ahead_ray.top_level = true
	_ahead_ray.collision_mask = AirframeBuilder.LAYER_WORLD
	add_child(_ahead_ray)

	_agl_ray = RayCast3D.new()
	_agl_ray.name = "AglRay"
	_agl_ray.enabled = false
	_agl_ray.top_level = true
	_agl_ray.target_position = Vector3(0.0, -6000.0, 0.0)
	_agl_ray.collision_mask = AirframeBuilder.LAYER_WORLD
	add_child(_agl_ray)
	for part: AircraftPart in parts:
		part.begin_tick()


## Moves the whole airframe rigidly so the root part lands on `root_xf`, with
## every part given `velocity`. For spawning and test set-up only: flight
## never moves bodies this way.
func teleport(root_xf: Transform3D, velocity: Vector3) -> void:
	var delta := root_xf * root_part.global_transform.affine_inverse()
	for part: AircraftPart in parts:
		part.global_transform = delta * part.global_transform
		part.linear_velocity = velocity
		part.angular_velocity = Vector3.ZERO
		part.has_prev = false
		part.reset_physics_interpolation()
		part.begin_tick()
	_prev_root_vel = velocity
	_has_prev_vel = true


## Gives every part the same initial velocity (use right after setup()).
func set_initial_velocity(velocity: Vector3) -> void:
	for part: AircraftPart in parts:
		part.linear_velocity = velocity
	_prev_root_vel = velocity
	_has_prev_vel = true


## Configures an in-flight start with engines already spooled to `throttle`.
func configure_airborne(throttle: float, gear_down: bool = false, flap_step: int = 0) -> void:
	controls.throttle = throttle
	controls.gear_down = gear_down
	controls.flap_step = flap_step
	gear_ratio = 1.0 if gear_down else 0.0
	var last := def.flap_steps_deg.size() - 1
	if last > 0 and def.flap_steps_deg[last] > 0.0:
		flap_ratio = def.flap_steps_deg[clampi(flap_step, 0, last)] / def.flap_steps_deg[last]
	trim = def.cruise_trim
	for engine: EngineUnit in engines:
		engine.spool = engine.def.idle_fraction + (1.0 - engine.def.idle_fraction) * throttle
	_gear_colliders_on = true
	_apply_gear_state()


func total_mass() -> float:
	return def.total_mass()


## Called when the wreck has stopped: nothing is left to simulate, so the
## flight model, structure monitor and cabin stand down and every body is
## allowed to sleep.
func rest() -> void:
	if resting:
		return
	resting = true
	cabin.stand_down()
	for part: AircraftPart in parts:
		part.can_sleep = true


## Anti-collision lights: a double white strobe every 1.2 s at the wingtips
## and a red beacon flash every second. Visual only.
func _process(delta: float) -> void:
	_light_time += delta
	var strobe_t := fmod(_light_time, 1.2)
	var strobe := strobe_t < 0.05 or (strobe_t > 0.16 and strobe_t < 0.21)
	for light: Node3D in _strobes:
		if light.visible != strobe:
			light.visible = strobe
	for i: int in _beacons.size():
		var on := fmod(_light_time + 0.5 * float(i), 1.0) < 0.12
		if _beacons[i].visible != on:
			_beacons[i].visible = on


func _physics_process(dt: float) -> void:
	if def == null or resting:
		return
	_ticks += 1
	var count := parts.size()
	for i: int in count:
		parts[i].begin_tick()
	sim_time += dt
	# Rolling record of the state before any impact (frozen during contact so
	# it keeps describing the approach, not the tumble).
	if not body_contact:
		_vel_history[_ticks % 4] = root_part.lin_vel
		if _ticks % 4 == 0:
			_attitude_before = Vector2(telemetry.pitch_deg, telemetry.roll_deg)
	structure.update(dt)
	if structure.broken.size() > 0:
		for k: int in structure.broken.size():
			var idx := structure.broken[k]
			# An inboard joint breaking this tick may have been reported first;
			# the outboard one is then no longer overloaded in fact, but it was
			# measured so, and both letting go is the physical outcome.
			detach(idx, structure.load_ratio[idx])
	_process_impacts(dt)
	for i: int in count:
		var part := parts[i]
		part.ext_force = Vector3.ZERO
		part.ext_torque = Vector3.ZERO

	_update_actuators(dt)

	var origin := root_part.xf.origin
	_agl_ray.global_position = origin
	_agl_ray.force_raycast_update()
	ground_y = _agl_ray.get_collision_point().y if _agl_ray.is_colliding() else -10000.0
	# ISA troposphere density.
	air_density = RHO0 * pow(maxf(1.0 - 2.2558e-5 * maxf(origin.y, 0.0), 0.1), 4.2559)
	var rho := air_density

	# Speed of sound falls with temperature (ISA lapse to the tropopause).
	sound_speed = 340.3 * sqrt(maxf(1.0 - 2.2558e-5 * clampf(origin.y, 0.0, 11000.0), 0.5))
	var mach := root_part.lin_vel.length() / sound_speed

	# Downwash at the tail: twice the induced angle of the inboard wing, from
	# the lift those strips made last tick. A wing that is gone, or stripped,
	# makes less lift and so less downwash.
	var downwash := 0.0
	if _downwash_sources.size() > 0:
		for i: int in _downwash_sources.size():
			var src := _downwash_sources[i]
			if src.part.assembly_root == 0:
				downwash += src.cl * src.induced_k
		downwash *= 2.0 / float(_downwash_sources.size())

	for i: int in surfaces.size():
		surfaces[i].apply(rho, _act, trim, flap_ratio, spoiler_ratio, ground_y, def, mach, downwash)
	var throttle := clampf(controls.throttle, 0.0, 1.0)
	for i: int in engines.size():
		engines[i].apply(throttle, rho, dt, sound_speed)
	var brake := clampf(controls.brake, 0.0, 1.0)
	for i: int in gears.size():
		var gear := gears[i]
		gear.apply(gear_ratio, _act.z, brake, dt, parts[gear.part.assembly_root])
		if gear_ratio > 0.02:
			var v := gear.part.lin_vel
			gear.part.push_central_force(v * (-0.5 * rho * gear.def.drag_area * gear_ratio * v.length()))
	# Transonic drag rise on the fuselage and nacelles.
	var body_drag_factor := 1.0 + def.body_wave_drag * smoothstep(0.85, 1.1, mach)
	for i: int in count:
		var part := parts[i]
		var area := part.def.drag_area
		if area == Vector3.ZERO:
			continue
		var basis := part.xf.basis
		var v_local := part.lin_vel * basis
		# Skin torn off a body exposes frames and cabin: more drag.
		var rough := body_drag_factor * (1.0 + 1.5 * (1.0 - part.skin_fraction))
		var f_local := Vector3(
				-area.x * absf(v_local.x) * v_local.x,
				-area.y * absf(v_local.y) * v_local.y,
				-area.z * absf(v_local.z) * v_local.z) * (0.5 * rho * rough)
		part.push_central_force(basis * f_local)

	_update_telemetry(dt)
	_update_arming()
	cabin.tick(dt)


## Arms the cabin (seat logging, dummies) shortly before an impact, so the
## whole deceleration is captured without simulating occupants all flight.
func _update_arming() -> void:
	if cabin.armed:
		return
	var v := root_part.lin_vel
	var speed := v.length()
	var eta := 999.0
	if v.y < -6.0:
		eta = telemetry.altitude_agl / -v.y
	if speed > 12.0 and _ticks % 3 == 0:
		# Look ahead along the flight path for terrain and buildings.
		_ahead_ray.global_position = root_part.xf.origin
		_ahead_ray.target_position = v * ARM_LEAD_TIME
		_ahead_ray.force_raycast_update()
		_ahead_hit = _ahead_ray.is_colliding()
		if _ahead_hit:
			_ahead_dist = root_part.xf.origin.distance_to(_ahead_ray.get_collision_point())
	if _ahead_hit and speed > 12.0 and not telemetry.on_ground:
		eta = minf(eta, maxf(_ahead_dist - def.wing_span * 0.5, 0.0) / speed)
	impact_eta = eta
	if eta < ARM_LEAD_TIME or telemetry.crashed or telemetry.g_total > 3.2:
		cabin.arm(sim_time)


## Cuts the joint holding part `index` to its parent.
func detach(index: int, load_ratio: float) -> void:
	var part := parts[index]
	if part.joint == null:
		return
	part.joint.queue_free()
	part.joint = null
	joints_alive -= 1
	var parent := parts[part.parent_index]
	# Re-label assemblies: a part belongs to its parent's assembly if its joint
	# is intact, otherwise it is the root of its own. Parents precede children.
	for i: int in parts.size():
		var p := parts[i]
		p.assembly_root = parts[p.parent_index].assembly_root if p.joint != null else i
	for i: int in parts.size():
		var p := parts[i]
		if p.assembly_root != 0:
			p.can_sleep = true
	for engine: EngineUnit in engines:
		# Torn from the fuel system: the engine runs down.
		if engine.part.assembly_root != 0:
			engine.running = false
	if part.def.kind == PartDef.Kind.GEAR:
		# A retracted leg has its collider off; torn loose it must hit the ground.
		(part.get_node(^"Collider") as CollisionShape3D).set_deferred(&"disabled", false)
		for gear: GearUnit in gears:
			if gear.part == part and gear.leg_visual != null:
				gear.leg_visual.visible = true
				gear.leg_visual.rotation.x = 0.0
	_mark_crashed()
	part_detached.emit(part, parent, load_ratio)
	# A joint never parts cleanly: skin around the break goes with it.
	var tear := 2 if load_ratio > 4.0 else 1
	shed_pieces(part, part.anchor_local, 3.5, tear, 6.0)
	shed_pieces(parent, part.def.anchor - parent.def.com, 3.5, tear, 6.0)

	# Ruptured tanks and hot engines catch fire.
	var speed := part.lin_vel.length()
	if part.def.kind == PartDef.Kind.ENGINE:
		for engine: EngineUnit in engines:
			if engine.part == part and engine.spool > 0.25:
				ignite(part, Vector3.ZERO, 0.7)
	elif part.def.fuel_kg > 0.0 and (speed > 18.0 or load_ratio > 2.5):
		ignite(part, part.anchor_local, clampf(part.def.fuel_kg / 3000.0, 0.35, 1.0))
		if parent.def.fuel_kg > 0.0:
			ignite(parent, part.def.anchor - parent.def.com, clampf(parent.def.fuel_kg / 3000.0, 0.35, 1.0))


## Starts (or intensifies) a fire on a part at a part-local position.
func ignite(part: AircraftPart, local_pos: Vector3, intensity: float) -> void:
	if part.burning > 0.0:
		part.burning = maxf(part.burning, intensity)
		return
	part.burning = intensity
	var source := FireSource.new()
	source.part = part
	source.local_pos = local_pos
	source.intensity = intensity
	source.start_time = sim_time
	fires.append(source)
	fire_started.emit(source)


## Records the velocity and attitude the aircraft had going into an impact.
func _snapshot_impact() -> void:
	# The fastest of the last few ticks: the tick that raised the alarm has
	# usually already been slowed by the contact.
	impact_velocity = _vel_history[0]
	for v: Vector3 in _vel_history:
		if v.length_squared() > impact_velocity.length_squared():
			impact_velocity = v
	impact_pitch_deg = _attitude_before.x
	impact_roll_deg = _attitude_before.y


## Withdraws the crash state after a contact the aircraft flew away from.
## Damage stays; a later impact starts a new crash with its own snapshot.
func clear_incident() -> void:
	crash_time = -1.0
	telemetry.crashed = false
	_body_contact_time = 0.0
	cabin.disarm()


func _mark_crashed() -> void:
	if crash_time >= 0.0:
		return
	crash_time = sim_time
	_snapshot_impact()
	telemetry.crashed = true
	crashed.emit()


## Turns hard contacts into dents, damage and events.
func _process_impacts(dt: float) -> void:
	var touching := false
	for i: int in parts.size():
		var part := parts[i]
		if part.burning > 0.0:
			part.burn_time += dt
			if (_ticks + i) % 20 == 0:
				part.set_scorch(minf(part.burn_time / 25.0, 0.85) * part.burning)
		# Past the never-exceed speed flutter and air loads start taking the
		# airframe apart: control surfaces and wing skin first.
		if telemetry.overspeed and part.pieces_left > 0 and part.def.kind != PartDef.Kind.FUSELAGE \
				and (_ticks + i * 7) % 20 == 0:
			var excess := telemetry.ias / def.v_never_exceed - 1.0
			if _rng.randf() < clampf(excess * 2.5, 0.0, 0.5):
				var victim := part.pieces[_rng.randi() % part.pieces.size()].center
				shed_pieces(part, victim, 1000.0, 1, 4.0)
				_mark_crashed()
		# Broken structure in a fast airstream keeps coming apart, panel by panel,
		# but slowly: a torn-off wing tumbles down mostly whole, losing the odd
		# panel where it is already open, not shedding its skin like confetti.
		if part.pieces_left > 0 and (part.stripped or part.assembly_root != 0) and (_ticks + i * 3) % 12 == 0:
			var q := 0.5 * air_density * part.lin_vel.length_squared()
			var chance := minf(q / 600000.0, 0.05)
			if not part.stripped:
				chance *= 0.3
			if part.assembly_root == 0:
				# A scraped but intact hull holds together; damaged wings and
				# tails on the aircraft peel slowly.
				chance *= 0.0 if part.def.kind == PartDef.Kind.FUSELAGE else 0.1
			if q > STRIP_DYN_PRESSURE and _rng.randf() < chance:
				var pick := part.pieces[_rng.randi() % part.pieces.size()].center
				shed_pieces(part, pick, 1000.0, 1, 4.0)
		if part.contact_count == 0 or part.sleeping:
			continue
		if part.def.kind != PartDef.Kind.GEAR:
			touching = true
		if part.assembly_root != 0:
			# Wreckage on the ground: rolling and ploughing resistance, so loose
			# wheels and nacelles do not trundle on forever. Applied as explicit
			# forces so the structure monitor still accounts for them.
			part.push_torque(part.angular_momentum() * -WRECK_ROLL_DRAG)
			part.push_central_force(part.lin_vel * (-WRECK_SLIDE_DRAG * part.mass))
		# Scraping along the ground at speed grinds skin off the contact patch.
		if part.pieces_left > 0 and (_ticks + i) % 8 == 0:
			var slide := part.lin_vel.length()
			if slide > SCRAPE_SPEED and _rng.randf() < slide / 420.0:
				shed_pieces(part, (part.hit_position - part.xf.origin) * part.xf.basis, 2.4, 1, 2.0)
		if part.hit_speed < IMPACT_MIN_SPEED:
			continue
		# Energy absorbed at the contact: impulse times mean closing speed.
		var energy := 0.5 * part.hit_impulse.length() * part.hit_speed
		part.pending_hit_energy += energy
		part.crush_energy += energy
		if _ticks - part.last_hit_tick < IMPACT_EVENT_TICKS:
			continue
		part.last_hit_tick = _ticks
		energy = part.pending_hit_energy
		part.pending_hit_energy = 0.0
		var kind := part.def.kind
		if kind != PartDef.Kind.GEAR:
			var depth := energy / (part.mass * GRAVITY * N_CRUSH)
			var basis := part.xf.basis
			var local_pos := (part.hit_position - part.xf.origin) * basis
			var dir := part.hit_impulse.normalized() * basis
			part.add_dent(local_pos, dir, depth)
			part_dented.emit(part)
			# Roughly one panel per 0.4 m of crush, nearest first.
			shed_pieces(part, local_pos, clampf(1.2 + depth * 2.0, 1.5, 5.0),
					clampi(int(depth * 2.5), 0, 4), 3.0 + minf(part.hit_speed * 0.2, 8.0))
			if part.hit_speed > 4.0:
				# A fresh hard impact after time in the air is the one the
				# report should describe, even if an earlier scrape began it.
				if crash_time >= 0.0 and _airborne_time > 1.0 and part.assembly_root == 0:
					_snapshot_impact()
					major_impact.emit()
				_mark_crashed()
			if part.def.fuel_kg > 0.0 and part.hit_speed > 22.0:
				ignite(part, local_pos, clampf(part.def.fuel_kg / 3000.0, 0.35, 1.0))
		part_impacted.emit(part, part.hit_position, part.hit_impulse, energy)
	# Airframe on the ground: arm the cabin at once, and call it a crash if it
	# stays there (a brief tail scrape on rotation is not one).
	if touching:
		cabin.arm(sim_time)
		_body_contact_time += dt
		if _body_contact_time > BODY_CONTACT_CRASH_TIME:
			_mark_crashed()
	else:
		_body_contact_time = maxf(_body_contact_time - dt * 0.5, 0.0)
	_airborne_time = 0.0 if body_contact else _airborne_time + dt
	body_contact = touching


func _update_actuators(dt: float) -> void:
	var c := controls
	var rate := def.control_rate * dt
	var pitch_demand := clampf(c.pitch, -1.0, 1.0)
	var roll_demand := clampf(c.roll, -1.0, 1.0)
	var fbw := not telemetry.on_ground and telemetry.ias > def.v_rotate * 0.6 and _fbw_alive()
	if fbw and def.fbw_max_g > 0.0:
		pitch_demand = _fbw_pitch(c.pitch, dt)
		_fbw_active = true
	else:
		if _fbw_active and not telemetry.on_ground:
			# The flight computer has dropped out (structural damage): keep the
			# elevator where it was holding it, so the hand-over is bumpless and
			# the stick flies the elevator directly from there.
			_fbw_offset = _fbw_out - clampf(c.pitch, -1.0, 1.0)
		elif telemetry.on_ground:
			_fbw_offset = 0.0
		_fbw_active = false
		pitch_demand = clampf(c.pitch + _fbw_offset, -1.0, 1.0)
		_fbw_pitch_i = _act.x
	if fbw and def.fbw_roll_rate_deg > 0.0:
		roll_demand = _fbw_roll(c.roll)
	_act.x = move_toward(_act.x, pitch_demand, rate)
	_act.y = move_toward(_act.y, roll_demand, rate)
	# Yaw damper: rudder against the washed-out yaw rate (airborne only, so it
	# never fights nose-wheel steering).
	var yaw_command := c.yaw
	if def.yaw_damper > 0.0 and not telemetry.on_ground:
		var yaw_right := -root_part.ang_vel.dot(root_part.xf.basis.y)
		_yaw_rate_slow = lerpf(_yaw_rate_slow, yaw_right, minf(dt / YAW_WASHOUT_TIME, 1.0))
		yaw_command -= def.yaw_damper * (yaw_right - _yaw_rate_slow)
	_act.z = move_toward(_act.z, clampf(yaw_command, -1.0, 1.0), rate)

	# Auto-trim: held stick slowly becomes trim, so releasing it holds attitude.
	if auto_trim and def.fbw_max_g <= 0.0 and not telemetry.on_ground and absf(c.pitch) > 0.003:
		trim = clampf(trim + c.pitch * def.trim_rate * dt, -1.0, 1.0)

	var steps := def.flap_steps_deg
	var last := steps.size() - 1
	var flap_target := 0.0
	if last > 0 and steps[last] > 0.0:
		flap_target = steps[clampi(c.flap_step, 0, last)] / steps[last]
	flap_ratio = move_toward(flap_ratio, flap_target, dt / def.flap_time)
	spoiler_ratio = move_toward(spoiler_ratio, 1.0 if c.spoilers else 0.0, dt * 2.0)

	_animate_surfaces()

	# Weight-on-wheels interlock: the gear will not retract on the ground.
	_wow_hold = 0.5 if telemetry.on_ground else maxf(_wow_hold - dt, 0.0)
	var gear_target := 1.0 if c.gear_down or _wow_hold > 0.0 else 0.0
	if gear_ratio != gear_target:
		gear_ratio = move_toward(gear_ratio, gear_target, dt / def.gear_time)
		_apply_gear_state()


## Gain schedule for the flight computer: control power grows with dynamic
## pressure, so the loop gains shrink with it (1 at cruise speed).
func _fbw_schedule() -> float:
	var v := maxf(telemetry.ias, def.v_rotate)
	return clampf(pow(def.v_cruise / v, 2.0), 0.25, 4.0)


## The flight computer flies only while the wing and tail it uses are on.
func _fbw_alive() -> bool:
	for part: AircraftPart in parts:
		if part.joint == null and part.parent_index >= 0 and part.def.kind != PartDef.Kind.GEAR:
			return false
	return true


## Pitch law: the stick commands normal load factor, with an angle-of-attack
## limiter, through a PI loop with pitch-rate damping.
func _fbw_pitch(stick: float, dt: float) -> float:
	var s := clampf(stick, -1.0, 1.0)
	var g_cmd := 1.0 + (s * (def.fbw_max_g - 1.0) if s >= 0.0 else s * (1.0 - def.fbw_min_g))
	# Hands off in a bank: hold the 1 g the pilot wants along the flight path,
	# so a released stick does not drop the nose.
	if absf(s) < 0.02:
		var bank_cos := clampf(cos(deg_to_rad(telemetry.roll_deg)), 0.5, 1.0)
		g_cmd = 1.0 / bank_cos
	# AoA limiter: fade the demand out over the last 6 degrees.
	var aoa_room := def.fbw_aoa_limit_deg - telemetry.aoa_deg
	if g_cmd > 1.0 and aoa_room < 6.0:
		g_cmd = lerpf(1.0, g_cmd, clampf(aoa_room / 6.0, 0.0, 1.0))
	var k := _fbw_schedule()
	var err := g_cmd - telemetry.g_load
	var q := root_part.ang_vel.dot(root_part.xf.basis.x)
	_fbw_pitch_i = clampf(_fbw_pitch_i + err * FBW_PITCH_KI * k * dt, -1.0, 1.0)
	_fbw_out = clampf(_fbw_pitch_i + err * FBW_PITCH_KP * k - q * FBW_PITCH_KQ * k, -1.0, 1.0)
	return _fbw_out


## Roll law: the stick commands roll rate.
func _fbw_roll(stick: float) -> float:
	var max_rate := deg_to_rad(def.fbw_roll_rate_deg)
	var p := root_part.ang_vel.dot(-root_part.xf.basis.z)
	var cmd := clampf(stick, -1.0, 1.0) * max_rate
	# Bank angle protection near the vertical when the stick is released.
	if absf(stick) < 0.02 and absf(telemetry.roll_deg) > FBW_BANK_HOLD_DEG:
		cmd = -signf(telemetry.roll_deg) * deg_to_rad(5.0)
	return clampf((cmd - p) * FBW_ROLL_KP * _fbw_schedule() / max_rate, -1.0, 1.0)


## Swings the visible control surfaces to match the actuators.
func _animate_surfaces() -> void:
	for i: int in _hinged_nodes.size():
		var node := _hinged_nodes[i]
		if not node.visible:
			continue
		var piece := _hinged_pieces[i]
		var amount := 0.0
		match piece.control:
			SkinPiece.Surface.AILERON:
				amount = -piece.side * _act.y
			SkinPiece.Surface.ELEVATOR:
				amount = -clampf(_act.x + trim * 0.4, -1.0, 1.0)
			SkinPiece.Surface.RUDDER:
				amount = _act.z
			SkinPiece.Surface.FLAP:
				amount = flap_ratio
		if absf(amount - _hinged_last[i]) < 0.0005:
			continue
		_hinged_last[i] = amount
		node.transform = Transform3D(Basis(piece.hinge, amount * piece.deflect_max), piece.xform.origin)


## Tears up to `max_count` skin pieces off `part`, nearest to `local_pos`
## first and no further than `radius` from it. Returns how many came off.
func shed_pieces(part: AircraftPart, local_pos: Vector3, radius: float, max_count: int, kick: float) -> int:
	var shed := 0
	if shed_room.is_valid():
		max_count = mini(max_count, int(shed_room.call()))
	for _n: int in max_count:
		var index := part.nearest_piece(local_pos, radius)
		if index < 0:
			break
		var first := not part.stripped
		var node := part.release_piece(index)
		if first:
			cabin.reveal_part(part.index)
		piece_shed.emit(part, part.pieces[index], node, kick)
		shed += 1
	return shed


func _apply_gear_state() -> void:
	var colliders_on := gear_ratio > 0.5
	for gear: GearUnit in gears:
		if gear.leg_visual != null and gear.part.joint != null:
			gear.leg_visual.visible = gear_ratio > 0.02
			gear.leg_visual.rotation.x = (1.0 - gear_ratio) * -1.45
	if colliders_on != _gear_colliders_on:
		_gear_colliders_on = colliders_on
		for gear: GearUnit in gears:
			if gear.part.joint == null:
				continue
			var collider := gear.part.get_node(^"Collider") as CollisionShape3D
			collider.set_deferred(&"disabled", not colliders_on)


func _update_telemetry(dt: float) -> void:
	var t := telemetry
	var xf := root_part.xf
	var v := root_part.lin_vel
	var basis := xf.basis
	var fwd := -basis.z
	var up := basis.y
	var right := basis.x
	var speed := v.length()
	t.tas = speed
	t.ias = speed * sqrt(air_density / RHO0)
	t.mach = speed / sound_speed
	t.overspeed = t.ias > def.v_never_exceed
	if speed > 1.0:
		t.aoa_deg = rad_to_deg(atan2(-v.dot(up), v.dot(fwd)))
		t.sideslip_deg = rad_to_deg(asin(clampf(v.dot(right) / speed, -1.0, 1.0)))
	else:
		t.aoa_deg = 0.0
		t.sideslip_deg = 0.0
	t.vertical_speed = v.y
	t.pitch_deg = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	t.roll_deg = rad_to_deg(atan2(-right.y, up.y))
	t.heading_deg = wrapf(rad_to_deg(atan2(fwd.x, -fwd.z)), 0.0, 360.0)
	t.altitude_msl = xf.origin.y
	t.altitude_agl = maxf(xf.origin.y - ground_y - def.ground_clearance, 0.0)

	if _has_prev_vel and dt > 0.0:
		var felt := ((v - _prev_root_vel) / dt + Vector3(0.0, GRAVITY, 0.0)) / GRAVITY
		_g_filtered = _g_filtered.lerp(felt, 0.35)
	_prev_root_vel = v
	_has_prev_vel = true
	t.g_load = _g_filtered.dot(up)
	t.g_total = _g_filtered.length()

	var thrust := 0.0
	for i: int in engines.size():
		thrust += engines[i].spool
	t.thrust_fraction = thrust / maxf(float(engines.size()), 1.0)
	t.flap_ratio = flap_ratio
	t.gear_ratio = gear_ratio
	t.trim = trim

	var grounded := false
	for i: int in gears.size():
		if gears[i].on_ground:
			grounded = true
	t.on_ground = grounded

	var stall := false
	if not grounded and speed > 15.0:
		for i: int in surfaces.size():
			var s := surfaces[i]
			if s.def.flap_fraction > 0.0 and s.part.assembly_root == 0 \
					and s.aoa_deg > s.stall_deg * 0.9:
				stall = true
	t.stall_warning = stall
	t.integrity = float(joints_alive) / maxf(float(parts.size() - 1), 1.0)
