class_name WorldAirport
extends RefCounted
## The airfield east of the runway (x > 150): taxiways, apron, terminal with
## jet bridges, control tower, hangars, radar, car park, roads, plus the fuel
## farm to the west and the runway/taxiway lights. Surfaces and solids are
## merged into two meshes; vehicles go through WorldBoxes; lights are one
## MultiMesh.

const Y_PAVE := 0.05
const Y_MARK := 0.08

var _solid := WorldMeshBuilder.new()
var _paved := WorldMeshBuilder.new()
var _col: WorldColliders
var _boxes: WorldBoxes
var _rng := RandomNumberGenerator.new()
var _light_xf: Array[Transform3D] = []
var _light_col: Array[Color] = []

var _conc := Color(0.74, 0.74, 0.72)
var _grey := Color(0.6, 0.62, 0.64)
var _white := Color(0.88, 0.88, 0.86)
var _red := Color(0.78, 0.12, 0.1)
var _roof := Color(0.5, 0.52, 0.55)


func build(parent: Node3D, col: WorldColliders, boxes: WorldBoxes) -> void:
	_col = col
	_boxes = boxes
	_rng.seed = 5150
	_build_surfaces()
	_build_tower(Vector3(260.0, 0.0, -450.0))
	_build_terminal()
	_build_hangars()
	_build_fuel_farm()
	_build_radar(Vector3(360.0, 0.0, -330.0))
	_build_vehicles()
	_build_lights()
	_commit(parent)


# ---------------------------------------------------------------- surfaces

func _strip(a: Vector2, b: Vector2, width: float, kind: int, y: float = Y_PAVE, extend: float = 0.0) -> void:
	var f2 := (b - a).normalized()
	a -= f2 * extend
	b += f2 * extend
	var fv := Vector3(f2.x, 0.0, f2.y)
	var r := fv.cross(Vector3.UP) * width * 0.5
	var pa := Vector3(a.x, y, a.y)
	var pb := Vector3(b.x, y, b.y)
	_paved.quad(pa - r, pa + r, pb + r, pb - r, Color(float(kind) / 16.0, 0.0, 0.0, 1.0),
			Vector2(width, a.distance_to(b)))


func _rect(x0: float, x1: float, z0: float, z1: float, kind: int, y: float = Y_PAVE) -> void:
	# z0 > z1: strip runs along -Z.
	_strip(Vector2((x0 + x1) * 0.5, z0), Vector2((x0 + x1) * 0.5, z1), x1 - x0, kind, y)


func _poly(pts: Array[Vector2], width: float, kind: int, closed: bool = false) -> void:
	var n := pts.size()
	var segs := n if closed else n - 1
	for i: int in segs:
		_strip(pts[i], pts[(i + 1) % n], width, kind, Y_PAVE, width * 0.5 if (closed or i > 0) else 0.0)


