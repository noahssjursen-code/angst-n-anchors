extends SceneTree

## SCRATCH PROBE — leading underscore, never a gate unit. Pass 2.

func _initialize() -> void:
	_concave_plumb()
	_refused_corners()
	_strake_on_tumblehome()
	quit(0)


func _edges(p: Dictionary) -> Dictionary:
	var res := PieceKit.resolve_placement(p, 1)
	var items := res["items"] as Array
	if items.is_empty():
		return {"out": [Vector3.INF, Vector3.INF], "in": [Vector3.INF, Vector3.INF]}
	var of := Vector3.INF
	var oh := Vector3.INF
	var if_ := Vector3.INF
	var ih := Vector3.INF
	for step in items.size():
		var c := PieceKit.placed_corners(p, step)
		if c.size() != 4:
			continue
		if of == Vector3.INF or c[0].y < of.y: of = c[0]
		if oh == Vector3.INF or c[3].y > oh.y: oh = c[3]
		if if_ == Vector3.INF or c[1].y < if_.y: if_ = c[1]
		if ih == Vector3.INF or c[2].y > ih.y: ih = c[2]
	return {"out": [of, oh], "in": [if_, ih]}


func _wall(cx: int, cy: int, cz: int, f: int, span: int, rake: int, h := 5) -> Dictionary:
	return {"id": "w", "piece": "wall_panel", "cell": [cx, cy, cz], "facing": f,
		"params": {"span": span, "height": h, "rake": rake}}


func _corner(cx: int, cy: int, cz: int, f: int, span: int, ra: int, rb: int, h := 5) -> Dictionary:
	return {"id": "c", "piece": "corner_45", "cell": [cx, cy, cz], "facing": f,
		"params": {"span": span, "height": h, "rake_a": ra, "rake_b": rb}}


func _pair_gap(a: Array, b: Array) -> float:
	if a[0] == Vector3.INF or b[0] == Vector3.INF:
		return INF
	return a[0].distance_to(b[0]) + a[1].distance_to(b[1])


func _concave_plumb() -> void:
	print("\n=== 6. THE CONCAVE CORNER AT EVERY RAKE PAIR, SEARCHED OVER EVERY LEGAL FILLER ===")
	print("  incoming wall on x=12 running +z (facing 270), outgoing on z=46 running +x (facing 0).")
	print("  For each pair of wall rakes, every corner_45 in a 9x9 cell neighbourhood, at all")
	print("  four facings, all four spans and all 81 rake pairs, is tried and the best kept.")
	for ri in [-1, 0, 2]:
		var line := "    incoming rake %+d:" % ri
		for ro in [0, 2]:
			var incoming := _wall(12, 0, 43, 270, 2, ri)
			var outgoing := _wall(13, 0, 46, 0, 3, ro)
			var need_in: Array = _edges(incoming)["out"]
			var need_out: Array = _edges(outgoing)["in"]
			var best := INF
			var best_desc := ""
			for f in [0, 90, 180, 270]:
				for span in [1, 2]:
					for dx in range(-2, 3):
						for dz in range(-2, 3):
							for ra in range(-4, 5):
								for rb in range(-4, 5):
									var e := _edges(_corner(12 + dx, 0, 46 + dz, f, span, ra, rb))
									var t := _pair_gap(e["in"], need_in) + _pair_gap(e["out"], need_out)
									if t < best:
										best = t
										best_desc = "cell(%d,%d) f%d span%d ra%+d rb%+d" % [12 + dx, 46 + dz, f, span, ra, rb]
			line += "  outgoing %+d -> %.4f m (%s)" % [ro, best, best_desc]
		print(line)


func _refused_corners() -> void:
	print("\n=== 8. WHICH corner_45 SETTINGS THE BAKER REFUSES ===")
	var count := 0
	var total := 0
	var shown := 0
	for span in [1, 2, 3, 4]:
		for h in [2, 3, 4, 5, 6]:
			for ra in range(-4, 5):
				for rb in range(-4, 5):
					total += 1
					var r := PieceKit.resolve("corner_45",
						{"span": span, "height": h, "rake_a": ra, "rake_b": rb})
					if not (r["specs"] as Array).is_empty():
						continue
					count += 1
					if shown < 8:
						shown += 1
						print("    span %d height %d rake_a %+d rake_b %+d: %s"
							% [span, h, ra, rb, ", ".join(r["errors"] as PackedStringArray)])
	print("    %d of %d settings refused." % [count, total])
	print("    corner_45 declares NO `constraints` block, so none of these is refused in the")
	print("    piece's own words — they surface as StructureBaker's degeneracy message.")


func _strake_on_tumblehome() -> void:
	print("\n=== 9. A RUBBING STRAKE ON A WALL THAT TUMBLES HOME ===")
	print("  wall_panel is 0.10 m thick, so its OUTBOARD face sits 0.05 m outboard of the")
	print("  plate centreline. The strake is 0.09 m thick at z = -0.05 - offset*0.25, so its")
	print("  INBOARD face sits at -0.005 - offset*0.25. offset takes 0..4 and only pushes")
	print("  OUTBOARD (-z). A wall with a NEGATIVE rake leans INBOARD (+z).")
	for rake in [-4, -2, -1, 0, 1, 2, 4]:
		var w := PieceKit.resolve("wall_panel", {"span": 4, "height": 5, "rake": rake})
		var wc := (w["specs"][0] as Dictionary)["corners"] as PackedVector3Array
		var row := "    rake %+d:" % rake
		for y_cell in [1, 2, 4]:
			var y := float(y_cell) * 0.5
			var face_z: float = wc[2].z * (y / 2.5) - 0.05   # outboard face of the plating
			var best := INF
			var best_off := -1
			for off in [0, 1, 2, 3, 4]:
				var inboard: float = -0.005 - float(off) * 0.25
				var clear: float = face_z - inboard
				if absf(clear) < absf(best):
					best = clear
					best_off = off
			row += "  at %.1f m: offset %d leaves %+.3f m" % [y, best_off, best]
		print(row)
	print("  positive = daylight between the strake and the plating; negative = buried in it.")
