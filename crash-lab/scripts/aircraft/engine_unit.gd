class_name EngineUnit
extends RefCounted

const RHO0 := 1.225
const SPEED_OF_SOUND := 340.0

var def: EngineDef
var part: AircraftPart
var local_pos: Vector3
var local_dir: Vector3
## Current output 0..1 (lags the throttle by the spool time constant).
var spool: float = 0.0
## False once the engine is starved, torn off or destroyed.
var running: bool = true
var thrust: float = 0.0
## Afterburner setting 0..1 (0 when unlit or not fitted).
var afterburner: float = 0.0


func setup(engine: EngineDef, owner: AircraftPart) -> void:
	def = engine
	part = owner
	local_pos = engine.position - owner.def.com
	local_dir = engine.direction.normalized()


## `sound_speed` is the local speed of sound (m/s).
func apply(throttle: float, rho: float, dt: float, sound_speed: float) -> void:
	var target := 0.0
	if running:
		target = def.idle_fraction + (1.0 - def.idle_fraction) * throttle
	var tau := def.spool_time if running else 0.6
	spool += (target - spool) * (1.0 - exp(-dt / tau))
	if spool < 0.001:
		thrust = 0.0
		afterburner = 0.0
		return
	var basis := part.xf.basis
	var dir := basis * local_dir
	var pos := part.xf.origin + basis * local_pos
	var mach := maxf(part.velocity_at(pos).dot(dir), 0.0) / sound_speed
	var rated := def.max_thrust * spool
	# Afterburner: the last tenth of throttle travel, once the core is spooled up.
	afterburner = 0.0
	if def.afterburner_thrust > def.max_thrust and running and throttle > 0.9 and spool > 0.88:
		afterburner = (throttle - 0.9) * 10.0
		rated += (def.afterburner_thrust - def.max_thrust) * afterburner
	thrust = rated * pow(rho / RHO0, 0.7) * maxf(1.0 - def.mach_lapse * mach, 0.0)
	part.push_force(dir * thrust, pos)
