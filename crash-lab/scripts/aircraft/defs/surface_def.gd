class_name SurfaceDef
extends Resource
## One aerodynamic strip. Forces are computed from the airflow at this strip's
## own position, so damping and asymmetric-stall moments come from geometry.

@export var name: StringName
## Structural part that carries this strip's loads.
@export var part: StringName
@export var airfoil: AirfoilDef

@export_group("Geometry")
## Aerodynamic centre (quarter chord, mid span of the strip), aircraft frame.
@export var position: Vector3
## Unit normal of the surface ("up" for a wing, sideways for a fin).
@export var normal: Vector3 = Vector3.UP
## Unit chord direction pointing at the leading edge.
@export var chord_dir: Vector3 = Vector3.FORWARD
@export var area: float = 10.0
@export var chord: float = 2.0
## Aspect ratio and span efficiency of the whole lifting surface this strip
## belongs to; they set lift-curve slope and induced drag.
@export var aspect_ratio: float = 8.0
@export var efficiency: float = 0.85
## Full span of the parent lifting surface, for ground effect.
@export var full_span: float = 30.0

@export_group("Control")
## Pilot input mix (pitch, roll, yaw) -> normalised deflection in [-1, 1].
## Positive deflection increases lift along +normal.
@export var control_mix: Vector3
@export var max_deflection_deg: float = 0.0
## Lift effectiveness of the control (d alpha / d delta). 1 = all-moving.
@export var effectiveness: float = 0.5
## Trim authority in degrees of incidence at full trim, signed like control_mix.x.
@export var trim_deg: float = 0.0
## Fraction of the strip that carries flaps (0..1).
@export var flap_fraction: float = 0.0
## Fraction of the strip that carries spoilers / lift dumpers (0..1).
@export var spoiler_fraction: float = 0.0
## How far those spoilers rise to help the ailerons at full roll input, on
## the down-going wing only (0 = they are not used for roll).
@export var roll_spoiler: float = 0.0

@export_group("Interference")
## True for the inboard wing strips whose lift sets the downwash at the tail.
@export var downwash_source: bool = false
## How much of the wing's downwash this strip sits in (0 = none, 1 = a
## tailplane directly behind the wing).
@export var downwash: float = 0.0
