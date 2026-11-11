class_name InjuryModel
extends RefCounted
## Turns what the simulation recorded into survival odds, seat by seat.
## Every constant here is explained in docs/INJURY_MODEL.md; keep the two in
## step. The model is deliberately simple and conservative: it is a game's
## estimate built on published tolerance figures, not a certification tool.
##
## Four independent ways to die, combined as
##     survival = (1 - p_decel)(1 - p_head)(1 - p_structure)(1 - p_fire)
## plus restraint failure, which is treated as near-certainly fatal.

## Whole-body deceleration at which half of restrained occupants die, by
## axis of the seat (g): fore-aft, vertical, lateral. After Eiband (1959).
const G_LIMIT_FORE_AFT := 45.0
const G_LIMIT_VERTICAL := 25.0
const G_LIMIT_LATERAL := 20.0
## Steepness of the deceleration risk curve around the limit.
const DECEL_STEEPNESS := 7.0
## NHTSA HIC risk curve for AIS 4+ head injury: Phi((ln HIC - MU) / SIGMA).
const HIC_MU := 7.45231
const HIC_SIGMA := 0.73998
## For seats without a dummy, head acceleration is taken as this multiple of
## the seat's, acting for HIC_WINDOW seconds (both read off the sled test).
const HEAD_AMPLIFICATION := 1.9
const HIC_WINDOW := 0.033
## Seat-level peak g between which unmonitored seats' restraints fail.
const RESTRAINT_FAIL_LOW := 19.0
const RESTRAINT_FAIL_HIGH := 27.0
const RESTRAINT_LETHALITY := 0.9
## Distance (m) at which a fire's effect has fallen to half.
const FIRE_RADIUS := 6.0
## A seat within this distance (m) of a fuselage break counts as crushed.
const BREAK_RADIUS := 1.3
const BREAK_INTRUSION := 0.6


static func decel_index(axes: Vector3) -> float:
	# axes: x lateral, y vertical, z fore-aft (peak g on each).
	var a := axes.z / G_LIMIT_FORE_AFT
	var b := axes.y / G_LIMIT_VERTICAL
	var c := axes.x / G_LIMIT_LATERAL
	return sqrt(a * a + b * b + c * c)


static func p_decel(index: float) -> float:
	return 1.0 / (1.0 + exp(-DECEL_STEEPNESS * (index - 1.0)))


## Standard normal CDF (Abramowitz-Stegun 7.1.26, |error| < 1.5e-7).
static func _phi(x: float) -> float:
	var t := 1.0 / (1.0 + 0.3275911 * absf(x) / sqrt(2.0))
	var poly := t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
	var erf := 1.0 - poly * exp(-x * x / 2.0)
	return 0.5 * (1.0 + signf(x) * erf)


static func p_head(hic: float) -> float:
	if hic < 1.0:
		return 0.0
	return _phi((log(hic) - HIC_MU) / HIC_SIGMA)


static func estimated_hic(seat_peak_g: float) -> float:
	return pow(maxf(seat_peak_g * HEAD_AMPLIFICATION, 0.0), 2.5) * HIC_WINDOW


static func p_intrusion(intrusion: float) -> float:
	return pow(clampf(intrusion, 0.0, 1.0), 1.5)


## `incapacitation` 0..1: how badly hurt the occupant already is, which sets
## how long they stay in the fire.
static func p_fire(exposure: float, incapacitation: float) -> float:
	return 1.0 - exp(-exposure * (0.6 + 2.0 * clampf(incapacitation, 0.0, 1.0)))


static func verdict(overall: float) -> String:
	if overall >= 0.9:
		return "Survivable: minor injuries likely"
	if overall >= 0.6:
		return "Survivable with serious injuries"
	if overall >= 0.2:
		return "Partially survivable"
	return "Unsurvivable"


## How much of the seat's space the part's dents have taken (0..1).
static func _dent_intrusion(part: AircraftPart, seat_local: Vector3) -> float:
	var worst := 0.0
	for slot: int in 2:
		var dent := part.dent_slot(slot)
		if dent.w <= 0.0:
			continue
		var push := part.dent_push(slot)
		var depth := push.length()
		if depth < 0.01:
			continue
		var falloff := 1.0 - smoothstep(0.0, dent.w, seat_local.distance_to(Vector3(dent.x, dent.y, dent.z)))
		# From below there is `crush_depth` of structure to use up first; from
		# the side there is barely a wall's thickness.
		var margin := lerpf(0.3, part.def.crush_depth, absf(push.y) / depth)
		worst = maxf(worst, clampf((depth * falloff - margin) / 1.0, 0.0, 1.0))
	return worst


