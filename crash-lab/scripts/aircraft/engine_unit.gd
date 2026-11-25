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
## 1 = healthy. A fire eats it over FIRE_LIFE seconds: the engine surges and
## loses thrust, then fails, and the thrust asymmetry yaws and banks the
## aircraft toward the dead side.
var health: float = 1.0
var _surge_phase: float = 0.0
## Set when the fire has destroyed the engine (read once by the HUD).
var burned_out: bool = false

const FIRE_LIFE := 25.0
## Drag area of a stopped, windmilling engine as a share of its frontal area.
const WINDMILL_CD := 0.55


func setup(engine: EngineDef, owner: AircraftPart) -> void:
	def = engine
	part = owner
	local_pos = engine.position - owner.def.com
	local_dir = engine.direction.normalized()


## `sound_speed` is the local speed of sound (m/s).
func apply(throttle: float, rho: float, dt: float, sound_speed: float) -> void:
	if part.burning > 0.0 and running:
		health -= dt * part.burning / FIRE_LIFE
		if health <= 0.0:
			health = 0.0
			running = false
			burned_out = true
	if not running and part.joint != null:
		_windmill_drag(rho)
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
	if health < 1.0:
		# A burning engine surges: thrust drops with the damage and pulses.
		_surge_phase += dt * 6.3
		thrust *= health * (0.8 + 0.2 * sin(_surge_phase) * sin(_surge_phase * 0.37))
	part.push_force(dir * thrust, pos)


## A failed engine still in the airflow windmills: a large drag on its side,
## which is what makes an engine failure yaw the aircraft so hard.
func _windmill_drag(rho: float) -> void:
	var basis := part.xf.basis
	var pos := part.xf.origin + basis * local_pos
	var v := part.velocity_at(pos)
	var speed := v.length()
	if speed < 5.0:
		return
	var area := PI * part.def.r0 * part.def.r0 * WINDMILL_CD
	part.push_force(v * (-0.5 * rho * speed * area), pos)
