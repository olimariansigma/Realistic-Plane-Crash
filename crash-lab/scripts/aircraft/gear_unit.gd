class_name GearUnit
extends RefCounted
## Ray-cast oleo strut and tyre model. The ground force is applied to the gear
## leg's own rigid body, so it reaches the airframe through the leg's joint.

const SLIP_PEAK := 0.14  # tan of the slip angle where lateral grip saturates (~8 deg)

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
	if not ray.is_colliding():
		compression = maxf(compression - 2.0 * dt, 0.0)
		if wheel_visual != null:
			wheel_visual.position.y = compression
		return
	var hit := ray.get_collision_point()
	var normal := ray.get_collision_normal()
	var basis := part.xf.basis
	var origin := part.xf.origin + basis * local_pivot
	var axis_down := -basis.y
	var x := clampf(def.free_length - origin.distance_to(hit), 0.0, def.travel)
	var v_c := frame.velocity_at(hit)
	var rate := v_c.dot(axis_down)
	var f := maxf(def.spring_k * x + def.damper_c * rate, 0.0)
	compression = x
	if wheel_visual != null:
		wheel_visual.position.y = x
	if f <= 0.0:
		return
	on_ground = true
	load = f

	# Steering fades with speed so full rudder at rotation speed is a few degrees.
	var speed := v_c.length()
	if def.steer_max_deg > 0.0:
		steer_rad = -yaw_input * deg_to_rad(def.steer_max_deg) / (1.0 + speed * speed * 0.012)
	var fwd := -basis.z
	if steer_rad != 0.0:
		fwd = fwd.rotated(basis.y, steer_rad)
	fwd = (fwd - normal * fwd.dot(normal)).normalized()
	var lat := normal.cross(fwd)
	var v_f := v_c.dot(fwd)
	var v_l := v_c.dot(lat)
	var f_long := -f * (def.rolling_mu + def.brake_mu * brake) * clampf(v_f * 2.0, -1.0, 1.0)
	var f_lat := -f * def.lateral_mu * clampf(v_l / maxf(absf(v_f) * SLIP_PEAK, 0.6), -1.0, 1.0)
	part.push_force(normal * f + fwd * f_long + lat * f_lat, hit)
