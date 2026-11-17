class_name WorldBoxes
extends RefCounted
## Every building, rooftop unit and vehicle in the world is a scaled unit box
## in one MultiMesh (one draw call). Colour = base colour; custom data =
## (style, seed, roof type, ground-floor band flag), read by world_building.

const STYLE_GLASS := 0
const STYLE_CONCRETE := 1
const STYLE_BRICK := 2
const STYLE_METAL := 3
const STYLE_VEHICLE := 4
const STYLE_WAREHOUSE := 5

var _xforms: Array[Transform3D] = []
var _colors: Array[Color] = []
var _customs: Array[Color] = []


func count() -> int:
	return _xforms.size()


## Adds a box standing on `base` (bottom centre).
func add(base: Vector3, size: Vector3, yaw: float, color: Color, style: int, seed_value: float,
		roof: int = 0, band: bool = false) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled(size)
	_xforms.append(Transform3D(basis, base + Vector3(0.0, size.y * 0.5, 0.0)))
	_colors.append(color)
	_customs.append(Color(float(style), seed_value, float(roof), 1.0 if band else 0.0))


func build(parent: Node3D) -> void:
	var mesh := BoxMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world_building.gdshader") as Shader
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = _xforms.size()
	for i: int in _xforms.size():
		mm.set_instance_transform(i, _xforms[i])
		mm.set_instance_color(i, _colors[i])
		mm.set_instance_custom_data(i, _customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Buildings"
	mmi.multimesh = mm
	# Thousands of boxes in the sun's shadow pass every frame cost more than
	# their shadows are worth at flight distances.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	_xforms.clear()
	_colors.clear()
	_customs.clear()
