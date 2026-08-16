extends Node

## Lane B. **A ROOF COURSE LANDS ON THE WALL IT COVERS.**
##
## Lane B, not A, because the land path is `BuildingCache` -> `BuildingFitout`
## -> `brick_door.gd:96`, which names the `WorldGateway` autoload as a bare
## compile-time identifier; under `--script` that is `Identifier not found` and
## the cascade takes this file with it.
##
## ── WHAT WENT WRONG, AND WHY NOTHING CAUGHT IT ──────────────────────────────
##
## `BrickCatalog.create_visual` drew every `roof_flat*` as a 0.18 m plate pinned
## to the CEILING of its own box. A roof course laid directly above the wall
## head therefore hung `cell_pitch - 0.18` m clear of the wall, with daylight
## right round the eaves:
##
##   shipped warehouse, 1.0 m building lattice   0.820 m
##   brick-cell arm (a) 1.0 m brick               0.820 m   — the brick size
##   brick-cell arm (c) 0.5 m lattice             0.320 m     CANCELS out of it
##   every prebuilt vessel, 0.5 m deck lattice    0.320 m
##
## Six gate units ran over that warehouse and 218 checks ran over the piece kit.
## None of them asked this question of DRAWN geometry, which is REALITY.md §4b:
## a whole property with no check pointed at it.
##
## ── THE FORMULATION, AND THE THREE THAT WERE REJECTED ───────────────────────
##
## **REJECTED — "the roof underside sits at the floor of its own cell."** That
## is the FIX restated (REALITY.md §4a). It would go green on a build whose roof
## course was authored three metres above the building, because three metres up
## is still the floor of *its own* cell.
##
## **REJECTED — "the roof underside == the blueprint's wall-top course x
## CELL_M."** That reads the answer out of the same document that positions the
## roof: one derivation testing itself. The blind mutation below is exactly this
## — raise the roof course a cell in the blueprint — and a check of that shape
## stays green while the roof flies.
##
## **REJECTED — "the gap is 0.000."** False today at the shipped constants and
## honestly so: `BrickCatalog.size_m` draws a 0.5 m brick on a 1.0 m building
## lattice, so EVERY course joint in a land building carries 0.5 m of daylight,
## roof or not. Requiring 0.000 would demand this unit be red until an OPEN
## OWNER DECISION (CONVENTIONS §3a, the brick cell) is settled — a red that
## says nothing about roofs.
##
## **THE PROPERTY THIS FILE HOLDS:** *a roof course seats on the wall below it
## no worse than one wall course seats on another, in the same model.* The
## reference is measured, per model, off the drawn wall-on-wall joints of that
## same model — so it is 0.500 m on today's land lattice, 0.000 m on a vessel,
## and 0.000 m in the brick-1.0 arm, and this file needs no edit when the owner
## decides. A roof that hangs higher than the building's own courses hang is a
## roof that is not on the building, at every setting of every constant.
##
## Everything is read off `MeshInstance3D.global_transform * get_aabb()` of the
## nodes the fit-out actually built. Nothing below reads a `y` out of a
## blueprint, and nothing below asks `BrickCatalog` where it thinks it put the
## plate.
##
## ── AND THE ONE YOU STAND ON ────────────────────────────────────────────────
##
## §3 asserts the collider agrees with the plate. It was written because the two
## were separate derivations that had drifted (REALITY.md §3b): on the shipped
## warehouse the roof DREW at y 6.570..6.750 and its collider stood at
## 6.250..6.750, and on every vessel the roof collider was a full 0.5 m cell
## under a plate occupying its top 0.18 m.

const TestReport := preload("res://tests/support/test_report.gd")

## Floating point only. This is NOT a slop allowance: every number this file
## compares is a sum of exact binary-representable cell arithmetic, and the
## observed residual is ~1e-7.
const EPS := 0.0005

var _t: RefCounted
var _host: Node3D


func _ready() -> void:
	_t = TestReport.new("roof_seat_test")
	_host = Node3D.new()
	add_child(_host)

	_land()
	_vessels()

	_host.free()
	_t.finish(get_tree())


## ── 1. LAND — every shipped blueprint, not the one being worked on (§3c) ────
func _land() -> void:
	var ids := BuildingBlueprintCatalog.ids()
	_t.check("the building catalogue ships blueprints to check (%d)" % ids.size(),
		ids.size() > 0)
	for blueprint_id in ids:
		var layout := BuildingBlueprintCatalog.by_id(blueprint_id)
		if layout == null:
			_t.fail("blueprint %s must load" % blueprint_id)
			continue
		_land_one(blueprint_id, layout)


