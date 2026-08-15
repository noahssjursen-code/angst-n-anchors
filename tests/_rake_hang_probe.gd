extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## THE RAKE-8 DOORWAY DRIFT MARGIN, re-measured — the number the predecessor's
## wave died without reporting.
##
## `piece_interior_test.DOOR_PHYSICS_SLACK` and `piece_kit_test.COLLIDER_HANG`
## are the same 0.06 m bound spent in two places, and the recorded measurement
## behind it is "0.022 m at rake 2, 0.052 m at rake 8" — 0.008 m from red. The
## mechanism is stated there: a casing slab's box is fitted to the slab plus and
## minus half its 0.20 m thickness ALONG THE PLATE NORMAL, and a raked plate's
## normal tilts, so the lintel's box hangs below the lintel that is drawn. That
## is exactly the quantity `_plate_panel_colliders` decides, so the finer dice
## either moved it or it did not, and either answer is a finding.
##
## No shipped fixture uses rake 8 — the three piece vessels are rake 2 and rake 0
## — so `piece_interior_test` cannot report this number and never did. It is
## resolved straight out of the kit here, across the whole rake ladder.
##
## THE TWO HEADS, both taken the way piece_interior_test takes them:
##
##   drawn   `_door_head_y` — the lowest y of the opening's top edge on the
##           plate's own mid-surface, sampled across the door's width.
##   solid   `_physics_head_y` — vertical columns across the door width, each
##           walked along the path a player takes THROUGH the wall, each read
##           upward from just over the floor, stopping at the first occupied
##           point. The only substitution is that occupancy is asked of the boxes
##           `StructureBaker.plate_colliders` emits rather than of a spawned
##           vessel's PhysicsServer3D — the same boxes, since
##           `BoatBody.add_walk_brick_collider` puts each one in as a yaw-rotated
##           BoxShape3D at that centre and changes nothing else.
##
## NOT CALIBRATED AGAINST THE LIVE FIXTURES, and it must not be read as though it
## were. Those doors are 2.032 m drawn where this panel is 2.100 m and they stand
## on a WalkDeck slab this one does not have, so the absolute numbers differ —
## rake 2 reads 0.010 m here against the 0.022 m piece_interior_test prints for
## probe_piece_house. What this probe is FOR is the delta: the same panel, the
## same scan, one baker swapped for the other, so the question "did the finer
## dice move the margin" gets an answer that does not depend on the calibration.
##
## The mechanism predicts where it lands: the casing slab is
## PLATE_FRAME_WIDTH + 2*PLATE_FRAME_PROUD = 0.19 m thick and its box is fitted
## +-half of that ALONG the plate normal, so at rake 8 (1.0 m over 2.5 m, 21.8
## degrees) the hang is 0.095 * sin(21.8) = 0.035 m before the dice contributes
## anything at all. That term is the same in both bakers.

const COLUMNS := 5
const PATH := 0.50
const PATH_STEP := 0.05
const SCAN_LO := 0.05
const SCAN_HI := 2.60
## Finer than piece_interior_test.DOOR_SCAN_STEP (0.01) on purpose: a coarser
## step can only UNDER-report a hang, and this number is being read against a
## bound it is close to.
const SCAN_STEP := 0.002
## The 1.8 m figure, so the columns stand where a player can stand.
const CAPSULE_R := 0.35

## The kit's most extreme legal door, and the ladder up to it.
const RAKES := [0, 1, 2, 3, 4, 5, 6, 7, 8]
const SETTING := {"span": 4, "height": 5, "head": 0, "fall": 0, "opening": "door"}


func _initialize() -> void:
	print("wall_panel span %d height %d, opening door — the collider hang at each rake"
		% [int(SETTING["span"]), int(SETTING["height"])])
	print("%6s %10s %10s %10s   %s"
		% ["rake", "drawn m", "solid m", "hang m", "against the 0.06 m bound"])
	for rake_variant in RAKES:
		_survey(int(rake_variant))
	quit()


