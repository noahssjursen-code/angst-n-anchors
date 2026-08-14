extends SceneTree

## SCRATCH PROBE (leading underscore). The focused table behind _critic_kit_sweep:
## what the baker actually cuts for the PLAINEST legal picks — rake 0, fall 0,
## head 0, lift 0 — and then rake alone at the kit's default height.


func _init() -> void:
	PieceKit.ensure_loaded()
	print("\n=== A. opening x height, everything else at its default/zero ===")
	print("%-8s %-6s %-8s | %-9s %-9s %-9s | %-8s %s"
		% ["opening", "span", "height_m", "asked_w", "cut_w", "cut_h", "head_m", "verdict"])
	for opening in ["door", "window", "scuttle"]:
		for span in [1, 2, 3, 4]:
			for height in [2, 3, 4, 5]:
				_row(opening, span, height, 0, 0)
	print("\n=== B. rake alone: span 4, height 5 (2.50 m), a door ===")
	print("%-6s %-9s %-9s %-9s %s" % ["rake", "rake_m", "slant_m", "head_m", "verdict"])
	for rake in [0, 2, 4, 5, 6, 7, 8, -8]:
		_rake_row(span_default(), 5, rake)
	print("\n=== C. head/fall trims at height 4 (2.00 m), a door ===")
	for combo in [[4, 0, 0], [4, 0, 1], [4, 0, 2], [4, 1, 0], [4, 4, 0], [3, 7, 0]]:
		_trim_row(int(combo[0]), int(combo[1]), int(combo[2]))
	quit()


func span_default() -> int:
	return 4


func _resolve(given: Dictionary) -> Dictionary:
	var res := PieceKit.resolve("wall_panel", given)
	if (res["errors"] as PackedStringArray).size() > 0:
		return {}
	var spec := (res["specs"] as Array)[0] as Dictionary
	var probe: Dictionary = {
		"corners": _corner_array(spec["corners"] as PackedVector3Array),
		"thickness": float(spec["thickness"]),
	}
	if spec.has("openings"):
		probe["openings"] = spec["openings"]
	return probe


func _corner_array(corners: PackedVector3Array) -> Array:
	var out: Array = []
	for c in corners:
		out.append([c.x, c.y, c.z])
	return out


func _row(opening: String, span: int, height: int, rake: int, fall: int) -> void:
	var given := {"span": span, "height": height, "rake": rake, "fall": fall, "opening": opening}
	var res := PieceKit.resolve("wall_panel", given)
	if (res["errors"] as PackedStringArray).size() > 0:
		print("%-8s %-6d %-8.2f | REFUSED" % [opening, span, height * 0.5])
		return
	var probe := _resolve(given)
	var corners := StructureBaker.plate_corners(probe)
	var ref := StructureBaker.plate_ref_lengths(corners)
	var asked := (probe["openings"] as Array)[0] as Dictionary
	var cut := StructureBaker.plate_openings(probe, ref)
	if cut.is_empty():
		print("%-8s %-6d %-8.2f | HOLE VANISHED" % [opening, span, height * 0.5])
		return
	var c := cut[0] as Dictionary
	var v := (float(c["sill"]) + float(c["h"])) / ref.y
	var u := (float(c["off"]) + float(c["w"]) * 0.5) / ref.x
	var head := StructureBaker.plate_point(corners, u, v).y \
		- StructureBaker.plate_point(corners, u, 0.0).y
	var verdict := "ok"
	if absf(float(asked["height"]) - float(c["h"])) > 1e-6 \
			or absf(float(asked["sill"]) - float(c["sill"])) > 1e-6 \
			or absf(float(asked["width"]) - float(c["w"])) > 1e-6:
		verdict = "CLAMPED"
	if opening == "door" and head < 1.85:
		verdict += " HEAD<1.85"
	var frames := StructureBaker.plate_frames(probe).size()
	var want := 4 if float(c["sill"]) > 0.05 else 3
	if frames != want:
		verdict += " CASING %d/%d" % [frames, want]
	print("%-8s %-6d %-8.2f | %-9.3f %-9.3f %-9.3f | %-8.3f %s"
		% [opening, span, height * 0.5, float(asked["width"]), float(c["w"]), float(c["h"]),
		   head, verdict])


func _rake_row(span: int, height: int, rake: int) -> void:
	var given := {"span": span, "height": height, "rake": rake, "opening": "door"}
	var res := PieceKit.resolve("wall_panel", given)
	if (res["errors"] as PackedStringArray).size() > 0:
		print("%-6d REFUSED" % rake)
		return
	var probe := _resolve(given)
	var corners := StructureBaker.plate_corners(probe)
	var ref := StructureBaker.plate_ref_lengths(corners)
	var cut := (StructureBaker.plate_openings(probe, ref)[0]) as Dictionary
	var v := (float(cut["sill"]) + float(cut["h"])) / ref.y
	var u := (float(cut["off"]) + float(cut["w"]) * 0.5) / ref.x
	var head := StructureBaker.plate_point(corners, u, v).y \
		- StructureBaker.plate_point(corners, u, 0.0).y
	print("%-6d %-9.3f %-9.4f %-9.4f %s"
		% [rake, rake * 0.125, ref.y, head, "HEAD < 1.85 m" if head < 1.85 else "ok"])


func _trim_row(height: int, head_cells: int, fall: int) -> void:
	var given := {"span": 4, "height": height, "head": head_cells, "fall": fall, "opening": "door"}
	var res := PieceKit.resolve("wall_panel", given)
	if (res["errors"] as PackedStringArray).size() > 0:
		print("height %d head %d fall %d: REFUSED" % [height, head_cells, fall])
		return
	var probe := _resolve(given)
	var corners := StructureBaker.plate_corners(probe)
	var ref := StructureBaker.plate_ref_lengths(corners)
	var cut := (StructureBaker.plate_openings(probe, ref)[0]) as Dictionary
	var v := (float(cut["sill"]) + float(cut["h"])) / ref.y
	var u := (float(cut["off"]) + float(cut["w"]) * 0.5) / ref.x
	var head := StructureBaker.plate_point(corners, u, v).y \
		- StructureBaker.plate_point(corners, u, 0.0).y
	print("height %d (%.2f m) head %d fall %d -> wall %.3f m, hole %.3f m tall, head %.3f m %s"
		% [height, height * 0.5, head_cells, fall, ref.y, float(cut["h"]), head,
		   "<<< CLAMPED" if absf(float(cut["h"]) - 1.95) > 1e-6 else ""])
