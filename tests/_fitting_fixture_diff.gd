extends SceneTree

## SCRATCH PROBE (leading underscore — the gate must not discover it).
##
## Characterises what every shipped structure fixture BAKES, so a geometry
## change can be diffed rather than asserted about: per fixture, mesh instances,
## drawn vertices, triangles, collider boxes and the bake AABB.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_fitting_fixture_diff.gd
##
## Run it against a `git archive HEAD` copy for the BEFORE column.

const STRUCTURES := "res://resources/data/structures/"


func _init() -> void:
	var dir := DirAccess.open(STRUCTURES)
	if dir == null:
		printerr("[fixdiff] cannot open %s" % STRUCTURES)
		quit(1)
		return
	var names := PackedStringArray()
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	var total_v := 0
	var total_t := 0
	var total_c := 0
	var total_e := 0
	print("[fixdiff] %-34s %6s %8s %8s %7s  %s"
		% ["fixture", "meshes", "verts", "tris", "collide", "bake AABB"])
	for f in names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRUCTURES + f))
		if not (parsed is Dictionary):
			continue
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		var node := StructureBaker.bake(plan)
		var census := _census(node)
		var box := _aabb(node)
		node.free()
		var colliders := StructureBaker.collect_colliders(plan).size()
		total_v += int(census["verts"])
		total_t += int(census["tris"])
		total_c += colliders
		total_e += plan.entity_count()
		print("[fixdiff] %-34s %6d %8d %8d %7d  pos %s size %s"
			% [f, int(census["meshes"]), int(census["verts"]), int(census["tris"]),
				colliders, _s(box.position), _s(box.size)])
	print("[fixdiff] TOTAL %d fixtures  %d entities  %d verts  %d tris  %d colliders"
		% [names.size(), total_e, total_v, total_t, total_c])
	quit(0)


func _s(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _census(node: Node) -> Dictionary:
	var meshes := 0
	var verts := 0
	var tris := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			meshes += 1
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var raw: Variant = arrays[Mesh.ARRAY_VERTEX]
				if raw is PackedVector3Array:
					verts += (raw as PackedVector3Array).size()
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
					tris += (idx as PackedInt32Array).size() / 3
				elif raw is PackedVector3Array:
					tris += (raw as PackedVector3Array).size() / 3
	for child in node.get_children():
		var sub := _census(child)
		meshes += int(sub["meshes"])
		verts += int(sub["verts"])
		tris += int(sub["tris"])
	return {"meshes": meshes, "verts": verts, "tris": tris}


func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local := (n as MeshInstance3D).mesh.get_aabb()
			box = local if first else box.merge(local)
			first = false
		for child in n.get_children():
			stack.append(child)
	return box
