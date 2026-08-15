extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## `_collider_build_probe` established that BOTH halves are quadratic. This one
## asks WHICH OPERATION is quadratic, by holding the box count fixed and varying
## one thing at a time. Every variant ends with N boxes' worth of collision on a
## body in an active space, so the totals are comparable.
##
##   srv_space    body in a space, N box_shape_create + body_add_shape. baseline.
##   srv_nospace  same, but the body is put in the space AFTER all N adds.
##   srv_sharerid ONE box_shape_create, that RID added N times, body in space.
##   srv_trimesh  ONE concave_polygon_shape_create holding N boxes of triangles.
##   node_intree  N CollisionShape3D added to a body already in the tree. prod.
##   node_offtree N CollisionShape3D added to a body OUTSIDE the tree, then the
##                body is added to the tree (the add_child is inside the timer).
##   node_trimesh ONE CollisionShape3D holding a ConcavePolygonShape3D of N boxes.
##
## If srv_nospace is linear and srv_space is not, the cost is Jolt rebuilding the
## body's compound shape on every add and the fix is to batch. If srv_sharerid is
## linear, the cost is shape CREATION and the fix is RID reuse. If neither, the
## per-shape add itself is quadratic and only fewer shapes will do.

const COUNTS := [500, 2000, 4000, 8000]

var _rows: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for count_variant in COUNTS:
		var n := int(count_variant)
		var row := {
			"n": n,
			"srv_space": _srv(n, true, false),
			"srv_nospace": _srv(n, false, false),
			"srv_sharerid": _srv(n, true, true),
			"srv_trimesh": _srv_trimesh(n),
			"node_intree": _nodes(n, true),
			"node_offtree": _nodes(n, false),
			"node_trimesh": _node_trimesh(n),
		}
		_rows.append(row)
	var cols := ["srv_space", "srv_nospace", "srv_sharerid", "srv_trimesh",
		"node_intree", "node_offtree", "node_trimesh"]
	var head := "%8s" % "boxes"
	for c in cols:
		head += "%14s" % c
	print(head)
	for row_variant in _rows:
		var row := row_variant as Dictionary
		var line := "%8d" % int(row["n"])
		for c in cols:
			line += "%14.1f" % float(row[c])
		print(line)
	print("")
	print("scaling 500 -> 8000 (16x boxes; 16.0 == linear, 256.0 == quadratic)")
	var first := _rows[0] as Dictionary
	var last := _rows[_rows.size() - 1] as Dictionary
	for c in cols:
		var a := float(first[c])
		var b := float(last[c])
		print("  %-14s %8.1f ms -> %8.1f ms   x%.1f" % [c, a, b, b / maxf(a, 0.001)])
	quit()


func _box_center(i: int) -> Vector3:
	return Vector3(float(i % 40) * 0.5, float(i / 40) * 0.3, 0.0)


func _srv(count: int, space_first: bool, share_rid: bool) -> float:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	var made: Array[RID] = []
	if space_first:
		PhysicsServer3D.body_set_space(body, space)
	var t0 := Time.get_ticks_usec()
	var shared := RID()
	if share_rid:
		shared = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shared, Vector3(0.2, 0.15, 0.05))
		made.append(shared)
	for i in count:
		var shape := shared
		if not share_rid:
			shape = PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_data(shape, Vector3(0.2, 0.15, 0.05))
			made.append(shape)
		PhysicsServer3D.body_add_shape(body, shape, Transform3D(
			Basis(Vector3.UP, deg_to_rad(17.0)), _box_center(i)))
	if not space_first:
		PhysicsServer3D.body_set_space(body, space)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	PhysicsServer3D.free_rid(body)
	for rid in made:
		PhysicsServer3D.free_rid(rid)
	PhysicsServer3D.free_rid(space)
	return ms


func _srv_trimesh(count: int) -> float:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	var t0 := Time.get_ticks_usec()
	var faces := PackedVector3Array()
	faces.resize(count * 36)
	var w := 0
	for i in count:
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(17.0)), _box_center(i))
		for v in _box_triangles(Vector3(0.4, 0.3, 0.1)):
			faces[w] = xf * v
			w += 1
	var shape := PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"faces": faces, "backface_collision": false})
	PhysicsServer3D.body_add_shape(body, shape, Transform3D.IDENTITY)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	return ms


func _nodes(count: int, in_tree_first: bool) -> float:
	var body := StaticBody3D.new()
	if in_tree_first:
		root.add_child(body)
	var t0 := Time.get_ticks_usec()
	for i in count:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.4, 0.3, 0.1)
		cs.shape = shape
		cs.position = _box_center(i)
		cs.rotation_degrees = Vector3(0.0, 17.0, 0.0)
		cs.name = "BrickCol_plan_%d" % i
		body.add_child(cs)
	if not in_tree_first:
		root.add_child(body)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	body.free()
	return ms


func _node_trimesh(count: int) -> float:
	var body := StaticBody3D.new()
	root.add_child(body)
	var t0 := Time.get_ticks_usec()
	var faces := PackedVector3Array()
	faces.resize(count * 36)
	var w := 0
	for i in count:
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(17.0)), _box_center(i))
		for v in _box_triangles(Vector3(0.4, 0.3, 0.1)):
			faces[w] = xf * v
			w += 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	body.free()
	return ms


## 12 triangles, 36 verts, in the box's own frame.
func _box_triangles(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var quads := [
		[0, 1, 2, 3], [7, 6, 5, 4], [4, 5, 1, 0],
		[6, 7, 3, 2], [5, 6, 2, 1], [7, 4, 0, 3],
	]
	var out := PackedVector3Array()
	for q_variant in quads:
		var q := q_variant as Array
		out.append(c[int(q[0])])
		out.append(c[int(q[1])])
		out.append(c[int(q[2])])
		out.append(c[int(q[0])])
		out.append(c[int(q[2])])
		out.append(c[int(q[3])])
	return out