func _land_one(blueprint_id: String, layout: BuildingLayout) -> void:
	var fitout := BuildingFitout.build(layout, true)
	_host.add_child(fitout)

	## column key "x,z" -> [{ y, id, lo, hi }], drawn.
	var columns: Dictionary = {}
	var roof_plates: Dictionary = {}
	for child in fitout.get_children():
		if not (child is Node3D) or str(child.name) == "Collision":
			continue
		var parsed := _parse_node_name(str(child.name))
		if parsed.is_empty():
			continue
		var brick_id := str(parsed["id"])
		var cell: Vector3i = parsed["cell"]
		if not BrickCatalog.has(brick_id):
			continue
		var aabb := _bounds(child)
		if aabb.size == Vector3.ZERO:
			continue
		var yaw := int(round(child.rotation_degrees.y / 90.0)) % 4
		if yaw < 0:
			yaw += 4
		_record(columns, layout.grid().footprint_cells(
			cell, BrickCatalog.footprint_of(brick_id), yaw), brick_id, aabb, cell)
		if BrickCatalog.is_flat_roof(brick_id):
			roof_plates[BuildingLayout.cell_key(cell)] = aabb

	_seat_checks("blueprint %s" % blueprint_id, columns)

	## §3 — the collider is the plate. Land colliders are named
	## "Shape_<brick_id>_<x,y,z>".
	var body := fitout.get_node_or_null("Collision")
	var compared := 0
	var worst_lo := 0.0
	var worst_hi := 0.0
	if body != null:
		for c in body.get_children():
			var shape_node := c as CollisionShape3D
			if shape_node == null:
				continue
			var box := shape_node.shape as BoxShape3D
			if box == null:
				continue
			var raw := str(shape_node.name)
			if not raw.begins_with("Shape_"):
				continue
			var parsed := _parse_node_name(raw.substr(6))
			if parsed.is_empty() or not BrickCatalog.is_flat_roof(str(parsed["id"])):
				continue
			var plate_key := BuildingLayout.cell_key(parsed["cell"] as Vector3i)
			if not roof_plates.has(plate_key):
				continue
			var plate: AABB = roof_plates[plate_key]
			var col_lo := shape_node.position.y - box.size.y * 0.5
			var col_hi := shape_node.position.y + box.size.y * 0.5
			worst_lo = maxf(worst_lo, absf(col_lo - plate.position.y))
			worst_hi = maxf(worst_hi, absf(col_hi - (plate.position.y + plate.size.y)))
			compared += 1
	if compared > 0:
		_t.check(
			"blueprint %s: the roof you stand on is the roof you see — %d plates, "
			% [blueprint_id, compared]
			+ "collider underside off by %.4f m, top by %.4f m" % [worst_lo, worst_hi],
			worst_lo <= EPS and worst_hi <= EPS)

	## The game reaches a blueprint through `BuildingCache.instance`, which
	## stamps a flattened prototype, not through `BuildingFitout` directly
	## (REALITY.md §3). The cache throws per-brick names away, so the numbers
	## above cannot be taken there — but its ENVELOPE can, and if the stamp drew
	## the plate anywhere else the envelope would say so.
	var stamped := BuildingCache.instance(layout, false)
	_host.add_child(stamped)
	var a := _bounds(fitout)
	var b := _bounds(stamped)
	_t.check("blueprint %s: the cache stamp draws the fit-out's envelope "
		% blueprint_id
		+ "(fitout %s %s vs stamp %s %s)"
			% [str(a.position.snappedf(0.001)), str(a.size.snappedf(0.001)),
				str(b.position.snappedf(0.001)), str(b.size.snappedf(0.001))],
		a.position.distance_to(b.position) <= EPS and a.size.distance_to(b.size) <= EPS)
	_host.remove_child(stamped)
	stamped.free()

	_host.remove_child(fitout)
	fitout.free()


## ── 2. VESSELS — the same bricks on the 0.5 m deck lattice ──────────────────
func _vessels() -> void:
	var dir := DirAccess.open("res://resources/data/vessels/prebuilt")
	if dir == null:
		_t.fail("the prebuilt vessel directory must be readable")
		return
	var stems: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			stems.append(f.get_basename())
	stems.sort()
	_t.check("the game ships prebuilt vessels to check (%d)" % stems.size(),
		stems.size() > 0)
	for stem in stems:
		_vessel_one(stem)