func _build_surfaces() -> void:
	# Parallel taxiway and connectors.
	_strip(Vector2(120.0, 330.0), Vector2(120.0, -3080.0), 23.0, 0)
	for z: float in [300.0, -400.0, -1000.0, -1600.0, -2200.0, -2800.0]:
		_strip(Vector2(30.0, z), Vector2(108.5, z), 23.0, 0)
	# Terminal apron with stands.
	_rect(132.0, 335.0, -590.0, -1130.0, 1)
	_rect(169.8, 170.2, -590.0, -1130.0, 4, Y_MARK)
	for i: int in 5:
		var z := -690.0 - 80.0 * float(i)
		_strip(Vector2(170.0, z), Vector2(318.0, z), 0.35, 4, Y_MARK)
		_strip(Vector2(300.0, z - 4.0), Vector2(300.0, z + 4.0), 0.5, 4, Y_MARK)
		_strip(Vector2(262.0, z - 26.0), Vector2(318.0, z - 26.0), 0.25, 5, Y_MARK)
		_strip(Vector2(262.0, z + 26.0), Vector2(318.0, z + 26.0), 0.25, 5, Y_MARK)
		_strip(Vector2(262.0, z - 26.0), Vector2(262.0, z + 26.0), 0.25, 5, Y_MARK)
		_strip(Vector2(318.0, z - 26.0), Vector2(318.0, z + 26.0), 0.25, 5, Y_MARK)
	# Hangar apron.
	_rect(132.0, 232.0, -1235.0, -1705.0, 1)
	for i: int in 5:
		var z := -1290.0 - 90.0 * float(i)
		_strip(Vector2(135.0, z), Vector2(225.0, z), 0.35, 4, Y_MARK)
	# Car park, access roads, perimeter loop.
	_strip(Vector2(455.0, -690.0), Vector2(455.0, -888.0), 70.0, 3)
	_strip(Vector2(505.0, -640.0), Vector2(505.0, -940.0), 12.0, 2)
	_strip(Vector2(505.0, -790.0), Vector2(600.0, -790.0), 10.0, 2)
	_strip(Vector2(380.0, -600.0), Vector2(505.0, -600.0), 10.0, 2)
	_poly([Vector2(-200.0, 420.0), Vector2(600.0, 420.0), Vector2(600.0, -3150.0), Vector2(-200.0, -3150.0)],
			8.0, 2, true)
	# Highway to the city and a few country roads.
	_poly([Vector2(600.0, -1500.0), Vector2(780.0, -2400.0), Vector2(907.0, -3000.0), Vector2(907.0, -3807.0)],
			10.0, 2)
	_poly([Vector2(700.0, 2200.0), Vector2(700.0, -700.0), Vector2(600.0, -1500.0)], 7.0, 2)
	_poly([Vector2(-900.0, 3000.0), Vector2(-900.0, -1000.0), Vector2(-1500.0, -2500.0),
			Vector2(-2400.0, -3500.0), Vector2(-2900.0, -4500.0)], 7.0, 2)
	_poly([Vector2(-3000.0, 1400.0), Vector2(0.0, 1400.0), Vector2(3000.0, 1700.0)], 7.0, 2)
	_poly([Vector2(900.0, -300.0), Vector2(2500.0, -1400.0), Vector2(3500.0, -2500.0)], 7.0, 2)
	# Fuel farm bund and access.
	_rect(-402.0, -278.0, -870.0, -968.0, 6)
	_strip(Vector2(-200.0, -920.0), Vector2(-278.0, -920.0), 6.0, 2)


# ------------------------------------------------------------------- solids

