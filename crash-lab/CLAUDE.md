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
| `godot --headless --path . -s res://tools/gen_aircraft.gd` | Regenerates `data/airfoils/*.tres` and `data/aircraft/*.tres` from the parameter tables in the script. |
| `godot --headless --path . --fixed-fps 60 -s res://tools/flight_probe.gd -- <id> <takeoff\|cruise>` | Prints a telemetry time series for tuning. |
| `xvfb-run -a godot --path . -s res://tools/shot.gd -- <id> <runway\|air\|approach> <seconds> <out.png>` | Renders the flight scene offscreen (needs `mesa-vulkan-drivers` for lavapipe). |

One-off: `godot --headless --path . -s res://tests/<file>.gd` runs a single test.
Release export needs `GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}` set.

## Milestones

1. **Toolchain + APK skeleton** - done
2. **Flight model + controls (one plane)** - done
3. **Hangar + 3 planes** - done
4. **Fracture crash** - done
5. **FRED + cutaway** - done (plus piece-by-piece skin breakup and the visual overhaul)
6. **Telemetry + survival report** - done
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

Directories appear as the milestone that needs them lands.

## Architecture

Planned shape. Sections are updated as each milestone lands; anything not yet
built is marked *(planned)*.

- **Aircraft are data.** An `AircraftDef` (`scripts/aircraft/defs/`) lists
  parts (mass, inertia, geometry, joint thresholds), aero surfaces (area,
  airfoil, control mix), engines, gear and seat blocks. `AirframeBuilder`
  turns it into rigid bodies, colliders, joints and procedural meshes
  (`MeshFactory`). The runtime has no per-type code; a new plane is a new
  `.tres`. The three shipped planes are written by `tools/gen_aircraft.gd`.
- **Airframe is multi-body from the start.** Every part is an `AircraftPart`
  (`RigidBody3D`, origin at its own centre of mass, explicit inertia) held to
  its parent by a locked `Generic6DOFJoint3D`. Parts collide with the world
  only, never with each other.
- **Flight model** (`aircraft.gd`, `aero_surface.gd`). Forces only, applied in
  `_physics_process` to the part that carries them:
  - Each `AeroSurface` strip takes the air velocity at its own position, so
    roll/pitch/yaw damping and asymmetric stall come from geometry.
  - `AirfoilDef` curves are section (2D) data over -180..180 deg. At load each
    strip solves `cl = section(alpha - cl / (pi e AR))` into a 0.5 deg table,
    so stall angle and lift slope depend on aspect ratio and runtime cost is
    one lookup.
  - Induced drag `cl^2 / (pi e AR)`, flaps and spoilers as section increments
    that fade past the stall, pitching moment about the quarter chord.
  - Ground effect (McCormick): induced angle and drag scale by
    `phi = (16h/b)^2 / (1 + (16h/b)^2)`.
  - Controls shift the lookup angle by `effectiveness * deflection`; trim
    shifts tailplane incidence. Auto-trim integrates held stick into trim.
  - Engines: first-order spool, density and Mach lapse, thrust at the nacelle.
  - Gear: ray-cast oleo (spring + damper) and a slip-angle tyre model, applied
    to the gear leg's own body so landing loads go through its joint.
  - Bluff-body drag per part from `drag_area`, ISA density with altitude.
  - Not modelled: wing downwash on the tail, compressibility, propwash, wind.
- **Scene flow.** `Game` autoload (`GameState`) loads the next scene and the
  aircraft def on loader threads and pre-generates meshes on a worker thread
  behind a loading overlay. `FlightScene` builds world, aircraft, `CameraRig`
  and the touch HUD (`FlightHud` writes `ControlState`, reads
  `FlightTelemetry`).
