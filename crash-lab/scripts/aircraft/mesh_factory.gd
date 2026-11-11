class_name MeshFactory
extends RefCounted
## Procedural geometry for airframe parts, generated from the PartDef alone in
## the part's local frame (origin = the part's centre of mass).
##
## A part is not one mesh but a set of skin pieces over a core:
##   - pieces: fuselage skin panels (bay x quadrant), wing box segments,
##     control surfaces, cowl halves... Each can be torn off individually and
##     becomes its own rigid chunk, so wreckage comes apart panel by panel.
##   - core: what is left underneath - frames, longerons and floor in a
##     fuselage, spars and ribs in a wing, the fan and core in an engine.
##   - far: one cheap merged mesh shown at distance while the part is intact.
##
## UVs address the shared atlas painted by tools/gen_atlas.gd.

const GLASS := Color(0.16, 0.22, 0.3)
const DARK := Color(0.2, 0.21, 0.23)
const TYRE := Color(0.3, 0.3, 0.32)
const METAL := Color(0.7, 0.72, 0.75)
const PRIMER := Color(0.47, 0.55, 0.3)
const CARPET := Color(0.2, 0.25, 0.36)
## Skin mass per square metre, for piece masses.
const SKIN_KG_M2 := 14.0
## Length of fuselage one strip of the atlas covers.
const STRIP_METRES := 24.0

const TILE_NOSE := Vector2i(0, 1)
const TILE_WING := Vector2i(1, 1)
const TILE_ENGINE := Vector2i(2, 1)
const TILE_FAN := Vector2i(3, 1)
const TILE_TYRE := Vector2i(0, 2)
const TILE_METAL := Vector2i(1, 2)
const TILE_SEAT := Vector2i(2, 2)
const TILE_FLOOR := Vector2i(3, 2)
const TILE_FRED := Vector2i(0, 3)
const TILE_CAP := Vector2i(1, 3)
const TILE_PRIMER := Vector2i(2, 3)
const TILE_PLAIN := Vector2i(3, 3)

# Airfoil outline: chord station and half-thickness as a fraction of maximum.
const BOX_X: Array[float] = [0.0, 0.012, 0.05, 0.14, 0.3, 0.5, 0.68]
const BOX_T: Array[float] = [0.0, 0.34, 0.62, 0.87, 1.0, 0.9, 0.68]
const FLAP_X: Array[float] = [0.68, 0.84, 1.0]
const FLAP_T: Array[float] = [0.68, 0.36, 0.03]
const REAR_SPAR := 0.68


## Collects triangles for one mesh and tracks its bounds.
class Surf:
	var st := SurfaceTool.new()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var area := 0.0
	var explicit_normals := false

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)

	func _vertex(p: Vector3, col: Color, uv: Vector2) -> void:
		st.set_color(col)
		st.set_uv(uv)
		st.add_vertex(p)
		lo = lo.min(p)
		hi = hi.max(p)

	## Triangle wound so its front face points away from `inside`.
	func tri(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color,
			ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		var n := (c - a).cross(b - a)
		area += n.length() * 0.5
		if n.dot((a + b + c) / 3.0 - inside) < 0.0:
			_vertex(a, col, ua)
			_vertex(c, col, uc)
			_vertex(b, col, ub)
		else:
			_vertex(a, col, ua)
			_vertex(b, col, ub)
			_vertex(c, col, uc)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Color,
			ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
		tri(a, b, c, inside, col, ua, ub, uc)
		tri(a, c, d, inside, col, ua, uc, ud)

	func flat_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Color,
			uv: Vector2) -> void:
		quad(a, b, c, d, inside, col, uv, uv, uv, uv)

	func empty() -> bool:
		return area <= 0.0

	func mesh() -> ArrayMesh:
		st.index()
		st.generate_normals()
		return st.commit()

	func center() -> Vector3:
		return (lo + hi) * 0.5

	func size() -> Vector3:
		return (hi - lo).max(Vector3(0.08, 0.08, 0.08))


static func strip_uv(u: float, v: float, plain: bool) -> Vector2:
	return Vector2((2.0 + clampf(u, 0.0, 1.0) * 1020.0) / 1024.0,
			((130.0 if plain else 2.0) + clampf(v, 0.0, 1.0) * 124.0) / 1024.0)


static func tile_uv(tile: Vector2i, u: float, v: float) -> Vector2:
	return Vector2((float(tile.x) * 256.0 + 6.0 + clampf(u, 0.0, 1.0) * 244.0) / 1024.0,
			(float(tile.y) * 256.0 + 6.0 + clampf(v, 0.0, 1.0) * 244.0) / 1024.0)


static func _skin_color(adef: AircraftDef, part: PartDef) -> Color:
	match part.skin:
		1:
			return adef.accent
		2:
			return METAL
	return adef.paint


static func _piece(surf: Surf, kg_m2: float) -> SkinPiece:
	var piece := SkinPiece.new()
	piece.mesh = surf.mesh()
	piece.center = surf.center()
	piece.size = surf.size()
	piece.mass = maxf(surf.area * kg_m2, 4.0)
	return piece


## Everything needed to draw one part.
static func build_part(adef: AircraftDef, part: PartDef, detail: int) -> PartMeshes:
	var out := PartMeshes.new()
	match part.kind:
		PartDef.Kind.FUSELAGE:
			_fuselage(adef, part, detail, out)
		PartDef.Kind.ENGINE:
			_engine(adef, part, detail, out)
		PartDef.Kind.WING, PartDef.Kind.STABILIZER, PartDef.Kind.FIN:
			_panel(adef, part, detail, out)
		PartDef.Kind.CANOPY:
			_canopy(part, out)
		PartDef.Kind.GEAR:
			out.strut = gear_strut_mesh(part)
			out.wheels = gear_wheel_mesh(part)
	return out


