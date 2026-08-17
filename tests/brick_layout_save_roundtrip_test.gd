extends Node

const TestReport := preload("res://tests/support/test_report.gd")

## ── THE HALF OF THE SAVE PATH NOTHING USED TO RUN (REALITY.md §3) ──────────
##
## `BrickLayout.to_dict()` is what AUTHORS the `brick_layout` record a vessel is
## stored with — `shipyard_brick_editor.gd:3109` (in-game confirm) and `:3134`
## (the prebuilt JSON the shipwright then sells) both write it — and until this
## file existed **nothing in the gate ran it**.
##
## `vessel_persistence_test` builds its expected dictionary itself and compares
## it against the same dictionary after a JSON write; `VesselSpawn.brick_layout_of()`
## is a raw `duplicate(true)` passthrough. So that unit walks a dictionary the
## test wrote against itself, and `captain_vessel_hard_persistence_test` does the
## same with a `duplicate(true)` of a shipped fixture plus two hand-typed cells.
## Measured 2026-08-17: `to_dict()` mutated to `erase("light_yaw")` on every cell
## it saves left `vessel_persistence_test` at PASS (48), `shipyard_editor_ui_test`
## at PASS (42) and the hard persistence unit green — all unchanged.
##
## ── HOW THIS FILE AVOIDS BEING THE SAME TRAP ───────────────────────────────
##
## The expected value is never a dictionary this file typed. It is:
##
##   (a) a LIVE `BrickLayout` object, built by the production mutators the
##       shipyard editor calls (`place_footprint`, `attach_sign`, `attach_light`,
##       `add_bulk_hold`, `add_container_pad`) on top of a CERTIFIED shipped
##       prebuilt — i.e. an in-game refit — and read back through `BrickLayout`'s
##       own accessors; or
##   (b) the literal PLAYER INPUT handed to those mutators (the paint colour, the
##       sign text, the light's yaw), which is an action, not a serialised form.
##
## Every comparison crosses the whole authoring path:
##
##   live BrickLayout
##     → to_dict()                          ← the authoring seam nothing ran
##     → PlayerData.upsert_owned_vessel()   ← normalize_record + ledger_vessel_record
##     → PlayerData.to_dict() → JSON text → JSON.parse_string()
##     → PlayerData.from_dict() → find_owned_vessel()
##     → VesselSpawn.brick_layout_of()
##     → BrickLayout.from_dict()            ← the record's own loader
##
## and again through `VesselArchive.save_record()` / `load_records()`, the durable
## per-vessel copy `PlayerSession.persist_vessel_configuration` writes.
##
## ── WHY THE POPULATION IS DECLARED (REALITY.md §4f, shape 1) ────────────────
##
## `FIXTURES` is a literal, and every declared fact about a fixture — its hull, its
## registration, how many bulk holds and container pads it ships — is asserted, not
## discovered. A fixture that leaves the directory reds the parse check instead of
## quietly shrinking the run, and a fixture that stops shipping its bulk hold reds
## the zone census instead of making the zone round-trip checks vacuous.
##
## `CELL_FIELDS` is the second half of that defence. A round-trip check is only
## worth what its input vocabulary carries: if the refit stopped producing a
## `light_yaw`, every light assertion below would still pass, on nothing. So each
## field is asserted PRESENT in the live layout before it is asserted to survive.
## The check count is structurally fixed — no loop over a discovered collection
## contributes a check site — and `EXPECTED_CHECKS` freezes the total anyway.

const PREBUILT_DIR := "res://resources/data/vessels/prebuilt"

