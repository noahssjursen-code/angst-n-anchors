extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
## Walks the wall_panel cross product through the REAL path — PieceKit.resolve()
## then StructureBaker.plate_openings/plate_frames on the resolved spec — and
## reports, per opening choice:
##   accepted, clamped (the baker cut the hole the piece asked for), casing
##   members lost or trimmed, and for doors the DRAWN vertical head above the
##   panel's own foot.
## `lift` is excluded from the sweep and checked separately: it is a pure
## translation of every corner, so it cannot change a ref length or an opening.
##
## WHAT IT MEASURED, before and after the door rule landed. Basis: span(6) x
## height(5) x head(8) x rake(17) x fall(9), lift fixed, per opening choice.
##
##                     accepted   clamped        casing short   worst door head
##   before  door        24 480     6 432 (26%)         7 336     0.549 m
##           window      30 600     7 370 (24%)         8 560
##           scuttle     36 720     5 940 (16%)        12 020
##           ALL HOLES   91 800    19 742 (21.5%)      27 916
##
##   after   door         7 208         0               0        2.100 m
##           window      22 040         0               0
##           scuttle     29 640         0            4 940
##           ALL HOLES   58 888         0 (0.0%)        4 940
##
## The 19 742 reproduces an adversarial critic's figure exactly. The 4 940 that
## remain are all one shape and none of them is a MISSING member: a 0.40 m
## scuttle in a 0.50 m panel leaves 0.05 m of plating, so its 0.09 m outer jamb
## is clipped to 0.06 m at both sides, symmetrically. That is a `span` claim, and
## `span-1` for a scuttle is the constraint that would have to change.

const SPANS := [1, 2, 3, 4, 6, 8]
const HEIGHTS := [2, 3, 4, 5, 6]
const HEADS := [0, 1, 2, 3, 4, 5, 6, 7]
const RAKES := [-8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8]
const FALLS := [-4, -3, -2, -1, 0, 1, 2, 3, 4]
const OPENINGS := ["none", "door", "window", "scuttle"]


func _init() -> void:
	PieceKit.ensure_loaded()
	print("kit errors: %s" % str(PieceKit.load_errors()))
	_lift_is_translation()
	var totals := {}
	for opening in OPENINGS:
		totals[opening] = _sweep(opening)
	var all_accepted := 0
	var all_clamped := 0
	var all_casing := 0
	for opening in OPENINGS:
		var row := totals[opening] as Dictionary
		all_accepted += int(row["accepted"])
		all_clamped += int(row["clamped"])
		all_casing += int(row["casing"])
		print("%-8s tried %6d accepted %6d  clamped %6d (%.1f%%)  casing short %6d (%.1f%%)"
			% [opening, int(row["tried"]), int(row["accepted"]), int(row["clamped"]),
			   100.0 * float(row["clamped"]) / maxf(1.0, float(row["accepted"])),
			   int(row["casing"]),
			   100.0 * float(row["casing"]) / maxf(1.0, float(row["accepted"]))])
	print("TOTAL accepted %d  clamped %d (%.1f%%)  casing short %d (%.1f%%)"
		% [all_accepted, all_clamped, 100.0 * float(all_clamped) / maxf(1.0, float(all_accepted)),
		   all_casing, 100.0 * float(all_casing) / maxf(1.0, float(all_accepted))])
	if OS.get_environment("DOOR_HEADS") != "":
		_door_heads()
	quit()


func _lift_is_translation() -> void:
	var worst := 0.0
	for lift in [-4, 0, 3]:
		var a := _corners({"span": 4, "height": 5, "rake": 3, "fall": 0, "opening": "door", "lift": 0})
		var b := _corners({"span": 4, "height": 5, "rake": 3, "fall": 0, "opening": "door", "lift": lift})
		for i in 4:
			worst = maxf(worst, absf((b[i] - a[i]).y - float(lift) * 0.125))
			worst = maxf(worst, (b[i] - a[i]).x)
			worst = maxf(worst, (b[i] - a[i]).z)
	print("lift is a pure translation: worst deviation %.9f m" % worst)


func _corners(given: Dictionary) -> PackedVector3Array:
	var out := PieceKit.resolve("wall_panel", given)
	var specs := out["specs"] as Array
	if specs.is_empty():
		return PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	return StructureBaker.plate_corners(specs[0] as Dictionary)