func _build_tower(c: Vector3) -> void:
	var stone := Color(0.72, 0.72, 0.7)
	_solid.wall_box(c, Vector3(26.0, 7.0, 26.0), 0.0, stone, 7, 0.0, _roof, 0)
	_col.box_on("TowerBase", c, Vector3(26.0, 7.0, 26.0))
	# Tapered octagonal shaft, y 7..43, with red/white bands near the top.
	var segs: Array[Vector3] = [Vector3(7.0, 30.0, 0), Vector3(30.0, 34.0, 1), Vector3(34.0, 38.0, 2),
			Vector3(38.0, 43.0, 1)]
	for s: Vector3 in segs:
		var colr := stone if int(s.z) == 0 else (_red if int(s.z) == 1 else _white)
		var r0 := 5.8 - (s.x - 7.0) / 36.0 * 1.2
		var r1 := 5.8 - (s.y - 7.0) / 36.0 * 1.2
		_solid.frustum(c + Vector3(0.0, s.x, 0.0), r0, r1, s.y - s.x, 8, colr, 7 if int(s.z) == 0 else 0, 0.0,
				false, Color(-1.0, 0.0, 0.0), 0, PI / 8.0)
	_col.box_on("TowerShaft", c + Vector3(0.0, 7.0, 0.0), Vector3(11.0, 36.0, 11.0))
	# Flared equipment floor, glazed cab (wider than the shaft), roof slab.
	_solid.frustum(c + Vector3(0.0, 43.0, 0.0), 4.6, 9.2, 3.0, 8, stone, 7, 0.0, false, Color(-1.0, 0.0, 0.0), 0,
			PI / 8.0)
	_solid.frustum(c + Vector3(0.0, 46.0, 0.0), 9.6, 10.6, 5.5, 8, Color(0.5, 0.6, 0.65), 5, 0.0, false,
			Color(-1.0, 0.0, 0.0), 0, PI / 8.0)
	_solid.frustum(c + Vector3(0.0, 51.5, 0.0), 11.4, 11.4, 1.2, 8, _white, 0, 0.0, false, _white, 0, PI / 8.0)
	_col.box_on("TowerCab", c + Vector3(0.0, 43.0, 0.0), Vector3(20.0, 9.0, 20.0))
	_solid.wall_box(c + Vector3(0.0, 52.7, 0.0), Vector3(6.0, 2.4, 6.0), 0.0, _grey, 0, 0.0, _roof, 0)
	# Banded antenna mast, radar rotator and beacon.
	for k: int in 6:
		var y0 := 55.1 + 1.8 * float(k)
		var rr0 := 0.45 - 0.03 * float(k)
		_solid.frustum(c + Vector3(0.0, y0, 0.0), rr0, rr0 - 0.03, 1.8, 6, _red if k % 2 == 0 else _white, 0, 0.0)
	_solid.wall_box(c + Vector3(0.0, 61.0, 0.0), Vector3(5.0, 0.3, 1.0), 0.3, _white, 0, 0.0, _white, 0)
	_solid.wall_box(c + Vector3(0.0, 66.0, 0.0), Vector3(0.6, 0.6, 0.6), 0.0, _red, 0, 0.0, _red, 0)
	_solid.wall_box(c + Vector3(7.0, 52.7, 7.0), Vector3(0.2, 3.0, 0.2), 0.0, _grey, 0, 0.0, _grey, 0)


func _build_terminal() -> void:
	var x := 380.0
	var zc := -860.0
	var len_z := 440.0
	_solid.wall_box(Vector3(x, 0.0, zc), Vector3(56.0, 14.0, len_z), 0.0, Color(0.78, 0.78, 0.76), 7, 0.0,
			_roof, 3)
	_col.box_on("Terminal", Vector3(x, 0.0, zc), Vector3(56.0, 14.0, len_z))
	# Glazed atrium on the airside, with an overhanging canopy.
	_solid.wall_box(Vector3(x - 33.0, 0.0, zc), Vector3(10.0, 11.0, len_z - 20.0), 0.0, Color(0.5, 0.6, 0.66),
			1, 0.0, _roof, 3, 1, 0.0)
	_solid.wall_box(Vector3(x - 36.0, 11.0, zc), Vector3(20.0, 1.0, len_z - 10.0), 0.0, _white, 0, 0.0,
			Color(0.8, 0.8, 0.8), 0)
	# Rooftop plant.
	for i: int in 6:
		_solid.wall_box(Vector3(x + _rng.randf_range(-12.0, 12.0), 14.0, zc - 190.0 + 76.0 * float(i)),
				Vector3(10.0, 3.0, 14.0), 0.0, _grey, 3, 0.0, _grey, 3)
	# Jet bridges at each stand.
	for i: int in 5:
		var z := -690.0 - 80.0 * float(i)
		_solid.wall_box(Vector3(x - 52.0, 4.2, z), Vector3(30.0, 3.0, 3.2), 0.0, Color(0.85, 0.86, 0.88), 0,
				0.0, Color(0.7, 0.7, 0.72), 0)
		_solid.frustum(Vector3(x - 38.0, 0.0, z), 3.2, 3.2, 8.0, 10, Color(0.8, 0.8, 0.82), 0, 0.0, true,
				Color(0.7, 0.7, 0.72))
		_solid.wall_box(Vector3(x - 69.0, 3.6, z), Vector3(4.2, 3.6, 4.2), 0.0, Color(0.8, 0.8, 0.82), 0, 0.0,
				_grey, 0)
		_solid.wall_box(Vector3(x - 69.0, 0.0, z), Vector3(0.9, 3.6, 0.9), 0.0, _grey, 0, 0.0, _grey, 0)


