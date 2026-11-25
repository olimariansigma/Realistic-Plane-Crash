class_name GearUnit
extends RefCounted
## Ray-cast oleo strut and tyre model. The ground force is applied to the gear
## leg's own rigid body, so it reaches the airframe through the leg's joint.

const SLIP_PEAK := 0.14  # tan of the slip angle where lateral grip saturates (~8 deg)
## Tyre failure: brakes held (>= 50 %) while the engines push with more than
## BURST_THROTTLE for BURST_TIME seconds, on a braked gear on the ground: the
## locked tyres are dragged and scrubbed until they burst. Nothing else
## bursts them.
const BURST_THROTTLE := 0.3
const BURST_TIME := 2.0
## On the rims: far more rolling drag, less side grip, and the gear sits lower
## by this share of the wheel radius.
const RIM_ROLLING_MU := 0.1
const RIM_LATERAL_FACTOR := 0.5
const RIM_DROP := 0.4

var def: GearDef
var part: AircraftPart
var ray: RayCast3D
var local_pivot: Vector3
## Visual nodes: the whole leg (hidden/rotated when retracting) and the wheel
## bogie, which slides up the strut as it compresses.
var leg_visual: Node3D
var wheel_visual: Node3D

var compression: float = 0.0
var on_ground: bool = false
var load: float = 0.0
var steer_rad: float = 0.0
## True once the tyres on this gear have burst. `burst_now` is set for the one
## tick it happens (Aircraft raises the event and clears it).
var burst: bool = false
var burst_now: bool = false
var burst_at: Vector3
## Seconds of brakes held against thrust so far; the throttle (0..1) is set
## by Aircraft each tick.
var scrub: float = 0.0
var throttle: float = 0.0
var _was_on_ground: bool = false
## Contact patch (world) and rolling speed while on the ground, for effects.
var contact: Vector3
var ground_speed: float = 0.0


func setup(gear: GearDef, owner: AircraftPart) -> void:
	def = gear
	part = owner
	local_pivot = gear.pivot - owner.def.com
	ray = RayCast3D.new()
	ray.name = "GroundRay"
	ray.enabled = false
	ray.position = local_pivot
	ray.target_position = Vector3(0.0, -gear.free_length, 0.0)
	ray.collision_mask = 1
	owner.add_child(ray)


## `deployed` is the gear position 0..1; only a locked-down leg carries load.
## `frame` is the root part of the assembly the leg is bolted to. Contact
## velocities are taken from it, not from the leg: the leg is light, so a
## stiff tyre or damper force fed back through the leg's own velocity would
## overshoot every step and fight the joint solver.
func apply(deployed: float, yaw_input: float, brake: float, dt: float, frame: AircraftPart) -> void:
	on_ground = false
	load = 0.0
	if deployed < 0.98 or part.joint == null and part.parent_index >= 0:
		compression = 0.0
		return
	ray.force_raycast_update()
	var drop := def.wheel_radius * RIM_DROP if burst else 0.0
	if not ray.is_colliding():
		compression = maxf(compression - 2.0 * dt, 0.0)
		if wheel_visual != null:
			wheel_visual.position.y = compression + drop
		_was_on_ground = false
		return
	var hit := ray.get_collision_point()
	var normal := ray.get_collision_normal()
	var basis := part.xf.basis
	var origin := part.xf.origin + basis * local_pivot
	var axis_down := -basis.y
	var x := clampf(def.free_length - drop - origin.distance_to(hit), 0.0, def.travel)
	var v_c := frame.velocity_at(hit)
	# Stroke rate is the closing speed along the ground normal, projected onto
	# the strut. Using the strut axis directly would count forward speed as
	# stroke whenever the aircraft is pitched, unloading the gear nose-down.
	var rate := -v_c.dot(normal) / maxf(-axis_down.dot(normal), 0.3)
	var f := maxf(def.spring_k * x + def.damper_c * rate, 0.0)
	compression = x
	if wheel_visual != null:
		wheel_visual.position.y = x + drop
	var touchdown := not _was_on_ground
	_was_on_ground = f > 0.0
	if f <= 0.0:
		return
	on_ground = true
	load = f
	contact = hit
	ground_speed = v_c.length()

	# Steering fades with speed so full rudder at rotation speed is a few degrees.
	var speed := v_c.length()
	if def.steer_max_deg > 0.0:
		steer_rad = -yaw_input * deg_to_rad(def.steer_max_deg) / (1.0 + speed * speed * 0.012)
	var fwd := -basis.z
	if steer_rad != 0.0:
		fwd = fwd.rotated(basis.y, steer_rad)
	var along := fwd - normal * fwd.dot(normal)
	# Nose straight down into the ground: no rolling direction to speak of.
	fwd = along.normalized() if along.length_squared() > 1.0e-6 else basis.y
	var lat := normal.cross(fwd)
	var v_f := v_c.dot(fwd)
	var v_l := v_c.dot(lat)
	if not burst and def.brake_mu > 0.0:
		if brake >= 0.5 and throttle > BURST_THROTTLE:
			scrub += dt
			if scrub >= BURST_TIME:
				burst = true
				burst_now = true
				burst_at = hit
		else:
			scrub = 0.0
	var rolling := def.rolling_mu + (RIM_ROLLING_MU if burst else 0.0)
	var lateral := def.lateral_mu * (RIM_LATERAL_FACTOR if burst else 1.0)
	var f_long := -f * (rolling + def.brake_mu * brake) * clampf(v_f * 2.0, -1.0, 1.0)
	var f_lat := -f * lateral * clampf(v_l / maxf(absf(v_f) * SLIP_PEAK, 0.6), -1.0, 1.0)
	part.push_force(normal * f + fwd * f_long + lat * f_lat, hit)
