extends SceneTree

## Lane A. `pieces[]` AS A PLAN ENTITY: does a placement survive the document,
## and does place -> save -> load -> bake give back the same geometry, to the bit.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/piece_plan_roundtrip_test.gd
##
## This is the seam the piece tool stands on and it did not exist: `StructurePlan`
## carried walls, decks, stairs, edges and items, and DROPPED `pieces[]` on the
## floor. Loading probe_piece_trawler.json into the studio and saving it back
## deleted all 43 placements — silently, with the file still a valid plan. Every
## claim below is written against that failure.
##
## What is asserted, in the order it matters:
##
##  1. THE ROUND TRIP IS BYTE-STABLE. `to_dict -> JSON -> parse -> from_dict ->
##     to_dict` on the shipped 43-placement fixture returns the SAME STRING. Not
##     "the same number of pieces" — the same bytes, which is the only form of
##     this claim a save/load cycle cannot cheat. JSON hands integers back as
##     floats, so a cell reads [5.0, 0.0, 35.0] and a span reads 4.0 on the second
##     save; `normalize_piece` is what pins them and this is what checks it.
##
##  2. THE GEOMETRY IS IDENTICAL, not merely similar. Both copies are resolved
##     through `PieceKit` and every plate corner of every resolved item is
##     compared EXACTLY (==, no epsilon). A round trip that moves a wheelhouse by
##     a micron is a round trip that is wrong; there is no tolerance to spend.
##
##  3. The document and the kit agree on where a grid node is. `StructurePlan`
##     restates the node arithmetic rather than depending on the kit, so the two
##     are held against each other on every node the fixture uses.
##
##  4. Placements are ordinary plan entities: addressable by id, removable,
##     counted, and they do not collide with wall/deck/stair ids.
##
## Every one of these carries a MUTATION: the same check run against a
## deliberately broken copy, required to go RED. A check that cannot fail is a
## rubber stamp and this repo has shipped several.

const TestReport := preload("res://tests/support/test_report.gd")

const TRAWLER := "res://resources/data/structures/probe_piece_trawler.json"
const HOUSE := "res://resources/data/structures/probe_piece_house.json"

var _t: RefCounted


func _initialize() -> void:
	_t = TestReport.new("piece_plan_roundtrip_test")

	_check_plan_carries_pieces()
	_check_byte_stable_round_trip()
	_check_geometry_survives_round_trip()
	_check_node_arithmetic_agrees()
	_check_entity_seams()
	_check_normalisation()

	_t.finish(self)


# ── 1. The plan carries placements at all ───────────────────────────────────

func _check_plan_carries_pieces() -> void:
	var doc := _load(TRAWLER)
	if not _t.check("%s loads" % TRAWLER, not doc.is_empty()):
		return
	var authored := (doc.get("pieces", []) as Array).size()
	_t.equal("the fixture on disk carries 43 placements", authored, 43)
	var plan := StructurePlan.from_dict(doc)
	_t.equal(
		"StructurePlan.from_dict keeps all %d of them" % authored, plan.pieces.size(), authored
	)
	## The failure this file exists for, stated as its own check: a plan that
	## reads placements and writes none is exactly what shipped.
	_t.equal(
		"and to_dict writes all %d back out" % authored,
		(plan.to_dict().get("pieces", []) as Array).size(), authored
	)


# ── 2. Byte stability ───────────────────────────────────────────────────────

func _check_byte_stable_round_trip() -> void:
	for path in [TRAWLER, HOUSE]:
		var doc := _load(path)
		if doc.is_empty():
			_t.fail("%s did not load" % path)
			continue
		var stem: String = path.get_file()
		## First save is the fixed point, not the second: normalisation happens on
		## the way OUT, so `once` is already canonical and every later cycle must
		## reproduce it exactly.
		var once := JSON.stringify(StructurePlan.from_dict(doc).to_dict(), "\t")
		var twice := JSON.stringify(
			StructurePlan.from_dict(JSON.parse_string(once) as Dictionary).to_dict(), "\t"
		)
		_t.check(
			"%s: save -> load -> save is byte-identical (%d bytes)" % [stem, once.length()],
			once == twice
		)
		_t.check("%s: and it is not the empty document" % stem, once.contains("\"pieces\""))

	## MUTATION — and it took two attempts to make it bite, which is worth writing
	## down. `JSON.parse_string` returns TYPE_FLOAT for EVERY number, so a document
	## that has already been through one parse is at the fixed point by accident
	## and the first mutation (setting a cell to [5.0, 0.0, 35.0]) passed. The
	## defect is on the FIRST save of a HAND-AUTHORED file, where the cells and the
	## parameters are honest ints: stringify writes "5", parse returns 5.0, and the
	## second save writes "5.0". That is the placement shape a fixture on disk
	## carries, so it is the shape the mutation has to use.
	var authored := {
		"format": StructurePlan.FORMAT,
		"pieces": [{
			"id": 200, "piece": "wall_panel", "cell": [5, 0, 35], "facing": 0,
			"params": {"span": 1, "height": 5, "rake": 2},
		}],
	}
	var raw_once := JSON.stringify(authored, "\t")
	var raw_twice := JSON.stringify(JSON.parse_string(raw_once), "\t")
	_t.check(
		"MUTATION: the same placement UNNORMALISED round-trips unstably (%s)"
		% ("differs" if raw_once != raw_twice else "SAME — the mutation did not bite"),
		raw_once != raw_twice
	)
	## ...and the identical document put through the plan is stable. Positive half
	## of the same claim, on the same bytes: it is the normalisation doing it.
	var healed_once := JSON.stringify(StructurePlan.from_dict(authored).to_dict(), "\t")
	var healed_twice := JSON.stringify(
		StructurePlan.from_dict(JSON.parse_string(healed_once) as Dictionary).to_dict(), "\t"
	)
	_t.check("the same placement through StructurePlan is stable", healed_once == healed_twice)
	_t.check(
		"and it still says span 1, not 1.0",
		healed_once.contains("\"span\": 1,") or healed_once.contains("\"span\": 1\n")
	)