func _survey(rake: int) -> void:
	var setting := SETTING.duplicate()
	setting["rake"] = rake
	var result := PieceKit.resolve("wall_panel", setting)
	var specs := result.get("specs", []) as Array
	if specs.is_empty():
		print("%6d   REFUSED: %s" % [rake, str(result.get("why", "no specs"))])
		return
	var spec := specs[0] as Dictionary
	var corners := StructureBaker.plate_corners(spec)
	if corners.size() != 4:
		print("%6d   no plate" % rake)
		return
	var ref := StructureBaker.plate_ref_lengths(corners)
	var openings := StructureBaker.plate_openings(spec, ref)
	if openings.is_empty():
		print("%6d   no opening" % rake)
		return
	var opening := openings[0] as Dictionary
	var boxes := StructureBaker.plate_colliders(spec, corners, Vector3.ZERO)
	var floor_y := StructureBaker.plate_point(corners, 0.5, 0.0).y

	var drawn := _drawn_head(corners, ref, opening)
	var solid := _solid_head(corners, ref, opening, boxes, floor_y)
	var hang := drawn - solid
	print("%6d %10.4f %10.4f %10.4f   %s (%d boxes)"
		% [rake, drawn, solid, hang,
		   "OVER" if hang > 0.06 else "%.4f m of margin" % (0.06 - hang), boxes.size()])


func _drawn_head(corners: PackedVector3Array, ref: Vector2, opening: Dictionary) -> float:
	var v := (float(opening["sill"]) + float(opening["h"])) / ref.y
	var lowest := INF
	for i in 9:
		var u := lerpf(float(opening["off"]), float(opening["off"]) + float(opening["w"]),
			float(i) / 8.0)
		lowest = minf(lowest, StructureBaker.plate_point(corners, u / ref.x, v).y)
	return lowest


func _solid_head(corners: PackedVector3Array, ref: Vector2, opening: Dictionary,
		boxes: Array, floor_y: float) -> float:
	## The HORIZONTAL outward normal, which is what piece_interior_test._outward
	## hands its own scan: a player walks level, not up the lean of the plate.
	## Using the plate's true 3D normal was tried and gave `reach` = 0 for every
	## rake — a flat quad's corners all lie in its own plane — so the columns
	## never reached a lintel that stands 1.0 m outboard at rake 8 and the scan
	## reported the 2.60 m ceiling as the head.
	var n := StructureBaker.plate_normal(corners)
	var normal := Vector3(n.x, 0.0, n.z)
	normal = Vector3(1.0, 0.0, 0.0) if normal.length() < 0.001 else normal.normalized()
	if normal.dot(StructureBaker.plate_point(corners, 0.5, 0.5)
			- StructureBaker.plate_point(corners, 0.5, 0.0)) < 0.0:
		normal = -normal
	var v := _v_at_height(corners, 0.5, floor_y + SCAN_LO)
	var lowest := floor_y + SCAN_HI
	## The head of a raked doorway is not over its threshold, so the path is taken
	## from the plate's own reach rather than from a fixed distance.
	var reach := 0.0
	for point in corners:
		reach = maxf(reach, (point - StructureBaker.plate_point(corners, 0.5, v)).dot(normal))
	## INSET OFF THE JAMBS. piece_interior_test spans `_door_column` — the
	## interval where a capsule clears both jambs at every height it occupies —
	## not the raw opening edges. Running the columns to the raw edges was tried
	## first and put the outermost two INSIDE the jamb casing, so every rake read
	## a 0.05 m head: the scan was measuring the door frame, not the doorway.
	var inset := StructureBaker.PLATE_FRAME_WIDTH + CAPSULE_R
	var lo_u := float(opening["off"]) + inset
	var hi_u := float(opening["off"]) + float(opening["w"]) - inset
	for i in COLUMNS:
		var u := lerpf(lo_u, hi_u, float(i) / float(COLUMNS - 1))
		var base := StructureBaker.plate_point(corners, u / ref.x, v)
		var t := -PATH
		while t <= reach + PATH + 1e-6:
			var here := base + normal * t
			var y := floor_y + SCAN_LO
			while y < lowest:
				if _inside_any(boxes, Vector3(here.x, y, here.z)):
					lowest = y
					break
				y += SCAN_STEP
			t += PATH_STEP
	return lowest


func _inside_any(boxes: Array, p: Vector3) -> bool:
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var inv := Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0)))).transposed()
		var local := inv * (p - (box["center"] as Vector3))
		var half := (box["size"] as Vector3) * 0.5
		if (absf(local.x) <= half.x and absf(local.y) <= half.y
				and absf(local.z) <= half.z):
			return true
	return false


func _v_at_height(corners: PackedVector3Array, u: float, y: float) -> float:
	var lo := 0.0
	var hi := 1.0
	if StructureBaker.plate_point(corners, u, 0.0).y > StructureBaker.plate_point(corners, u, 1.0).y:
		lo = 1.0
		hi = 0.0
	for _i in 24:
		var m := (lo + hi) * 0.5
		if StructureBaker.plate_point(corners, u, m).y < y:
			lo = m
		else:
			hi = m
	return (lo + hi) * 0.5
