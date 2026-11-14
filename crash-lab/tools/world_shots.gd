extends SceneTree
## Developer tool: renders the world from camera positions and saves PNGs.
##   xvfb-run -a godot --path . -s res://tools/world_shots.gd -- <out_dir> <name:cx,cy,cz:tx,ty,tz>...

var _world: World
var _cam: Camera3D
var _shots: Array[String] = []
var _out := "user://"
var _frame := 0
var _idx := 0


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _world == null:
		root.size = Vector2i(1280, 720)
		_out = args[0] if args.size() > 0 else "user://"
		for i: int in range(1, args.size()):
			_shots.append(args[i])
		_world = World.new()
		root.add_child(_world)
		_world.apply_quality(1)
		_cam = Camera3D.new()
		_cam.far = 40000.0
		_cam.fov = 70.0
		root.add_child(_cam)
		_cam.current = true
		return false
	_frame += 1
	if _idx >= _shots.size():
		quit()
		return true
	if _frame == 1:
		var parts := _shots[_idx].split(":")
		var p := parts[1].split(",")
		var t := parts[2].split(",")
		_cam.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		_cam.look_at(Vector3(float(t[0]), float(t[1]), float(t[2])), Vector3.UP)
	elif _frame == 6:
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [_out, _shots[_idx].split(":")[0]])
		_idx += 1
		_frame = 0
	return false