static func part_hull(part: PartDef) -> PackedVector3Array:
	match part.kind:
		PartDef.Kind.FUSELAGE, PartDef.Kind.ENGINE:
			return body_hull(part)
		PartDef.Kind.WING, PartDef.Kind.STABILIZER, PartDef.Kind.FIN:
			return panel_hull(part)
		PartDef.Kind.CANOPY:
			return _canopy_hull(part)
	return PackedVector3Array()


# ---------------------------------------------------------------- fuselage

## Radius and vertical centre offset of a body at distance `d` from p0.
static func body_profile(part: PartDef, d: float, length: float) -> Vector2:
	var radius := lerpf(part.r0, part.r1, d / maxf(length, 0.001))
	var y_off := 0.0
	if part.kind == PartDef.Kind.FUSELAGE:
		if part.shape_a > 0.0 and d < part.shape_a:
			var u := d / part.shape_a
			radius = part.r0 * maxf(pow(1.0 - pow(1.0 - u, 2.0), part.nose_power), 0.04)
			y_off = -part.nose_droop * part.r0 * (1.0 - u) * (1.0 - u)
		elif part.shape_b > 0.0 and d > length - part.shape_b:
			var u := (d - (length - part.shape_b)) / part.shape_b
			radius = part.r1 * (1.0 - (1.0 - part.tail_ratio) * pow(u, 1.4))
			y_off = (part.r1 - radius) * part.tail_upsweep
	return Vector2(radius, y_off)


