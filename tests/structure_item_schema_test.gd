extends SceneTree

## Headless contract test for the StructurePlan item placement model:
## float positions, free yaw/pitch/roll, host attachment, the props bag, the
## legacy cell migration, and the plan <-> DeckGrid frame conversion. Lane A:
##   xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/structure_item_schema_test.gd
## Exit 0 = all assertions hold.

const EPS := 0.0005
## A script error aborts the enclosing function and lets _initialize carry on,
## so a broken StructurePlan reports "ALL PASS" having asserted nothing. That
## happened while writing this file. Pin the count: fewer checks than this and
## the run is a failure regardless of what the ones that ran said.
const EXPECTED_CHECKS := 99

var _failures := 0
var _checks := 0


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS


func _near_v3(a: Vector3, b: Vector3) -> bool:
	return _near(a.x, b.x) and _near(a.y, b.y) and _near(a.z, b.z)


func _initialize() -> void:
	_test_float_position()
	_test_free_rotation()
	_test_rotation_order()
	_test_props_bag()
	_test_roundtrip_byte_stable()
	_test_normalize_idempotent()
	_test_legacy_migration()
	_test_migration_matches_deck_grid()
	_test_plans_without_items_load_unchanged()
	_test_counting_still_works()
	_test_host_offset()
	_test_host_follows_its_entity()
	_test_host_anchor_end()
	_test_host_chain_and_cycle()
	_test_frame_conversion()
	print("---")
	if _checks != EXPECTED_CHECKS:
		print(
			"FAIL ran %d checks, expected %d — a check aborted before asserting"
			% [_checks, EXPECTED_CHECKS]
		)
		_failures += 1
	print(
		"structure_item_schema_test: %d checks, %s"
		% [_checks, "ALL PASS" if _failures == 0 else "%d FAILURES" % _failures]
	)
	quit(0 if _failures == 0 else 1)


## ── Float position ──────────────────────────────────────────────────────────


func _test_float_position() -> void:
	var plan := StructurePlan.new()
	var item := plan.add_item("cleat", Vector3(3.6, 1.05, 7.4), 6.0)
	_check("item carries a float position, not a cell", not item.has("cell") and item.has("at"))
	_check("sub-metre x survives", _near(float((item["at"] as Array)[0]), 3.6))
	_check("sub-metre y survives", _near(float((item["at"] as Array)[1]), 1.05))
	_check("sub-metre z survives", _near(float((item["at"] as Array)[2]), 7.4))
	_check("item_at reads it back", _near_v3(StructurePlan.item_at(item), Vector3(3.6, 1.05, 7.4)))
	## The whole point: a fitting 0.4 m inboard of a rail is expressible.
	var inboard := plan.add_item("cleat", Vector3(4.0, 1.05, 7.0) - Vector3(0.0, 0.0, 0.4))
	_check("0.4 m offset is not quantised", _near(float((inboard["at"] as Array)[2]), 6.6))


## ── Rotation ────────────────────────────────────────────────────────────────


func _test_free_rotation() -> void:
	var plan := StructurePlan.new()
	var raked := plan.add_item("mast", Vector3.ZERO, 6.5)
	_check("yaw is free, not a quarter turn", _near(float(raked["yaw"]), 6.5))
	_check("pitch omitted when zero", not raked.has("pitch"))
	_check("roll omitted when zero", not raked.has("roll"))
	StructurePlan.set_item_rotation(raked, 6.5, 6.0, -2.0)
	_check("pitch appears when set", raked.has("pitch") and _near(float(raked["pitch"]), 6.0))
	_check("roll appears when set", raked.has("roll") and _near(float(raked["roll"]), -2.0))
	StructurePlan.set_item_rotation(raked, 6.5, 0.0, 0.0)
	_check("zeroing strips pitch/roll again", not raked.has("pitch") and not raked.has("roll"))


