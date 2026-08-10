extends SceneTree

## Entity ids across a whole plan, held to the claim StructurePlan's own header
## makes for them.
##
## THE GAP THIS CLOSES. `StructurePlan` keeps six collections and ONE id space.
## `entity_by_id`, `entity_kind_by_id` and `remove_entity` each walk the
## collections in order and return the FIRST match, so a duplicate id does not
## error — it silently resolves to the wrong entity. That is invisible until an
## editor exists, at which point selecting a piece hands you the item that shares
## its number and deleting it deletes the item.
##
## It was live. Measured on the shipped fixtures the day this was written:
## probe_piece_trawler carried 51 duplicates and 0 of its 43 piece placements
## were addressable by id; both trawler bulwark fixtures carried 8. Every check
## those fixtures had was about geometry, so nothing asked.
##
## Note what this does NOT do: it never re-states an id. It asserts the PROPERTY
## — that every id resolves to the entity that owns it — which is the form that
## survives a fixture being regenerated (REALITY.md §4a).

const TestReport := preload("res://tests/support/test_report.gd")
const FIXTURE_DIR := "res://resources/data/structures"

var _t: TestReport


func _initialize() -> void:
	_t = TestReport.new("plan_entity_id_test")
	var fixtures := _fixtures()
	## Guard against the vacuous pass: an empty directory would otherwise report
	## success having checked nothing. TestReport also fails a zero-check run,
	## but this says WHY.
	if not _t.check("there are plan fixtures to check (%d)" % fixtures.size(), fixtures.size() > 0):
		_t.finish(self)
		return

	for path in fixtures:
		_check_fixture(path)
	_check_mutation()

	_t.finish(self)


func _check_fixture(path: String) -> void:
	var stem := path.get_file().get_basename()
	var raw := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	if raw == null:
		_t.fail("%s: does not parse" % stem)
		return
	var plan := StructurePlan.from_dict(raw)

	## 1. Every id is used once. Reported with the collision so a failure is a
	## diagnosis rather than a number.
	var duplicates := _duplicates(plan)
	_t.equal(
		"%s: every entity id is unique across all six collections%s"
		% [stem, "" if duplicates.is_empty() else " — collides: " + str(duplicates.slice(0, 6))],
		duplicates.size(),
		0,
	)

	## 2. Every id resolves to the entity that owns it, and to the right KIND.
	## This is the property the editor actually depends on; (1) is the reason it
	## can hold. Checked through the public seams, not by re-walking the arrays.
	var total := 0
	var wrong_entity := 0
	var wrong_kind := 0
	for kind_index in StructurePlan.ENTITY_KINDS.size():
		var kind := str(StructurePlan.ENTITY_KINDS[kind_index])
		for entity_variant in _collection(plan, kind):
			var entity := entity_variant as Dictionary
			var id := int(entity.get("id", 0))
			total += 1
			if plan.entity_by_id(id) != entity:
				wrong_entity += 1
			if plan.entity_kind_by_id(id) != kind:
				wrong_kind += 1
	_t.equal("%s: entity_by_id returns the owning entity for all %d ids" % [stem, total],
		wrong_entity, 0)
	_t.equal("%s: entity_kind_by_id names the owning collection" % stem, wrong_kind, 0)
	_t.equal("%s: entity_count agrees with the walk (%d)" % [stem, total],
		plan.entity_count(), total)

	## 3. Ids are positive. A zero id is what a dictionary missing the key reads
	## as, so a zero would make every lookup on it ambiguous with a typo.
	var non_positive := 0
	for kind in StructurePlan.ENTITY_KINDS:
		for entity_variant in _collection(plan, str(kind)):
			if int((entity_variant as Dictionary).get("id", 0)) <= 0:
				non_positive += 1
	_t.equal("%s: no entity carries a zero or negative id" % stem, non_positive, 0)


## MUTATION. Every check above passes, which on its own is worth nothing. This
## builds the defect the fixtures actually had — a piece placement carrying an
## id an item already uses — and requires the checks to see it.
##
## Built here rather than left in a fixture so the repo can be clean AND the
## check stay proven. If someone weakens the uniqueness check, this goes red.
func _check_mutation() -> void:
	var plan := StructurePlan.new()
	plan.hull_id = "hull_28x10"
	var wall := plan.add_wall(Vector3(1.0, 0.0, 4.0), "+x", 4.0, 2.5)
	var piece := plan.add_piece("wall_panel", Vector3i(2, 0, 8), 0, {"span": 2, "height": 5})
	_t.check("MUTATION setup: the clean plan has unique ids", _duplicates(plan).is_empty())

	var stolen := int(wall["id"])
	piece["id"] = stolen

	_t.equal("MUTATION: a piece stealing a wall's id is reported as a duplicate",
		_duplicates(plan).size(), 1)
	_t.check(
		"MUTATION: ...and entity_by_id now returns the WALL for the piece's id, "
		+ "which is the silent failure this test exists to prevent",
		plan.entity_by_id(stolen) == wall,
	)
	_t.equal("MUTATION: ...and entity_kind_by_id calls it a wall",
		plan.entity_kind_by_id(stolen), "wall")


## Ids used more than once, as ["<id> in wall+piece", …].
func _duplicates(plan: StructurePlan) -> Array:
	var seen: Dictionary = {}
	for kind_index in StructurePlan.ENTITY_KINDS.size():
		var kind := str(StructurePlan.ENTITY_KINDS[kind_index])
		for entity_variant in _collection(plan, kind):
			var id := int((entity_variant as Dictionary).get("id", 0))
			if not seen.has(id):
				seen[id] = []
			(seen[id] as Array).append(kind)
	var out: Array = []
	for id in seen.keys():
		var where := seen[id] as Array
		if where.size() > 1:
			out.append("%d in %s" % [id, "+".join(where)])
	out.sort()
	return out


func _collection(plan: StructurePlan, kind: String) -> Array:
	match kind:
		"wall": return plan.walls
		"deck": return plan.decks
		"stair": return plan.stairs
		"edge": return plan.edges
		"item": return plan.items
		"piece": return plan.pieces
	return []


func _fixtures() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(FIXTURE_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var path := "%s/%s" % [FIXTURE_DIR, name]
		var raw := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
		if raw != null and str(raw.get("format", "")) == "structure_plan_v1":
			out.append(path)
	out.sort()
	return out