static func build_report(aircraft: Aircraft, director: CrashDirector) -> CrashReport:
	var report := CrashReport.new()
	var def := aircraft.def
	var cabin := aircraft.cabin
	report.aircraft_name = def.display_name
	report.impact_velocity = aircraft.impact_velocity
	report.impact_speed = aircraft.impact_velocity.length()
	report.impact_vertical_speed = aircraft.impact_velocity.y
	report.impact_pitch_deg = aircraft.impact_pitch_deg
	report.impact_roll_deg = aircraft.impact_roll_deg
	var horizontal := Vector2(aircraft.impact_velocity.x, aircraft.impact_velocity.z).length()
	report.impact_angle_deg = rad_to_deg(atan2(-aircraft.impact_velocity.y, maxf(horizontal, 0.01)))
	report.duration = director.crash_clock if director != null else 0.0
	report.joints_total = aircraft.parts.size() - 1
	report.joints_broken = report.joints_total - aircraft.joints_alive
	report.fires = aircraft.fires.size()
	for part: AircraftPart in aircraft.parts:
		report.skin_total += part.pieces.size()
		report.skin_lost += part.pieces.size() - part.pieces_left

	# Rows of the seat map: how many seats share each row number.
	var per_row: Dictionary = {}
	for seat: Seat in cabin.seats:
		per_row[seat.row] = int(per_row.get(seat.row, 0)) + 1

	var total := 0.0
	for seat: Seat in cabin.seats:
		var part := seat.part
		var r := SeatResult.new()
		r.label = seat.label
		r.row = seat.row
		r.column = seat.column
		r.columns_in_row = per_row[seat.row]
		r.is_crew = seat.is_crew
		r.has_fred = seat.fred != null
		r.zone = String(part.name)
		r.peak_g = seat.peak_g
		r.peak_g_axes = seat.peak_axes

		# Structure: dents reaching the seat, or the fuselage breaking beside it.
		var intrusion := _dent_intrusion(part, seat.local_pos)
		for other: AircraftPart in aircraft.parts:
			if other.def.kind != PartDef.Kind.FUSELAGE or other.joint != null or other.parent_index < 0:
				continue
			if other.index != part.index and other.parent_index != part.index:
				continue
			if absf(seat.def_pos.z - other.def.anchor.z) < BREAK_RADIUS:
				intrusion = maxf(intrusion, BREAK_INTRUSION)
		r.intrusion = intrusion
		r.p_intrusion = p_intrusion(intrusion)

		# Deceleration and head.
		var index := decel_index(seat.peak_axes)
		r.p_decel = p_decel(index)
		var restraint := 0.0
		if seat.fred != null:
			r.hic = seat.fred.hic
			r.ejected = seat.fred.ejected
			restraint = 0.95 if seat.fred.ejected else 0.0
		else:
			r.hic = estimated_hic(seat.peak_g)
			restraint = smoothstep(RESTRAINT_FAIL_LOW, RESTRAINT_FAIL_HIGH, seat.peak_g) * RESTRAINT_LETHALITY
			r.ejected = restraint > 0.6
		r.p_head = p_head(r.hic)

		# Fire: every source, weighted by distance from the seat.
		var seat_world := part.global_transform * seat.local_pos
		var exposure := 0.0
		for source: FireSource in aircraft.fires:
			if not is_instance_valid(source.part):
				continue
			var d := seat_world.distance_to(source.world_position()) / FIRE_RADIUS
			exposure += source.intensity / (1.0 + d * d)
		r.fire = clampf(exposure, 0.0, 1.0)
		r.p_fire = p_fire(exposure, maxf(index - 0.4, intrusion) * 1.5)

		r.survival = (1.0 - r.p_decel) * (1.0 - r.p_head) * (1.0 - r.p_intrusion) * (1.0 - r.p_fire) \
				* (1.0 - restraint)
		var worst := maxf(maxf(r.p_decel, r.p_head), maxf(r.p_intrusion, maxf(r.p_fire, restraint)))
		if worst < 0.05:
			r.cause = ""
		elif worst == restraint:
			r.cause = "Ejected"
		elif worst == r.p_intrusion:
			r.cause = "Structure"
		elif worst == r.p_fire:
			r.cause = "Fire"
		elif worst == r.p_head:
			r.cause = "Head impact"
		else:
			r.cause = "Deceleration"
		report.seats.append(r)
		report.peak_g = maxf(report.peak_g, seat.peak_g)
		total += r.survival

		if seat.fred != null:
			var fred := seat.fred
			var f := FredResult.new()
			f.seat_label = seat.label
			f.limb_names = PackedStringArray(Fred.LIMB_NAMES)
			f.limb_peak_g = fred.peak_g.duplicate()
			f.hic = fred.hic
			f.belt_peak_kn = fred.belt_peak / 1000.0
			f.stroke_m = fred.stroke_peak
			f.bottomed = fred.bottomed
			f.ejected = fred.ejected
			f.survival = r.survival
			report.freds.append(f)

	var count := maxi(report.seats.size(), 1)
	report.survivors_expected = total
	report.survival_overall = total / float(count)
	report.verdict = verdict(report.survival_overall)
	return report
