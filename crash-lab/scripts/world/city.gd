class_name WorldCity
extends RefCounted
## Procedural city at x 900..3320, z -3800..-6770: a 110 m street grid with a
## downtown core of towers, mid-rise blocks, low-rise edges and parks. Buildings
## are scaled boxes in the shared WorldBoxes MultiMesh; ground, streets and
## lot types come from the world_city shader plus a tiny code-made block map.

const ORIGIN := Vector2(900.0, -3800.0)
const COLS := 22
const ROWS := 27
const PITCH := 110.0
const ROAD := 14.0
const CORE := Vector2(2000.0, -5200.0)
const COLLIDER_CAP := 205

var _boxes: WorldBoxes
var _col: WorldColliders
var _trees: WorldTrees
var _rng := RandomNumberGenerator.new()
var _colliders := 0
var _map := Image.create(COLS, ROWS, false, Image.FORMAT_RGB8)
var _landmarks := {}


func build(parent: Node3D, col: WorldColliders, boxes: WorldBoxes, trees: WorldTrees) -> void:
	_col = col
	_boxes = boxes
	_trees = trees
	_rng.seed = 9090
	_landmarks = {Vector2i(9, 13): 0, Vector2i(10, 13): 1, Vector2i(9, 12): 2, Vector2i(10, 12): 3,
			Vector2i(11, 13): 4, Vector2i(8, 13): 5}
	var order: Array[Vector2i] = []
	for j: int in ROWS:
		for i: int in COLS:
			order.append(Vector2i(i, j))
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist(a) < _dist(b))
	var parks := {Vector2i(14, 8): true, Vector2i(5, 17): true, Vector2i(15, 19): true, Vector2i(14, 9): true}
	for b: Vector2i in order:
		var d := _dist(b)
		var lot := 1
		if parks.has(b):
			lot = 2
			_park(b)
		elif d > 0.82 and _rng.randf() < 0.55:
			lot = 0
		elif _landmarks.has(b):
			_landmark(b, _landmarks[b])
		else:
			_block(b, d)
		if d > 0.9 and lot == 1 and _rng.randf() < 0.5:
			lot = 0
		_map.set_pixel(b.x, b.y, Color8(lot * 64, 0, 0))
	_cars()
	_ground(parent)


func _block_origin(b: Vector2i) -> Vector2:
	return Vector2(ORIGIN.x + float(b.x) * PITCH + ROAD + 3.0, ORIGIN.y - float(b.y) * PITCH - ROAD - 3.0)


func _dist(b: Vector2i) -> float:
	var c := _block_origin(b) + Vector2(45.0, -45.0)
	return Vector2((c.x - CORE.x) / 1300.0, (c.y - CORE.y) / 1500.0).length()


func _facade(zone: float) -> Array:
	# Returns [style, colour].
	var r := _rng.randf()
	if zone < 0.3:
		if r < 0.65:
			var glass: Array[Color] = [Color(0.25, 0.35, 0.45), Color(0.2, 0.38, 0.35), Color(0.55, 0.58, 0.6),
					Color(0.4, 0.33, 0.27), Color(0.15, 0.17, 0.2)]
			return [WorldBoxes.STYLE_GLASS, glass[_rng.randi() % glass.size()]]
		return [WorldBoxes.STYLE_CONCRETE, _concrete()]
	if r < 0.35:
		var glass2: Array[Color] = [Color(0.25, 0.35, 0.45), Color(0.55, 0.58, 0.6), Color(0.2, 0.38, 0.35)]
		return [WorldBoxes.STYLE_GLASS, glass2[_rng.randi() % glass2.size()]]
	if r < 0.7:
		return [WorldBoxes.STYLE_CONCRETE, _concrete()]
	if r < 0.9 or zone < 0.7:
		var brick: Array[Color] = [Color(0.55, 0.28, 0.2), Color(0.5, 0.35, 0.25), Color(0.6, 0.5, 0.4)]
		return [WorldBoxes.STYLE_BRICK, brick[_rng.randi() % brick.size()]]
	var wh: Array[Color] = [Color(0.6, 0.6, 0.58), Color(0.5, 0.55, 0.6)]
	return [WorldBoxes.STYLE_WAREHOUSE, wh[_rng.randi() % wh.size()]]