## Declared population. Every field is a claim about the shipped file, asserted below.
const FIXTURES: Array[Dictionary] = [
	{
		"id": "fishing_trawler", "hull": "hull_28x10", "reg": "fishing_vessel",
		"ships_holds": 0, "ships_pads": 0, "author_hold": true,
	},
	{
		"id": "28_10_m", "hull": "hull_28x10", "reg": "cargo_vessel",
		"ships_holds": 0, "ships_pads": 2, "author_hold": true,
	},
	{
		"id": "bulk_small", "hull": "hull_28x10", "reg": "bulk_vessel",
		"ships_holds": 1, "ships_pads": 0, "author_hold": true,
	},
	## A 10 x 30 deck has no room for a 6 x 12 hold. That is a PROPERTY of this
	## fixture, asserted as a refusal — not a case this file skips.
	{
		"id": "sjark_15m", "hull": "hull_15x5", "reg": "fishing_vessel",
		"ships_holds": 0, "ships_pads": 0, "author_hold": false,
	},
]

## Every field a saved cell can carry. Each must be produced by the refit below,
## or the round-trip assertion for it is testing an absence.
const CELL_FIELDS: Array[String] = [
	"brick_id", "yaw", "occupied_by", "color", "text",
	"sign_id", "sign_yaw", "light_id", "light_yaw",
]

## The player's inputs — the expected side of every per-field assertion.
const PAINT := Color(0.9, 0.2, 0.15)
const SIGN_BRICK := "wall_text"
const SIGN_YAW := 90
const SIGN_TEXT := "PORT SIDE"
const LIGHT_BRICK := "light_deck"
const LIGHT_YAW := 45
const BENCH_BRICK := "bench"
const BENCH_YAW := 270
const NAME_BRICK := "wall_text"
const NAME_YAW := 180
const NAME_TEXT := "MARY ROSE"
const HOLD_BRICK := "bulk_hold_6x12"

const EXPECTED_CHECKS := 191

var _t := TestReport.new("brick_layout_save_roundtrip_test", false)
var _owner_id := ""
var _saved_uids: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_owner_id = PlayerData.new_uuid()
	var data := PlayerData.new()
	## uid → { live: BrickLayout, grid: DeckGrid, fixture: Dictionary, marks: Dictionary }
	var authored: Dictionary = {}

	for fixture in FIXTURES:
		_author_one(fixture, data, authored)

	## One JSON write for the whole fleet — the inter-process boundary.
	var json := JSON.stringify({"version": PlayerSaveStore.SAVE_VERSION, "player": data.to_dict()})
	var parsed: Variant = JSON.parse_string(json)
	_t.check("fleet envelope parses after JSON write", typeof(parsed) == TYPE_DICTIONARY)
	var restored := PlayerData.from_dict(
		((parsed as Dictionary).get("player", {}) if typeof(parsed) == TYPE_DICTIONARY else {})
		as Dictionary
	)
	_t.equal("every refitted vessel survives the write", restored.owned_vessels.size(), FIXTURES.size())

	for uid in authored:
		_verify_one(str(uid), authored[uid] as Dictionary, restored)

	for uid in _saved_uids:
		DirAccess.remove_absolute(VesselArchive.archive_path_for_uid(uid))

	_t.equal("check budget (REALITY.md §4f shape 4)", _t.check_count() + 1, EXPECTED_CHECKS)
	_t.finish(get_tree())


