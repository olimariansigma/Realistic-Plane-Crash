class_name Aircraft
extends Node3D
## A flyable, breakable aircraft built from an AircraftDef.
##
## Each physics tick: read every part's state, let the structure monitor judge
## last step's joint loads, then apply this tick's aerodynamic, thrust and
## gear forces. Nothing here ever sets a transform or a velocity; motion is
## whatever Jolt integrates from the forces.

signal part_detached(part: AircraftPart, parent: AircraftPart, load_ratio: float)

const GRAVITY := 9.80665
const RHO0 := 1.225

var def: AircraftDef
var controls := ControlState.new()
var telemetry := FlightTelemetry.new()

var parts: Array[AircraftPart] = []
var joints_alive: int = 0
var surfaces: Array[AeroSurface] = []
var engines: Array[EngineUnit] = []
var gears: Array[GearUnit] = []
var root_part: AircraftPart
## Set by the crash milestone; null means joints never break.
var structure: StructureMonitor

var auto_trim: bool = true
var trim: float = 0.0
var flap_ratio: float = 0.0
var gear_ratio: float = 1.0
var spoiler_ratio: float = 0.0
## Height of the terrain under the root part (world Y).
var ground_y: float = 0.0
var air_density: float = RHO0

var _act := Vector3.ZERO
var _agl_ray: RayCast3D
var _prev_root_vel := Vector3.ZERO
var _has_prev_vel: bool = false
var _g_filtered := Vector3(0.0, 1.0, 0.0)
var _gear_colliders_on: bool = true
var _ticks: int = 0


## Builds the airframe at this node's current transform. Call once, in-tree.
func setup(aircraft_def: AircraftDef) -> void:
	def = aircraft_def
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

	_agl_ray = RayCast3D.new()
	_agl_ray.name = "AglRay"
	_agl_ray.enabled = false
	_agl_ray.top_level = true
	_agl_ray.target_position = Vector3(0.0, -6000.0, 0.0)
	_agl_ray.collision_mask = AirframeBuilder.LAYER_WORLD
	add_child(_agl_ray)
	for part: AircraftPart in parts:
		part.begin_tick()


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


func _physics_process(dt: float) -> void:
	if def == null:
		return
	_ticks += 1
	var count := parts.size()
	for i: int in count:
		parts[i].begin_tick()
	if structure != null:
		structure.update(dt)
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

	for i: int in surfaces.size():
		surfaces[i].apply(rho, _act, trim, flap_ratio, spoiler_ratio, ground_y, def)
	var throttle := clampf(controls.throttle, 0.0, 1.0)
	for i: int in engines.size():
		engines[i].apply(throttle, rho, dt)
	var brake := clampf(controls.brake, 0.0, 1.0)
	for i: int in gears.size():
		var gear := gears[i]
		gear.apply(gear_ratio, _act.z, brake, dt, parts[gear.part.assembly_root])
		if gear_ratio > 0.02:
			var v := gear.part.lin_vel
			gear.part.push_central_force(v * (-0.5 * rho * gear.def.drag_area * gear_ratio * v.length()))
	for i: int in count:
		var part := parts[i]
		var area := part.def.drag_area
		if area == Vector3.ZERO:
			continue
		var basis := part.xf.basis
		var v_local := part.lin_vel * basis
		var f_local := Vector3(
				-area.x * absf(v_local.x) * v_local.x,
				-area.y * absf(v_local.y) * v_local.y,
				-area.z * absf(v_local.z) * v_local.z) * (0.5 * rho)
		part.push_central_force(basis * f_local)

	_update_telemetry(dt)


func _update_actuators(dt: float) -> void:
	var c := controls
	var rate := def.control_rate * dt
	_act.x = move_toward(_act.x, clampf(c.pitch, -1.0, 1.0), rate)
	_act.y = move_toward(_act.y, clampf(c.roll, -1.0, 1.0), rate)
	_act.z = move_toward(_act.z, clampf(c.yaw, -1.0, 1.0), rate)

	# Auto-trim: held stick slowly becomes trim, so releasing it holds attitude.
	if auto_trim and not telemetry.on_ground and absf(c.pitch) > 0.01:
		trim = clampf(trim + c.pitch * def.trim_rate * dt, -1.0, 1.0)

	var steps := def.flap_steps_deg
	var last := steps.size() - 1
	var flap_target := 0.0
	if last > 0 and steps[last] > 0.0:
		flap_target = steps[clampi(c.flap_step, 0, last)] / steps[last]
	flap_ratio = move_toward(flap_ratio, flap_target, dt / def.flap_time)
	spoiler_ratio = move_toward(spoiler_ratio, 1.0 if c.spoilers else 0.0, dt * 2.0)

	# Weight-on-wheels interlock: the gear will not retract on the ground.
	var gear_target := 1.0 if c.gear_down or telemetry.on_ground else 0.0
	if gear_ratio != gear_target:
		gear_ratio = move_toward(gear_ratio, gear_target, dt / def.gear_time)
		_apply_gear_state()


func _apply_gear_state() -> void:
	var colliders_on := gear_ratio > 0.5
	for gear: GearUnit in gears:
		if gear.leg_visual != null:
			gear.leg_visual.visible = gear_ratio > 0.02
			gear.leg_visual.rotation.x = (1.0 - gear_ratio) * -1.45
	if colliders_on != _gear_colliders_on:
		_gear_colliders_on = colliders_on
		for gear: GearUnit in gears:
			var collider := gear.part.get_node("Collider") as CollisionShape3D
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
	t.mach = speed / 340.0
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
