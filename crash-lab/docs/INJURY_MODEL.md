# Injury and survival model

How Aircraft Crash Lab turns a simulated crash into a survival percentage for
every seat. The code is `scripts/telemetry/injury_model.gd`; the constants
there and the numbers here must match.

This is a game's estimate built on published human-tolerance figures. It is
not validated against accident data and must not be used for anything real.

## What is measured

| Quantity | Where | How |
|---|---|---|
| Impact velocity vector, pitch, roll | `Aircraft` | Root-part state on the last tick before the first hard contact or structural failure. |
| Peak g per seat, by axis | `Cabin.track_seat` | Velocity of the seat's point on its fuselage part, differenced each physics tick, plus 1 g for gravity, low-passed at the part's crush time constant (0.07 to 0.105 s). Kept as a total and along the seat's lateral, vertical and fore-aft axes. |
| Peak g per FRED limb | `Fred.tick` | Each limb body's velocity, differenced per tick, low-passed at 0.03 s. Nine limbs. |
| Head injury criterion | `Fred.tick` | `max((mean g)^2.5 * duration)` over windows of one and two ticks (16.7 and 33 ms) of filtered head acceleration. |
| Seat mount stroke, restraint load | `Fred` | See "The seat mount" below. |
| Structural intrusion | `AircraftPart` dents, broken joints | Dent depth at the seat, and fuselage breaks next to it. |
| Fire | `Aircraft.fires` | Every fire's intensity and distance from the seat when the wreck stops. |

### Why the filters

Rigid bodies stop in one or two physics ticks. A 13 m/s stop over one 16.7 ms
tick is 80 g on paper; a real fuselage crushes for a tenth of a second or
more and the occupant sees a fraction of that. The seat filter stands in for
that crush. Its time constant follows the seat mount described below,
`tau = 1 / (0.8 * omega)`, which is 0.085 s for the narrow-body: an abrupt
13.4 m/s stop, the velocity change of the 14 CFR 25.562 longitudinal seat
test, then reads close to that test's 16 g peak (`tests/smoke_fred.gd`
measures 14.6 g).

### The seat mount

A FRED is not bolted rigidly to its seat. Its pelvis hangs on a plastic
energy absorber (`Fred._mount_force`): a spring with light damping and no
rebound, whose stroke is the fuselage part's `crush_depth` and which is
sized to reach 16 g exactly as the stroke runs out, `omega^2 = 16 g / stroke`.

| Aircraft | Crush depth | omega | Seat filter tau | Stop that uses the whole stroke |
|---|---|---|---|---|
| Wide-body | 1.1 m | 11.9 rad/s | 0.105 s | about 17 m/s |
| Narrow-body | 0.75 m | 14.5 rad/s | 0.086 s | about 14 m/s |
| Fighter | 0.5 m | 17.7 rad/s | 0.071 s | about 12 m/s |

So the same stop is gentler in an aircraft with more structure to crush.
Past the stroke the mount bottoms out on a stop ten times stiffer, which
is the structure having run out of crush. If the filtered mount load passes
34 g on the whole 82 kg dummy, the restraint fails and the dummy is thrown
clear.

Sled test results (`tests/smoke_fred.gd`):

| Stop | Seat | Pelvis | Head | HIC | Stroke | Outcome |
|---|---|---|---|---|---|---|
| 13.4 m/s | 14.6 g | 13.9 g | 28 g | 131 | 0.65 m | belted, torso folds forward 77 deg |
| 32 m/s | 34.9 g | 104 g | 94 g | 1994 | bottomed | restraint fails, ejected |

## The four risks

Each seat gets four independent probabilities of fatal injury.

### 1. Whole-body deceleration

Tolerance depends on direction (Eiband, 1959, for restrained seated
subjects and pulses near 0.1 s). The model uses the level at which about
half of occupants would die:

| Axis | 50 % level |
|---|---|
| Fore-aft | 45 g |
| Vertical (spine) | 25 g |
| Lateral | 20 g |

