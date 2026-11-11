extends SceneTree
## Developer tool: renders the flight scene offscreen and saves a PNG.
## Needs a display and a Vulkan driver; on a headless box use Xvfb + lavapipe:
##   xvfb-run -a godot --path . -s res://tools/shot.gd -- <id> <runway|air|approach|dive|hangar> <seconds> <out.png> [cam_mode] [yaw] [pitch] [zoom]

var _scene: FlightScene
var _t := 0.0
var _seconds := 1.0
var _out := "user://shot.png"
var _started := false
var _frames_after := 0
var _hangar: Node


func _process(delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if not _started:
		_started = true
		var game := GameState.instance()
		game.selected_id = args[0] if args.size() > 0 else "meridian_220"
		var mode: String = args[1] if args.size() > 1 else "runway"
		game.start_mode = GameState.StartMode.AIRBORNE if mode in ["air", "dive"] else (
				GameState.StartMode.APPROACH if mode == "approach" else GameState.StartMode.RUNWAY)
		_seconds = float(args[2]) if args.size() > 2 else 1.0
		_out = args[3] if args.size() > 3 else _out
		root.size = Vector2i(1280, 720)
		if mode == "hangar":
			_hangar = (load("res://scenes/hangar/hangar.tscn") as PackedScene).instantiate()
			root.add_child(_hangar)
			return false
		_scene = (load("res://scenes/flight/flight.tscn") as PackedScene).instantiate() as FlightScene
		root.add_child(_scene)
		if mode == "dive":
			# 25 degree dive from 120 m: hits the ground about 2 s in.
			var basis := Basis(Vector3.RIGHT, deg_to_rad(-25.0)) * Basis(Vector3.FORWARD, deg_to_rad(12.0))
			var v := _scene.def.v_cruise * 0.75
			_scene.aircraft.teleport(Transform3D(basis, World.RUNWAY_START + Vector3(0.0, 120.0, -300.0)),
					basis * Vector3(0.0, 0.0, -v))
		return false
	_t += delta
	if _hangar != null and args.size() > 4 and _t > 0.6:
		RenderingServer.global_shader_parameter_set(&"cutaway_amount", float(args[4]))
	if _t < 0.2 and _scene != null:
		if args.size() > 4:
			_scene.camera_rig.set_mode(int(args[4]) as CameraRig.Mode)
		if args.size() > 5:
			_scene.camera_rig._yaw = float(args[5])
		if args.size() > 6:
			_scene.camera_rig._pitch = float(args[6])
		if args.size() > 7:
			_scene.camera_rig._zoom = float(args[7])
	if _t >= _seconds:
		_frames_after += 1
		if _frames_after == 3:
			var img := root.get_texture().get_image()
			img.save_png(_out)
			print("saved ", _out, " ", img.get_size())
			quit(0)
			return true
	return false
