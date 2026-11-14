class_name WorldMeshBuilder
extends RefCounted
## Accumulates static geometry into one ArrayMesh surface. Every vertex carries
## a colour, UV in metres along the face (u along, v up) and UV2, which the
## world shaders read as (style, parameter). Winding follows Godot (clockwise
## front faces); callers list quad corners counter-clockwise seen from outside.

var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
var _idx := PackedInt32Array()


func is_empty() -> bool:
	return _verts.is_empty()


func _push(p: Vector3, n: Vector3, c: Color, uv: Vector2, uv2: Vector2) -> int:
	var i := _verts.size()
	_verts.append(p)
	_norms.append(n)
	_cols.append(c)
	_uvs.append(uv)
	_uv2s.append(uv2)
	return i


## One quad. Corners: bottom-left, bottom-right, top-right, top-left seen from outside.
func quad(bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3, color: Color, uv2: Vector2) -> void:
	var n := (br - bl).cross(tl - bl).normalized()
	var w := bl.distance_to(br)
	var h := br.distance_to(tr)
	var i0 := _push(bl, n, color, Vector2(0.0, 0.0), uv2)
	var i1 := _push(br, n, color, Vector2(w, 0.0), uv2)
	var i2 := _push(tr, n, color, Vector2(w, h), uv2)
	var i3 := _push(tl, n, color, Vector2(0.0, h), uv2)
	_idx.append_array(PackedInt32Array([i0, i3, i2, i0, i2, i1]))


## Quad with explicit per-vertex normals (smooth surfaces).
func quad_smooth(bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3, nbl: Vector3, nbr: Vector3,
		ntr: Vector3, ntl: Vector3, color: Color, uv2: Vector2, uv_w: float, uv_h: float, u0: float) -> void:
	var i0 := _push(bl, nbl, color, Vector2(u0, 0.0), uv2)
	var i1 := _push(br, nbr, color, Vector2(u0 + uv_w, 0.0), uv2)
	var i2 := _push(tr, ntr, color, Vector2(u0 + uv_w, uv_h), uv2)
	var i3 := _push(tl, ntl, color, Vector2(u0, uv_h), uv2)
	_idx.append_array(PackedInt32Array([i0, i3, i2, i0, i2, i1]))


## One triangle, counter-clockwise seen from outside.
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, uv2: Vector2) -> void:
	var n := (b - a).cross(c - a).normalized()
	var ab := b - a
	var along := ab.normalized()
	var w := ab.length()
	var cu := (c - a).dot(along)
	var cv := (c - a - along * cu).length()
	var i0 := _push(a, n, color, Vector2(0.0, 0.0), uv2)
	var i1 := _push(b, n, color, Vector2(w, 0.0), uv2)
	var i2 := _push(c, n, color, Vector2(cu, cv), uv2)
	_idx.append_array(PackedInt32Array([i0, i2, i1]))


