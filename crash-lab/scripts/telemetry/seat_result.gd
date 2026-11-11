class_name SeatResult
extends RefCounted
## One seat's outcome in the crash report. Plain data.

var label: String = ""            ## "CPT", "12A"...
var row: int = 0
var column: int = 0               ## 0-based position across the row, left to right
var columns_in_row: int = 1
var is_crew: bool = false
var has_fred: bool = false
var zone: String = ""             ## fuselage part name, e.g. "fus_mid"
var peak_g: float = 0.0
var peak_g_axes: Vector3          ## x lateral, y vertical, z fore-aft, in g
var hic: float = 0.0
var intrusion: float = 0.0        ## 0..1 fraction of survivable space lost
var fire: float = 0.0             ## 0..1 fire exposure
var ejected: bool = false
var p_decel: float = 0.0          ## 0..1 probability of fatal injury from each cause
var p_head: float = 0.0
var p_intrusion: float = 0.0
var p_fire: float = 0.0
var survival: float = 1.0         ## 0..1
var cause: String = ""            ## "Deceleration", "Head impact", "Structure", "Fire", "Ejected" or ""