## ── authoring: an in-game refit of a certified vessel ────────────────────────
func _author_one(fixture: Dictionary, data: PlayerData, authored: Dictionary) -> void:
	var fid := str(fixture.get("id", ""))
	var path := "%s/%s.json" % [PREBUILT_DIR, fid]
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not _t.check("%s: declared prebuilt parses" % fid, typeof(doc) == TYPE_DICTIONARY):
		## A missing fixture is a FAILURE, never a shrunk run (REALITY.md §4f shape 2).
		for _i in range(37):
			_t.fail("%s: refit and round trip never ran — the fixture is gone" % fid)
		return
	var preset := doc as Dictionary
	var hull_id := str(fixture.get("hull", ""))
	var reg_id := str(fixture.get("reg", ""))
	_t.equal("%s: declared hull matches the shipped file" % fid, str(preset.get("hull_id", "")), hull_id)
	_t.equal(
		"%s: declared registration matches the shipped file" % fid,
		str(preset.get("registration_id", "")), reg_id,
	)

	var grid := HullRegistry.make_grid(hull_id)
	var live := BrickLayout.from_dict(preset.get("brick_layout", {}) as Dictionary)
	_t.equal("%s: shipped bulk hold census" % fid, live.bulk_holds.size(), int(fixture.get("ships_holds", 0)))
	_t.equal("%s: shipped container pad census" % fid, live.container_pads.size(), int(fixture.get("ships_pads", 0)))
	_t.check("%s: shipped layout is not empty" % fid, live.count() > 0)
	var as_shipped := DeckFitout.compliance_for_layout(live.to_dict(), hull_id, reg_id, grid)
	_t.check(
		"%s: the vessel a player buys is certified as shipped" % fid,
		bool(as_shipped.get("ok", false)),
	)

	## The refit, through the editor's own mutators.
	var paint_cell := _place_first(live, grid, "block", 0, {"color": PAINT})
	_t.check("%s: a painted block goes down on a free deck cell" % fid, paint_cell.x >= 0)
	_t.check(
		"%s: a sign mounts on that block" % fid,
		paint_cell.x >= 0 and live.attach_sign(paint_cell, SIGN_BRICK, SIGN_YAW, SIGN_TEXT),
	)
	_t.check(
		"%s: a work light mounts on that block" % fid,
		paint_cell.x >= 0 and live.attach_light(paint_cell, LIGHT_BRICK, LIGHT_YAW),
	)
	var bench_cell := _place_first(live, grid, BENCH_BRICK, BENCH_YAW, {})
	_t.check("%s: a multi-cell bench goes down (produces occupied_by)" % fid, bench_cell.x >= 0)
	var name_cell := _place_first(live, grid, NAME_BRICK, NAME_YAW, {"text": NAME_TEXT})
	_t.check("%s: a named wall-text brick goes down" % fid, name_cell.x >= 0)
	var hold_cell := _add_first_hold(live, grid)
	if bool(fixture.get("author_hold", false)):
		_t.check("%s: a bulk hold is authorable on this deck" % fid, hold_cell.x >= 0)
	else:
		_t.check(
			"%s: this deck is too small for a %s and says so" % [fid, HOLD_BRICK],
			hold_cell.x < 0,
		)
	var pad_cell := _add_first_pad(live, grid)
	_t.check("%s: a container pad is authorable on this deck" % fid, pad_cell.x >= 0)

	## The vocabulary guard: a field that is never authored cannot be shown to survive.
	var present: Dictionary = {}
	for entry_raw in live.cells.values():
		for f in (entry_raw as Dictionary).keys():
			present[str(f)] = true
	for field in CELL_FIELDS:
		_t.check("%s: the refit actually produces a '%s' to lose" % [fid, field], present.has(field))

	var refitted := DeckFitout.compliance_for_layout(live.to_dict(), hull_id, reg_id, grid)
	_t.check(
		"%s: the refitted layout is one the save path would accept" % fid,
		bool(refitted.get("ok", false)),
	)

	var uid := "roundtrip_%s" % fid
	## THE AUTHORING SEAM. Everything downstream sees only what `to_dict()` emitted.
	data.upsert_owned_vessel({
		"uid": uid,
		"hull_id": hull_id,
		"name": "Refit %s" % fid,
		"display": str(preset.get("name", fid)),
		"registration_id": reg_id,
		"scene_path": HullRegistry.scene_path_for(hull_id),
		"shaft_power_kw": float(preset.get("shaft_power_kw", 1000.0)),
		"brick_layout": live.to_dict(),
	})
	authored[uid] = {
		"live": live,
		"grid": grid,
		"fid": fid,
		"hull": hull_id,
		"reg": reg_id,
		"paint_cell": paint_cell,
		"bench_cell": bench_cell,
		"name_cell": name_cell,
	}