func _test_rotation_order() -> void:
	## A 6 deg raked mast: the spar's own +Y must lean, and yaw must steer WHICH
	## WAY it leans. That is the YXZ order, checked through its consequence.
	var item := StructurePlan.normalize_item({"id": 1, "item_id": "mast", "at": [0, 0, 0], "yaw": 0.0, "pitch": 6.0})
	var top := StructurePlan.item_basis(item) * Vector3.UP
	_check("rake tilts the spar axis", _near(top.y, cos(deg_to_rad(6.0))))
	_check("rake with yaw 0 leans +Z", _near(top.z, sin(deg_to_rad(6.0))) and _near(top.x, 0.0))
	var yawed := StructurePlan.normalize_item({"id": 2, "item_id": "mast", "at": [0, 0, 0], "yaw": 90.0, "pitch": 6.0})
	var yawed_top := StructurePlan.item_basis(yawed) * Vector3.UP
	_check(
		"yaw steers the rake direction (yaw applied outside pitch)",
		_near(yawed_top.x, sin(deg_to_rad(6.0))) and _near(yawed_top.z, 0.0)
	)
	_check("yaw does not change the lean angle", _near(yawed_top.y, cos(deg_to_rad(6.0))))


## ── Props ───────────────────────────────────────────────────────────────────


func _test_props_bag() -> void:
	var plan := StructurePlan.new()
	var item := plan.add_item(
		"spar",
		Vector3(1, 0, 1),
		0.0,
		{"length": 6, "radius": 0.12, "region": "hull_red", "sides": [1, 2.5], "cap": {"n": 3}}
	)
	_check("props survive", item.has("props"))
	var props := StructurePlan.item_props(item)
	_check("string prop kept", str(props.get("region", "")) == "hull_red")
	_check("float prop kept", _near(float(props.get("radius", 0.0)), 0.12))
	_check(
		"integer prop canonicalised to float (JSON returns floats anyway)",
		typeof(props.get("length")) == TYPE_FLOAT and _near(float(props["length"]), 6.0)
	)
	_check(
		"nested array canonicalised",
		(props.get("sides") as Array).size() == 2
		and typeof((props["sides"] as Array)[0]) == TYPE_FLOAT
	)
	_check(
		"nested dict canonicalised",
		typeof((props.get("cap") as Dictionary).get("n")) == TYPE_FLOAT
	)
	_check("typed getter reads through", _near(float(StructurePlan.item_prop(item, "radius", 0.0)), 0.12))
	_check("missing prop falls back", str(StructurePlan.item_prop(item, "nope", "x")) == "x")
	var bare := plan.add_item("cleat", Vector3.ZERO)
	_check("empty props bag is omitted", not bare.has("props"))
	## A non-JSON value cannot round-trip; dropping it loudly beats corrupting it.
	print("(expect one 'not JSON data' error below — that is this check working)")
	var dirty := StructurePlan.normalize_item(
		{"id": 9, "item_id": "x", "at": [0, 0, 0], "yaw": 0.0, "props": {"ok": 1.5, "bad": Vector3(1, 2, 3)}}
	)
	_check(
		"non-JSON prop is dropped, JSON siblings survive",
		not (dirty.get("props", {}) as Dictionary).has("bad")
		and (dirty.get("props", {}) as Dictionary).has("ok")
	)


## ── Round trip ──────────────────────────────────────────────────────────────


func _sample_plan() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.context = "vessel"
	plan.hull_id = "hull_28x10"
	var wall := plan.add_wall(Vector3(2, 0, 3), "x", 6.0, 1.1, 0.12)
	plan.add_deck(Vector3(0, 0, 0), Vector2(10, 28))
	plan.add_room(Vector3(3, 0, 12), Vector3(4, 2.4, 5))
	plan.add_stair(Vector3(1, 0, 6), "+z", 3.0, 0.9, 2.4)
	plan.add_item("mast", Vector3(5.0, 0.0, 9.5), 0.0)
	var raked := plan.add_item("mast", Vector3(5.0, 0.0, 14.25), 12.5, {"length": 7.5, "radius": 0.1})
	StructurePlan.set_item_rotation(raked, 12.5, 6.0, -1.5)
	plan.add_hosted_item("cleat", int(wall["id"]), Vector3(1.5, 0.9, -0.4), 90.0, "front")
	plan.add_hosted_item("fender", int(wall["id"]), Vector3(0.0, 0.2, 0.15), 0.0, "back", StructurePlan.ITEM_ANCHOR_END)
	return plan