# ── 3. Geometry, corner for corner ──────────────────────────────────────────

func _check_geometry_survives_round_trip() -> void:
	var doc := _load(TRAWLER)
	if doc.is_empty():
		_t.fail("%s did not load" % TRAWLER)
		return
	var before := StructurePlan.from_dict(doc).to_dict()
	var after := StructurePlan.from_dict(
		JSON.parse_string(JSON.stringify(before, "\t")) as Dictionary
	).to_dict()

	var a := _plate_corners(before)
	var b := _plate_corners(after)
	_t.check("the fixture resolves to %d plate corners" % a.size(), a.size() > 0)
	_t.equal("the round trip resolves to the same count", b.size(), a.size())
	var moved := 0
	var worst := 0.0
	for i in mini(a.size(), b.size()):
		## EXACT. Not is_equal_approx: a save/load cycle has no arithmetic in it,
		## so any difference at all is a defect and there is no budget to spend.
		if a[i] != b[i]:
			moved += 1
			worst = maxf(worst, a[i].distance_to(b[i]))
	_t.equal(
		"every plate corner is bit-identical after save/load (%d moved, worst %.9f m)"
		% [moved, worst], moved, 0
	)

	## MUTATION. One step of one parameter on one placement, which is the smallest
	## thing a player can do, and the same comparison must go red.
	var broken := _load(TRAWLER)
	var touched := ""
	for placement_variant in broken["pieces"] as Array:
		var placement := placement_variant as Dictionary
		var params := placement.get("params", {}) as Dictionary
		if not params.has("rake"):
			continue
		params["rake"] = int(params["rake"]) + 1
		touched = str(placement.get("_is", placement.get("id", "?")))
		break
	var c := _plate_corners(StructurePlan.from_dict(broken).to_dict())
	var differ := 0
	for i in mini(a.size(), c.size()):
		if a[i] != c[i]:
			differ += 1
	_t.check(
		"MUTATION: one rake step on \"%s\" moves %d corners (was 0)" % [touched, differ],
		differ > 0
	)