static func _stations(part: PartDef, length: float, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := 0.0
	while d < length - 0.01:
		out.append(d)
		var in_nose := part.shape_a > 0.0 and d < part.shape_a
		var in_tail := part.shape_b > 0.0 and d > length - part.shape_b - step
		var next := d + step * (0.42 if in_nose and d < part.shape_a * 0.3 else (0.6 if in_nose or in_tail else 1.0))
		# Land a station exactly on the end of the nose cap so it is a clean seam.
		if in_nose and next > part.shape_a and part.shape_a - d > 0.05:
			next = part.shape_a
		d = next
	out.append(length)
	return out


static func _ring_point(center: Vector3, radius: float, angle: float, squash: Vector2) -> Vector3:
	return center + Vector3(sin(angle) * radius * squash.x, cos(angle) * radius * squash.y, 0.0)


static func _floor_y(adef: AircraftDef, part: PartDef) -> float:
	var y := 1.0e9
	for block: SeatBlockDef in adef.seat_blocks:
		if block.part == part.name:
			y = minf(y, block.floor_y)
	return y if y < 1.0e8 else -0.32 * part.r0 * part.squash.y


static func _fuselage(adef: AircraftDef, part: PartDef, detail: int, out: PartMeshes) -> void:
	var length := (part.p1 - part.p0).length()
	var dir := (part.p1 - part.p0) / length
	var origin := part.p0 - part.com
	var sides := 16 if detail == 0 else 24
	var per_quadrant := sides / 4
	var stations := _stations(part, length, 1.5 if detail == 0 else 1.05)
	var bay_length: float = [5.0, 3.3, 2.5][clampi(detail, 0, 2)]
	var windows := adef.seat_count() > 8
	var paint := _skin_color(adef, part)
	var squash := part.squash

	var bay_start := 0
	while bay_start < stations.size() - 1:
		var bay_end := bay_start + 1
		while bay_end < stations.size() - 1 and stations[bay_end] - stations[bay_start] < bay_length:
			# Keep the nose cap and the constant section in separate bays.
			if part.shape_a > 0.0 and is_equal_approx(stations[bay_end], part.shape_a):
				break
			bay_end += 1
		var in_nose := part.shape_a > 0.0 and stations[bay_start] < part.shape_a - 0.01
		var in_tail := part.shape_b > 0.0 and stations[bay_start] >= length - part.shape_b - 0.01
		var plain := not windows or in_tail
		var u_start := fposmod(stations[bay_start] + part.p0.z * 0.37, STRIP_METRES) / STRIP_METRES
		if u_start + (stations[bay_end] - stations[bay_start]) / STRIP_METRES > 1.0:
			u_start = 0.0
		for q: int in 4:
			var surf := Surf.new()
			for s: int in range(bay_start, bay_end):
				var d0 := stations[s]
				var d1 := stations[s + 1]
				var pr0 := body_profile(part, d0, length)
				var pr1 := body_profile(part, d1, length)
				var c0 := origin + dir * d0 + Vector3(0.0, pr0.y, 0.0)
				var c1 := origin + dir * d1 + Vector3(0.0, pr1.y, 0.0)
				var inside := (c0 + c1) * 0.5
				for k: int in range(q * per_quadrant, (q + 1) * per_quadrant):
					# Quadrant 0 is the crown (-45..45 deg), then right, belly, left.
					var a0 := TAU * float(k) / float(sides) - PI * 0.25
					var a1 := TAU * float(k + 1) / float(sides) - PI * 0.25
					var mid := absf(wrapf((a0 + a1) * 0.5, -PI, PI))
					var col := paint
					if mid > 1.57 and mid < 1.84:
						col = adef.accent
					elif mid > 2.3:
						col = paint.darkened(0.14)
					if in_nose and d1 <= part.shape_a * 0.2:
						col = paint.darkened(0.3)
					var v0 := absf(wrapf(a0, -PI, PI)) / PI
					var v1 := absf(wrapf(a1, -PI, PI)) / PI
					# The seam at the belly: keep v monotonic across the quad.
					if absf(v0 - v1) > 0.5:
						if v0 < v1:
							v0 = 1.0
						else:
							v1 = 1.0
					var uv00: Vector2
					var uv01: Vector2
					var uv11: Vector2
					var uv10: Vector2
					if in_nose and windows:
						var n0 := d0 / part.shape_a
						var n1 := d1 / part.shape_a
						uv00 = tile_uv(TILE_NOSE, n0, v0)
						uv01 = tile_uv(TILE_NOSE, n0, v1)
						uv11 = tile_uv(TILE_NOSE, n1, v1)
						uv10 = tile_uv(TILE_NOSE, n1, v0)
					else:
						var u0 := u_start + (d0 - stations[bay_start]) / STRIP_METRES
						var u1 := u_start + (d1 - stations[bay_start]) / STRIP_METRES
						uv00 = strip_uv(u0, v0, plain)
						uv01 = strip_uv(u0, v1, plain)
						uv11 = strip_uv(u1, v1, plain)
						uv10 = strip_uv(u1, v0, plain)
					surf.quad(_ring_point(c0, pr0.x, a0, squash), _ring_point(c0, pr0.x, a1, squash),
							_ring_point(c1, pr1.x, a1, squash), _ring_point(c1, pr1.x, a0, squash),
							inside, col, uv00, uv01, uv11, uv10)
			if not surf.empty():
				out.pieces.append(_piece(surf, SKIN_KG_M2))
		bay_start = bay_end

	# Core: frames, longerons and the floor.
	var core := Surf.new()
	var floor_y := _floor_y(adef, part) - part.com.y
	var primer_uv := tile_uv(TILE_PRIMER, 0.5, 0.5)
	var floor_uv := tile_uv(TILE_FLOOR, 0.5, 0.5)
	var frame_sides := 12
	var floor_col := Color(CARPET.r, CARPET.g, CARPET.b, 0.0)
	for s: int in stations.size():
		var d := stations[s]
		var pr := body_profile(part, d, length)
		if pr.x < 0.35:
			continue
		var c := origin + dir * d + Vector3(0.0, pr.y, 0.0)
		for k: int in frame_sides:
			var a0 := TAU * float(k) / float(frame_sides)
			var a1 := TAU * float(k + 1) / float(frame_sides)
			core.flat_quad(_ring_point(c, pr.x * 0.86, a0, squash), _ring_point(c, pr.x * 0.86, a1, squash),
					_ring_point(c, pr.x * 0.985, a1, squash), _ring_point(c, pr.x * 0.985, a0, squash),
					c - dir, PRIMER, primer_uv)
		if s == stations.size() - 1:
			break
		var d1 := stations[s + 1]
		var pr1 := body_profile(part, d1, length)
		if pr1.x < 0.35:
			continue
		var c1 := origin + dir * d1 + Vector3(0.0, pr1.y, 0.0)
		for k: int in 6:
			var a := TAU * (float(k) + 0.5) / 6.0
			var da := 0.05
			core.flat_quad(_ring_point(c, pr.x * 0.97, a - da, squash), _ring_point(c, pr.x * 0.97, a + da, squash),
					_ring_point(c1, pr1.x * 0.97, a + da, squash), _ring_point(c1, pr1.x * 0.97, a - da, squash),
					(c + c1) * 0.5, PRIMER.darkened(0.15), primer_uv)
		# Floor: alpha 0 keeps it out of the cutaway clip.
		var fy0 := floor_y - c.y
		var fy1 := floor_y - c1.y
		var ry0 := pr.x * 0.95 * squash.y
		var ry1 := pr1.x * 0.95 * squash.y
		if absf(fy0) < ry0 and absf(fy1) < ry1:
			var w0 := sqrt(1.0 - (fy0 / ry0) * (fy0 / ry0)) * pr.x * 0.95 * squash.x
			var w1 := sqrt(1.0 - (fy1 / ry1) * (fy1 / ry1)) * pr1.x * 0.95 * squash.x
			core.flat_quad(Vector3(-w0, floor_y, c.z), Vector3(w0, floor_y, c.z),
					Vector3(w1, floor_y, c1.z), Vector3(-w1, floor_y, c1.z),
					Vector3(0.0, floor_y - 5.0, (c.z + c1.z) * 0.5), floor_col, floor_uv)
	if not core.empty():
		out.core = core.mesh()
	out.far = _body_far(adef, part, 10)


## Cheap merged tube for the far LOD.
static func _body_far(adef: AircraftDef, part: PartDef, sides: int) -> ArrayMesh:
	var surf := Surf.new()
	var length := (part.p1 - part.p0).length()
	var dir := (part.p1 - part.p0) / length
	var origin := part.p0 - part.com
	var stations := _stations(part, length, 3.2)
	var paint := _skin_color(adef, part)
	var uv := tile_uv(TILE_PLAIN, 0.5, 0.5)
	for s: int in stations.size() - 1:
		var pr0 := body_profile(part, stations[s], length)
		var pr1 := body_profile(part, stations[s + 1], length)
		var c0 := origin + dir * stations[s] + Vector3(0.0, pr0.y, 0.0)
		var c1 := origin + dir * stations[s + 1] + Vector3(0.0, pr1.y, 0.0)
		for k: int in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var mid := absf(wrapf((a0 + a1) * 0.5, -PI, PI))
			var col := adef.accent if part.kind == PartDef.Kind.FUSELAGE and mid > 1.5 and mid < 1.9 else paint
			surf.flat_quad(_ring_point(c0, pr0.x, a0, part.squash), _ring_point(c0, pr0.x, a1, part.squash),
					_ring_point(c1, pr1.x, a1, part.squash), _ring_point(c1, pr1.x, a0, part.squash),
					(c0 + c1) * 0.5, col, uv)
	return surf.mesh()


static func body_hull(part: PartDef) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var axis := part.p1 - part.p0
	var length := axis.length()
	var dir := axis / length
	var origin := part.p0 - part.com
	var samples: Array[float] = [0.0, 0.3, 0.7, 1.0]
	if part.shape_a > 0.0:
		samples = [0.02, part.shape_a * 0.45 / length, part.shape_a / length, 1.0]
	elif part.shape_b > 0.0:
		samples = [0.0, 1.0 - part.shape_b / length, 1.0 - part.shape_b * 0.5 / length, 1.0]
	for t: float in samples:
		var pr := body_profile(part, t * length, length)
		var c := origin + dir * (t * length) + Vector3(0.0, pr.y, 0.0)
		for k: int in 8:
			var a := TAU * (float(k) + 0.5) / 8.0
			pts.append(_ring_point(c, maxf(pr.x, 0.08), a, part.squash))
	return pts


# ---------------------------------------------------------------- engines

static func _engine(adef: AircraftDef, part: PartDef, detail: int, out: PartMeshes) -> void:
	var length := (part.p1 - part.p0).length()
	var dir := (part.p1 - part.p0) / length
	var origin := part.p0 - part.com
	var sides := 12 if detail == 0 else 18
	var paint := _skin_color(adef, part)
	# Nacelle profile: (fraction of length, radius factor of r0).
	var prof_d: Array[float] = [0.0, 0.04, 0.2, 0.55, 0.82, 1.0]
	var nozzle := part.r1 / part.r0
	var prof_r: Array[float] = [0.9, 0.99, 1.0, 0.96, lerpf(0.96, nozzle, 0.6), nozzle]
	# Two cowl halves (right, left).
	for half: int in 2:
		var surf := Surf.new()
		for s: int in prof_d.size() - 1:
			var c0 := origin + dir * (prof_d[s] * length)
			var c1 := origin + dir * (prof_d[s + 1] * length)
			var r0 := part.r0 * prof_r[s]
			var r1 := part.r0 * prof_r[s + 1]
			for k: int in sides / 2:
				var a0 := TAU * float(k + half * sides / 2) / float(sides)
				var a1 := TAU * float(k + 1 + half * sides / 2) / float(sides)
				var col := METAL if s == 0 else (paint if s < 4 else METAL.darkened(0.25))
				surf.quad(_ring_point(c0, r0, a0, Vector2.ONE), _ring_point(c0, r0, a1, Vector2.ONE),
						_ring_point(c1, r1, a1, Vector2.ONE), _ring_point(c1, r1, a0, Vector2.ONE),
						(c0 + c1) * 0.5, col,
						tile_uv(TILE_ENGINE, prof_d[s], float(k) / float(sides / 2)),
						tile_uv(TILE_ENGINE, prof_d[s], float(k + 1) / float(sides / 2)),
						tile_uv(TILE_ENGINE, prof_d[s + 1], float(k + 1) / float(sides / 2)),
						tile_uv(TILE_ENGINE, prof_d[s + 1], float(k) / float(sides / 2)))
		out.pieces.append(_piece(surf, SKIN_KG_M2 * 1.5))
	# Pylon up to the mount point, for podded engines.
	var mount := part.anchor - part.com
	var top := origin + dir * (length * 0.45) + Vector3(0.0, part.r0 * 0.95, 0.0)
	if mount.y - top.y > 0.15:
		var pylon := Surf.new()
		var half_w := 0.16
		var z0 := origin.z + length * 0.12
		var z1 := origin.z + length * 0.86
		var m0 := mount.z - length * 0.3
		var m1 := mount.z + length * 0.42
		var inside := Vector3(mount.x, (mount.y + top.y) * 0.5, (z0 + z1) * 0.5)
		var uv := tile_uv(TILE_PLAIN, 0.5, 0.5)
		for sx: float in [-1.0, 1.0]:
			pylon.flat_quad(Vector3(top.x + sx * half_w, top.y - 0.3, z0), Vector3(top.x + sx * half_w, top.y - 0.3, z1),
					Vector3(mount.x + sx * half_w, mount.y, m1), Vector3(mount.x + sx * half_w, mount.y, m0),
					inside, paint, uv)
		pylon.flat_quad(Vector3(top.x - half_w, top.y - 0.3, z0), Vector3(top.x + half_w, top.y - 0.3, z0),
				Vector3(mount.x + half_w, mount.y, m0), Vector3(mount.x - half_w, mount.y, m0), inside, METAL, uv)
		pylon.flat_quad(Vector3(top.x - half_w, top.y - 0.3, z1), Vector3(top.x + half_w, top.y - 0.3, z1),
				Vector3(mount.x + half_w, mount.y, m1), Vector3(mount.x - half_w, mount.y, m1), inside, paint, uv)
		out.pieces.append(_piece(pylon, SKIN_KG_M2 * 2.0))

	# Core, always visible through the intake: fan face, spinner, hot section.
	var core := Surf.new()
	var hidden := Color(DARK.r, DARK.g, DARK.b, 0.0)
	var fan_c := origin + dir * (length * 0.1)
	var fan_r := part.r0 * 0.93
	for k: int in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		core.tri(fan_c, _ring_point(fan_c, fan_r, a0, Vector2.ONE), _ring_point(fan_c, fan_r, a1, Vector2.ONE),
				fan_c + dir, Color(1.0, 1.0, 1.0, 0.0), tile_uv(TILE_FAN, 0.5, 0.5),
				tile_uv(TILE_FAN, 0.5 + 0.5 * sin(a0), 0.5 + 0.5 * cos(a0)),
				tile_uv(TILE_FAN, 0.5 + 0.5 * sin(a1), 0.5 + 0.5 * cos(a1)))
		# Spinner cone ahead of the fan.
		var tip := fan_c - dir * (part.r0 * 0.5)
		core.tri(tip, _ring_point(fan_c, fan_r * 0.3, a0, Vector2.ONE), _ring_point(fan_c, fan_r * 0.3, a1, Vector2.ONE),
				fan_c, Color(0.85, 0.86, 0.88, 0.0), tile_uv(TILE_METAL, 0.5, 0.2),
				tile_uv(TILE_METAL, 0.2, 0.8), tile_uv(TILE_METAL, 0.8, 0.8))
		# Core casing and exhaust plug.
		var c0 := origin + dir * (length * 0.14)
		var c1 := origin + dir * (length * 0.98)
		var c2 := origin + dir * (length * 1.14)
		var core_r := part.r0 * 0.52
		var muv := tile_uv(TILE_METAL, 0.5, 0.5)
		core.flat_quad(_ring_point(c0, core_r, a0, Vector2.ONE), _ring_point(c0, core_r, a1, Vector2.ONE),
				_ring_point(c1, core_r * 0.8, a1, Vector2.ONE), _ring_point(c1, core_r * 0.8, a0, Vector2.ONE),
				(c0 + c1) * 0.5, hidden, muv)
		core.tri(c2, _ring_point(c1, core_r * 0.8, a0, Vector2.ONE), _ring_point(c1, core_r * 0.8, a1, Vector2.ONE),
				c1, Color(0.3, 0.3, 0.32, 0.0), muv, muv, muv)
	out.core = core.mesh()
	out.core_always_visible = true
	out.far = _body_far(adef, part, 8)


# ---------------------------------------------------------------- lifting panels

## Unit thickness direction of a panel (up for wings, sideways for fins).
static func panel_normal(part: PartDef) -> Vector3:
	var n := (part.p1 - part.p0).normalized().cross(Vector3.FORWARD).normalized()
	if n.y < -0.01 or (absf(n.y) <= 0.01 and n.x < 0.0):
		n = -n
	return n


## Point on the airfoil: `xc` chord fraction, `tf` thickness fraction of
## maximum, `side` +1 upper / -1 lower. `quarter` is the quarter-chord point.
static func _foil(quarter: Vector3, chord: float, thick: float, normal: Vector3, xc: float,
		tf: float, side: float) -> Vector3:
	var half := chord * thick * 0.5 * tf * (1.0 if side > 0.0 else 0.7)
	return quarter + Vector3(0.0, 0.0, (xc - 0.25) * chord) + normal * (half * side)


## Which control the trailing edge of this panel carries, from the def's
## aero surfaces: 0 none, 1 aileron, 2 elevator, 3 rudder, 4 flap.
static func _panel_control(adef: AircraftDef, part: PartDef) -> Vector2:
	var role := 0
	var max_deg := 0.0
	for s: SurfaceDef in adef.surfaces:
		if s.part != part.name:
			continue
		if s.control_mix.y != 0.0 and part.kind == PartDef.Kind.WING:
			role = SkinPiece.Surface.AILERON
			max_deg = s.max_deflection_deg
		elif s.control_mix.x != 0.0:
			role = SkinPiece.Surface.ELEVATOR
			max_deg = s.max_deflection_deg
		elif s.control_mix.z != 0.0:
			role = SkinPiece.Surface.RUDDER
			max_deg = s.max_deflection_deg
		elif s.flap_fraction > 0.0 and role == 0:
			role = SkinPiece.Surface.FLAP
			var last := adef.flap_steps_deg.size() - 1
			max_deg = adef.flap_steps_deg[last] if last >= 0 else 30.0
	return Vector2(float(role), max_deg)


static func _panel(adef: AircraftDef, part: PartDef, detail: int, out: PartMeshes) -> void:
	var normal := panel_normal(part)
	var root := part.p0 - part.com
	var tip := part.p1 - part.com
	var span := (tip - root).length()
	var segments := clampi(int(round(span / (4.5 if detail == 0 else 3.2))), 1, 4)
	var paint := _skin_color(adef, part)
	var thick := part.shape_a
	var control := _panel_control(adef, part)
	var all_moving := false
	for s: SurfaceDef in adef.surfaces:
		if s.part == part.name and s.effectiveness >= 0.99 and s.control_mix != Vector3.ZERO:
			all_moving = true
	# Hinge axis, oriented so a positive rotation moves the trailing edge down
	# (wings, tailplanes) or to the right (fins).
	var hinge := (tip - root).normalized()
	if part.kind == PartDef.Kind.FIN:
		if hinge.y < 0.0:
			hinge = -hinge
	elif hinge.x < 0.0:
		hinge = -hinge

	for i: int in segments:
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var q0 := root.lerp(tip, t0)
		var q1 := root.lerp(tip, t1)
		var ch0 := lerpf(part.r0, part.r1, t0)
		var ch1 := lerpf(part.r0, part.r1, t1)
		var inside := (q0 + q1) * 0.5 + Vector3(0.0, 0.0, 0.12 * (ch0 + ch1))

		# Wing box: leading edge back to the rear spar.
		var box := Surf.new()
		for side_i: int in 2:
			var side := 1.0 if side_i == 0 else -1.0
			for k: int in BOX_X.size() - 1:
				var shade := paint if side > 0.0 else paint.darkened(0.12)
				if k < 2:
					shade = METAL.lightened(0.15)
				box.quad(_foil(q0, ch0, thick, normal, BOX_X[k], BOX_T[k], side),
						_foil(q0, ch0, thick, normal, BOX_X[k + 1], BOX_T[k + 1], side),
						_foil(q1, ch1, thick, normal, BOX_X[k + 1], BOX_T[k + 1], side),
						_foil(q1, ch1, thick, normal, BOX_X[k], BOX_T[k], side),
						inside, shade,
						tile_uv(TILE_WING, BOX_X[k], t0), tile_uv(TILE_WING, BOX_X[k + 1], t0),
						tile_uv(TILE_WING, BOX_X[k + 1], t1), tile_uv(TILE_WING, BOX_X[k], t1))
		if i == segments - 1:
			_tip_rib(box, q1, ch1, thick, normal, 0.0, REAR_SPAR, inside)
			if part.winglet > 0.0:
				_winglet(box, q1, ch1, thick, normal, part.winglet, paint, adef.accent)
		out.pieces.append(_piece(box, SKIN_KG_M2 * 1.6))

		# Trailing edge: flap / aileron / elevator / rudder, or fixed skin.
		var te := Surf.new()
		var h0 := _foil(q0, ch0, thick, normal, REAR_SPAR, 0.0, 1.0)
		var h1 := _foil(q1, ch1, thick, normal, REAR_SPAR, 0.0, 1.0)
		var pivot := (h0 + h1) * 0.5
		var te_inside := (q0 + q1) * 0.5 + Vector3(0.0, 0.0, 0.58 * (ch0 + ch1) * 0.5) - pivot
		var te_col := paint.darkened(0.06)
		for side_i: int in 2:
			var side := 1.0 if side_i == 0 else -1.0
			for k: int in FLAP_X.size() - 1:
				te.quad(_foil(q0, ch0, thick, normal, FLAP_X[k], FLAP_T[k], side) - pivot,
						_foil(q0, ch0, thick, normal, FLAP_X[k + 1], FLAP_T[k + 1], side) - pivot,
						_foil(q1, ch1, thick, normal, FLAP_X[k + 1], FLAP_T[k + 1], side) - pivot,
						_foil(q1, ch1, thick, normal, FLAP_X[k], FLAP_T[k], side) - pivot,
						te_inside, te_col if side > 0.0 else te_col.darkened(0.12),
						tile_uv(TILE_WING, FLAP_X[k], t0), tile_uv(TILE_WING, FLAP_X[k + 1], t0),
						tile_uv(TILE_WING, FLAP_X[k + 1], t1), tile_uv(TILE_WING, FLAP_X[k], t1))
		# Close the front face and the two ends so a loose surface is solid.
		var cap_uv := tile_uv(TILE_METAL, 0.5, 0.5)
		te.flat_quad(_foil(q0, ch0, thick, normal, REAR_SPAR, FLAP_T[0], 1.0) - pivot,
				_foil(q1, ch1, thick, normal, REAR_SPAR, FLAP_T[0], 1.0) - pivot,
				_foil(q1, ch1, thick, normal, REAR_SPAR, FLAP_T[0], -1.0) - pivot,
				_foil(q0, ch0, thick, normal, REAR_SPAR, FLAP_T[0], -1.0) - pivot,
				te_inside, METAL.darkened(0.2), cap_uv)
		for end: int in 2:
			var q := q0 if end == 0 else q1
			var ch := ch0 if end == 0 else ch1
			te.tri(_foil(q, ch, thick, normal, REAR_SPAR, FLAP_T[0], 1.0) - pivot,
					_foil(q, ch, thick, normal, REAR_SPAR, FLAP_T[0], -1.0) - pivot,
					_foil(q, ch, thick, normal, 1.0, 0.0, 1.0) - pivot,
					te_inside, METAL.darkened(0.2), cap_uv, cap_uv, cap_uv)
		var te_piece := _piece(te, SKIN_KG_M2 * 1.4)
		te_piece.xform = Transform3D(Basis.IDENTITY, pivot)
		te_piece.center += pivot
		if int(control.x) != 0 and not all_moving:
			te_piece.control = int(control.x) as SkinPiece.Surface
			te_piece.hinge = hinge
			te_piece.deflect_max = deg_to_rad(control.y)
			te_piece.side = signf(part.com.x) if absf(part.com.x) > 0.05 else 1.0
		out.pieces.append(te_piece)

	# Core: two spars and a rib at every segment boundary.
	var core := Surf.new()
	var primer := Color(PRIMER.r, PRIMER.g, PRIMER.b, 0.0)
	var uv := tile_uv(TILE_PRIMER, 0.5, 0.5)
	for spar: float in [0.16, REAR_SPAR - 0.02]:
		core.flat_quad(_foil(root, part.r0, thick, normal, spar, 0.82, 1.0),
				_foil(tip, part.r1, thick, normal, spar, 0.82, 1.0),
				_foil(tip, part.r1, thick, normal, spar, 0.82, -1.0),
				_foil(root, part.r0, thick, normal, spar, 0.82, -1.0),
				root + Vector3(0.0, 0.0, -10.0), primer, uv)
	for i: int in segments * 2 + 1:
		var t := float(i) / float(segments * 2)
		var q := root.lerp(tip, t)
		var ch := lerpf(part.r0, part.r1, t)
		core.flat_quad(_foil(q, ch, thick, normal, 0.05, 0.6, 1.0), _foil(q, ch, thick, normal, REAR_SPAR, 0.66, 1.0),
				_foil(q, ch, thick, normal, REAR_SPAR, 0.66, -1.0), _foil(q, ch, thick, normal, 0.05, 0.6, -1.0),
				q - (tip - root), primer.darkened(0.12), uv)
	out.core = core.mesh()
	out.far = _panel_far(adef, part)


static func _tip_rib(surf: Surf, q: Vector3, ch: float, thick: float, normal: Vector3, x0: float,
		x1: float, inside: Vector3) -> void:
	var uv := tile_uv(TILE_METAL, 0.5, 0.5)
	for k: int in BOX_X.size() - 1:
		if BOX_X[k + 1] < x0 or BOX_X[k] > x1:
			continue
		surf.flat_quad(_foil(q, ch, thick, normal, BOX_X[k], BOX_T[k], 1.0),
				_foil(q, ch, thick, normal, BOX_X[k + 1], BOX_T[k + 1], 1.0),
				_foil(q, ch, thick, normal, BOX_X[k + 1], BOX_T[k + 1], -1.0),
				_foil(q, ch, thick, normal, BOX_X[k], BOX_T[k], -1.0), inside, METAL, uv)


## Blended winglet rising from the tip of the outermost wing panel.
static func _winglet(surf: Surf, q: Vector3, ch: float, thick: float, normal: Vector3, height: float,
		paint: Color, accent: Color) -> void:
	var outward := Vector3(signf(q.x) if absf(q.x) > 0.01 else 1.0, 0.0, 0.0)
	var up := (normal + outward * 0.28).normalized()
	var top := q + up * height + Vector3(0.0, 0.0, height * 0.55)
	var top_ch := ch * 0.42
	var half := maxf(ch * thick * 0.25, 0.03)
	var uv := tile_uv(TILE_PLAIN, 0.5, 0.5)
	var le0 := q + Vector3(0.0, 0.0, -0.25 * ch)
	var te0 := q + Vector3(0.0, 0.0, 0.43 * ch)
	var le1 := top + Vector3(0.0, 0.0, -0.25 * top_ch)
	var te1 := top + Vector3(0.0, 0.0, 0.6 * top_ch)
	var mid := (le0 + te0 + le1 + te1) * 0.25
	for sx: float in [-1.0, 1.0]:
		var off := outward * (half * sx)
		surf.flat_quad(le0 + off, te0 + off, te1 + off * 0.5, le1 + off * 0.5, mid,
				accent if sx > 0.0 else paint, uv)
	surf.flat_quad(le0 - outward * half, le0 + outward * half, le1 + outward * half * 0.5,
			le1 - outward * half * 0.5, mid, METAL, uv)


static func _panel_far(adef: AircraftDef, part: PartDef) -> ArrayMesh:
	var surf := Surf.new()
	var normal := panel_normal(part)
	var root := part.p0 - part.com
	var tip := part.p1 - part.com
	var paint := _skin_color(adef, part)
	var uv := tile_uv(TILE_PLAIN, 0.5, 0.5)
	var inside := (root + tip) * 0.5 + Vector3(0.0, 0.0, 0.2 * (part.r0 + part.r1) * 0.5)
	var xs: Array[float] = [0.0, 0.3, 1.0]
	var ts: Array[float] = [0.0, 1.0, 0.03]
	for side: float in [1.0, -1.0]:
		for k: int in 2:
			surf.flat_quad(_foil(root, part.r0, part.shape_a, normal, xs[k], ts[k], side),
					_foil(root, part.r0, part.shape_a, normal, xs[k + 1], ts[k + 1], side),
					_foil(tip, part.r1, part.shape_a, normal, xs[k + 1], ts[k + 1], side),
					_foil(tip, part.r1, part.shape_a, normal, xs[k], ts[k], side),
					inside, paint if side > 0.0 else paint.darkened(0.12), uv)
	return surf.mesh()


static func panel_hull(part: PartDef) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var normal := panel_normal(part)
	for end: int in 2:
		var q := (part.p0 if end == 0 else part.p1) - part.com
		var ch := part.r0 if end == 0 else part.r1
		var half := maxf(ch * part.shape_a * 0.5, 0.06)
		for z_frac: float in [-0.25, 0.1, 0.75]:
			var scale := 0.35 if z_frac != 0.1 else 1.0
			pts.append(q + Vector3(0.0, 0.0, z_frac * ch) + normal * half * scale)
			pts.append(q + Vector3(0.0, 0.0, z_frac * ch) - normal * half * scale)
	return pts


# ---------------------------------------------------------------- canopy

## Glass dome: p0 front, p1 back (on the fuselage crown), r0 half-width, r1 height.
static func _canopy(part: PartDef, out: PartMeshes) -> void:
	var surf := Surf.new()
	var a := part.p0 - part.com
	var b := part.p1 - part.com
	var mid := (a + b) * 0.5
	var steps := 8
	var arcs := 6
	var uv := tile_uv(TILE_PLAIN, 0.5, 0.5)
	for s: int in steps:
		var t0 := float(s) / float(steps)
		var t1 := float(s + 1) / float(steps)
		for k: int in arcs:
			var a0 := PI * (float(k) / float(arcs) - 0.5)
			var a1 := PI * (float(k + 1) / float(arcs) - 0.5)
			var col := GLASS if s > 0 and s < steps - 1 else GLASS.lightened(0.25)
			surf.flat_quad(_dome(a, b, part.r0, part.r1, t0, a0), _dome(a, b, part.r0, part.r1, t0, a1),
					_dome(a, b, part.r0, part.r1, t1, a1), _dome(a, b, part.r0, part.r1, t1, a0),
					mid - Vector3(0.0, part.r1, 0.0), col, uv)
	out.pieces.append(_piece(surf, 9.0))
	out.far = out.pieces[0].mesh


static func _dome(a: Vector3, b: Vector3, half_width: float, height: float, t: float, angle: float) -> Vector3:
	# Fatter toward the back, like a bubble canopy.
	var bulge := pow(sin(PI * clampf(t, 0.0, 1.0)), 0.55) * lerpf(0.8, 1.0, t)
	return a.lerp(b, t) + Vector3(sin(angle) * half_width * bulge, cos(angle) * height * bulge, 0.0)


static func _canopy_hull(part: PartDef) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var a := part.p0 - part.com
	var b := part.p1 - part.com
	for t: float in [0.1, 0.5, 0.9]:
		for angle: float in [-1.2, 0.0, 1.2]:
			pts.append(_dome(a, b, part.r0, part.r1, t, angle))
	return pts


# ---------------------------------------------------------------- landing gear

static func _cylinder(surf: Surf, a: Vector3, b: Vector3, radius: float, sides: int, col: Color,
		tile: Vector2i, capped: bool) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u)
	var inside := (a + b) * 0.5
	for k: int in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var r0 := (u * cos(a0) + v * sin(a0)) * radius
		var r1 := (u * cos(a1) + v * sin(a1)) * radius
		var v0 := float(k) / float(sides)
		var v1 := float(k + 1) / float(sides)
		surf.quad(a + r0, a + r1, b + r1, b + r0, inside, col, tile_uv(tile, 0.0, v0),
				tile_uv(tile, 0.0, v1), tile_uv(tile, 1.0, v1), tile_uv(tile, 1.0, v0))
		if capped:
			var uv := tile_uv(TILE_METAL, 0.5, 0.5)
			var hub := Color(0.75, 0.76, 0.78)
			surf.tri(a, a + r0 * 0.55, a + r1 * 0.55, inside, hub, uv, uv, uv)
			surf.tri(b, b + r0 * 0.55, b + r1 * 0.55, inside, hub, uv, uv, uv)
			var side_uv := tile_uv(tile, 0.5, 0.5)
			surf.flat_quad(a + r0 * 0.55, a + r1 * 0.55, a + r1, a + r0, inside, col, side_uv)
			surf.flat_quad(b + r0 * 0.55, b + r1 * 0.55, b + r1, b + r0, inside, col, side_uv)


