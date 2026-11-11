class_name MeshFactory
extends RefCounted
## Procedural geometry for airframe parts. Every mesh is generated from the
## PartDef alone, in the part's local frame (origin = the part's centre of
## mass), so new aircraft need no art assets.
##
## UVs address a 4x4 texture atlas: each part kind uses one tile.

const GLASS := Color(0.08, 0.11, 0.15)
const DARK := Color(0.16, 0.17, 0.19)
const TYRE := Color(0.06, 0.06, 0.07)
const METAL := Color(0.62, 0.64, 0.67)

# Atlas tiles (column, row) in a 4x4 grid.
const TILE_SKIN := Vector2i(0, 0)
const TILE_WING := Vector2i(1, 0)
const TILE_ENGINE := Vector2i(2, 0)
const TILE_METAL := Vector2i(3, 0)
const TILE_TYRE := Vector2i(0, 1)
const TILE_CAP := Vector2i(1, 1)
const TILE_INTERIOR := Vector2i(2, 1)
const TILE_SEAT := Vector2i(3, 1)
const TILE_FLOOR := Vector2i(0, 2)
const TILE_DEBRIS := Vector2i(1, 2)
const TILE_FRED := Vector2i(2, 2)
const TILE_PLAIN := Vector2i(3, 3)

# Airfoil outline: chordwise station (0 = leading edge) and half-thickness
# fraction of the maximum, shared by upper and lower skins.
const FOIL_X: Array[float] = [0.0, 0.03, 0.12, 0.3, 0.6, 1.0]
const FOIL_T: Array[float] = [0.0, 0.5, 0.86, 1.0, 0.72, 0.06]


static func atlas_uv(tile: Vector2i, u: float, v: float) -> Vector2:
	# Inset so bilinear filtering and mipmaps do not bleed between tiles.
	return Vector2((float(tile.x) + 0.04 + 0.92 * clampf(u, 0.0, 1.0)) * 0.25,
			(float(tile.y) + 0.04 + 0.92 * clampf(v, 0.0, 1.0)) * 0.25)


static func _skin_color(adef: AircraftDef, part: PartDef) -> Color:
	match part.skin:
		1:
			return adef.accent
		2:
			return METAL
	return adef.paint


## Emits a triangle wound so its front face points away from `inside`.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3,
		ca: Color, cb: Color, cc: Color, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		st.set_color(ca); st.set_uv(ua); st.add_vertex(a)
		st.set_color(cc); st.set_uv(uc); st.add_vertex(c)
		st.set_color(cb); st.set_uv(ub); st.add_vertex(b)
	else:
		st.set_color(ca); st.set_uv(ua); st.add_vertex(a)
		st.set_color(cb); st.set_uv(ub); st.add_vertex(b)
		st.set_color(cc); st.set_uv(uc); st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		inside: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, inside, col, col, col, ua, ub, uc)
	_tri(st, a, c, d, inside, col, col, col, ua, uc, ud)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


# ---------------------------------------------------------------- bodies of revolution

## Radius and vertical centre offset of a body at distance `d` from p0.
static func body_profile(part: PartDef, d: float, length: float) -> Vector2:
	var radius := lerpf(part.r0, part.r1, d / maxf(length, 0.001))
	var y_off := 0.0
	if part.kind == PartDef.Kind.FUSELAGE:
		if part.shape_a > 0.0 and d < part.shape_a:
			var u := d / part.shape_a
			radius = part.r0 * maxf(pow(1.0 - (1.0 - u) * (1.0 - u), 0.62), 0.06)
			y_off = -0.28 * part.r0 * (1.0 - u) * (1.0 - u)
		elif part.shape_b > 0.0 and d > length - part.shape_b:
			var u := (d - (length - part.shape_b)) / part.shape_b
			radius = part.r1 * (1.0 - 0.86 * pow(u, 1.4))
			y_off = (part.r1 - radius) * 0.72
	return Vector2(radius, y_off)