func _concrete() -> Color:
	var c: Array[Color] = [Color(0.62, 0.6, 0.55), Color(0.55, 0.56, 0.57), Color(0.72, 0.71, 0.68)]
	return c[_rng.randi() % c.size()]


## Adds one building (with collider when 10 m+ and budget allows). Returns the actual height.
func _building(base: Vector3, size: Vector3, zone: float, tiered: bool = false, helipad: bool = false) -> float:
	var fac := _facade(zone)
	var style: int = fac[0]
	var colr: Color = fac[1]
	var s := _rng.randf()
	if size.y >= 10.0 and _colliders >= COLLIDER_CAP:
		size.y = 9.0
	if size.y >= 10.0:
		_colliders += 1
		_col.box_on("Bld", base, size)
	if tiered:
		# Stepped setbacks: 45 % / 30 % / 25 % of the height.
		var y := 0.0
		var fr := [0.45, 0.3, 0.25]
		var sc := 1.0
		for k: int in 3:
			var h: float = size.y * float(fr[k])
			var sz := Vector3(size.x * sc, h, size.z * sc)
			_boxes.add(base + Vector3(0.0, y, 0.0), sz, 0.0, colr, style, s, 0, k == 0)
			if k > 0:
				_colliders += 1
				_col.box_on("Tier", base + Vector3(0.0, y, 0.0), sz)
			y += h
			sc *= 0.72
		_boxes.add(base + Vector3(0.0, y, 0.0), Vector3(1.4, size.y * 0.18, 1.4), 0.0, Color(0.7, 0.7, 0.72),
				WorldBoxes.STYLE_METAL, 0.1)
		return size.y
	_boxes.add(base, size, 0.0, colr, style, s, 1 if helipad else 0, true)
	if size.y > 24.0 and not helipad:
		_boxes.add(base + Vector3(0.0, size.y, 0.0),
				Vector3(size.x * 0.3, _rng.randf_range(3.0, 5.0), size.z * 0.35), 0.0, Color(0.6, 0.6, 0.62),
				WorldBoxes.STYLE_METAL, 0.2)
		for k: int in 3:
			_boxes.add(base + Vector3((_rng.randf() - 0.5) * size.x * 0.6, size.y, (_rng.randf() - 0.5) * size.z * 0.6),
					Vector3(3.5, 1.6, 2.5), 0.0, Color(0.7, 0.72, 0.72), WorldBoxes.STYLE_METAL, 0.3)
	elif size.y > 10.0 and _rng.randf() < 0.5:
		_boxes.add(base + Vector3(0.0, size.y, 0.0), Vector3(3.5, 1.6, 2.5), 0.0, Color(0.7, 0.72, 0.72),
				WorldBoxes.STYLE_METAL, 0.3)
	return size.y


func _landmark(b: Vector2i, kind: int) -> void:
	var o := _block_origin(b)
	var c := Vector3(o.x + 45.0, 0.0, o.y - 45.0)
	match kind:
		0:
			_building(c, Vector3(54.0, 220.0, 54.0), 0.0, true)
		1:
			_building(c, Vector3(50.0, 185.0, 50.0), 0.0, true)
		2:
			_building(c + Vector3(-18.0, 0.0, 0.0), Vector3(30.0, 170.0, 30.0), 0.0)
			_building(c + Vector3(20.0, 0.0, 0.0), Vector3(28.0, 150.0, 28.0), 0.0)
		3:
			_building(c, Vector3(56.0, 130.0, 40.0), 0.0, false, true)
		4:
			_building(c, Vector3(60.0, 160.0, 30.0), 0.0)
			_boxes.add(c + Vector3(0.0, 160.0, 0.0), Vector3(1.2, 55.0, 1.2), 0.0, Color(0.8, 0.12, 0.1),
					WorldBoxes.STYLE_METAL, 0.9)
		_:
			_building(c, Vector3(50.0, 120.0, 50.0), 0.1, true)


