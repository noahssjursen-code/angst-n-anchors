extends SceneTree

## CRITIC SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
## Lane A. No autoload identifiers named.
##
## `DeckFitout.apply_plan` opens the collider window at line 102 and evaluates
## `StructureBaker.collect_colliders(plan, offset)` at line 103 — INSIDE it. A
## GDScript runtime error anywhere in that pipeline aborts `apply_plan`, so
## `end_walk_collider_batch()` is never reached.
##
## Two questions:
##   1. Over EVERY shipped structure fixture, does collect_colliders return a
##      well-formed array (REALITY §4b — run it over every fixture, not the one
##      you are working on)?
##   2. Can a hostile / corrupt plan dictionary — the shape
##      ReplicationDrawingService._apply_remote_ship_layout hands straight to
##      apply_brick_layout from the wire — make it return anything else?

const DIR := "res://resources/data/structures/"


func _init() -> void:
	print("=== 1. every shipped structure fixture ===")
	var d := DirAccess.open(DIR)
	var names := []
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				names.append(f)
	names.sort()
	var bad := 0
	for n in names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + n))
		if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
			continue
		var verdict := _probe(StructurePlan.from_dict(parsed as Dictionary), n)
		if not verdict:
			bad += 1
	print("--- %d fixtures with a malformed collider entry\n" % bad)

	print("=== 2. hostile / corrupt plan dictionaries ===")
	for case_variant in _cases():
		var c := case_variant as Dictionary
		_probe(StructurePlan.from_dict(c["plan"] as Dictionary), str(c["name"]))
	quit()


func _probe(plan: StructurePlan, label: String) -> bool:
	var boxes: Variant = StructureBaker.collect_colliders(plan, Vector3(1.0, 2.0, 3.0))
	if not (boxes is Array):
		print("%-46s ABORTED — collect_colliders returned %s"
			% [label, type_string(typeof(boxes))])
		return false
	var arr := boxes as Array
	var nulls := 0
	var no_size := 0
	var no_center := 0
	var bad_type := 0
	for b in arr:
		if not (b is Dictionary):
			nulls += 1
			continue
		var bd := b as Dictionary
		if not bd.has("size"):
			no_size += 1
		elif typeof(bd["size"]) != TYPE_VECTOR3:
			bad_type += 1
		if not bd.has("center"):
			no_center += 1
	var ok := nulls == 0 and no_size == 0 and no_center == 0 and bad_type == 0
	print("%-46s %5d boxes  %s%s"
		% [label, arr.size(), "clean" if ok else "MALFORMED",
			"" if ok else "  (null=%d no_size=%d no_center=%d bad_size_type=%d)"
				% [nulls, no_size, no_center, bad_type]])
	return ok


## Every one of these is a dictionary a peer could send. None of them is
## rejected anywhere between the wire and `apply_plan`'s loop.
func _cases() -> Array:
	return [
		{"name": "wall: thickness is a string", "plan": {
			"schema": "structure_plan_v1",
			"walls": [{"a": [0, 0], "b": [4, 0], "height": 2.0, "thickness": "wide"}],
		}},
		{"name": "wall: a is a string", "plan": {
			"schema": "structure_plan_v1",
			"walls": [{"a": "zero", "b": [4, 0], "height": 2.0, "thickness": 0.2}],
		}},
		{"name": "wall: a has one component", "plan": {
			"schema": "structure_plan_v1",
			"walls": [{"a": [0], "b": [4, 0], "height": 2.0, "thickness": 0.2}],
		}},
		{"name": "wall: height is null", "plan": {
			"schema": "structure_plan_v1",
			"walls": [{"a": [0, 0], "b": [4, 0], "height": null, "thickness": 0.2}],
		}},
		{"name": "wall: NaN height", "plan": {
			"schema": "structure_plan_v1",
			"walls": [{"a": [0, 0], "b": [4, 0], "height": "nan", "thickness": 0.2}],
		}},
		{"name": "deck: corners is a dictionary", "plan": {
			"schema": "structure_plan_v1",
			"decks": [{"corners": {"a": 1}, "y": 1.0, "thickness": 0.1}],
		}},
		{"name": "deck: one corner", "plan": {
			"schema": "structure_plan_v1",
			"decks": [{"corners": [[0, 0]], "y": 1.0, "thickness": 0.1}],
		}},
		{"name": "stairs: run is a string", "plan": {
			"schema": "structure_plan_v1",
			"stairs": [{"a": [0, 0], "b": [2, 0], "y0": 0.0, "y1": 2.0, "width": "x"}],
		}},
		{"name": "item: spar path of one point", "plan": {
			"schema": "structure_plan_v1",
			"items": [{"primitive": "spar", "props": {"path": [[0, 0, 0]]}}],
		}},
		{"name": "item: spar path entries are scalars", "plan": {
			"schema": "structure_plan_v1",
			"items": [{"primitive": "spar", "props": {"path": [1, 2]}}],
		}},
		{"name": "item: spar radii shorter than path", "plan": {
			"schema": "structure_plan_v1",
			"items": [{"primitive": "spar",
				"props": {"path": [[0, 0, 0], [0, 4, 0], [0, 8, 0]], "radii": [0.1]}}],
		}},
		{"name": "item: spar radii is a string", "plan": {
			"schema": "structure_plan_v1",
			"items": [{"primitive": "spar",
				"props": {"path": [[0, 0, 0], [0, 4, 0]], "radii": "thin"}}],
		}},
		{"name": "item: plate with three corners", "plan": {
			"schema": "structure_plan_v1",
			"items": [{"primitive": "plate",
				"props": {"corners": [[0, 0, 0], [1, 0, 0], [1, 0, 1]]}}],
		}},
		{"name": "item: plate corners are scalars", "plan": {
			"schema": "structure_plan_v1",
			"items": [{"primitive": "plate", "props": {"corners": [0, 1, 2, 3]}}],
		}},
		{"name": "edge: path of one point", "plan": {
			"schema": "structure_plan_v1",
			"edges": [{"primitive": "railing", "path": [[0, 0]], "height": 1.0}],
		}},
		{"name": "edge: path entries are scalars", "plan": {
			"schema": "structure_plan_v1",
			"edges": [{"primitive": "railing", "path": [0, 1, 2], "height": 1.0}],
		}},
		{"name": "edge: height is a string", "plan": {
			"schema": "structure_plan_v1",
			"edges": [{"primitive": "railing", "path": [[0, 0], [4, 0]], "height": "tall"}],
		}},
		{"name": "edge: negative / zero thickness", "plan": {
			"schema": "structure_plan_v1",
			"edges": [{"primitive": "sheer_band", "path": [[0, 0], [4, 0]],
				"height": -1.0, "thickness": 0.0}],
		}},
		{"name": "pieces: unknown piece id", "plan": {
			"schema": "structure_plan_v1",
			"pieces": [{"piece": "no_such_piece_at_all", "cell": [0, 0, 0]}],
		}},
		{"name": "pieces: entry is a string", "plan": {
			"schema": "structure_plan_v1",
			"pieces": ["deckhouse"],
		}},
		{"name": "walls: the list is a dictionary", "plan": {
			"schema": "structure_plan_v1",
			"walls": {"a": 1},
		}},
		{"name": "walls: entries are strings", "plan": {
			"schema": "structure_plan_v1",
			"walls": ["a wall"],
		}},
	]