## Fixed upper strut, in the leg's pivot frame (pivot at the origin).
static func gear_strut_mesh(part: PartDef) -> ArrayMesh:
	var surf := Surf.new()
	var leg := part.p1 - part.p0
	_cylinder(surf, Vector3.ZERO, leg * 0.62, part.r1 * 1.35, 8, METAL, TILE_METAL, false)
	# Drag brace.
	_cylinder(surf, leg * 0.5, leg * 0.08 + Vector3(0.0, 0.0, part.r0 * 1.3), part.r1 * 0.6, 6,
			METAL.darkened(0.2), TILE_METAL, false)
	return surf.mesh()


## Sliding lower strut, axle and wheels, in the pivot frame.
static func gear_wheel_mesh(part: PartDef) -> ArrayMesh:
	var surf := Surf.new()
	var leg := part.p1 - part.p0
	var r := part.r0
	var width := r * 0.62
	_cylinder(surf, leg * 0.45, leg, part.r1, 8, Color(0.85, 0.86, 0.88), TILE_METAL, false)
	var axles: Array[float] = [0.0]
	if part.shape_a >= 4.0:
		axles = [-r * 1.12, r * 1.12]
	for z: float in axles:
		var c := leg + Vector3(0.0, 0.0, z)
		_cylinder(surf, c - Vector3(width * 1.25, 0.0, 0.0), c + Vector3(width * 1.25, 0.0, 0.0),
				part.r1 * 0.8, 6, METAL, TILE_METAL, false)
		for sx: float in [-1.0, 1.0]:
			var w0 := c + Vector3(sx * width * 0.62, 0.0, 0.0)
			var w1 := c + Vector3(sx * width * 1.62, 0.0, 0.0)
			_cylinder(surf, w0, w1, r, 14, TYRE, TILE_TYRE, true)
	return surf.mesh()


