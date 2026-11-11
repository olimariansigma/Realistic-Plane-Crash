class_name ControlState
extends RefCounted
## Pilot commands, written by the input layer and read by the aircraft once
## per physics tick. Plain data so UI, gyro and test autopilots can all drive it.

## +1 = stick back (nose up).
var pitch: float = 0.0
## +1 = roll right.
var roll: float = 0.0
## +1 = nose right.
var yaw: float = 0.0
## 0..1.
var throttle: float = 0.0
## Index into AircraftDef.flap_steps_deg.
var flap_step: int = 0
var gear_down: bool = true
## 0..1 wheel brakes.
var brake: float = 0.0
## Ground spoilers / speed brakes.
var spoilers: bool = false