func _test_roundtrip_byte_stable() -> void:
	var plan := _sample_plan()
	var json1 := JSON.stringify(plan.to_dict())
	var reloaded := StructurePlan.from_dict(JSON.parse_string(json1) as Dictionary)
	var json2 := JSON.stringify(reloaded.to_dict())
	_check("plan is byte-stable through to_dict/from_dict/JSON", json1 == json2)
	var again := StructurePlan.from_dict(JSON.parse_string(json2) as Dictionary)
	_check("and stays byte-stable on a third pass", JSON.stringify(again.to_dict()) == json1)
	_check("items survive the trip", reloaded.items.size() == plan.items.size())
	var hosted := reloaded.items[2] as Dictionary
	_check("host reference survives", StructurePlan.item_host_id(hosted) >= 0)
	_check(
		"host face survives",
		str((hosted["host"] as Dictionary).get("face", "")) == "front"
	)
	var raked := reloaded.items[1] as Dictionary
	_check("pitch survives", _near(float(raked.get("pitch", 0.0)), 6.0))
	_check("roll survives", _near(float(raked.get("roll", 0.0)), -1.5))
	_check(
		"props survive",
		_near(float(StructurePlan.item_prop(raked, "length", 0.0)), 7.5)
	)
	_check(
		"ids come back as ints, not JSON floats",
		typeof((reloaded.walls[0] as Dictionary)["id"]) == TYPE_INT
		and typeof((reloaded.items[0] as Dictionary)["id"]) == TYPE_INT
	)


func _test_normalize_idempotent() -> void:
	var raw := {
		"id": 4,
		"item_id": "davit",
		"at": [1.25, 0.5, 9.75],
		"yaw": 33.0,
		"pitch": 0.0,
		"roll": -4.0,
		"host": {"id": 2, "face": "", "anchor": "start"},
		"props": {"reach": 2},
		"junk": "dropped by the schema",
	}
	var once := StructurePlan.normalize_item(raw)
	var twice := StructurePlan.normalize_item(once)
	_check("normalize_item is idempotent", JSON.stringify(once) == JSON.stringify(twice))
	_check("zero pitch is not stored", not once.has("pitch"))
	_check("default anchor is not stored", not (once["host"] as Dictionary).has("anchor"))
	_check("empty face is not stored", not (once["host"] as Dictionary).has("face"))
	_check("unknown keys are dropped", not once.has("junk"))
	_check(
		"canonical key order",
		once.keys() == ["id", "item_id", "at", "yaw", "roll", "host", "props"]
	)


## ── Migration ───────────────────────────────────────────────────────────────


func _test_legacy_migration() -> void:
	var legacy := {
		"format": StructurePlan.FORMAT,
		"context": "vessel",
		"hull_id": "hull_28x10",
		"walls": [],
		"decks": [],
		"rooms": [],
		"stairs": [],
		"items": [
			{"id": 1, "item_id": "light_nav_port", "cell": [3, 0, 7], "yaw": 90},
			{"id": 2, "item_id": "mast", "cell": [5, 2, 14], "yaw": 0},
		],
	}
	var plan := StructurePlan.from_dict(legacy)
	var first := plan.items[0] as Dictionary
	_check("legacy plan still loads", plan.items.size() == 2)
	_check("cell key is gone", not first.has("cell"))
	_check("float position replaces it", first.has("at"))
	## Cell (3,0,7) was a brick standing ON the deck in the middle of its cell.
	_check(
		"cell migrates to its base centre",
		_near_v3(StructurePlan.item_at(first), Vector3(3.5, 0.0, 7.5))
	)
	_check("legacy yaw carries over unchanged", _near(float(first["yaw"]), 90.0))
	var second := plan.items[1] as Dictionary
	_check(
		"stacked cell y becomes metres",
		_near_v3(StructurePlan.item_at(second), Vector3(5.5, 2.0, 14.5))
	)
	_check("migrated items keep their ids", int(first["id"]) == 1 and int(second["id"]) == 2)
	_check("next id continues past migrated items", plan.allocate_id() == 3)
	## Re-migrating must not shift anything a second time.
	var twice := StructurePlan.from_dict(plan.to_dict())
	_check(
		"migration is idempotent",
		_near_v3(StructurePlan.item_at(twice.items[0] as Dictionary), Vector3(3.5, 0.0, 7.5))
	)
	_check(
		"migrated plan is byte-stable afterwards",
		JSON.stringify(plan.to_dict()) == JSON.stringify(twice.to_dict())
	)
	_check("is_legacy_item recognises the old form", StructurePlan.is_legacy_item({"cell": [0, 0, 0]}))
	_check("and not the new one", not StructurePlan.is_legacy_item({"at": [0.0, 0.0, 0.0]}))