func _sweep(opening: String) -> Dictionary:
	var tried := 0
	var refused: Dictionary = {}
	var accepted := 0
	var clamped := 0
	var casing := 0
	var lost := 0
	var worst_head := INF
	var worst_at := ""
	var examples := PackedStringArray()
	for span in SPANS:
		for height in HEIGHTS:
			for head in HEADS:
				for rake in RAKES:
					for fall in FALLS:
						tried += 1
						var given := {
							"span": span, "height": height, "head": head,
							"rake": rake, "fall": fall, "opening": opening,
						}
						var out := PieceKit.resolve("wall_panel", given)
						if (out["errors"] as PackedStringArray).size() > 0:
							var why := ", ".join(out["errors"] as PackedStringArray)
							var tag := "narrow" if why.contains("wide enough") else (
								"short" if why.contains("TALL ENOUGH") else (
								"ramped head" if why.contains("LEVEL") else "other"))
							refused[tag] = int(refused.get(tag, 0)) + 1
							continue
						accepted += 1
						if opening == "none":
							continue
						var spec := (out["specs"] as Array)[0] as Dictionary
						var corners := StructureBaker.plate_corners(spec)
						var ref := StructureBaker.plate_ref_lengths(corners)
						var asked := (spec["openings"] as Array)[0] as Dictionary
						var got := StructureBaker.plate_openings(spec, ref)
						var is_clamped := got.is_empty()
						if not is_clamped:
							var g := got[0] as Dictionary
							is_clamped = (
								absf(float(g["w"]) - float(asked["width"])) > 1e-6
								or absf(float(g["h"]) - float(asked["height"])) > 1e-6
								or absf(float(g["sill"]) - float(asked["sill"])) > 1e-6
								or absf(float(g["off"]) - float(asked["offset"])) > 1e-6
							)
						if is_clamped:
							clamped += 1
							if examples.size() < 4:
								examples.append(
									"span %d height %d head %d rake %d fall %d: asked %.2f x %.3f got %s"
									% [span, height, head, rake, fall,
									   float(asked["width"]), float(asked["height"]),
									   "nothing" if got.is_empty()
									   else "%.2f x %.3f" % [float((got[0] as Dictionary)["w"]),
															 float((got[0] as Dictionary)["h"])]]
								)
						var want_members := 3 if opening == "door" else 4
						var frames := StructureBaker.plate_frames(spec)
						var full := 0
						for frame_variant in frames:
							var frame := frame_variant as Dictionary
							var du := (float(frame["u1"]) - float(frame["u0"])) * ref.x
							var dv := (float(frame["v1"]) - float(frame["v0"])) * ref.y
							if minf(du, dv) > 0.09 - 1e-6:
								full += 1
						if frames.size() < want_members:
							lost += 1
						if full < want_members:
							casing += 1
						if opening == "door" and not got.is_empty():
							var g2 := got[0] as Dictionary
							var v := (float(g2["sill"]) + float(g2["h"])) / ref.y
							var lowest := INF
							for i in 9:
								var u := lerpf(float(g2["off"]), float(g2["off"]) + float(g2["w"]),
									float(i) / 8.0) / ref.x
								lowest = minf(lowest, StructureBaker.plate_point(corners, u, v).y)
							var foot := minf(corners[0].y, corners[1].y)
							if lowest - foot < worst_head:
								worst_head = lowest - foot
								worst_at = "span %d height %d head %d rake %d fall %d" % [
									span, height, head, rake, fall]
	if opening == "door":
		print("  door: worst DRAWN head above the panel foot %.3f m at %s" % [worst_head, worst_at])
	for line in examples:
		print("  [%s] %s" % [opening, line])
	print("  [%s] refused: %s" % [opening, str(refused)])
	print("  [%s] casing members MISSING entirely: %d" % [opening, lost])
	return {"tried": tried, "accepted": accepted, "clamped": clamped, "casing": casing}


## The default door, rake by rake: what the drawing says and what fits under it.
func _door_heads() -> void:
	print("\nrake  refy   drawn head above foot   clear over hull deck (0.092)  over heavy sole (0.155)")
	for rake in RAKES:
		if rake < 0:
			continue
		var given := {"span": 4, "height": 5, "head": 0, "rake": rake, "fall": 0, "opening": "door"}
		var out := PieceKit.resolve("wall_panel", given)
		if (out["errors"] as PackedStringArray).size() > 0:
			print("%4d  REFUSED: %s" % [rake, str(out["errors"])])
			continue
		var spec := (out["specs"] as Array)[0] as Dictionary
		var corners := StructureBaker.plate_corners(spec)
		var ref := StructureBaker.plate_ref_lengths(corners)
		var got := StructureBaker.plate_openings(spec, ref)
		if got.is_empty():
			print("%4d  no opening survived" % rake)
			continue
		var g := got[0] as Dictionary
		var v := (float(g["sill"]) + float(g["h"])) / ref.y
		var lowest := INF
		for i in 9:
			var u := lerpf(float(g["off"]), float(g["off"]) + float(g["w"]), float(i) / 8.0) / ref.x
			lowest = minf(lowest, StructureBaker.plate_point(corners, u, v).y)
		var foot := minf(corners[0].y, corners[1].y)
		print("%4d  %.3f  %.3f  %.3f  %.3f"
			% [rake, ref.y, lowest - foot, lowest - foot - 0.092, lowest - foot - 0.155])
