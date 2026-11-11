class_name FlightTelemetry
extends RefCounted
## Read-only snapshot of the aircraft state, refreshed every physics tick.
## The HUD and recorder read this; nothing but Aircraft writes it.

## True airspeed and indicated airspeed, m/s.
var tas: float = 0.0
var ias: float = 0.0
var mach: float = 0.0
## Wing angle of attack and sideslip, degrees.
var aoa_deg: float = 0.0
var sideslip_deg: float = 0.0
## Load factor felt at the cockpit along the aircraft's up axis (1 = level).
var g_load: float = 1.0
## Magnitude of total felt acceleration, in g.
var g_total: float = 1.0
## Vertical speed, m/s (+ = climbing).
var vertical_speed: float = 0.0
var pitch_deg: float = 0.0
var roll_deg: float = 0.0
var heading_deg: float = 0.0
## Height above ground under the aircraft and above the world datum, m.
var altitude_agl: float = 0.0
var altitude_msl: float = 0.0
## Average engine output, 0..1.
var thrust_fraction: float = 0.0
var flap_ratio: float = 0.0
## 0 = up, 1 = down and locked.
var gear_ratio: float = 1.0
var trim: float = 0.0
var on_ground: bool = false
var stall_warning: bool = false
## Fraction of the airframe's structural joints still intact.
var integrity: float = 1.0
var crashed: bool = false
