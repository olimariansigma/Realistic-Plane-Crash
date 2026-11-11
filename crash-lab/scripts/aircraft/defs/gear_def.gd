class_name GearDef
extends Resource
## Ray-cast oleo strut and tyre. The strut is its own structural part, so
## landing loads travel through its joint and can collapse it.

@export var name: StringName
## The GEAR part that carries this leg.
@export var part: StringName
## Top of the strut (ray origin), aircraft frame.
@export var pivot: Vector3
## Pivot to bottom of tyre with the strut fully extended (m).
@export var free_length: float = 2.5
## Usable stroke (m). Beyond it the wheel collider bottoms out.
@export var travel: float = 0.45
@export var spring_k: float = 1.0e6
@export var damper_c: float = 1.5e5
@export var wheel_radius: float = 0.55
## Nose-wheel steering lock at walking pace, degrees (0 = fixed).
@export var steer_max_deg: float = 0.0
@export var rolling_mu: float = 0.02
@export var brake_mu: float = 0.0
@export var lateral_mu: float = 0.8
## Cd*A added while extended (m^2).
@export var drag_area: float = 0.8