The seat's three axis peaks combine into one index,
`n = sqrt((gz/45)^2 + (gy/25)^2 + (gx/20)^2)`, and the risk is a logistic
curve around `n = 1`: `p = 1 / (1 + exp(-7 (n - 1)))`.

| n | p |
|---|---|
| 0.36 (16 g fore-aft) | 1 % |
| 0.75 | 15 % |
| 1.0 | 50 % |
| 1.25 | 85 % |
| 1.5 | 97 % |

### 2. Head injury

`p = Phi((ln HIC - 7.45231) / 0.73998)`, the NHTSA risk curve for AIS 4+
head injury. HIC 1000 gives about 18 %, HIC 1700 about 50 %.

Seats with a FRED use the dummy's measured HIC. Other seats estimate it as
`(1.9 * seat peak g)^2.5 * 0.033`: the sled test showed head acceleration at
1.9 times the seat's, and that formula reproduces the dummy's HIC there (138
estimated against 131 measured).

Note that the simulation steps at 60 Hz, so the shortest window is 16.7 ms
where the standard HIC15 allows any window up to 15 ms. Sharp head strikes
are under-resolved; treat HIC here as approximate.

### 3. Structural intrusion

Intrusion is the fraction of the seat's space taken by structure (0 to 1).

- **Dents.** Each part records up to two dents: centre, radius, depth and
  direction. Depth is `impact energy / (part mass * g * 12)`, that is,
  structure crushing at 12 g. At the seat the dent depth falls off with
  distance from its centre. Intrusion starts once that local depth exceeds a
  margin: the part's `crush_depth` for a dent from below (underfloor
  structure to use up first) down to 0.3 m for one from the side.
- **Breaks.** A seat within 1.3 m of a fuselage joint that has failed gets
  at least 0.6.

`p = intrusion^1.5`.

### 4. Fire

Tanks ignite when the part holding them breaks off at speed or is hit above
22 m/s; running engines ignite when torn off. Each fire has an intensity
from 0.35 to 1 set by the fuel in the part.

For a seat, `exposure = sum(intensity / (1 + (d / 6 m)^2))` over all fires,
with `d` measured when the wreck has stopped. How deadly that is depends on
whether the occupant can get out: `p = 1 - exp(-exposure * (0.6 + 2 * i))`,
where `i` is incapacitation, `1.5 * max(n - 0.4, intrusion)` clamped to 0..1.
Beside a large fire, an unhurt occupant has about a 45 % risk and an
incapacitated one about 93 %.

### Restraint failure

For a FRED, being thrown clear is taken as 95 % fatal. Seats without a
dummy have no mount to measure, so their restraint is assumed to fail
between 19 and 27 g of seat-level peak (the sled test puts the dummy's
failure in that range), at 90 % lethality.

## Combining

```
survival = (1 - p_decel) * (1 - p_head) * (1 - p_structure) * (1 - p_fire) * (1 - p_restraint)
```

The report's overall figure is the mean over all seats; "expected
survivors" is the sum. The cause shown for a seat is whichever risk is
largest, if any is above 5 %.

| Overall | Verdict |
|---|---|
| 90 % and up | Survivable: minor injuries likely |
| 60 to 90 % | Survivable with serious injuries |
| 20 to 60 % | Partially survivable |
| under 20 % | Unsurvivable |

## Known limits

- Contact impulses in Godot's Jolt integration are estimates, so impact
  energy and dent depth are approximate.
- Dummy limbs do not collide with the cabin, so there are no head strikes on
  seat backs; head loads come from the neck joint reaching its limits.
- Only seats with a FRED get a measured HIC and restraint load. The number
  of dummies follows the graphics quality setting (4, 8 or 12).
- No evacuation model: fire risk is a single exposure figure, not a
  time-to-escape simulation.
- Seat peaks include the 1 g of gravity, a small overstatement at low g.