## ── verification: against the LIVE object, never against a dict this file typed ──
func _verify_one(uid: String, ctx: Dictionary, restored: PlayerData) -> void:
	var fid := str(ctx.get("fid", ""))
	var live: BrickLayout = ctx.get("live")
	var grid: DeckGrid = ctx.get("grid")
	var row := restored.find_owned_vessel(uid)
	if not _t.check("%s: the refitted vessel survives reload" % fid, not row.is_empty()):
		for _i in range(21):
			_t.fail("%s: layout comparison never ran — the record is gone" % fid)
		return
	var back := BrickLayout.from_dict(VesselSpawn.brick_layout_of(row))

	_t.equal("%s: hull_id survives the save" % fid, back.hull_id, live.hull_id)
	_t.equal("%s: cell count survives the save" % fid, back.count(), live.count())
	_compare("%s: player.json" % fid, live, back)

	## Per-field, against the literal player input rather than a serialised form.
	var paint_cell: Vector3i = ctx.get("paint_cell")
	var e := back.get_brick(paint_cell)
	var rgb: Array = e.get("color", []) as Array
	_t.check(
		"%s: the paint the player chose survives" % fid,
		rgb.size() == 3
		and is_equal_approx(float(rgb[0]), PAINT.r)
		and is_equal_approx(float(rgb[1]), PAINT.g)
		and is_equal_approx(float(rgb[2]), PAINT.b),
	)
	_t.equal("%s: sign_id survives" % fid, str(e.get("sign_id", "")), SIGN_BRICK)
	_t.equal("%s: sign_yaw survives" % fid, int(e.get("sign_yaw", -1)), SIGN_YAW)
	_t.equal("%s: the sign's text survives" % fid, str(e.get("text", "")), SIGN_TEXT)
	_t.equal("%s: light_id survives" % fid, str(e.get("light_id", "")), LIGHT_BRICK)
	_t.equal("%s: the work light's rotation survives" % fid, int(e.get("light_yaw", -1)), LIGHT_YAW)
	_t.check("%s: the reloaded brick still reports a sign" % fid, back.has_sign(paint_cell))
	_t.check("%s: the reloaded brick still reports a light" % fid, back.has_light(paint_cell))

	var name_cell: Vector3i = ctx.get("name_cell")
	_t.equal(
		"%s: the vessel's painted name survives" % fid,
		str(back.get_brick(name_cell).get("text", "")), NAME_TEXT,
	)

	## `occupied_by` is what makes a multi-cell brick one brick. Ask the accessor
	## that consumes it, not the raw field.
	var bench_cell: Vector3i = ctx.get("bench_cell")
	var filler := Vector3i(bench_cell.x + 1, bench_cell.y, bench_cell.z)
	_t.equal(
		"%s: the bench's footprint still walks back to one origin" % fid,
		back.primary_cell_of(filler), live.primary_cell_of(filler),
	)
	_t.equal(
		"%s: the same number of bricks survive as bricks, not filler" % fid,
		back.iter_primary_cells().size(), live.iter_primary_cells().size(),
	)
	## Keyed by cell, NOT index-by-index, and that is a measured decision rather
	## than a loosened assertion: `JSON.stringify` sorts dictionary keys, so a
	## refit brick appended after the shipped ones comes back sorted into place
	## and `iter_primary_cells()` returns the same rows in a different ORDER.
	## Nothing downstream reads that order, and asserting it would red on every
	## save for a reason that is not data loss.
	_t.check(
		"%s: what DeckFitout reads back is brick-for-brick what the editor built" % fid,
		_primaries_match(live, back),
	)

	_t.check(
		"%s: every bulk hold survives with its brick and yaw" % fid,
		PlayerData.json_equivalent(back.iter_bulk_holds(), live.iter_bulk_holds()),
	)
	_t.check(
		"%s: every container pad survives" % fid,
		PlayerData.json_equivalent(back.iter_container_pads(), live.iter_container_pads()),
	)
	_t.equal(
		"%s: reserved deck area survives" % fid,
		back.deck_cargo_cell_count(), live.deck_cargo_cell_count(),
	)

	var after := DeckFitout.compliance_for_layout(
		back.to_dict(), str(ctx.get("hull", "")), str(ctx.get("reg", "")), grid
	)
	_t.check(
		"%s: the reloaded vessel is still legally registered" % fid,
		bool(after.get("ok", false)),
	)

	## The durable per-vessel archive is the other half of the write
	## `PlayerSession.persist_vessel_configuration` performs.
	var saved := VesselArchive.save_record(_owner_id, row)
	_t.check("%s: the vessel archive accepts the refit" % fid, saved)
	if saved:
		_saved_uids.append(uid)
	var archived: Dictionary = {}
	for raw in VesselArchive.load_records(_owner_id):
		if typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("uid", "")) == uid:
			archived = raw as Dictionary
	if not _t.check("%s: the archive returns the refit by uid" % fid, not archived.is_empty()):
		_t.fail("%s: archive layout comparison never ran" % fid)
		return
	var from_archive := BrickLayout.from_dict(VesselSpawn.brick_layout_of(archived))
	_compare("%s: vessel archive" % fid, live, from_archive)