func _test_migration_matches_deck_grid() -> void:
	## The migration target must be the SAME point DeckGrid calls the cell base,
	## or the two frames stay off by half a cell forever.
	var grid := DeckGrid.from_hull(28.0, 10.0, 2.0, 5.0)
	var ok := true
	for cell in [Vector3i(0, 0, 0), Vector3i(3, 0, 7), Vector3i(9, 2, 27), Vector3i(5, 1, 14)]:
		var via_grid := StructurePlan.local_to_plan(grid.cell_base_local(cell), grid)
		if not _near_v3(via_grid, StructurePlan.cell_base_plan(cell)):
			ok = false
	_check("cell_base_plan agrees with DeckGrid.cell_base_local", ok)
	var centre_ok := true
	for cell in [Vector3i(0, 0, 0), Vector3i(4, 1, 11)]:
		var via_grid := StructurePlan.local_to_plan(grid.cell_center_local(cell), grid)
		if not _near_v3(via_grid, StructurePlan.cell_center_plan(cell)):
			centre_ok = false
	_check("cell_center_plan agrees with DeckGrid.cell_center_local", centre_ok)
	var plan := StructurePlan.new()
	var by_cell := plan.add_item_at_cell("mast", Vector3i(3, 0, 7), 90.0)
	_check(
		"add_item_at_cell lands where the migration lands",
		_near_v3(StructurePlan.item_at(by_cell), Vector3(3.5, 0.0, 7.5))
	)


## ── Backwards compatibility ─────────────────────────────────────────────────


func _test_plans_without_items_load_unchanged() -> void:
	var source := _sample_plan()
	source.items.clear()
	var before := source.to_dict()
	var after := StructurePlan.from_dict(before).to_dict()
	_check("walls unchanged by the item work", (before["walls"] as Array) == (after["walls"] as Array))
	_check("decks unchanged", (before["decks"] as Array) == (after["decks"] as Array))
	_check("rooms unchanged", (before["rooms"] as Array) == (after["rooms"] as Array))
	_check("stairs unchanged", (before["stairs"] as Array) == (after["stairs"] as Array))
	_check("absent items load as an empty array", (after["items"] as Array).is_empty())
	## And the real fixtures, which predate every line of this.
	var text := FileAccess.get_file_as_string("res://resources/data/structures/demo_workboat.json")
	_check("fixture is readable", not text.is_empty())
	var data := JSON.parse_string(text) as Dictionary
	_check("fixture is recognised as a plan", StructurePlan.is_plan(data))
	var fixture := StructurePlan.from_dict(data)
	_check("fixture keeps its walls", fixture.walls.size() == (data.get("walls", []) as Array).size())
	_check("fixture has no items", fixture.items.is_empty())
	_check(
		"fixture round-trips byte-stably",
		JSON.stringify(fixture.to_dict())
		== JSON.stringify(StructurePlan.from_dict(fixture.to_dict()).to_dict())
	)


func _test_counting_still_works() -> void:
	var plan := StructurePlan.new()
	_check("empty plan is empty", plan.is_empty() and plan.entity_count() == 0)
	var item := plan.add_item("bollard", Vector3(1.5, 0.0, 2.5))
	_check("an item alone makes the plan non-empty", not plan.is_empty())
	_check("entity_count counts items", plan.entity_count() == 1)
	plan.add_wall(Vector3.ZERO, "x", 4.0)
	_check("entity_count sums collections", plan.entity_count() == 2)
	var id := int(item["id"])
	_check("entity_by_id finds items", int(plan.entity_by_id(id).get("id", -1)) == id)
	_check("entity_kind_by_id names the collection", plan.entity_kind_by_id(id) == "item")
	_check("unknown id has no kind", plan.entity_kind_by_id(9999) == "")
	_check("remove_entity removes items", plan.remove_entity(id))
	_check("count drops after removal", plan.entity_count() == 1 and plan.items.is_empty())


## ── Hosting ─────────────────────────────────────────────────────────────────