func _build_hangars() -> void:
	for i: int in 5:
		var z := -1290.0 - 90.0 * float(i)
		var c := Vector3(260.0, 0.0, z)
		var wall_col := Color(0.62, 0.64, 0.66) if i % 2 == 0 else Color(0.7, 0.68, 0.62)
		var roof_col := Color(0.45, 0.5, 0.56)
		var hx := 30.0
		var hz := 39.0
		var wh := 11.0
		# Walls except the doored west face.
		_solid.wall_box(c, Vector3(60.0, wh, 78.0), 0.0, wall_col, 0, 0.0, roof_col, 3, 0, 0.0)
		# Door leaf proud of the west wall.
		_solid.wall(Vector3(c.x - hx - 0.1, 0.0, z - 30.0), Vector3(c.x - hx - 0.1, 0.0, z + 30.0), 10.0,
				Color(0.5, 0.55, 0.6), 2, 10.0)
		# Roof: gabled on even hangars, curved on odd ones.
		if i % 2 == 0:
			_solid.gable(c + Vector3(0.0, wh, 0.0), hx + 0.5, hz + 0.5, 7.0, roof_col, 3)
		else:
			_solid.vault(c + Vector3(0.0, wh, 0.0), hx + 0.5, hz + 0.5, 8.0, 8, roof_col, 3)
		_col.box_on("Hangar%d" % i, c, Vector3(60.0, 18.0, 78.0))


func _build_fuel_farm() -> void:
	var idx := 0
	for row: int in 2:
		for k: int in 3:
			var c := Vector3(-300.0 - 36.0 * float(k), 0.0, -900.0 - 36.0 * float(row))
			_solid.frustum(c, 11.0, 11.0, 14.0, 20, Color(0.88, 0.88, 0.85), 4, 0.0, true, Color(0.8, 0.8, 0.78), 0)
			_solid.frustum(c + Vector3(0.0, 14.0, 0.0), 11.0, 3.0, 1.2, 20, Color(0.8, 0.8, 0.78), 0, 0.0, true,
					Color(0.75, 0.75, 0.75), 0)
			_col.box_on("Tank%d" % idx, c, Vector3(20.0, 15.0, 20.0))
			idx += 1
	_solid.wall_box(Vector3(-390.0, 0.0, -935.0), Vector3(8.0, 4.0, 12.0), 0.0, _grey, 0, 0.0, _grey, 0)


func _build_radar(c: Vector3) -> void:
	_solid.wall_box(c, Vector3(9.0, 12.0, 9.0), 0.0, Color(0.8, 0.8, 0.78), 7, 0.0, _roof, 0)
	_solid.dome(c + Vector3(0.0, 12.0, 0.0), 6.5, Color(0.95, 0.95, 0.95), 14, 6)
	_col.box_on("RadarHouse", c, Vector3(10.0, 19.0, 10.0))


# ---------------------------------------------------------------- vehicles

func _car(x: float, z: float, yaw: float, col: Color) -> void:
	_boxes.add(Vector3(x, 0.0, z), Vector3(4.4, 1.5, 1.8), yaw, col, WorldBoxes.STYLE_VEHICLE, _rng.randf())