func _vessel_one(stem: String) -> void:
	var path := "res://resources/data/vessels/prebuilt/%s.json" % stem
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		_t.fail("prebuilt %s must parse" % stem)
		return
	var doc := parsed as Dictionary
	var layout := BrickLayout.from_dict(doc.get("brick_layout", {}) as Dictionary)
	var grid := HullRegistry.make_grid(str(doc.get("hull_id", "")))
	if layout == null or grid == null:
		_t.fail("prebuilt %s must resolve a layout and a grid" % stem)
		return

	var root := Node3D.new()
	_host.add_child(root)

	var columns: Dictionary = {}
	var roofs: Array[Dictionary] = []
	for item_v in layout.iter_primary_cells():
		var item := item_v as Dictionary
		var brick_id := str(item.get("brick_id", ""))
		if not BrickCatalog.has(brick_id):
			continue
		var cell: Vector3i = item.get("cell", Vector3i.ZERO)
		var visual := DeckFitout.create_item_visual(root, grid, item)
		if visual == null:
			continue
		var aabb := _bounds(visual)
		if aabb.size != Vector3.ZERO:
			var yaw := int(round(float(item.get("yaw", 0)) / 90.0)) % 4
			if yaw < 0:
				yaw += 4
			_record(columns, grid.footprint_cells(
				cell, BrickCatalog.footprint_of(brick_id), yaw), brick_id, aabb, cell)
			if BrickCatalog.is_flat_roof(brick_id) and roofs.size() < 3:
				roofs.append({"item": item, "aabb": aabb})
		root.remove_child(visual)
		visual.free()

	_seat_checks("prebuilt %s" % stem, columns)

	## The shipping vessel path merges static bricks into a skin
	## (`DeckFitout.skin_enabled`), so the per-brick node measured above is not
	## the node the player sees. The merger re-instantiates the same catalog
	## visual and appends it under the placement transform — assert that, do not
	## assume it (REALITY.md §6).
	for r in roofs:
		var merged := VesselSkinBaker.bake_items(grid, [r["item"]])
		root.add_child(merged)
		var m := _bounds(merged)
		var d: AABB = r["aabb"]
		_t.check("prebuilt %s: the merged skin draws the roof plate where the "
			% stem
			+ "live node does (%s vs %s)"
				% [str(m.position.snappedf(0.001)), str(d.position.snappedf(0.001))],
			m.position.distance_to(d.position) <= EPS
				and m.size.distance_to(d.size) <= EPS)
		root.remove_child(merged)
		merged.free()

	_host.remove_child(root)
	root.free()