## Box standing on `base` (bottom centre). Walls use `style`, the roof `roof_style`.
## `west_style` >= 0 overrides the -X wall (before yaw), e.g. hangar doors or a glass front.
func wall_box(base: Vector3, size: Vector3, yaw: float, color: Color, style: int, param: float,
		roof_color: Color, roof_style: int, west_style: int = -1, west_param: float = 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := size.y
	var pp := b * Vector3(hx, 0.0, hz)
	var pm := b * Vector3(hx, 0.0, -hz)
	var mp := b * Vector3(-hx, 0.0, hz)
	var mm := b * Vector3(-hx, 0.0, -hz)
	var up := Vector3(0.0, h, 0.0)
	var s := Vector2(float(style), param)
	quad(base + pp, base + pm, base + pm + up, base + pp + up, color, s)
	var sw := s if west_style < 0 else Vector2(float(west_style), west_param)
	quad(base + mm, base + mp, base + mp + up, base + mm + up, color, sw)
	quad(base + mp, base + pp, base + pp + up, base + mp + up, color, s)
	quad(base + pm, base + mm, base + mm + up, base + pm + up, color, s)
	quad(base + mp + up, base + pp + up, base + pm + up, base + mm + up, roof_color,
			Vector2(float(roof_style), 0.0))


## Vertical wall quad from `a` to `b` (seen from outside, a on the left), `h` tall.
func wall(a: Vector3, b: Vector3, h: float, color: Color, style: int, param: float) -> void:
	var up := Vector3(0.0, h, 0.0)
	quad(a, b, b + up, a + up, color, Vector2(float(style), param))


## Vertical frustum with `sides` faces (regular polygon, vertex radius r0 at the
## bottom and r1 at the top). Flat or smooth shaded. Optional top cap.
func frustum(base: Vector3, r0: float, r1: float, h: float, sides: int, color: Color, style: int,
		param: float, smooth: bool = false, cap_color: Color = Color(-1.0, 0.0, 0.0), cap_style: int = 0,
		yaw: float = 0.0) -> void:
	var s := Vector2(float(style), param)
	var top := base + Vector3(0.0, h, 0.0)
	var slope := Vector3(0.0, r0 - r1, 0.0)
	var u := 0.0
	for k: int in sides:
		var a0 := yaw + TAU * float(k) / float(sides)
		var a1 := yaw + TAU * float(k + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0.0, -sin(a0))
		var d1 := Vector3(cos(a1), 0.0, -sin(a1))
		var bl := base + d0 * r0
		var br := base + d1 * r0
		var tr := top + d1 * r1
		var tl := top + d0 * r1
		var side_len := bl.distance_to(br) if r0 > 0.0001 else tl.distance_to(tr)
		var hh := bl.distance_to(tl)
		if smooth:
			var n0 := (d0 * h + slope).normalized()
			var n1 := (d1 * h + slope).normalized()
			quad_smooth(bl, br, tr, tl, n0, n1, n1, n0, color, s, side_len, hh, u)
		else:
			quad(bl, br, tr, tl, color, s)
		u += side_len
	if cap_color.r >= 0.0 and r1 > 0.0001:
		var cs := Vector2(float(cap_style), 0.0)
		for k: int in sides:
			var a0 := yaw + TAU * float(k) / float(sides)
			var a1 := yaw + TAU * float(k + 1) / float(sides)
			tri(top, top + Vector3(cos(a0), 0.0, -sin(a0)) * r1, top + Vector3(cos(a1), 0.0, -sin(a1)) * r1,
					cap_color, cs)


## Upper hemisphere (smooth) centred on `center`.
func dome(center: Vector3, r: float, color: Color, lon: int, lat: int, style: int = 0) -> void:
	var s := Vector2(float(style), 0.0)
	for j: int in lat:
		var e0 := 0.5 * PI * float(j) / float(lat)
		var e1 := 0.5 * PI * float(j + 1) / float(lat)
		for k: int in lon:
			var a0 := TAU * float(k) / float(lon)
			var a1 := TAU * float(k + 1) / float(lon)
			var n_bl := Vector3(cos(a0) * cos(e0), sin(e0), -sin(a0) * cos(e0))
			var n_br := Vector3(cos(a1) * cos(e0), sin(e0), -sin(a1) * cos(e0))
			var n_tr := Vector3(cos(a1) * cos(e1), sin(e1), -sin(a1) * cos(e1))
			var n_tl := Vector3(cos(a0) * cos(e1), sin(e1), -sin(a0) * cos(e1))
			quad_smooth(center + n_bl * r, center + n_br * r, center + n_tr * r, center + n_tl * r,
					n_bl, n_br, n_tr, n_tl, color, s, 1.0, 1.0, 0.0)


## Gable roof, ridge along Z, eaves at `base.y`.
func gable(base: Vector3, hx: float, hz: float, h: float, color: Color, style: int) -> void:
	var s := Vector2(float(style), 0.0)
	var r := base + Vector3(0.0, h, 0.0)
	quad(base + Vector3(-hx, 0.0, -hz), base + Vector3(-hx, 0.0, hz), r + Vector3(0.0, 0.0, hz),
			r + Vector3(0.0, 0.0, -hz), color, s)
	quad(base + Vector3(hx, 0.0, hz), base + Vector3(hx, 0.0, -hz), r + Vector3(0.0, 0.0, -hz),
			r + Vector3(0.0, 0.0, hz), color, s)
	var gs := Vector2(0.0, 0.0)
	var gc := color.darkened(0.15)
	tri(base + Vector3(-hx, 0.0, hz), base + Vector3(hx, 0.0, hz), r + Vector3(0.0, 0.0, hz), gc, gs)
	tri(base + Vector3(hx, 0.0, -hz), base + Vector3(-hx, 0.0, -hz), r + Vector3(0.0, 0.0, -hz), gc, gs)


## Barrel-vault roof, axis along Z.
func vault(base: Vector3, hx: float, hz: float, h: float, segs: int, color: Color, style: int) -> void:
	var s := Vector2(float(style), 0.0)
	var pts: Array[Vector3] = []
	for k: int in segs + 1:
		var th := PI - PI * float(k) / float(segs)
		pts.append(Vector3(hx * cos(th), h * sin(th), 0.0))
	var gc := color.darkened(0.15)
	for k: int in segs:
		var a := pts[k]
		var b := pts[k + 1]
		quad(base + a + Vector3(0.0, 0.0, hz), base + b + Vector3(0.0, 0.0, hz),
				base + b + Vector3(0.0, 0.0, -hz), base + a + Vector3(0.0, 0.0, -hz), color, s)
		tri(base + Vector3(0.0, 0.0, hz), base + b + Vector3(0.0, 0.0, hz), base + a + Vector3(0.0, 0.0, hz),
				gc, Vector2.ZERO)
		tri(base + Vector3(0.0, 0.0, -hz), base + a + Vector3(0.0, 0.0, -hz), base + b + Vector3(0.0, 0.0, -hz),
				gc, Vector2.ZERO)


## Flat horizontal blob (triangle fan) for water and similar. UV.x = 0 at the centre, 1 at the rim.
func blob(center: Vector3, radii: PackedFloat32Array, color: Color) -> void:
	var n := radii.size()
	var c_i := _push(center, Vector3.UP, color, Vector2(0.0, 0.0), Vector2.ZERO)
	var first := _verts.size()
	for k: int in n:
		var a := TAU * float(k) / float(n)
		_push(center + Vector3(cos(a), 0.0, -sin(a)) * radii[k], Vector3.UP, color, Vector2(1.0, 0.0), Vector2.ZERO)
	for k: int in n:
		var i1 := first + k
		var i2 := first + (k + 1) % n
		_idx.append_array(PackedInt32Array([c_i, i1, i2]))


func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _cols
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	arrays[Mesh.ARRAY_INDEX] = _idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
