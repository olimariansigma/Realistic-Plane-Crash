class_name Seat
extends RefCounted
## One seat and what its occupant went through. Geometry is filled by Cabin;
## the acceleration history by OccupantMonitor.

var index: int = 0
## "CPT", "F/O" or row + letter such as "12A".
var label: String = ""
var is_crew: bool = false
var row: int = 0
## Position across the row, left to right.
var column: int = 0
## Hip point in the aircraft frame and in the owning part's local frame.
var def_pos: Vector3
var local_pos: Vector3
var part_index: int = 0
var part: AircraftPart
## The dummy in this seat, if any.
var fred: Fred

# --- recorded during a crash (see OccupantMonitor) ---
var prev_vel: Vector3
var has_prev: bool = false
## Per-tick weight of the acceleration low-pass (set when the cabin arms).
var filter_alpha: float = 0.2
## Low-passed felt acceleration (m/s^2, world frame).
var accel: Vector3
## Peak felt acceleration in g: total, and split along the seat's own axes
## (x lateral, y vertical, z fore-aft).
var peak_g: float = 0.0
var peak_axes: Vector3
