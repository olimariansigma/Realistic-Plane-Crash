class_name CrashReport
extends RefCounted
## Everything the report screen shows about one crash. Plain data.

var aircraft_name: String = ""
var impact_speed: float = 0.0         ## m/s
var impact_velocity: Vector3          ## m/s, world frame (x east, y up, z south)
var impact_vertical_speed: float = 0.0  ## m/s, negative = descending
var impact_pitch_deg: float = 0.0
var impact_roll_deg: float = 0.0
var impact_angle_deg: float = 0.0     ## flight-path angle below the horizon
var peak_g: float = 0.0               ## highest seat peak
var duration: float = 0.0             ## s from first impact to rest
var joints_broken: int = 0
var joints_total: int = 0
var skin_lost: int = 0
var skin_total: int = 0
var fires: int = 0
var seats: Array[SeatResult] = []
var freds: Array[FredResult] = []
var survival_overall: float = 1.0     ## mean of seat survival
var survivors_expected: float = 0.0   ## sum of seat survival
var verdict: String = ""              ## one line, e.g. "Survivable with serious injuries"


func seat_count() -> int:
	return seats.size()