func _build_vehicles() -> void:
	var palette: Array[Color] = [Color(0.8, 0.8, 0.8), Color(0.1, 0.1, 0.12), Color(0.6, 0.1, 0.1),
			Color(0.15, 0.25, 0.5), Color(0.5, 0.5, 0.52), Color(0.8, 0.7, 0.2)]
	for pair: int in 11:
		for half: int in 2:
			var v := 18.0 * float(pair) + (2.75 if half == 0 else 15.25)
			for m: int in 27:
				if _rng.randf() < 0.6:
					continue
				_car(420.0 + (float(m) + 0.5) * 2.6, -690.0 - v, PI * 0.5,
						palette[_rng.randi() % palette.size()])
	# Ground support at every stand.
	var yellow := Color(0.9, 0.75, 0.1)
	for i: int in 5:
		var z := -690.0 - 80.0 * float(i)
		_boxes.add(Vector3(280.0, 0.0, z + 18.0), Vector3(6.0, 2.4, 2.5), 0.0, yellow, WorldBoxes.STYLE_VEHICLE, 0.3)
		_boxes.add(Vector3(272.0, 0.0, z + 18.0), Vector3(3.0, 1.2, 1.8), 0.0, Color(0.5, 0.5, 0.5),
				WorldBoxes.STYLE_VEHICLE, 0.6)
		_boxes.add(Vector3(240.0, 0.0, z - 20.0), Vector3(7.0, 3.2, 2.4), 0.0, Color(0.9, 0.9, 0.9),
				WorldBoxes.STYLE_VEHICLE, 0.4)
	for i: int in 8:
		_boxes.add(Vector3(150.0 + 15.0 * float(i), 0.0, -1260.0), Vector3(5.0, 2.2, 2.2), 0.0, yellow,
				WorldBoxes.STYLE_VEHICLE, 0.2)
	# Fuel tankers at the farm.
	for i: int in 3:
		_boxes.add(Vector3(-250.0, 0.0, -890.0 - 14.0 * float(i)), Vector3(9.0, 3.0, 2.6), 0.0,
				Color(0.85, 0.85, 0.82), WorldBoxes.STYLE_VEHICLE, 0.5)


# ------------------------------------------------------------------ lights

func _light(p: Vector3, size: float, c: Color) -> void:
	_light_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(size, size, size)), p))
	_light_col.append(c)


func _build_lights() -> void:
	var white := Color(1.0, 0.97, 0.85)
	var z := 340.0
	while z > -3040.0:
		_light(Vector3(-31.5, 0.3, z), 0.6, white)
		_light(Vector3(31.5, 0.3, z), 0.6, white)
		z -= 60.0
	for k: int in 16:
		var x := -30.0 + 4.0 * float(k)
		_light(Vector3(x, 0.2, 352.0), 0.6, Color(0.1, 1.0, 0.3))
		_light(Vector3(x, 0.2, -3052.0), 0.6, Color(1.0, 0.1, 0.1))
	# Approach lights: centreline bars and two cross bars, 900 m out.
	for r: int in 20:
		var az := 360.0 + 30.0 * float(r)
		for k: int in 5:
			_light(Vector3(-3.0 + 1.5 * float(k), 0.5, az), 0.9, white)
		if r == 6 or r == 14:
			for k: int in 11:
				_light(Vector3(-15.0 + 3.0 * float(k), 0.5, az), 0.9, white)
	# Taxiway edge (blue) and centreline (green) lights.
	z = 320.0
	while z > -3070.0:
		_light(Vector3(107.5, 0.25, z), 0.5, Color(0.2, 0.3, 1.0))
		_light(Vector3(132.5, 0.25, z), 0.5, Color(0.2, 0.3, 1.0))
		_light(Vector3(120.0, 0.12, z), 0.4, Color(0.2, 1.0, 0.3))
		z -= 40.0


# ------------------------------------------------------------------ commit

func _commit(parent: Node3D) -> void:
	var paved_mat := ShaderMaterial.new()
	paved_mat.shader = load("res://shaders/world_paved.gdshader") as Shader
	var paved := MeshInstance3D.new()
	paved.name = "Paved"
	paved.mesh = _paved.build()
	paved.material_override = paved_mat
	paved.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(paved)

	var solid_mat := ShaderMaterial.new()
	solid_mat.shader = load("res://shaders/world_solid.gdshader") as Shader
	var solid := MeshInstance3D.new()
	solid.name = "AirportSolids"
	solid.mesh = _solid.build()
	solid.material_override = solid_mat
	parent.add_child(solid)

	var lmesh := BoxMesh.new()
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.vertex_color_use_as_albedo = true
	lmesh.material = lmat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = lmesh
	mm.instance_count = _light_xf.size()
	for i: int in _light_xf.size():
		mm.set_instance_transform(i, _light_xf[i])
		mm.set_instance_color(i, _light_col[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Lights"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	_light_xf.clear()
	_light_col.clear()
