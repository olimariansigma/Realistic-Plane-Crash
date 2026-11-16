extends SceneTree
## Prints what the world costs: draw items, triangles, colliders, and whether
## anything stands in the runway corridor.
##   godot --headless --path . -s res://tools/world_stats.gd

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var world := World.new()
	root.add_child(world)
	var meshes := 0
	var multimeshes := 0
	var instances := 0
	var triangles := 0
	var colliders := 0
	var intruders: PackedStringArray = []
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			multimeshes += 1
			instances += mm.instance_count
			triangles += _triangles(mm.mesh) * mm.instance_count
		elif node is MeshInstance3D:
			meshes += 1
			triangles += _triangles((node as MeshInstance3D).mesh)
		elif node is CollisionShape3D:
			colliders += 1
			var shape := node as CollisionShape3D
			var at := shape.global_position
			# Clear strip: 75 m either side of the centreline, from 1 km before the
			# threshold to 1 km past the far end.
			if shape.shape is BoxShape3D and absf(at.x) < 75.0 + (shape.shape as BoxShape3D).size.x * 0.5 \
					and at.z < World.RUNWAY_START.z + 1100.0 and at.z > World.RUNWAY_START.z - World.RUNWAY_LENGTH - 900.0 \
					and node.get_parent().name != &"Ground":
				intruders.append("%s at %s" % [node.get_parent().name, at])
	print("WORLD: %d meshes + %d multimeshes (%d instances), ~%d k triangles, %d colliders" %
			[meshes, multimeshes, instances, triangles / 1000, colliders])
	print("WORLD: runway corridor " + ("clear" if intruders.is_empty() else "BLOCKED by " + ", ".join(intruders)))
	quit(0 if intruders.is_empty() else 1)
	return true


func _triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		if index != null and (index as PackedInt32Array).size() > 0:
			total += (index as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total