## ── THE PROPERTY ───────────────────────────────────────────────────────────
##
## In each vertical column of drawn bricks:
##  - the REFERENCE is the largest daylight between two vertically adjacent
##    wall bricks, anywhere in THIS model. It is how well this model's own
##    courses seat: 0.500 m on today's land lattice, 0.000 m on a vessel. It is
##    measured, never written down here, so this file survives the open
##    brick-cell decision without an edit.
##  - the ROOF JOINT is measured PER ROOF PLATE, not per cell: over every column
##    that plate covers, take the topmost wall anywhere below it, and keep the
##    HIGHEST such wall the plate has. That is the wall this plate lands on. A
##    plate the daylight of which exceeds the reference is a plate that is not
##    on the building.
##
## ⚠ TWO REFINEMENTS, EACH FORCED BY A WRONG RESULT ON THE ONLY BUILDING THERE IS.
##
## **DISTANCE-BLIND.** The first cut paired a roof only with the brick in the
## cell IMMEDIATELY below it. Under the blind mutation — `warehouse.json`'s roof
## course raised from y=6 to y=7, the roof left flying a metre over the wall
## head, which is the exact DATA fault STATE.md accused the blueprint of — that
## form found zero adjacent roof-on-wall pairs, printed "no flat-roof-on-wall
## joint in this model", ran two fewer checks and **reported PASS.** REALITY.md
## §4: an early return on a missing fixture is a check that cannot fail.
## Filtering to adjacency was the same mistake in a different coat as reading
## the answer out of the blueprint: it assumed the document had put the roof in
## the right course and then only measured how the brick sat inside it.
##
## **PER ROOF COURSE, NOT PER PLATE OR PER COLUMN.** Made distance-blind and
## left per-column, it went red on the FIXED tree at 3.500 m over column
## (20,16), and per-plate it stayed red at the same place — both true
## measurements of a DIFFERENT defect. `wall_text_lg` is footprint 6x3x1, tagged
## `text`, and `_add_deck_text_visual` draws painted letters and NO PLATE, so
## the warehouse's sign placement leaves **no wall at all for 6 x 3 m of the
## front elevation** behind the word WAREHOUSE, and one 4x4 roof plate sits
## entirely inside that span. Real, reported, worth its own wave — and NOT this
## property. Attributing a missing wall to the roof would redden for the wrong
## reason, and the next wave would go and "fix" the roof.
##
## A roof course is ONE PLANE, so it is judged as one: all plates drawn at the
## same height are a course, and a course lands on the highest wall anywhere
## beneath it. Grouping by DRAWN height rather than by cell level is deliberate
## — a tiered deckhouse has two roof courses and each finds its own tier's wall
## head, with no notion of "tier" needed anywhere in this file.
func _seat_checks(label: String, columns: Dictionary) -> void:
	var reference := -INF
	var reference_at := ""
	## placement uid -> { lo, id, support, at }
	var plates: Dictionary = {}
	var plate_count := 0

	for key_v in columns.keys():
		var stack := (columns[key_v] as Array).duplicate()
		stack.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["y"]) < int(b["y"]))

		## The model's own course seating — adjacent wall on wall.
		for i in range(1, stack.size()):
			var below := stack[i - 1] as Dictionary
			var above := stack[i] as Dictionary
			if int(above["y"]) != int(below["y"]) + 1:
				continue
			if not _is_wall(str(below["id"])) or not _is_wall(str(above["id"])):
				continue
			var gap := float(above["lo"]) - float(below["hi"])
			if gap > reference:
				reference = gap
				reference_at = "%s y%d %s on %s" \
					% [str(key_v), int(above["y"]), str(above["id"]), str(below["id"])]

		## Each roof plate against the topmost wall anywhere beneath it, in this
		## column, at any distance. A column with no wall under the plate
		## contributes nothing and is not a defect — that is an EAVE, or the
		## open middle of the shed, and a roof is supposed to span both.
		for i in stack.size():
			var plate := stack[i] as Dictionary
			if not BrickCatalog.is_flat_roof(str(plate["id"])):
				continue
			var uid := str(plate["uid"])
			if not plates.has(uid):
				plates[uid] = {
					"lo": float(plate["lo"]), "id": str(plate["id"]),
					"support": -INF, "at": "",
				}
				plate_count += 1
			for j in range(i - 1, -1, -1):
				var candidate := stack[j] as Dictionary
				if int(candidate["y"]) >= int(plate["y"]):
					continue
				if not _is_wall(str(candidate["id"])):
					continue
				if float(candidate["hi"]) > float((plates[uid] as Dictionary)["support"]):
					(plates[uid] as Dictionary)["support"] = float(candidate["hi"])
					(plates[uid] as Dictionary)["at"] = "%s y%d %s over %s at y%d" \
						% [str(key_v), int(plate["y"]), str(plate["id"]),
							str(candidate["id"]), int(candidate["y"])]
				break

	## Collapse the plates into COURSES by drawn height, and take each course's
	## best support. The per-plate spread is printed, never asserted: it is how
	## the sign hole shows up without being blamed on the roof.
	var courses: Dictionary = {}
	for uid_v in plates.keys():
		var p := plates[uid_v] as Dictionary
		if float(p["support"]) == -INF:
			continue
		var key := "%.3f" % float(p["lo"])
		if not courses.has(key):
			courses[key] = {"lo": float(p["lo"]), "support": -INF, "at": "", "n": 0}
		var course := courses[key] as Dictionary
		course["n"] = int(course["n"]) + 1
		if float(p["support"]) > float(course["support"]):
			course["support"] = float(p["support"])
			course["at"] = str(p["at"])

	var plate_worst := -INF
	var plate_worst_at := ""
	for uid_v in plates.keys():
		var p := plates[uid_v] as Dictionary
		if float(p["support"]) == -INF:
			continue
		var g := float(p["lo"]) - float(p["support"])
		if g > plate_worst:
			plate_worst = g
			plate_worst_at = str(p["at"])
	if plate_worst > -INF:
		print("  ....  %s: worst SINGLE plate %.4f m (%s) — diagnostic only; a "
			% [label, plate_worst, plate_worst_at]
			+ "lone high reading here means a WALL is missing under that plate")

	var roof_pairs: Array[Dictionary] = []
	for key_v in courses.keys():
		var course := courses[key_v] as Dictionary
		roof_pairs.append({
			"gap": float(course["lo"]) - float(course["support"]),
			"at": "%s, %d plates" % [str(course["at"]), int(course["n"])],
		})

	if roof_pairs.is_empty():
		## NOT an early return. A model that draws flat roofs and seats none of
		## them on a wall has failed the property, not escaped it.
		if plate_count > 0:
			_t.fail("%s: draws %d flat roof plates and NOT ONE of them stands "
				% [label, plate_count] + "over a wall — the roof covers nothing")
		else:
			print("  ....  %s: draws no flat roof at all" % label)
		return
	if reference == -INF:
		_t.fail("%s: carries a roof over a wall but no wall-on-wall joint to "
			% label + "measure the model's own course seating against")
		return

	var worst := -INF
	var worst_at := ""
	for p in roof_pairs:
		if float(p["gap"]) > worst:
			worst = float(p["gap"])
			worst_at = str(p["at"])

	_t.check("%s: the roof seats no worse than this model's own course joints "
		% label
		+ "— worst roof course %.4f m (%s) against reference course joint %.4f m (%s), over %d roof courses / %d plates"
			% [worst, worst_at, reference, reference_at, roof_pairs.size(), plate_count],
		worst <= reference + EPS)


	## Sign check, separate on purpose: "no worse than the reference" is silent
	## about a roof driven DOWN into the wall. A plate that has sunk below the
	## head it lands on is a different defect with the same one-line fix, and
	## averaging the two into one signed comparison would hide it.
	var lowest := INF
	var lowest_at := ""
	for p in roof_pairs:
		if float(p["gap"]) < lowest:
			lowest = float(p["gap"])
			lowest_at = str(p["at"])
	_t.check("%s: the roof does not sink into the wall it covers "
		% label + "— lowest roof joint %.4f m (%s)" % [lowest, lowest_at],
		lowest >= -EPS)