func _primaries_match(live: BrickLayout, back: BrickLayout) -> bool:
	var lm: Dictionary = {}
	for row in live.iter_primary_cells():
		lm[str((row as Dictionary).get("cell", ""))] = row
	var bm: Dictionary = {}
	for row in back.iter_primary_cells():
		bm[str((row as Dictionary).get("cell", ""))] = row
	if lm.size() != bm.size():
		return false
	for k in lm:
		if not bm.has(k) or not PlayerData.json_equivalent(lm[k], bm[k]):
			return false
	return true


## One check, not one per cell — but it cannot be diluted: a single differing
## field reds it, and the label names the first one so the failure is readable.
func _compare(label: String, live: BrickLayout, back: BrickLayout) -> void:
	var first := ""
	var diffs := 0
	for k in live.cells.keys():
		var le: Dictionary = live.cells[k]
		if not back.cells.has(k):
			diffs += 1
			if first.is_empty():
				first = "cell %s vanished" % k
			continue
		var be: Dictionary = back.cells[k]
		for f in le.keys():
			if not be.has(f):
				diffs += 1
				if first.is_empty():
					first = "cell %s lost '%s' (%s)" % [k, f, le[f]]
			elif not PlayerData.json_equivalent(le[f], be[f]):
				diffs += 1
				if first.is_empty():
					first = "cell %s '%s': %s became %s" % [k, f, le[f], be[f]]
		for f in be.keys():
			if not le.has(f):
				diffs += 1
				if first.is_empty():
					first = "cell %s gained '%s' = %s" % [k, f, be[f]]
	for k in back.cells.keys():
		if not live.cells.has(k):
			diffs += 1
			if first.is_empty():
				first = "cell %s appeared from nowhere" % k
	_t.check(
		"%s: every authored cell field survives (%s)" % [
			label, "0 differences" if diffs == 0 else "%d differences, first: %s" % [diffs, first],
		],
		diffs == 0,
	)


## ── deterministic placement helpers ─────────────────────────────────────────
func _place_first(
	layout: BrickLayout, grid: DeckGrid, brick_id: String, yaw: int, props: Dictionary
) -> Vector3i:
	for iz in range(grid.length):
		for ix in range(grid.width):
			var cell := Vector3i(ix, 0, iz)
			if layout.place_footprint(cell, brick_id, yaw, grid, props):
				return cell
	return Vector3i(-1, -1, -1)


func _add_first_hold(layout: BrickLayout, grid: DeckGrid) -> Vector3i:
	for iz in range(grid.length):
		for ix in range(grid.width):
			if layout.add_bulk_hold(Vector3i(ix, 0, iz), HOLD_BRICK, 0, grid):
				return Vector3i(ix, 0, iz)
	return Vector3i(-1, -1, -1)


func _add_first_pad(layout: BrickLayout, grid: DeckGrid) -> Vector3i:
	var fp := ContainerUnit.DEFAULT_FOOTPRINT
	for iz in range(grid.length):
		for ix in range(grid.width):
			var a := Vector3i(ix, 0, iz)
			var b := Vector3i(ix + fp.x - 1, 0, iz + fp.y - 1)
			if layout.add_container_pad(a, b, grid):
				return a
	return Vector3i(-1, -1, -1)
