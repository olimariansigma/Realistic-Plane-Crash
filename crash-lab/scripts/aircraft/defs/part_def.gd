class_name PartDef
extends Resource
## One structural chunk of the airframe: a rigid body plus the joint that holds
## it to its parent. All positions are in the aircraft frame (-Z forward, +Y up,
## +X right wing), metres.

enum Kind { FUSELAGE, WING, STABILIZER, FIN, ENGINE, GEAR, CANOPY }

@export var name: StringName
## Name of the part this one is bolted to. Empty for the root part.
@export var parent: StringName
@export var kind: Kind = Kind.FUSELAGE

@export_group("Mass")
@export var mass: float = 1000.0
## Centre of mass. The rigid body's origin is placed here.
@export var com: Vector3
## Principal moments of inertia about the centre of mass (kg m^2), aircraft axes.
@export var inertia: Vector3 = Vector3.ONE

@export_group("Joint")
## Where the joint to the parent sits.
@export var anchor: Vector3
## Shear/tension load (N) at which the joint to the parent fails.
@export var break_force: float = 1.0e6
## Bending/torsion moment (N m) at which the joint to the parent fails.
@export var break_torque: float = 1.0e6

@export_group("Geometry")
## Bodies of revolution (FUSELAGE, ENGINE): front and back centre points.
## Lifting panels (WING, STABILIZER, FIN): root and tip quarter-chord points.
## GEAR: pivot and extended wheel-centre points.
## CANOPY: front and back of the dome; r0 = half width, r1 = height.
@export var p0: Vector3
@export var p1: Vector3
## Radius at p0 / p1, chord at root / tip, or wheel radius / strut radius.
@export var r0: float = 1.0
@export var r1: float = 1.0
## Panels: thickness-to-chord ratio. Bodies: length of the rounded nose cap at
## p0 (0 = flat end). GEAR: number of wheels on the axle.
@export var shape_a: float = 0.0
## Bodies: length of the tapered tail cap at p1 (0 = flat end).
@export var shape_b: float = 0.0
## 0 = main paint, 1 = accent colour, 2 = bare metal.
@export var skin: int = 0
## Fuselage nose bluntness: 0.5 is a blunt ellipse, 1.0 a pointed ogive.
@export var nose_power: float = 0.62
## How far the nose tip sits below the centreline, in radii.
@export var nose_droop: float = 0.28
## Radius at the very end of the tail cap as a fraction of the body radius.
@export var tail_ratio: float = 0.14
## How much of the tail taper is taken from the belly (1 = flat crown line).
@export var tail_upsweep: float = 0.72
## Cross-section scale (width, height): (1, 1) is a circle.
@export var squash: Vector2 = Vector2.ONE
## Height of a winglet on the tip of this panel (0 = none).
@export var winglet: float = 0.0

@export_group("Aerodynamics")
## Bluff-body drag area Cd*A (m^2) along the part's local X, Y and Z axes.
@export var drag_area: Vector3

@export_group("Crash")
## Fuel carried in this part. Drives fire intensity when the part ruptures.
@export var fuel_kg: float = 0.0
## Metres of structure that can crush before the occupied volume is reached.
@export var crush_depth: float = 0.5