## ── PLUMBING ───────────────────────────────────────────────────────────────


## A wall, for this file's purposes: something that holds a building up. Tagged
## `solid` and not tagged `roof`, so a roof laid on another roof is not counted
## as having landed on anything.
func _is_wall(brick_id: String) -> bool:
	return BrickCatalog.has_tag(brick_id, "solid") \
		and not BrickCatalog.has_tag(brick_id, "roof")


## A brick is recorded against EVERY cell its footprint covers, not just its
## origin. A `roof_flat_4x4` covers sixteen cells and its origin sits over open
## floor; keying on the origin alone found 5 joints on the warehouse where
## footprint expansion finds 62, and the ones it missed were the EAVE — the
## perimeter, which is the only place the daylight is visible from outside.
func _record(
		columns: Dictionary,
		cells: Array[Vector3i],
		brick_id: String,
		aabb: AABB,
		origin: Vector3i,
) -> void:
	## `uid` identifies the PLACEMENT, so a 4x4 plate spread over sixteen
	## columns is judged once, as the one plate it is.
	var uid := "%s@%d,%d,%d" % [brick_id, origin.x, origin.y, origin.z]
	for c in cells:
		var key := "%d,%d" % [c.x, c.z]
		if not columns.has(key):
			columns[key] = []
		(columns[key] as Array).append({
			"y": c.y, "id": brick_id, "uid": uid,
			"lo": aabb.position.y, "hi": aabb.position.y + aabb.size.y,
		})


## "<brick_id>_<x,y,z>" — a brick id may itself contain underscores, so cut at
## the LAST one, and the tail must parse as three integers or this is not a
## brick node at all.
func _parse_node_name(raw: String) -> Dictionary:
	var cut := raw.rfind("_")
	if cut <= 0:
		return {}
	var parts := raw.substr(cut + 1).split(",")
	if parts.size() != 3:
		return {}
	for p in parts:
		if not p.is_valid_int():
			return {}
	return {
		"id": raw.substr(0, cut),
		"cell": Vector3i(int(parts[0]), int(parts[1]), int(parts[2])),
	}


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = aabb
			first = false
		else:
			out = out.merge(aabb)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
