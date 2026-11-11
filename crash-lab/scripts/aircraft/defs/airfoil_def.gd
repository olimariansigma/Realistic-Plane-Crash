class_name AirfoilDef
extends Resource
## Section (2D) aerodynamic data. Finite-wing effects are applied per surface
## from its aspect ratio, so one airfoil serves surfaces of any planform.
##
## Both curves cover the full circle so tumbling wreckage still gets sensible
## forces: curve x in [0, 1] maps to angle of attack in [-180, +180] degrees.

@export var display_name: String = ""
## Section lift coefficient vs AoA.
@export var cl_curve: Curve
## Section profile drag coefficient vs AoA (no induced drag).
@export var cd_curve: Curve
## Pitching-moment coefficient about the quarter chord (negative = nose down).
@export var cm0: float = 0.0
## Positive stall angle of the section. Used for stall warning and flap fade.
@export var stall_deg: float = 15.0


static func aoa_to_x(aoa_deg: float) -> float:
	return (aoa_deg + 180.0) / 360.0
