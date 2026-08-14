extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
## Walks the DECLARED value sets of wall_panel and asks, for every combination
## the kit ACCEPTS, what the baker actually cuts. Three questions:
##
##   1. Does StructureBaker.plate_openings CLAMP the hole the kit asked for?
##      The kit's `constraints` claim to prevent exactly that ("the baker CLAMPS
##      the opening to what fits ... a kit whose pieces quietly change size is
##      worse than one that refuses"), but the constraint only relates the
##      opening to `span`.
##   2. Does any casing member get dropped by the MIN_PANEL guard?
##   3. What is the VERTICAL clearance of the resulting doorway, in plan metres,
##      against the 1.8 m figure + the test's own 0.05 m head margin?


func _init() -> void:
	PieceKit.ensure_loaded()
	var errs := PieceKit.load_errors()
	print("kit load errors: %d" % errs.size())
	for e in errs:
		print("  ! %s" % e)
	_sweep_wall_panel()
	_sweep_glazed()
	quit()


func _door_report(given: Dictionary) -> Dictionary:
	var res := PieceKit.resolve("wall_panel", given)
	var errors := res["errors"] as PackedStringArray
	if errors.size() > 0:
		return {"legal": false, "why": ", ".join(errors)}
	var specs := res["specs"] as Array
	var spec := specs[0] as Dictionary
	var probe: Dictionary = {
		"corners": _corner_array(spec["corners"] as PackedVector3Array),
		"thickness": float(spec["thickness"]),
	}
	if spec.has("openings"):
		probe["openings"] = spec["openings"]
	var corners := StructureBaker.plate_corners(probe)
	var ref := StructureBaker.plate_ref_lengths(corners)
	var authored: Array = spec.get("openings", [])
	var cut := StructureBaker.plate_openings(probe, ref)
	var frames := StructureBaker.plate_frames(probe)
	var out: Dictionary = {
		"legal": true, "ref": ref, "cut": cut, "frames": frames.size(),
		"authored": authored, "corners": corners,
	}
	if cut.is_empty():
		out["clamped"] = not authored.is_empty()
		return out
	var a := authored[0] as Dictionary
	var c := cut[0] as Dictionary
	out["clamped"] = (
		absf(float(a["width"]) - float(c["w"])) > 1e-6
		or absf(float(a["height"]) - float(c["h"])) > 1e-6
		or absf(float(a["sill"]) - float(c["sill"])) > 1e-6
		or absf(float(a["offset"]) - float(c["off"])) > 1e-6
	)
	## Vertical clearance: plan y of the head over plan y of the foot, at the
	## door's own centre line.
	var v_head := (float(c["sill"]) + float(c["h"])) / ref.y
	var u_mid := (float(c["off"]) + float(c["w"]) * 0.5) / ref.x
	var head_y := StructureBaker.plate_point(corners, u_mid, v_head).y
	var foot_y := StructureBaker.plate_point(corners, u_mid, 0.0).y
	out["head"] = head_y - foot_y
	out["expected_frames"] = 4 if float(c["sill"]) > 0.05 else 3
	return out


func _corner_array(corners: PackedVector3Array) -> Array:
	var out: Array = []
	for c in corners:
		out.append([c.x, c.y, c.z])
	return out


func _sweep_wall_panel() -> void:
	var params := PieceKit.params_of("wall_panel")
	var spans: Array = (params["span"] as Dictionary)["values"]
	var heights: Array = (params["height"] as Dictionary)["values"]
	var heads: Array = (params["head"] as Dictionary)["values"]
	var rakes: Array = (params["rake"] as Dictionary)["values"]
	var falls: Array = (params["fall"] as Dictionary)["values"]
	var openings: Array = (params["opening"] as Dictionary)["values"]
	var legal := 0
	var refused := 0
	var clamped: Array = []
	var dropped: Array = []
	var low: Array = []
	for span in spans:
		for opening in openings:
			if str(opening) == "none":
				continue
			for height in heights:
				for head in heads:
					for rake in rakes:
						for fall in falls:
							var given := {
								"span": span, "height": height, "head": head,
								"rake": rake, "fall": fall, "opening": opening,
							}
							var r := _door_report(given)
							if not bool(r["legal"]):
								refused += 1
								continue
							legal += 1
							if bool(r.get("clamped", false)):
								clamped.append(given)
							if int(r.get("frames", 0)) != int(r.get("expected_frames", 0)):
								dropped.append([given, r["frames"], r["expected_frames"]])
							if str(opening) == "door" and float(r.get("head", 9.0)) < 1.85:
								low.append([given, float(r["head"])])
	print("\n== wall_panel with an opening ==")
	print("legal combinations: %d   refused by constraints: %d" % [legal, refused])
	print("openings the BAKER CLAMPED (kit said it would refuse these): %d" % clamped.size())
	_print_some(clamped, 8)
	print("casing members dropped by MIN_PANEL: %d" % dropped.size())
	_print_some(dropped, 8)
	print("DOORS under 1.85 m of vertical clearance (the test's own bar): %d" % low.size())
	_print_some(low, 10)
	if not low.is_empty():
		var worst: Array = low[0]
		for entry_variant in low:
			var entry: Array = entry_variant
			if float(entry[1]) < float(worst[1]):
				worst = entry
		print("worst: %s -> %.4f m of head" % [str(worst[0]), float(worst[1])])
	## The narrowest legal door, measured rather than argued.
	for span in spans:
		var r := _door_report({"span": span, "opening": "door"})
		if not bool(r["legal"]):
			print("span %s + door: REFUSED — %s" % [str(span), str(r["why"])])
			continue
		var c := (r["cut"] as Array)[0] as Dictionary
		var ref := r["ref"] as Vector2
		print("span %s + door: panel %.3f m, hole %.3f m at offset %.3f, plating %.3f/%.3f m"
			% [str(span), ref.x, float(c["w"]), float(c["off"]), float(c["off"]),
			   ref.x - float(c["off"]) - float(c["w"])])


func _sweep_glazed() -> void:
	var params := PieceKit.params_of("wall_glazed")
	var refused := 0
	var legal := 0
	var thin: Array = []
	for height in (params["height"] as Dictionary)["values"]:
		for sill in (params["sill"] as Dictionary)["values"]:
			for band in (params["band"] as Dictionary)["values"]:
				for head in (params["head"] as Dictionary)["values"]:
					for fall in (params["fall"] as Dictionary)["values"]:
						var given := {
							"height": height, "sill": sill, "band": band,
							"head": head, "fall": fall,
						}
						var res := PieceKit.resolve("wall_glazed", given)
						if (res["errors"] as PackedStringArray).size() > 0:
							refused += 1
							continue
						legal += 1
						## The pane's own height band — the thing
						## piece_interior_test refuses to sweep under 0.45 m.
						var specs := res["specs"] as Array
						var glass := (specs[1] as Dictionary)["corners"] as PackedVector3Array
						var lo := glass[0].y
						var hi := glass[0].y
						for c in glass:
							lo = minf(lo, c.y)
							hi = maxf(hi, c.y)
						if hi - lo < 0.45:
							thin.append([given, hi - lo])
	print("\n== wall_glazed ==")
	print("legal: %d   refused: %d" % [legal, refused])
	print("panes under the sweep's own 0.45 m floor (silently unswept): %d" % thin.size())
	_print_some(thin, 8)


func _print_some(list: Array, n: int) -> void:
	for i in mini(n, list.size()):
		print("   %s" % str(list[i]))
	if list.size() > n:
		print("   ... and %d more" % (list.size() - n))