func _block(b: Vector2i, d: float) -> void:
	var o := _block_origin(b)
	var n := 1
	var hmin := 8.0
	var hmax := 20.0
	if d < 0.3:
		n = 1
		hmin = 80.0
		hmax = 200.0
	elif d < 0.55:
		n = 1 if _rng.randf() < 0.4 else 2
		hmin = 25.0
		hmax = 70.0
	elif d < 0.8:
		n = 2
		hmin = 10.0
		hmax = 30.0
	else:
		n = 3
		hmin = 5.0
		hmax = 9.0
	var cell := 82.0 / float(n)
	for ix: int in n:
		for iz: int in n:
			if n > 1 and _rng.randf() < 0.15:
				continue
			var w := cell - _rng.randf_range(4.0, 10.0)
			var dd := cell - _rng.randf_range(4.0, 10.0)
			if n == 1:
				w = _rng.randf_range(44.0, 68.0)
				dd = _rng.randf_range(44.0, 68.0)
			var h := _rng.randf_range(hmin, hmax)
			if d < 0.3:
				h = hmin + (hmax - hmin) * pow(_rng.randf(), 0.8) * (1.0 - d)
			var cx := o.x + 4.0 + cell * (float(ix) + 0.5)
			var cz := o.y - 4.0 - cell * (float(iz) + 0.5)
			if n == 1:
				cx = o.x + 45.0
				cz = o.y - 45.0
			_building(Vector3(cx, 0.0, cz), Vector3(w, h, dd), d)
	# Street trees along the top and left pavement.
	if d < 0.9:
		for k: int in 4:
			_trees.add_round(Vector3(o.x + 2.0, 0.0, o.y - 12.0 - 22.0 * float(k)), _rng.randf_range(0.6, 0.9))


func _park(b: Vector2i) -> void:
	var o := _block_origin(b)
	for k: int in 28:
		_trees.add_round(Vector3(o.x + _rng.randf_range(4.0, 86.0), 0.0, o.y - _rng.randf_range(4.0, 86.0)),
				_rng.randf_range(0.8, 1.4))


func _cars() -> void:
	var palette: Array[Color] = [Color(0.8, 0.8, 0.8), Color(0.1, 0.1, 0.12), Color(0.6, 0.1, 0.1),
			Color(0.15, 0.25, 0.5), Color(0.5, 0.5, 0.52), Color(0.8, 0.7, 0.2), Color(0.1, 0.4, 0.2)]
	for k: int in 260:
		var bx := _rng.randi_range(2, 19)
		var bz := _rng.randi_range(3, 23)
		var along := _rng.randf_range(20.0, 100.0)
		var lane := 3.4 if _rng.randf() < 0.5 else -3.4
		var col := palette[_rng.randi() % palette.size()]
		if _rng.randf() < 0.5:
			var x := ORIGIN.x + float(bx) * PITCH + along
			var z := ORIGIN.y - float(bz) * PITCH - ROAD * 0.5 + lane
			_boxes.add(Vector3(x, 0.0, z), Vector3(4.4, 1.5, 1.8), 0.0 if lane < 0.0 else PI,
					col, WorldBoxes.STYLE_VEHICLE, _rng.randf())
		else:
			var x2 := ORIGIN.x + float(bx) * PITCH + ROAD * 0.5 + lane
			var z2 := ORIGIN.y - float(bz) * PITCH - along
			_boxes.add(Vector3(x2, 0.0, z2), Vector3(4.4, 1.5, 1.8), PI * 0.5 if lane < 0.0 else -PI * 0.5,
					col, WorldBoxes.STYLE_VEHICLE, _rng.randf())


func _ground(parent: Node3D) -> void:
	var tex := ImageTexture.create_from_image(_map)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world_city.gdshader") as Shader
	mat.set_shader_parameter(&"block_map", tex)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(float(COLS) * PITCH, float(ROWS) * PITCH)
	var mi := MeshInstance3D.new()
	mi.name = "CityGround"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(ORIGIN.x + float(COLS) * PITCH * 0.5, 0.04, ORIGIN.y - float(ROWS) * PITCH * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
