class_name AeroSurface
extends RefCounted
## Runtime aerodynamic strip. Looks up finite-wing CL and profile CD from
## tables built once at load, then applies lift, drag and pitching moment to
## its structural part at the strip's own position.

const STEP_DEG := 0.5
const TABLE_SIZE := 721
const RHO0 := 1.225

var def: SurfaceDef
var part: AircraftPart
var local_pos: Vector3
var local_normal: Vector3
var local_chord: Vector3
var local_span: Vector3

var cl_table: PackedFloat32Array
var cd_table: PackedFloat32Array
## 1 / (pi e AR): induced angle (rad) and induced drag per unit CL.
var induced_k: float = 0.0
## Section lift slope (1/rad) near zero AoA, for the ground-effect ratio.
var section_slope: float = 6.0
## Finite-wing stall angle (deg) where the table's CL peaks.
var stall_deg: float = 15.0
var max_deflection: float = 0.0
var trim_rad: float = 0.0
var cm0: float = 0.0

# Outputs of the last apply(), read by telemetry.
var aoa_deg: float = 0.0
var cl: float = 0.0
var lift: float = 0.0
var dyn_pressure: float = 0.0


func setup(surface: SurfaceDef, owner: AircraftPart) -> void:
	def = surface
	part = owner
	local_pos = surface.position - owner.def.com
	local_normal = surface.normal.normalized()
	local_chord = surface.chord_dir.normalized()
	local_span = local_chord.cross(local_normal).normalized()
	induced_k = 1.0 / (PI * surface.efficiency * maxf(surface.aspect_ratio, 0.1))
	max_deflection = deg_to_rad(surface.max_deflection_deg)
	trim_rad = deg_to_rad(surface.trim_deg)
	cm0 = surface.airfoil.cm0
	_build_tables(surface.airfoil)


## Solves cl = section_cl(alpha - k * cl) for every geometric AoA so the
## runtime needs a single table lookup instead of an iteration per tick.
func _build_tables(airfoil: AirfoilDef) -> void:
	cl_table.resize(TABLE_SIZE)
	cd_table.resize(TABLE_SIZE)
	var k_deg := rad_to_deg(induced_k)
	var cl_curve := airfoil.cl_curve
	var cd_curve := airfoil.cd_curve
	section_slope = (cl_curve.sample(AirfoilDef.aoa_to_x(2.0))
			- cl_curve.sample(AirfoilDef.aoa_to_x(-2.0))) / deg_to_rad(4.0)
	var best := -10.0
	for i: int in TABLE_SIZE:
		var aoa := -180.0 + float(i) * STEP_DEG
		var lo := -3.0
		var hi := 3.0
		for _n: int in 28:
			var mid := (lo + hi) * 0.5
			var eff := wrapf(aoa - k_deg * mid, -180.0, 180.0)
			if mid - cl_curve.sample(AirfoilDef.aoa_to_x(eff)) < 0.0:
				lo = mid
			else:
				hi = mid
		var c := (lo + hi) * 0.5
		cl_table[i] = c
		cd_table[i] = cd_curve.sample(AirfoilDef.aoa_to_x(wrapf(aoa - k_deg * c, -180.0, 180.0)))
		if aoa > 0.0 and aoa < 45.0 and c > best:
			best = c
			stall_deg = aoa


## `act` is the actuator state (pitch, roll, yaw) in [-1, 1].
func apply(rho: float, act: Vector3, trim: float, flap_ratio: float, spoiler: float,
		ground_y: float, adef: AircraftDef) -> void:
	var p := part
	var basis := p.xf.basis
	var pos := p.xf.origin + basis * local_pos
	var v := p.lin_vel + p.ang_vel.cross(pos - p.xf.origin)
	var span := basis * local_span
	var v2 := v - span * v.dot(span)
	var speed_sq := v2.length_squared()
	if speed_sq < 0.04:
		lift = 0.0
		cl = 0.0
		dyn_pressure = 0.0
		return
	var normal := basis * local_normal
	var chord := basis * local_chord
	var aoa := atan2(-v2.dot(normal), v2.dot(chord))
	aoa_deg = rad_to_deg(aoa)

	var deflection := clampf(def.control_mix.dot(act), -1.0, 1.0) * max_deflection
	var lookup := wrapf(aoa_deg + rad_to_deg(def.effectiveness * deflection + trim * trim_rad),
			-180.0, 179.999)
	var t := (lookup + 180.0) / STEP_DEG
	var i := int(t)
	var f := t - float(i)
	var c_l := lerpf(cl_table[i], cl_table[i + 1], f)
	var c_d := lerpf(cd_table[i], cd_table[i + 1], f)

	# Attached-flow weight: flap/spoiler increments and induced drag fade out
	# past the stall, where the table's flat-plate regime takes over.
	var attached := 1.0 - smoothstep(stall_deg, stall_deg + 12.0, absf(aoa_deg))

	# Ground effect (McCormick): the ground suppresses downwash, so induced
	# angle and induced drag shrink by phi within about one span of the surface.
	var phi := 1.0
	var h := pos.y - ground_y
	if h < def.full_span:
		var r := 16.0 * maxf(h, 0.05) / def.full_span
		phi = r * r / (1.0 + r * r)
		var sk := section_slope * induced_k
		c_l *= lerpf(1.0, (1.0 + sk) / (1.0 + sk * phi), attached)

	var cm := cm0
	if def.flap_fraction > 0.0 and flap_ratio > 0.0:
		var fr := def.flap_fraction * flap_ratio * attached
		c_l += adef.flap_cl_gain * fr
		c_d += adef.flap_cd_gain * def.flap_fraction * flap_ratio * flap_ratio
		cm += adef.flap_cm_gain * fr
	if def.spoiler_fraction > 0.0 and spoiler > 0.0:
		c_l -= adef.spoiler_cl_loss * def.spoiler_fraction * spoiler * attached
		c_d += adef.spoiler_cd_gain * def.spoiler_fraction * spoiler
	c_d += induced_k * phi * c_l * c_l * attached

	var q := 0.5 * rho * speed_sq
	var qs := q * def.area
	var inv_speed := 1.0 / sqrt(speed_sq)
	var flow := v2 * inv_speed
	var force := span.cross(flow) * (qs * c_l) - flow * (qs * c_d)
	p.push_force(force, pos)
	if cm != 0.0:
		p.push_torque(span * (qs * def.chord * cm * attached))
	cl = c_l
	lift = qs * c_l
	dyn_pressure = q
