extends SceneTree

## Scratch probe (leading underscore — NOT a gate unit). Lane A.
##
## Measures what the shape bricks a raked deckhouse needs ACTUALLY DRAW, at each
## yaw, from the MESH VERTICES — not the AABB. The first version of this probe
## reported the AABB and every wedge came back as a perfect cube at every yaw,
## which is true and useless: a wedge and the cube it was cut from share a
## bounding box. That is REALITY §4's blind check in miniature, caught because
## the answer was obviously wrong rather than because anything failed.
##
## Same method as `_railing_yaw_probe.gd`, and for the same reason: the railing
## runs on all four presets pointed athwartships for weeks because everyone
## derived the yaw from the rotation convention instead of measuring it.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --script res://tests/_wedge_yaw_probe.gd

const SUBJECTS := [
	"block", "block_45", "block_window", "block_windshield",
	"block_door", "block_door_double",
	"ledge_45", "ledge_45_corner", "roof_flat", "roof_slope", "roof_corner",
]


func _initialize() -> void:
	for brick_id in SUBJECTS:
		if not BrickCatalog.has(brick_id):
			print("%-22s MISSING FROM CATALOGUE" % brick_id)
			continue
		var fp := BrickCatalog.footprint_of(brick_id)
		var sz := BrickCatalog.size_m(brick_id)
		print("\n%-22s footprint=%dx%dx%d  size_m=(%.3f, %.3f, %.3f)  tags=%s" % [
			brick_id, fp.x, fp.y, fp.z, sz.x, sz.y, sz.z,
			str(BrickCatalog.get_entry(brick_id).get("tags", [])),
		])
		var yaws := [0, 90, 180, 270] if BrickCatalog.has_tag(brick_id, "slope") \
			or BrickCatalog.has_tag(brick_id, "diagonal_plan") else [0]
		for yaw in yaws:
			var root := BrickCatalog.create_visual(brick_id, {})
			if root == null:
				print("    yaw %3d  NO VISUAL" % yaw)
				continue
			var verts := _verts(root, Transform3D())
			root.free()
			if verts.is_empty():
				print("    yaw %3d  NO VERTICES" % yaw)
				continue
			var basis := Basis(Vector3.UP, deg_to_rad(float(yaw)))
			var rotated: Array[Vector3] = []
			for v in verts:
				rotated.append(basis * v)
			var extra := ""
			if BrickCatalog.has_tag(brick_id, "diagonal_plan"):
				## A plan chamfer is CONSTANT with height, so the bot/top slices
				## above are identical for every yaw and see nothing. Report the
				## missing plan corner directly instead. (Found by reading an
				## obviously-wrong result, not by a failing check — REALITY §8.)
				extra = "  " + _missing_plan_corner(rotated, sz)
			print("    yaw %3d  %s%s" % [yaw, _slice_report(rotated, sz.y), extra])
	quit(0)


## The solid's plan footprint at the BOTTOM, MIDDLE and TOP of the cell. This is
## the property that matters for authoring: which way a wedge leans, and where a
## chamfer opens.
func _slice_report(verts: Array[Vector3], height: float) -> String:
	var y_lo: float = verts[0].y
	var y_hi: float = verts[0].y
	for v in verts:
		y_lo = minf(y_lo, v.y)
		y_hi = maxf(y_hi, v.y)
	var parts := PackedStringArray()
	for label in ["bot", "top"]:
		var y := y_lo if label == "bot" else y_hi
		var band := maxf(height * 0.02, 0.005)
		var x_lo := INF
		var x_hi := -INF
		var z_lo := INF
		var z_hi := -INF
		for v in verts:
			if absf(v.y - y) <= band:
				x_lo = minf(x_lo, v.x)
				x_hi = maxf(x_hi, v.x)
				z_lo = minf(z_lo, v.z)
				z_hi = maxf(z_hi, v.z)
		if x_lo == INF:
			parts.append("%s: none" % label)
			continue
		parts.append("%s x[%+.2f %+.2f] z[%+.2f %+.2f]" % [label, x_lo, x_hi, z_lo, z_hi])
	return "  ".join(parts)


func _verts(node: Node, xf: Transform3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
					continue
				for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					out.append(local * v)
	for child in node.get_children():
		out.append_array(_verts(child, local))
	return out


## Which of the four plan corners of the cell the solid does NOT reach.
func _missing_plan_corner(verts: Array[Vector3], sz: Vector3) -> String:
	var names := {
		Vector2(-1.0, -1.0): "(-X,-Z) port-fwd",
		Vector2(1.0, -1.0): "(+X,-Z) stbd-fwd",
		Vector2(1.0, 1.0): "(+X,+Z) stbd-aft",
		Vector2(-1.0, 1.0): "(-X,+Z) port-aft",
	}
	var missing := PackedStringArray()
	for key in names:
		var corner: Vector2 = key
		var target := Vector2(corner.x * sz.x * 0.5, corner.y * sz.z * 0.5)
		var found := false
		for v in verts:
			if Vector2(v.x, v.z).distance_to(target) <= 0.02:
				found = true
				break
		if not found:
			missing.append(str(names[key]))
	if missing.is_empty():
		return "plan: full cell"
	return "plan: MISSING " + ", ".join(missing)