func _test_host_offset() -> void:
	var plan := StructurePlan.new()
	var wall := plan.add_wall(Vector3(2, 0, 3), "x", 6.0, 1.1, 0.12)
	var cleat := plan.add_hosted_item("cleat", int(wall["id"]), Vector3(1.5, 0.9, -0.4), 0.0, "front")
	var xform := plan.item_transform(cleat)
	_check(
		"host offset resolves in the host's frame",
		_near_v3(xform.origin, Vector3(3.5, 0.9, 2.6))
	)
	var back := plan.add_hosted_item("fender", int(wall["id"]), Vector3(1.5, 0.2, 0.15), 0.0, "back")
	_check(
		"the back face flips run and normal",
		_near_v3(plan.item_transform(back).origin, Vector3(6.5, 0.2, 2.85))
	)
	var free := plan.add_item("buoy", Vector3(1.0, 2.0, 3.0))
	_check(
		"an unhosted item resolves straight into plan space",
		_near_v3(plan.item_transform(free).origin, Vector3(1.0, 2.0, 3.0))
	)
	## Deck hosting: +y is out of the deck's top face.
	var deck := plan.add_deck(Vector3(0, 1.5, 0), Vector2(10, 28))
	var vent := plan.add_hosted_item("vent", int(deck["id"]), Vector3(4.25, 0.0, 12.5))
	_check(
		"a deck-hosted fitting sits on the deck's top plane",
		_near_v3(plan.item_transform(vent).origin, Vector3(4.25, 1.5, 12.5))
	)


func _test_host_follows_its_entity() -> void:
	## The trap this model exists to avoid: a cleat that stays put when its
	## bulwark moves.
	var plan := StructurePlan.new()
	var wall := plan.add_wall(Vector3(2, 0, 3), "x", 6.0, 1.1, 0.12)
	var cleat := plan.add_hosted_item("cleat", int(wall["id"]), Vector3(1.5, 0.9, -0.4))
	var before := plan.item_transform(cleat).origin
	wall["start"] = [5.0, 1.0, 3.0]
	var after := plan.item_transform(cleat).origin
	_check("moving the host moves the fitting by the same delta", _near_v3(after - before, Vector3(3, 1, 0)))
	## And rotating the host carries the fitting round with it.
	wall["start"] = [2.0, 0.0, 3.0]
	wall["axis"] = "z"
	var rotated := plan.item_transform(cleat).origin
	## run = +Z, out = run x UP = -X. offset (1.5, 0.9, -0.4) -> +1.5 z, +0.4 x.
	_check("re-aiming the host re-aims the fitting", _near_v3(rotated, Vector3(2.4, 0.9, 4.5)))
	var free := plan.add_item("buoy", Vector3(1.0, 2.0, 3.0))
	wall["start"] = [40.0, 0.0, 40.0]
	_check(
		"an unhosted item is NOT dragged along",
		_near_v3(plan.item_transform(free).origin, Vector3(1.0, 2.0, 3.0))
	)


func _test_host_anchor_end() -> void:
	var plan := StructurePlan.new()
	var wall := plan.add_wall(Vector3(2, 0, 3), "x", 6.0, 1.1, 0.12)
	var at_end := plan.add_hosted_item(
		"stanchion", int(wall["id"]), Vector3(0.0, 0.9, 0.0), 0.0, "front", StructurePlan.ITEM_ANCHOR_END
	)
	_check("anchor end starts at the far end", _near_v3(plan.item_transform(at_end).origin, Vector3(8.0, 0.9, 3.0)))
	var mid := plan.add_hosted_item(
		"stanchion", int(wall["id"]), Vector3(0.0, 0.9, 0.0), 0.0, "front", StructurePlan.ITEM_ANCHOR_CENTER
	)
	_check("anchor center starts mid-run", _near_v3(plan.item_transform(mid).origin, Vector3(5.0, 0.9, 3.0)))
	## Growing the wall must carry the end-anchored fitting with the end.
	wall["length"] = 10.0
	_check(
		"end-anchored fitting follows the run's new end",
		_near_v3(plan.item_transform(at_end).origin, Vector3(12.0, 0.9, 3.0))
	)
	_check(
		"start-anchored fitting does not move when the run grows",
		_near_v3(plan.item_transform(mid).origin, Vector3(7.0, 0.9, 3.0))
	)