static func _body_stations(part: PartDef, length: float, lod: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var step := 1.1 if lod == 0 else 2.6
	if part.kind == PartDef.Kind.ENGINE:
		out.append(0.0)
		out.append(length * 0.18)
		out.append(length * 0.6)
		out.append(length)
		return out
	var d := 0.0
	while d < length - 0.01:
		out.append(d)
		var in_cap := (part.shape_a > 0.0 and d < part.shape_a) \
				or (part.shape_b > 0.0 and d > length - part.shape_b - step)
		d += step * (0.55 if in_cap else 1.0)
	out.append(length)
	return out


static func body_mesh(adef: AircraftDef, part: PartDef, lod: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var sides := 20 if lod == 0 else 10
	var axis := part.p1 - part.p0
	var length := axis.length()
	var dir := axis / length
	var origin := part.p0 - part.com
	var stations := _body_stations(part, length, lod)
	var is_fus := part.kind == PartDef.Kind.FUSELAGE
	var is_engine := part.kind == PartDef.Kind.ENGINE
	var base := _skin_color(adef, part)
	var tile := TILE_SKIN if is_fus else TILE_ENGINE
	var count := stations.size()

	for s: int in count - 1:
		var d0 := stations[s]
		var d1 := stations[s + 1]
		var pr0 := body_profile(part, d0, length)
		var pr1 := body_profile(part, d1, length)
		if is_engine:
			# Intake lip, fat middle, tapering nozzle.
			pr0.x = part.r0 * (0.9 if s == 0 else 1.0) if s < 2 else lerpf(part.r0, part.r1, 0.5)
			pr1.x = part.r0 if s == 0 else (lerpf(part.r0, part.r1, 0.5) if s == 1 else part.r1)
		var c0 := origin + dir * d0 + Vector3(0.0, pr0.y, 0.0)
		var c1 := origin + dir * d1 + Vector3(0.0, pr1.y, 0.0)
		var inside := (c0 + c1) * 0.5
		for k: int in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			# Angle 0 is straight up; positive toward +X.
			var r00 := Vector3(sin(a0), cos(a0), 0.0)
			var r01 := Vector3(sin(a1), cos(a1), 0.0)
			var col := base
			if is_fus:
				var mid_angle := absf(wrapf((a0 + a1) * 0.5, -PI, PI))
				# Cheat line with the cabin windows, and the windscreen on the nose.
				if mid_angle > 1.22 and mid_angle < 1.52:
					col = adef.accent
				if part.shape_a > 0.0 and d0 > part.shape_a * 0.42 and d1 < part.shape_a * 0.86 \
						and mid_angle < 0.95:
					col = GLASS
				if mid_angle > 2.5:
					col = base.darkened(0.12)
			var u0 := d0 / length
			var u1 := d1 / length
			var v0 := float(k) / float(sides)
			var v1 := float(k + 1) / float(sides)
			_quad(st, c0 + r00 * pr0.x, c0 + r01 * pr0.x, c1 + r01 * pr1.x, c1 + r00 * pr1.x,
					inside, col, atlas_uv(tile, u0, v0), atlas_uv(tile, u0, v1),
					atlas_uv(tile, u1, v1), atlas_uv(tile, u1, v0))

	# End caps: bulkheads on fuselage sections, intake and nozzle on engines.
	st.set_smooth_group(1)
	for end: int in 2:
		var d := 0.0 if end == 0 else length
		var pr := body_profile(part, d, length)
		if is_engine:
			pr.x = part.r0 * 0.9 if end == 0 else part.r1
		if pr.x < 0.02:
			continue
		var c := origin + dir * d + Vector3(0.0, pr.y, 0.0)
		var inside := origin + dir * (length * 0.5)
		var cap_col := DARK if is_engine else Color(0.3, 0.31, 0.33)
		for k: int in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var p_a := c + Vector3(sin(a0), cos(a0), 0.0) * pr.x
			var p_b := c + Vector3(sin(a1), cos(a1), 0.0) * pr.x
			_tri(st, c, p_a, p_b, inside, cap_col, cap_col, cap_col,
					atlas_uv(TILE_CAP, 0.5, 0.5),
					atlas_uv(TILE_CAP, 0.5 + 0.5 * sin(a0), 0.5 + 0.5 * cos(a0)),
					atlas_uv(TILE_CAP, 0.5 + 0.5 * sin(a1), 0.5 + 0.5 * cos(a1)))
	return _finish(st)


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
			pts.append(c + Vector3(sin(a), cos(a), 0.0) * maxf(pr.x, 0.08))
	return pts


# ---------------------------------------------------------------- lifting panels

## Unit thickness direction of a panel (up for wings, sideways for fins).
static func panel_normal(part: PartDef) -> Vector3:
	var n := (part.p1 - part.p0).normalized().cross(Vector3.FORWARD).normalized()
	if n.y < -0.01 or (absf(n.y) <= 0.01 and n.x < 0.0):
		n = -n
	return n


## Outline point: `xc` chord fraction from the leading edge, `side` +1 upper / -1 lower.
static func _foil_point(quarter: Vector3, chord: float, thick: float, normal: Vector3, xc: float,
		tf: float, side: float) -> Vector3:
	var z := (xc - 0.25) * chord
	var half := chord * thick * 0.5 * tf * (1.0 if side > 0.0 else 0.72)
	return quarter + Vector3(0.0, 0.0, z) + normal * (half * side)


static func panel_mesh(adef: AircraftDef, part: PartDef, lod: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var normal := panel_normal(part)
	var root := part.p0 - part.com
	var tip := part.p1 - part.com
	var spans := 6 if lod == 0 else 2
	var col := _skin_color(adef, part)
	var inside_root := root + Vector3(0.0, 0.0, 0.2 * part.r0)
	var inside_tip := tip + Vector3(0.0, 0.0, 0.2 * part.r1)
	var m := FOIL_X.size()
	for s: int in spans:
		var t0 := float(s) / float(spans)
		var t1 := float(s + 1) / float(spans)
		var q0 := root.lerp(tip, t0)
		var q1 := root.lerp(tip, t1)
		var ch0 := lerpf(part.r0, part.r1, t0)
		var ch1 := lerpf(part.r0, part.r1, t1)
		var inside := inside_root.lerp(inside_tip, (t0 + t1) * 0.5)
		for side_i: int in 2:
			var side := 1.0 if side_i == 0 else -1.0
			for k: int in m - 1:
				var a := _foil_point(q0, ch0, part.shape_a, normal, FOIL_X[k], FOIL_T[k], side)
				var b := _foil_point(q0, ch0, part.shape_a, normal, FOIL_X[k + 1], FOIL_T[k + 1], side)
				var c := _foil_point(q1, ch1, part.shape_a, normal, FOIL_X[k + 1], FOIL_T[k + 1], side)
				var d := _foil_point(q1, ch1, part.shape_a, normal, FOIL_X[k], FOIL_T[k], side)
				var shade := col if side > 0.0 else col.darkened(0.1)
				# Leading-edge band in bare metal.
				if k == 0:
					shade = METAL
				_quad(st, a, b, c, d, inside, shade,
						atlas_uv(TILE_WING, FOIL_X[k], t0), atlas_uv(TILE_WING, FOIL_X[k + 1], t0),
						atlas_uv(TILE_WING, FOIL_X[k + 1], t1), atlas_uv(TILE_WING, FOIL_X[k], t1))
	# Root and tip ribs.
	st.set_smooth_group(1)
	for end: int in 2:
		var q := root if end == 0 else tip
		var ch := part.r0 if end == 0 else part.r1
		var inside := (root + tip) * 0.5 + Vector3(0.0, 0.0, 0.2 * (part.r0 + part.r1) * 0.5)
		var rib := Color(0.3, 0.31, 0.33)
		for k: int in m - 1:
			var up0 := _foil_point(q, ch, part.shape_a, normal, FOIL_X[k], FOIL_T[k], 1.0)
			var up1 := _foil_point(q, ch, part.shape_a, normal, FOIL_X[k + 1], FOIL_T[k + 1], 1.0)
			var lo1 := _foil_point(q, ch, part.shape_a, normal, FOIL_X[k + 1], FOIL_T[k + 1], -1.0)
			var lo0 := _foil_point(q, ch, part.shape_a, normal, FOIL_X[k], FOIL_T[k], -1.0)
			var uv := atlas_uv(TILE_CAP, 0.5, 0.5)
			_quad(st, up0, up1, lo1, lo0, inside, rib, uv, uv, uv, uv)
	return _finish(st)


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


# ---------------------------------------------------------------- landing gear

static func _cylinder(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, sides: int,
		col: Color, tile: Vector2i, capped: bool) -> void:
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
		_quad(st, a + r0, a + r1, b + r1, b + r0, inside, col, atlas_uv(tile, 0.0, v0),
				atlas_uv(tile, 0.0, v1), atlas_uv(tile, 1.0, v1), atlas_uv(tile, 1.0, v0))
		if capped:
			var uv := atlas_uv(tile, 0.5, 0.5)
			_tri(st, a, a + r0, a + r1, inside, col, col, col, uv, uv, uv)
			_tri(st, b, b + r0, b + r1, inside, col, col, col, uv, uv, uv)


## Fixed upper strut, in the leg's pivot frame (pivot at the origin).
static func gear_strut_mesh(part: PartDef) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var leg := part.p1 - part.p0
	_cylinder(st, Vector3.ZERO, leg * 0.62, part.r1 * 1.35, 8, METAL, TILE_METAL, false)
	return _finish(st)


## Sliding lower strut, axle and wheels, in the pivot frame.
static func gear_wheel_mesh(part: PartDef) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var leg := part.p1 - part.p0
	var r := part.r0
	var width := r * 0.62
	_cylinder(st, leg * 0.45, leg, part.r1, 8, METAL.lightened(0.15), TILE_METAL, false)
	var axles: Array[float] = [0.0]
	if part.shape_a >= 4.0:
		axles = [-r * 1.12, r * 1.12]
	for z: float in axles:
		var c := leg + Vector3(0.0, 0.0, z)
		_cylinder(st, c - Vector3(width * 1.25, 0.0, 0.0), c + Vector3(width * 1.25, 0.0, 0.0),
				part.r1 * 0.8, 6, METAL, TILE_METAL, false)
		for sx: float in [-1.0, 1.0]:
			var w0 := c + Vector3(sx * width * 0.62, 0.0, 0.0)
			var w1 := c + Vector3(sx * width * 1.62, 0.0, 0.0)
			_cylinder(st, w0, w1, r, 12, TYRE, TILE_TYRE, true)
	return _finish(st)


# ---------------------------------------------------------------- cabin

## Low-poly cabin liner for a fuselage section, in the part's local frame:
## an inward-facing tube plus the floor. Only drawn in cutaway view. Floor
## vertices carry alpha 0 so the interior shader keeps them out of the cut.
static func interior_mesh(part: PartDef, floor_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var sides := 10
	var axis := part.p1 - part.p0
	var length := axis.length()
	var dir := axis / length
	var origin := part.p0 - part.com
	var wall := Color(0.78, 0.8, 0.82, 1.0)
	var floor_col := Color(0.2, 0.24, 0.34, 0.0)
	var steps := maxi(int(ceil(length / 3.5)), 2)
	for s: int in steps:
		var d0 := length * float(s) / float(steps)
		var d1 := length * float(s + 1) / float(steps)
		var pr0 := body_profile(part, d0, length)
		var pr1 := body_profile(part, d1, length)
		var r0 := pr0.x * 0.94
		var r1 := pr1.x * 0.94
		var c0 := origin + dir * d0 + Vector3(0.0, pr0.y, 0.0)
		var c1 := origin + dir * d1 + Vector3(0.0, pr1.y, 0.0)
		# A point far outside: _quad then faces the wall toward the axis.
		for k: int in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var n0 := Vector3(sin(a0), cos(a0), 0.0)
			var n1 := Vector3(sin(a1), cos(a1), 0.0)
			var outside := (c0 + c1) * 0.5 + (n0 + n1) * (r0 + r1)
			var uv := atlas_uv(TILE_INTERIOR, float(k) / float(sides), float(s) / float(steps))
			_quad(st, c0 + n0 * r0, c0 + n1 * r0, c1 + n1 * r1, c1 + n0 * r1, outside, wall, uv, uv, uv, uv)
		# Floor strip where the floor plane cuts the tube.
		var fy0 := floor_y - part.com.y - c0.y
		var fy1 := floor_y - part.com.y - c1.y
		if absf(fy0) < r0 * 0.95 and absf(fy1) < r1 * 0.95:
			var w0 := sqrt(r0 * r0 - fy0 * fy0)
			var w1 := sqrt(r1 * r1 - fy1 * fy1)
			var y := floor_y - part.com.y
			var below := Vector3(0.0, y - 5.0, (c0.z + c1.z) * 0.5)
			var fuv := atlas_uv(TILE_FLOOR, 0.5, 0.5)
			_quad(st, Vector3(-w0, y, c0.z), Vector3(w0, y, c0.z), Vector3(w1, y, c1.z),
					Vector3(-w1, y, c1.z), below, floor_col, fuv, fuv, fuv, fuv)
	return _finish(st)


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, tile: Vector2i) -> void:
	var h := size * 0.5
	var uv := atlas_uv(tile, 0.5, 0.5)
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
			_quad(st, c - du - dv, c + du - dv, c + du + dv, c - du + dv, center, col, uv, uv, uv, uv)


## One passenger seat: origin on the floor under the hip point, facing -Z.
static func seat_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(1)
	var col := Color(1.0, 1.0, 1.0)
	_box(st, Vector3(0.0, 0.34, -0.02), Vector3(0.44, 0.12, 0.46), col, TILE_SEAT)
	_box(st, Vector3(0.0, 0.72, 0.25), Vector3(0.44, 0.74, 0.08), col, TILE_SEAT)
	_box(st, Vector3(0.0, 0.14, 0.0), Vector3(0.36, 0.28, 0.06), col.darkened(0.5), TILE_METAL)
	return _finish(st)


static func part_mesh(adef: AircraftDef, part: PartDef, lod: int) -> ArrayMesh:
	match part.kind:
		PartDef.Kind.FUSELAGE, PartDef.Kind.ENGINE:
			return body_mesh(adef, part, lod)
		PartDef.Kind.WING, PartDef.Kind.STABILIZER, PartDef.Kind.FIN:
			return panel_mesh(adef, part, lod)
	return null


static func part_hull(part: PartDef) -> PackedVector3Array:
	match part.kind:
		PartDef.Kind.FUSELAGE, PartDef.Kind.ENGINE:
			return body_hull(part)
		PartDef.Kind.WING, PartDef.Kind.STABILIZER, PartDef.Kind.FIN:
			return panel_hull(part)
	return PackedVector3Array()