- **Hangar** (`scripts/hangar/hangar.gd`, `HangarUi`). Turntable showroom with
  an orbit camera. Selecting a plane loads its def on a loader thread and its
  meshes on a worker thread, then swaps a physics-free display model in.
  Planes are discovered by listing `data/aircraft/`, so dropping in a `.tres`
  adds one. Wall and floor lighting is baked into an unshaded shader.
- **Crash** (`scripts/crash/`).
  - `StructureMonitor` computes every joint's force and moment each physics
    tick by inverse dynamics (Godot's Jolt does not expose joint impulses):
    the residual `m a - F_applied - m g` summed over the subtree outboard of a
    joint is the joint load plus that subtree's contact force. It is exact
    when at most one side of the joint is touching something, and falls back
    to Jolt's estimated contact impulses (taking the smaller answer)
    otherwise. The header comment in the file has the derivation.
  - A joint breaks when its filtered load passes the part's `break_force` or
    `break_torque`. `Aircraft.detach()` frees the joint, relabels assemblies,
    flames out orphaned engines and ignites ruptured tanks.
  - Measured margins: normal flight peaks at ~55 % of break (outer wing in a
    roll), a 2.5 m/s touchdown at ~30 %. Full aileron or a hard pull-up well
    above cruise speed will fold the wings; that is intended.
  - Deformation: the airframe is pre-fractured along its parts, and each part
    carries two dent slots driven into the `airframe.gdshader` vertex stage.
    Dent depth is `energy / (m g * 12)`, i.e. structure crushing at 12 g,
    pushed along the contact impulse. No `SoftBody3D`.
  - `DebrisPool`: fixed set of fragment bodies, oldest recycled first, frozen
    to static with collisions off 0.6 s after they stop. `FxPool`: pooled
    fire/smoke/dust emitters. `CrashDirector` maps structural events to both
    and decides when the wreck is at rest.
- **Skin pieces** (`mesh_factory.gd`, `SkinPiece`, `ChunkPool`). A part is
  drawn as separate skin pieces over a core: fuselage panels (bay x
  quadrant), wing box segments, control surfaces, cowl halves, pylons.
  Underneath sit frames, longerons and floor (fuselage), spars and ribs
  (wing) or the fan and hot section (engine). `Aircraft.shed_pieces()` tears
  pieces off nearest-first and `ChunkPool` flies each one as its own rigid
  body. Four things shed skin: impacts (about one panel per 0.4 m of crush),
  joint breaks (the skin around the break), scraping along the ground, and
  the airstream over already-broken structure. Measured: firm landing 0 %,
  30 m flat drop 25-40 %, cruise-speed dive 70-100 % of pieces. While a part
  is intact it swaps to one merged mesh beyond 170 m.
- **Looks.** One shared material samples one 1024 px atlas
  (`tools/gen_atlas.gd` -> `assets/atlas.png`, imported VRAM-compressed, ASTC
  on Android): cabin windows, windscreen, doors, panel lines, fan face.
  Vertex colour carries the livery. Skin is two-sided with primer on the
  inside. Control surfaces are hinged pieces that move with the actuators.
- **Occupants** (`scripts/occupants/`).
  - `Cabin` flattens the def's seat blocks into `Seat`s, draws them as one
    `MultiMesh` per fuselage part, and logs every seat's felt acceleration
    through a 0.085 s low-pass (chosen so the 13.4 m/s stop of the
    14 CFR 25.562 seat test reads near its 16 g).
  - `Fred` is a nine-body dummy on Jolt 6-DOF joints with per-limb peak g and
    a head HIC. Its seat mount is a plastic energy absorber whose stroke is
    the part's `crush_depth`; past it the mount bottoms out, and at 34 g
    sustained the restraint fails and the dummy is thrown clear.
  - Seats and dummies are dormant in normal flight. `Aircraft._update_arming`
    arms the cabin 1.2 s before a predicted impact (sink rate vs height, a
    ray along the flight path) or on any crash event.
  - Cutaway: a global shader uniform clips skin on the +X side of the
    centreline; the cabin, structure and dummies are shown while it is on,
    and stay shown on any part that has lost skin.
- **Telemetry + survival** (`scripts/telemetry/`).
  - Live HUD: speed, altitude, V/S, AoA, G, heading, attitude indicator.
  - `Aircraft` snapshots the impact velocity vector, pitch and roll on the
    last tick before the crash. `Cabin` logs peak g per seat (total and by
    seat axis); `Fred` logs peak g per limb, HIC, mount stroke and restraint
    load.
  - `InjuryModel.build_report()` turns that into a `CrashReport`: four
    independent risks per seat (deceleration by axis after Eiband, head by
    the NHTSA HIC curve, structural intrusion from dents and fuselage breaks,
    fire by distance and incapacitation) plus restraint failure. Full
    derivation and every constant: `docs/INJURY_MODEL.md`.
  - Measured outcomes, in order of severity: firm landing 100 %, gear-up
    belly landing 99-100 %, 30 m flat drop 23-80 % by type, cruise dive 0 %.
  - `CrashRecorder` records from cabin arming for up to 14 s: one keyframe
    track per body, keyed only while that body is moving, plus timed events
    for skin tearing, dents and fires. Replay turns the physics server off
    and writes interpolated transforms, at 0.1x to 1x with scrubbing.
  - `CrashReportScreen` shows impact figures, a tappable seat map coloured
    by survival, per-seat detail with FRED limb readings, and the replay bar.

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

## Gotchas found the hard way

- **Never feed a light body's own velocity into a stiff force on it.** Tyre
  and damper forces computed from the 1 t gear leg's velocity overshot every
  step and made the legs fight the joint solver (the aircraft crept sideways).
  `GearUnit` takes contact velocity from the assembly's root part instead.
- **Threaded resource loading fails under `--fixed-fps`** (random "Parse
  Error" on scripts/resources). It is a test-mode artifact: headless tests
  build scenes directly, and the real boot flow is checked without the flag.
  Even so, `Game` loads the def and the scene one after the other and keeps
  the def script classes compiled on the main thread.
- **No `preload()` in scripts reachable from a threaded scene load** (same
  class of failure). Use `load()` at runtime.
- **Autoload globals are invisible to `--check-only`.** Autoload scripts carry
  a `class_name` and a static `instance()`; use that, not the bare global.
- **`SceneTree._initialize()` runs before the root is in the tree.** Tests
  build their scene on the first `_process`/`_physics_process` call.
- **"Jolt job system exceeded the maximum number of jobs"** appears now and
  then in headless fixed-fps runs, where steps run back to back with no frame
  pacing. Non-deterministic, harmless there; investigate if seen on device.

- **Spawn height sign.** `ground_clearance` was once computed with the CG
  offset subtracted instead of added; the aircraft spawned 0.5 m high and the
  drop alone loaded the gear to 57 % of break. If parked joint loads are not
  flat from the first tick, check the spawn pose.
- **Retracted gear has its collider disabled.** A leg torn off in that state
  fell through the ground until `detach()` re-enabled it.

- **GDScript enums must not shadow native classes.** `enum Control` in a
  script fails to parse ("shadows a native class").
- **Primitive meshes have 0..1 UVs**, which span the whole atlas. Anything
  using `BoxMesh`/`CapsuleMesh` with the airframe material sets the
  `uv_rect` instance uniform to one tile (`AirframeBuilder.tile_rect`).
- **Never joint a frozen body to a moving one.** Dormant FRED limbs are
  frozen; their joints are created unwired and only get node paths in
  `Fred.activate()`. Wired earlier, the belt would pin the fuselage in place.

## Not verifiable in this environment

No Android device or emulator is attached to the build machine. APK exports
are checked for signature, ABI, manifest and size, and gameplay is tested
headless on Linux. On-device frame times must be measured on real hardware;
until then, performance numbers in status reports are desktop/headless only.