# ---------------------------------------------------------------- cabin

static func _box(surf: Surf, center: Vector3, size: Vector3, col: Color, tile: Vector2i) -> void:
	var h := size * 0.5
	var uv := tile_uv(tile, 0.5, 0.5)
	for axis: int in 3:
		for sign: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var c := center + n * h[axis]
			var du := u * h[(axis + 1) % 3]
			var dv := v * h[(axis + 2) % 3]
			surf.flat_quad(c - du - dv, c + du - dv, c + du + dv, c - du + dv, center, col, uv)


## One passenger seat: origin on the floor under the hip point, facing -Z.
static func seat_mesh() -> ArrayMesh:
	var surf := Surf.new()
	surf.st.set_smooth_group(1)
	var col := Color(1.0, 1.0, 1.0)
	_box(surf, Vector3(0.0, 0.34, -0.02), Vector3(0.44, 0.12, 0.46), col, TILE_SEAT)
	_box(surf, Vector3(0.0, 0.72, 0.25), Vector3(0.44, 0.74, 0.08), col, TILE_SEAT)
	_box(surf, Vector3(0.0, 1.04, 0.24), Vector3(0.3, 0.16, 0.1), col.darkened(0.15), TILE_SEAT)
	_box(surf, Vector3(0.0, 0.14, 0.0), Vector3(0.36, 0.28, 0.06), Color(0.4, 0.4, 0.42), TILE_METAL)
	return surf.mesh()
