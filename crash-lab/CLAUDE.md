# Aircraft Crash Lab

Android crash-physics sandbox: pick an aircraft in a hangar, fly it with a real
force-based flight model, crash it, and read a per-seat survival report.

**Stack (fixed):** Godot 4.4.1, GDScript only, Jolt Physics, Mobile renderer,
landscape, touch only. **Targets:** stable 60 FPS on mid-range Android
(3-4 GB RAM), APK under 150 MB.

## Build commands

All commands run from `crash-lab/` (the Godot project root).

| Command | What it does |
|---|---|
| `tools/setup_toolchain.sh` | Idempotent. Installs anything missing: Godot 4.4.1, export templates, JDK 17, Android SDK/NDK, debug keystore, editor settings. |
| `tools/check.sh` | Gate 1. `--import` plus `--check-only` on every `.gd`; any error fails. |
| `tools/smoke.sh` | Gate 2. Runs every `tests/smoke_*.gd` headless at fixed 60 FPS. |
| `tools/export_apk.sh [debug\|release]` | Gate 3. Exports `build/crash-lab-<mode>.apk`, verifies the signature and the 150 MB budget. |
| `tools/gate.sh` | Runs gates 1-3 in order. **Must pass before a milestone is committed.** |

One-off: `godot --headless --path . -s res://tests/<file>.gd` runs a single test.
Release export needs `GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}` set.

## Milestones

1. **Toolchain + APK skeleton** - done
2. Flight model + controls (one plane)
3. Hangar + 3 planes
4. Fracture crash
5. FRED + cutaway
6. Telemetry + survival report
7. Optimization pass

Each milestone ends with `tools/gate.sh` green, a commit, and a 5-line status.

## Layout

```
project.godot  export_presets.cfg
data/aircraft/      AircraftDef .tres files (one per plane; planes are data only)
scenes/             .tscn, mirrored by feature (boot, hangar, flight, report)
scripts/
  core/             autoloads: game state, settings, object pools
  aircraft/         AircraftDef + sub-resources, airframe builder, flight model
  crash/            structural joints, load monitor, debris pool, crumple
  occupants/        seats, FRED ragdoll, per-limb G tracking
  telemetry/        recorder, injury model, survival report, replay
  ui/               HUD, touch controls, hangar, report screen
shaders/            cutaway clip, crumple vertex shader
tests/              smoke_*.gd headless tests (SceneTree scripts)
tools/              gate and toolchain scripts
build/              export output (git-ignored)
```

Only `scenes/boot`, `scripts/boot`, `tests`, `tools` exist after milestone 1;
the rest is created by the milestone that needs it.

## Architecture

Planned shape. Sections are updated as each milestone lands; anything not yet
built is marked *(planned)*.

- **Aircraft are data.** *(planned, M2-M3)* An `AircraftDef` resource holds
  mass, inertia tensor, per-surface aero (area, CL/CD vs AoA curves, control
  limits), thrust, gear, seat layout and per-part break thresholds. The
  airframe (bodies, colliders, meshes, joints) is generated from the def at
  load time, so a new plane is a new `.tres` and nothing else.
- **Flight model.** *(planned, M2)* Forces only. Each aero surface samples the
  local airflow at its own position (so roll/pitch/yaw damping fall out of the
  geometry), looks up CL/CD at its own AoA, and applies lift/drag at that
  point. Stall comes from the curves, ground effect scales induced drag and
  lift by height/span, flaps shift the curves. Thrust and gear are forces too.
  Nothing sets a transform or a velocity directly.
- **Crash.** *(planned, M4)* Fuselage sections, wings, tail, engines and gear
  are separate `RigidBody3D` chunks joined by `Generic6DOFJoint3D`. Joint load
  is computed every physics frame and compared with the part's threshold;
  over-threshold joints break and spawn pooled debris and fire/smoke.
  Deformation is pre-fractured crumple chunks plus a vertex-shader crumple
  driven by impact energy and direction. No `SoftBody3D`.
- **Occupants.** *(planned, M5)* FRED dummies are Jolt-jointed ragdolls with
  per-limb G tracking, seated from the def's seat layout. The cutaway uses a
  clip-plane shader on a separate lower-poly interior shell.
- **Telemetry + survival.** *(planned, M6)* A recorder captures impact velocity,
  peak G per seat and per FRED, and per-seat-zone damage (intrusion, fire,
  deceleration). The injury model (HIC / peak-G thresholds, documented in
  `docs/` when written) turns that into survival % per seat and overall.

## Conventions

- **Units:** SI everywhere (m, kg, s, N, rad). Data fields authored in degrees
  carry a `_deg` suffix and are converted once at load.
- **Axes:** Godot's. `-Z` forward, `+Y` up, `+X` right wing. Body-frame vectors
  are named `*_local`, world-frame `*_world`.
- **Physics:** all forces in `_physics_process` / `_integrate_forces`, never
  in `_process`. Never write a body's transform or velocity to steer it.
- **Allocations:** none per frame in gameplay code. Reuse arrays, pool
  debris/particles, no string formatting outside throttled UI updates.
- **GDScript:** static typing on every variable, parameter and return; tabs;
  `snake_case` files, `PascalCase` `class_name`; `##` doc comments say why,
  not what. Private members start with `_`.
- **Scenes:** unique-name (`%Node`) lookups, not long node paths.
- **Tests:** `tests/smoke_<area>.gd` extends `SceneTree`, prints exactly one
  `SMOKE PASS: ...` or `SMOKE FAIL: ...` line and exits 0 / 1.

## Decisions

Made without asking, per the brief. Revisit if they stop fitting.

- **Project location.** The brief says `/crash-lab`; the project lives at
  `crash-lab/` inside the repo so it can be committed (`/crash-lab` is a
  symlink to it on the dev machine).
- **Godot 4.4.1** stable, the first 4.4 patch release with Jolt built in.
- **Prebuilt export template, not a Gradle build.** No plugins need custom
  Java, and it removes the NDK compile from every export. The NDK is still
  installed in case a Gradle build is needed later.
- **arm64-v8a only.** Every device in the target range is 64-bit, and one ABI
  keeps the engine's share of the APK at about 25 MB instead of 100+.
- **JDK 17** for the export (Godot 4.4's supported version), even where a
  newer JDK is also installed.
- **Default linear and angular damping are 0** (`project.godot`). Godot's 0.1
  default silently removed ~5% of free-fall speed in the first smoke test;
  drag is modelled explicitly, so hidden damping would corrupt the physics.
- **60 Hz physics with physics interpolation on.** Matches the frame target;
  `max_physics_steps_per_frame=4` so a slow frame degrades instead of spiraling.
- **Procedural geometry.** Airframes, cabins and dummies are generated from
  data rather than imported models. This is what makes "new plane by data
  only" true, and it keeps the APK small.
- **`emulate_touch_from_mouse` is on** so touch UI can be driven on desktop.

## Not verifiable in this environment

No Android device or emulator is attached to the build machine. APK exports
are checked for signature, ABI, manifest and size, and gameplay is tested
headless on Linux. On-device frame times must be measured on real hardware;
until then, performance numbers in status reports are desktop/headless only.