func _test_host_chain_and_cycle() -> void:
	var plan := StructurePlan.new()
	var mast := plan.add_item("mast", Vector3(2.0, 0.0, 3.0), 90.0)
	var lamp := plan.add_hosted_item("lamp", int(mast["id"]), Vector3(1.0, 4.0, 0.0))
	## mast yaw 90 turns the lamp's +x arm toward -Z.
	_check(
		"item-on-item composes through the host's rotation",
		_near_v3(plan.item_transform(lamp).origin, Vector3(2.0, 4.0, 2.0))
	)
	var wall := plan.add_wall(Vector3(10, 0, 0), "x", 4.0)
	mast["host"] = {"id": int(wall["id"])}
	_check(
		"a three-deep chain resolves",
		_near_v3(plan.item_transform(lamp).origin, Vector3(12.0, 4.0, 2.0))
	)
	## A cycle must be reported and bounded, never hang the SceneTree.
	print("(expect one 'host cycle' error below — that is this check working)")
	mast["host"] = {"id": int(lamp["id"])}
	var cycled := plan.item_transform(lamp).origin
	_check("a host cycle terminates", is_finite(cycled.x) and is_finite(cycled.y) and is_finite(cycled.z))
	print("(expect one 'host ... not found' error below — that is this check working)")
	var orphan := plan.add_hosted_item("lamp", 4242, Vector3(1.0, 1.0, 1.0))
	_check(
		"a missing host falls back to plan space rather than crashing",
		_near_v3(plan.item_transform(orphan).origin, Vector3(1.0, 1.0, 1.0))
	)


## ── Frame conversion ────────────────────────────────────────────────────────


func _test_frame_conversion() -> void:
	var grid := DeckGrid.from_hull(28.0, 10.0, 2.0, 5.0)
	_check("grid is the expected shape", grid.width == 10 and grid.length == 28)
	_check(
		"plan y=0 is the deck plane, not cell 0's centre",
		_near(StructurePlan.plan_to_local(Vector3.ZERO, grid).y, grid.deck_y)
	)
	_check(
		"plan x=0 is the port edge corner, not a cell centre",
		_near(StructurePlan.plan_to_local(Vector3.ZERO, grid).x, -grid.half_beam)
	)
	var cell_m := WorldUnits.DECK_CELL_M
	var cell_ok := true
	var trip_ok := true
	for point in [
		Vector3(0.0, 0.0, 0.0),
		Vector3(3.6, 1.05, 7.4),
		Vector3(9.99, 0.0, 27.99),
		Vector3(5.0, 2.5, 14.0),
		Vector3(0.5, -0.4, 0.5),
	]:
		var expected := Vector3i(
			int(floor(point.x / cell_m)),
			maxi(int(floor(point.y / cell_m)), 0),
			int(floor(point.z / cell_m))
		)
		if StructurePlan.plan_to_cell(point, grid) != expected:
			cell_ok = false
		if not _near_v3(StructurePlan.local_to_plan(StructurePlan.plan_to_local(point, grid), grid), point):
			trip_ok = false
	_check("plan_to_cell floors into the containing cell", cell_ok)
	_check("plan -> local -> plan is the identity", trip_ok)
	## The recorded discrepancy, asserted as an explicit half-cell/CELL_M offset.
	var corner := Vector3(3.0, 0.0, 7.0)
	var centre := StructurePlan.cell_center_plan(StructurePlan.plan_to_cell(corner, grid))
	_check(
		"a plan corner and its cell centre differ by half a cell in x/z",
		_near(centre.x - corner.x, cell_m * 0.5) and _near(centre.z - corner.z, cell_m * 0.5)
	)
	_check(
		"and by half a cell in y, with y measured in metres either side",
		_near(centre.y - corner.y, cell_m * 0.5)
	)
	## An item placed in plan space must land in the cell a compliance rule
	## would count it in.
	var plan := StructurePlan.new()
	var light := plan.add_item("light_nav_port", Vector3(3.6, 1.05, 7.4))
	var cell := StructurePlan.plan_to_cell(plan.item_transform(light).origin, grid)
	_check("an item resolves into a countable grid cell", cell == Vector3i(3, 1, 7))
	_check(
		"and that cell is on the port side by the rule's own test",
		grid.cell_center_local(cell).x < 0.0
	)
