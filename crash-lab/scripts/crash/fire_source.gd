class_name FireSource
extends RefCounted
## A burning spot on a part. Shared by the FX pool (to draw it) and the
## survival model (to work out who it reaches).

var part: AircraftPart
## Position in the part's local frame.
var local_pos: Vector3
## 0..1, from the fuel available.
var intensity: float = 0.5
## Aircraft.sim_time when it lit.
var start_time: float = 0.0


func world_position() -> Vector3:
	return part.global_transform * local_pos