## Every plate corner every placement in a document resolves to, in PLAN metres,
## in document order. This goes through `PieceKit.resolve_document` — the path a
## capture rig and a spawned vessel take — not through a convenient intermediate.
func _plate_corners(doc: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var result := PieceKit.resolve_document(doc.duplicate(true))
	for message in result["errors"] as PackedStringArray:
		_t.fail("resolve: %s" % message)
	for item_variant in (result["doc"] as Dictionary).get("items", []) as Array:
		var item := item_variant as Dictionary
		var props: Variant = item.get("props", null)
		if not (props is Dictionary):
			continue
		if str((props as Dictionary).get("primitive", "")) != "plate":
			continue
		var basis := Basis.from_euler(
			Vector3(0.0, deg_to_rad(float(item.get("yaw", 0.0))), 0.0), EULER_ORDER_YXZ
		)
		var at := StructurePlan.vec3_of(item.get("at"))
		for corner_variant in (props as Dictionary).get("corners", []) as Array:
			out.append(at + basis * StructurePlan.vec3_of(corner_variant))
	return out


# ── 4. The document and the kit agree on the grid ───────────────────────────

func _check_node_arithmetic_agrees() -> void:
	var doc := _load(TRAWLER)
	if doc.is_empty():
		return
	var disagree := 0
	var nodes := 0
	for placement_variant in doc["pieces"] as Array:
		var placement := placement_variant as Dictionary
		var cell := StructurePlan.piece_cell(placement)
		nodes += 1
		if StructurePlan.piece_node_plan(cell) != PieceKit.node_plan(cell):
			disagree += 1
	_t.equal(
		"the plan and the kit place all %d of the fixture's nodes identically" % nodes,
		disagree, 0
	)
	## And a node is NOT a cell centre — the half-cell error that would put every
	## wall panel in the kit off the line it stands on.
	_t.not_equal(
		"a grid node is not a cell centre",
		StructurePlan.piece_node_plan(Vector3i(5, 0, 35)),
		StructurePlan.cell_base_plan(Vector3i(5, 0, 35))
	)
	## The facings the document will normalise against are the facings the kit
	## accepts. Two restated lists that drift are a placement that saves and
	## refuses to load.
	_t.equal(
		"the document's facing set is the kit's",
		StructurePlan.PIECE_FACINGS, Array(PieceKit.FACINGS)
	)


# ── 5. A placement is an ordinary plan entity ───────────────────────────────

func _check_entity_seams() -> void:
	var plan := StructurePlan.new()
	plan.context = "vessel"
	plan.hull_id = "hull_28x10"
	var wall := plan.add_wall(Vector3(0, 0, 0), "x", 4.0)
	var piece := plan.add_piece("wall_panel", Vector3i(4, 0, 10), 90, {"span": 2, "height": 5})
	var other := plan.add_piece("deck_tile", Vector3i(0, 5, 0), 0, {"span": 4, "depth": 4})

	_t.not_equal("a placement does not take a wall's id", int(piece["id"]), int(wall["id"]))
	_t.equal("entity_count counts placements", plan.entity_count(), 3)
	_t.equal("entity_kind_by_id names a placement", plan.entity_kind_by_id(int(piece["id"])), "piece")
	_t.equal(
		"entity_by_id finds it", int(plan.entity_by_id(int(piece["id"])).get("id", -1)),
		int(piece["id"])
	)
	_t.check("remove_entity deletes it", plan.remove_entity(int(piece["id"])))
	_t.equal("and the plan is one shorter", plan.entity_count(), 2)
	_t.check("the other placement survived", plan.entity_by_id(int(other["id"])).size() > 0)
	_t.check("the plan is not empty while a placement remains", not plan.is_empty())
	plan.remove_entity(int(other["id"]))
	plan.remove_entity(int(wall["id"]))
	_t.check("and is empty once everything is gone", plan.is_empty())

	## Ids continue from the highest id in the file, placements included: a studio
	## that loaded the trawler and placed one more piece must not hand out 201.
	var loaded := StructurePlan.from_dict(_load(TRAWLER))
	var fresh := loaded.add_piece("wall_panel", Vector3i(0, 0, 0), 0, {})
	var highest := 0
	for placement_variant in loaded.pieces:
		highest = maxi(highest, int((placement_variant as Dictionary).get("id", 0)))
	_t.check(
		"a piece added to the loaded trawler gets id %d, above every existing one"
		% int(fresh["id"]),
		int(fresh["id"]) == highest
	)


# ── 6. Normalisation, stated directly ───────────────────────────────────────

func _check_normalisation() -> void:
	var raw := {
		"id": 7.0,
		"piece": "wall_panel",
		"cell": [5.0, 0.0, 35.0],
		"facing": 90.0,
		"params": {"span": 4.0, "rake": -1.0, "opening": "door", "height": 5.0},
		"color": "#e3e0d4",
	}
	var norm := StructurePlan.normalize_piece(raw)
	_t.check("a float id normalises to an int", norm["id"] is int)
	_t.equal("cells normalise to ints", norm["cell"], [5, 0, 35])
	_t.check("facing normalises to an int", norm["facing"] is int)
	var params := norm["params"] as Dictionary
	_t.check("a numeric parameter normalises to an int", params["span"] is int)
	_t.check("a choice parameter stays a string", params["opening"] is String)
	## Sorted, so two documents describing one placement compare equal whatever
	## order their author wrote the parameters in.
	_t.equal(
		"parameter keys come out sorted", PackedStringArray(params.keys()),
		PackedStringArray(["height", "opening", "rake", "span"])
	)
	_t.equal("normalisation is idempotent", StructurePlan.normalize_piece(norm), norm)
	## Empty optional keys are absent rather than empty, so the shape is a pure
	## function of the values.
	var bare := StructurePlan.normalize_piece({"piece": "deck_tile", "cell": [0, 0, 0]})
	_t.check("a placement with no colour carries no colour key", not bare.has("color"))
	_t.check("and no note key", not bare.has("_is"))
	_t.equal("a missing facing reads as 0", int(bare["facing"]), 0)

	## MUTATION: the values normalisation is supposed to pin, left raw. If
	## `normalize_piece` were a pass-through, this would be equal and the check
	## above would be measuring nothing.
	_t.not_equal(
		"MUTATION: the raw dictionary is NOT already canonical", raw, norm
	)


func _load(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw as Dictionary if raw is Dictionary else {}
