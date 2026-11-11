class_name EngineDef
extends Resource

@export var name: StringName
## Structural part the thrust is applied to.
@export var part: StringName
## Thrust line position and direction, aircraft frame.
@export var position: Vector3
@export var direction: Vector3 = Vector3.FORWARD
## Static sea-level thrust at full throttle (N).
@export var max_thrust: float = 100000.0
## Fraction of max thrust at idle.
@export var idle_fraction: float = 0.05
## First-order spool time constant (s).
@export var spool_time: float = 3.0
## Thrust lost per unit Mach number (high-bypass ~0.45, low-bypass ~0.1).
@export var mach_lapse: float = 0.4
