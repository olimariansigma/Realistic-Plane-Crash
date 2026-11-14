class_name WorldTrees
extends RefCounted
## Conifers and round trees, each type one MultiMesh with a vertex-coloured mesh.

var _con_xf: Array[Transform3D] = []
var _con_col: Array[Color] = []
var _rnd_xf: Array[Transform3D] = []
var _rnd_col: Array[Color] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 31337


func add_conifer(p: Vector3, s: float) -> void:
	_con_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
	var t := _rng.randf_range(0.8, 1.2)
	_con_col.append(Color(t, t, t))


func add_round(p: Vector3, s: float) -> void:
	_rnd_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
	var t := _rng.randf_range(0.75, 1.25)
	_rnd_col.append(Color(t, t * _rng.randf_range(0.95, 1.1), t * 0.9))


func build(parent: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var con := WorldMeshBuilder.new()
	var trunk := Color(0.28, 0.2, 0.12)
	con.frustum(Vector3(0.0, 1.2, 0.0), 2.6, 0.0, 4.2, 6, Color(0.12, 0.27, 0.13), 0, 0.0)
	con.frustum(Vector3(0.0, 3.6, 0.0), 2.0, 0.0, 3.6, 6, Color(0.14, 0.3, 0.14), 0, 0.0)
	con.frustum(Vector3(0.0, 5.8, 0.0), 1.3, 0.0, 3.2, 6, Color(0.16, 0.32, 0.15), 0, 0.0)
	var rnd := WorldMeshBuilder.new()
	rnd.frustum(Vector3.ZERO, 0.3, 0.25, 2.8, 5, trunk, 0, 0.0)
	rnd.dome(Vector3(0.0, 4.2, 0.0), 2.9, Color(0.14, 0.3, 0.1), 6, 2)
	_commit(parent, "ConiferTrees", con.build(), mat, _con_xf, _con_col)
	_commit(parent, "RoundTrees", rnd.build(), mat, _rnd_xf, _rnd_col)


func _commit(parent: Node3D, node_name: String, mesh: ArrayMesh, mat: Material, xf: Array[Transform3D],
		cols: Array[Color]) -> void:
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i: int in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
