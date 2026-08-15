extends SceneTree

## SCRATCH PROBE. Why does the container feeder's free-fall lifeboat report a
## 0.955 m phantom on BOTH the old grid and the new dicer, when its own off-axis
## excursion says one box would do?

func _initialize() -> void:
	var corners := PackedVector3Array([
		Vector3(13.5, 7.1, 142.9), Vector3(18.5, 7.1, 142.9),
		Vector3(18.5, 3.5, 149.1), Vector3(13.5, 3.5, 149.1),
	])
	var spec := {"corners": [
		[13.5, 7.1, 142.9], [18.5, 7.1, 142.9], [18.5, 3.5, 149.1], [13.5, 3.5, 149.1],
	], "thickness": 2.2}
	var boxes := StructureBaker.plate_colliders(spec, corners, Vector3.ZERO)
	print("boxes: %d" % boxes.size())
	var n := StructureBaker.plate_normal(corners)
	print("normal %s  yaw of the quad %.3f" % [str(n), StructureBaker._plate_yaw(corners)])
	var worst := 0.0
	var worst_corner := Vector3.ZERO
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var basis := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"])))
		var half := (box["size"] as Vector3) * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := (box["center"] as Vector3) + basis * Vector3(
						half.x * float(sx), half.y * float(sy), half.z * float(sz))
					var d := _phantom(corners, 2.2, p)
					if d > worst:
						worst = d
						worst_corner = p
	print("worst phantom %.4f at %s" % [worst, str(worst_corner)])
	print("first box size %s centre %s yaw %.2f" % [
		str((boxes[0] as Dictionary)["size"]), str((boxes[0] as Dictionary)["center"]),
		float((boxes[0] as Dictionary)["yaw_deg"])])
	## What the nearest-point search says about a point that is definitely ON the
	## surface — the instrument's own control.
	var on := StructureBaker.plate_point(corners, 0.3, 0.7)
	print("control: a point on the mid-surface reports %.6f" % _phantom(corners, 2.2, on))
	var out := on + n * 1.1
	print("control: a point on the skin reports %.6f" % _phantom(corners, 2.2, out))
	var far := on + n * 1.6
	print("control: 0.5 m past the skin reports %.6f" % _phantom(corners, 2.2, far))
	quit()


func _phantom(quad: PackedVector3Array, thickness: float, p: Vector3) -> float:
	var u := 0.5
	var v := 0.5
	for _pass in 8:
		u = clampf(_project(StructureBaker.plate_point(quad, 0.0, v),
			StructureBaker.plate_point(quad, 1.0, v), p), 0.0, 1.0)
		v = clampf(_project(StructureBaker.plate_point(quad, u, 0.0),
			StructureBaker.plate_point(quad, u, 1.0), p), 0.0, 1.0)
	var near := StructureBaker.plate_point(quad, u, v)
	var n := StructureBaker.plate_normal(quad)
	var d := p - near
	var along := d.dot(n)
	var across := (d - n * along).length()
	var o := maxf(absf(along) - thickness * 0.5, 0.0)
	return sqrt(o * o + across * across)


func _project(a: Vector3, b: Vector3, p: Vector3) -> float:
	var run := b - a
	var len2 := run.length_squared()
	return 0.5 if len2 < 1e-12 else (p - a).dot(run) / len2
