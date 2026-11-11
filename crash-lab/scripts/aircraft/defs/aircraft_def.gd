class_name AircraftDef
extends Resource
## Complete description of one aircraft. The runtime contains no per-type
## code: everything that makes a narrow-body different from a fighter is here.

@export_group("Identity")
@export var id: StringName
@export var display_name: String = ""
@export var category: String = ""
@export_multiline var description: String = ""
@export var paint: Color = Color(0.92, 0.94, 0.96)
@export var accent: Color = Color(0.1, 0.3, 0.7)

@export_group("Structure")
## Parents must appear before their children; parts[0] is the root.
@export var parts: Array[PartDef] = []

@export_group("Aerodynamics")
@export var surfaces: Array[SurfaceDef] = []
## Reference wing area (m^2) and span (m), for stats and coefficients.
@export var wing_area: float = 100.0
@export var wing_span: float = 30.0
## Flap deflection per detent, degrees. First entry is "up".
@export var flap_steps_deg: PackedFloat32Array = PackedFloat32Array([0.0])
## Section CL and CD added on a fully flapped strip at the last detent.
@export var flap_cl_gain: float = 1.0
@export var flap_cd_gain: float = 0.06
## Section pitching moment added at the last detent.
@export var flap_cm_gain: float = -0.1
## Seconds to travel the whole flap range.
@export var flap_time: float = 10.0
## Section CL lost / CD gained on a fully spoilered strip.
@export var spoiler_cl_loss: float = 0.6
@export var spoiler_cd_gain: float = 0.08

@export_group("Controls")
## Control surface slew rate in full deflections per second.
@export var control_rate: float = 2.5
## Auto-trim rate in full trim range per second at full stick.
@export var trim_rate: float = 0.12
## Trim [-1, 1] and throttle [0, 1] that hold level flight at v_cruise; preset
## for an in-flight start (measured by tests/smoke_flight.gd).
@export var cruise_trim: float = 0.0
@export var cruise_throttle: float = 0.3

@export_group("Propulsion")
@export var engines: Array[EngineDef] = []

@export_group("Landing gear")
@export var gear: Array[GearDef] = []
@export var gear_time: float = 6.0

@export_group("Cabin")
@export var seat_blocks: Array[SeatBlockDef] = []
## Indices into the flattened seat list that get a FRED dummy.
@export var fred_seats: PackedInt32Array

@export_group("Reference speeds")
## Rotation and in-flight-start speeds (m/s), for the HUD and spawn modes.
@export var v_rotate: float = 70.0
@export var v_cruise: float = 130.0
@export var v_never_exceed: float = 250.0
## Height of the aircraft reference origin above the ground when parked.
@export var ground_clearance: float = 3.0


func total_mass() -> float:
	var m := 0.0
	for p: PartDef in parts:
		m += p.mass
	return m


func center_of_mass() -> Vector3:
	var acc := Vector3.ZERO
	var m := 0.0
	for p: PartDef in parts:
		acc += p.com * p.mass
		m += p.mass
	return acc / maxf(m, 1.0)


## Whole-aircraft principal inertia about the centre of mass (parallel-axis
## sum of the parts), aircraft axes: x = pitch, y = yaw, z = roll.
func total_inertia() -> Vector3:
	var c := center_of_mass()
	var i := Vector3.ZERO
	for p: PartDef in parts:
		var d := p.com - c
		i.x += p.inertia.x + p.mass * (d.y * d.y + d.z * d.z)
		i.y += p.inertia.y + p.mass * (d.x * d.x + d.z * d.z)
		i.z += p.inertia.z + p.mass * (d.x * d.x + d.y * d.y)
	return i


func total_thrust() -> float:
	var t := 0.0
	for e: EngineDef in engines:
		t += e.max_thrust
	return t


func seat_count() -> int:
	var n := 0
	for b: SeatBlockDef in seat_blocks:
		n += b.rows * b.abreast.size()
	return n


func find_part(part_name: StringName) -> int:
	for i: int in parts.size():
		if parts[i].name == part_name:
			return i
	return -1
