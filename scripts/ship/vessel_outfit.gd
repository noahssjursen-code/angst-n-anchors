class_name VesselOutfit
extends RefCounted

## Fair ship contract: hull size → outfit budget → validated slot fill.
## DeckFitout mounts only accepted slots. Same rules for store ships and UGC.

const MAX_FISHING := 1
const MAX_HELM := 1
const MAX_CRANE := 0
const MAX_TOW := 0
## Cargo may use this fraction of exposed full deck cells (y = 0).
const CARGO_DECK_FRACTION := 0.55


static func budget_for_hull(hull_id: String, policy_caps: Dictionary = {}) -> Dictionary:
	var id := HullRegistry.resolve_network_hull_id(hull_id)
	var entry := HullRegistry.get_by_id(id)
	var grid := HullRegistry.make_grid(id)
	var exposed := _exposed_deck_cells(grid)
	var cargo_max := maxi(1, int(floor(float(exposed) * CARGO_DECK_FRACTION)))
	## Optional per-hull overrides from catalog / registry entry.
	if entry.has("outfit_cargo_cells"):
		cargo_max = maxi(0, int(entry.get("outfit_cargo_cells", cargo_max)))
	if entry.has("max_cargo_cells"):
		cargo_max = maxi(0, int(entry.get("max_cargo_cells", cargo_max)))
	var fishing_max := MAX_FISHING
	if entry.has("outfit_fishing"):
		fishing_max = maxi(0, int(entry.get("outfit_fishing", fishing_max)))
	var helm_max := MAX_HELM
	if entry.has("outfit_helm"):
		helm_max = maxi(0, int(entry.get("outfit_helm", helm_max)))
	var crane_max := MAX_CRANE
	if entry.has("outfit_crane"):
		crane_max = maxi(0, int(entry.get("outfit_crane", crane_max)))
	var tow_max := MAX_TOW
	if entry.has("outfit_tow"):
		tow_max = maxi(0, int(entry.get("outfit_tow", tow_max)))
	var budget := {
		"hull_id": id,
		"fishing": fishing_max,
		"helm": helm_max,
		"cargo_cells": cargo_max,
		"crane": crane_max,
		"tow": tow_max,
		"exposed_deck_cells": exposed,
	}
	## Registration law may tighten a hull limit, but never enlarge it.
	for key in ["fishing", "helm", "cargo_cells", "crane", "tow"]:
		if policy_caps.has(key):
			budget[key] = mini(int(budget.get(key, 0)), maxi(int(policy_caps[key]), 0))
	return budget


static func validate(
	layout: BrickLayout,
	hull_id: String,
	grid: DeckGrid = null,
	policy_caps: Dictionary = {},
) -> Dictionary:
	## Returns { ok, errors, warnings, budget, usage, accepted_slots, capabilities }.
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	var id := HullRegistry.resolve_network_hull_id(
		hull_id if not hull_id.is_empty() else str(layout.hull_id if layout != null else "")
	)
	var budget := budget_for_hull(id, policy_caps)
	var g := grid
	if g == null:
		g = HullRegistry.make_grid(id)
	if layout == null:
		return _result(true, errors, warnings, budget, {}, {}, {})

	var fishing_cells: Array[Vector3i] = []
	var helm_cells: Array[Vector3i] = []
	var crane_cells: Array[Vector3i] = []
	var tow_cells: Array[Vector3i] = []
	var door_n := 0
	var window_n := 0
	var brick_n := layout.count()
	var max_y := 0

	## THE ONE WALK that asks whether a brick is on the deck. Everything
	## downstream — the slot budgets, `accepted_slots`, `capabilities`, and
	## `VesselCompliance._measure`'s registration counts — consumes the result of
	## this loop rather than re-deriving it (REALITY.md §3b).
	##
	## This loop used to take `grid` and ask it nothing about bricks. That is how
	## a layout with all eight `general_vessel` bricks authored for a 20 x 56 hull
	## and written onto a 10 x 30 one reported `ok=true, errors []`: an off-deck
	## helm filled the helm slot, so `has_helm` was true and the helm requirement
	## was met by a helm in the sea.
	var off_grid: Array = []
	## The bricks this walk ACCEPTED, handed to `BrickShellClassifier.enclosure`
	## below so it floods exactly what the fit-out will build without re-running
	## `cell_on_grid` over the whole layout to find out. The classifier's own
	## header prices that re-derivation at 25%.
	##
	## THIS IS A COST CHOICE, NOT A CORRECTNESS ONE, and that is measured rather
	## than assumed: dropping the argument and letting `enclosure` re-filter left
	## `brick_enclosure_test` at PASS (59 checks), including the case that builds
	## a sealed cabin on a bigger hull and judges it against this one. The
	## classifier applies the SAME `BrickLayout.cell_on_grid` predicate when it is
	## handed no list, so a cabin in the sea is refused either way. Said plainly
	## so the next reader does not believe this line is what keeps that honest.
	var on_deck_items: Array = []
	for item in layout.iter_primary_cells():
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		if not BrickCatalog.has(brick_id):
			continue
		## An unknown brick id is not a PLACEMENT fault — the catalogue is the
		## authority there and has always ignored it — so the order matters.
		if not BrickLayout.cell_on_grid(g, cell, brick_id, int(item.get("yaw", 0))):
			off_grid.append({"cell": cell, "brick_id": brick_id})
			continue
		on_deck_items.append(item)
		max_y = maxi(max_y, cell.y + BrickCatalog.footprint_of(brick_id).y - 1)
		if BrickCatalog.has_tag(brick_id, "fishing") or BrickCatalog.has_tag(brick_id, "trommel"):
			fishing_cells.append(cell)
		if BrickCatalog.has_tag(brick_id, "helm"):
			helm_cells.append(cell)
		if BrickCatalog.has_tag(brick_id, "crane"):
			crane_cells.append(cell)
		if BrickCatalog.has_tag(brick_id, "tow"):
			tow_cells.append(cell)
		if BrickCatalog.has_tag(brick_id, "door"):
			door_n += 1
		## The `wall` / `solid` tally that stood here fed nothing but the old
		## `wall_n >= 8` cabin rule, and it is gone with it rather than left as a
		## counter the next reader assumes something reads (REALITY.md §3d).
		if BrickCatalog.has_tag(brick_id, "window"):
			window_n += 1

	if not off_grid.is_empty():
		errors.append(_off_grid_error(off_grid, g))

	var accepted_fishing: Array[Vector3i] = []
	var accepted_helm: Array[Vector3i] = []
	var accepted_crane: Array[Vector3i] = []
	var accepted_tow: Array[Vector3i] = []
	_take_slots(fishing_cells, int(budget.get("fishing", 0)), accepted_fishing, errors, "Fishing")
	_take_slots(helm_cells, int(budget.get("helm", 0)), accepted_helm, errors, "Helm")
	_take_slots(crane_cells, int(budget.get("crane", 0)), accepted_crane, errors, "Crane")
	_take_slots(tow_cells, int(budget.get("tow", 0)), accepted_tow, errors, "Tow gear")

	var cargo_used := 0
	var cargo_max := int(budget.get("cargo_cells", 0))
	var accepted_pad_indices: Array[int] = []
	var accepted_bulk_indices: Array[int] = []
	var pad_i := 0
	for pad_raw in layout.iter_container_pads():
		var pad := pad_raw as Dictionary
		var mn := BrickLayout.zone_min(pad)
		var mx := BrickLayout.zone_max(pad)
		if mn.y != 0 or mx.y != 0:
			errors.append(
				"Container pad %d must sit on the exposed deck (y = 0)."
				% (pad_i + 1)
			)
			pad_i += 1
			continue
		var cells_n := BrickLayout.zone_cell_count(pad)
		var span_x := mx.x - mn.x + 1
		var span_z := mx.z - mn.z + 1
		var fp := ContainerUnit.DEFAULT_FOOTPRINT
		if (span_x % fp.x) != 0 or (span_z % fp.y) != 0 or (cells_n % (fp.x * fp.y)) != 0:
			errors.append(
				"Container pad %d must tile %d×%d m slots (%d cells, got %d×%d)."
				% [pad_i + 1, fp.x, fp.y, cells_n, span_x, span_z]
			)
			pad_i += 1
			continue
		var invalid := false
		for ix in range(mn.x, mx.x + 1):
			for iz in range(mn.z, mx.z + 1):
				var c := Vector3i(ix, 0, iz)
				if not g.has_deck_cell(c):
					invalid = true
					break
			if invalid:
				break
		if invalid:
			errors.append("Container pad %d covers cells outside the exposed deck." % (pad_i + 1))
			pad_i += 1
			continue
		if cargo_used + cells_n > cargo_max:
			errors.append(
				"Cargo exceeds hull budget (%d / %d cells). Shrink or remove pads/holds."
				% [cargo_used + cells_n, cargo_max]
			)
			pad_i += 1
			continue
		accepted_pad_indices.append(pad_i)
		cargo_used += cells_n
		pad_i += 1
	var hold_i := 0
	for hold_raw in layout.iter_bulk_holds():
		var hold := hold_raw as Dictionary
		var mn := BrickLayout.zone_min(hold)
		var mx := BrickLayout.zone_max(hold)
		if mn.y != 0 or mx.y != 0:
			errors.append(
				"Bulk hold %d must sit on the exposed deck (y = 0), not layered/hidden holds."
				% (hold_i + 1)
			)
			hold_i += 1
			continue
		var cells_n := BrickLayout.zone_cell_count(hold)
		var invalid := false
		for ix in range(mn.x, mx.x + 1):
			for iz in range(mn.z, mx.z + 1):
				var c := Vector3i(ix, 0, iz)
				if not g.has_deck_cell(c):
					invalid = true
					break
			if invalid:
				break
		if invalid:
			errors.append("Bulk hold %d covers cells outside the exposed deck." % (hold_i + 1))
			hold_i += 1
			continue
		if cargo_used + cells_n > cargo_max:
			errors.append(
				"Cargo exceeds hull budget (%d / %d cells). Shrink or remove holds."
				% [cargo_used + cells_n, cargo_max]
			)
			hold_i += 1
			continue
		accepted_bulk_indices.append(hold_i)
		cargo_used += cells_n
		hold_i += 1

	var usage := {
		"fishing": fishing_cells.size(),
		"helm": helm_cells.size(),
		"cargo_cells": layout.deck_cargo_cell_count(),
		"crane": crane_cells.size(),
		"tow": tow_cells.size(),
		"accepted_cargo_cells": cargo_used,
	}
	var accepted_slots := {
		"fishing": accepted_fishing,
		"helm": accepted_helm,
		"crane": accepted_crane,
		"tow": accepted_tow,
		"container_pad_indices": accepted_pad_indices,
		"cargo_zone_indices": [],
		"bulk_hold_indices": accepted_bulk_indices,
	}
	## ── THE CABIN IS MEASURED OFF THE BUILD, and it used to be counted ────────
	##
	## This was `door_n >= 1 or wall_n >= 8` — a count of brick IDS that asked
	## nothing about shape. Measured through this function before the change
	## (`tests/_brick_cabin_probe.gd`, hull_28x10):
	##
	##     8 `block` bricks in a STRAIGHT LINE on the deck   has_cabin true
	##     ONE `block_door` standing alone on the deck       has_cabin true
	##
	## and the second of those put `passenger_vessel/cabin` on the registration
	## checklist as *"Enclosed passenger accommodation: required (current: true)"*
	## — a licence to carry people, granted for one door brick lying on a bare
	## deck. Nothing pinned it: `plan_outfit.gd`'s header claimed
	## `plan_compliance_test` did, and that test pins the PLAN side of the same
	## question (REALITY.md §4d — a citation is not a verification).
	##
	## `BrickShellClassifier.enclosure` answers it off the geometry instead: a
	## pocket of air the exterior flood never reaches, with a door brick against
	## it. (The plan path's third clause, a floor under it, is not a clause on the
	## voxel grid — it FOLLOWS from enclosure, proved and mutation-measured in
	## `_read_pocket`'s header.) Two recorded blockers stood in front of this and
	## NEITHER SURVIVED BEING CHECKED (both re-measured 2026-08-16):
	##
	##  1. *"The classifier publishes bricks, not air."* True of what it RETURNED
	##     and false of what it KNEW. `_flood_exterior_air` already visits every
	##     air cell the sky reaches; the enclosed air is the complement inside the
	##     same bounds, and on the hollow 5x5x3 cabin that complement is exactly
	##     the 27 cells the old note said "appear nowhere". No new flood, no
	##     second derivation — `_solid_field` builds the field once and both
	##     readings run on it (REALITY.md §3d: a value computed and discarded).
	##
	##  2. *"A brick cell has no agreed metre size."* Real, and NOT ON THIS PATH.
	##     The factor of two is between `BuildingGrid.CELL_M` (1.0) and
	##     `BrickCatalog.size_m` (0.5) — and `BuildingGrid` is the LAND blueprint
	##     lattice in `scripts/port/`, with zero references from `scripts/ship/`.
	##     A vessel brick is positioned by `DeckGrid.cell_center_local`, which
	##     steps `DeckGrid.CELL_M` = 0.5, and drawn at `BrickCatalog.size_m`,
	##     which is that same 0.5: on a boat the lattice and the brick AGREE.
	##     The open decision is whether 0.5 m is the right brick, not which of two
	##     numbers this path is using.
	##
	## SO WHY IS THE READING STILL SCALE-FREE HERE. Because the answer that does
	## not move when that product decision is settled is worth more than the
	## stricter one that does. `enclosure` is asked for the TOPOLOGY — enclosed,
	## with a way in — and NOT for the 1.8 m / 1.2 m² bars, which are the only
	## clauses that need a metre size. Both defects above are false under every
	## reading, so closing them never needed the decision, and
	## `brick_enclosure_test` asserts BOTH halves of that: the published verdict
	## is identical at 0.5 m and at 1.0 m on five fixtures, and the three-course
	## cabin — the one fixture whose answer the metre size really does decide —
	## is named with the figures either way.
	##
	## ── WHO READS THIS, AND HOW FAR THE OLD WRONG YES COULD TRAVEL ────────────
	##
	## Grepped and traced 2026-08-16, because the severity of a wrong capability
	## is decided by its consumers and not by how wrong it is (REALITY.md §3d).
	##
	##   `passenger_vessel/cabin` in `resources/data/vessels/registrations/catalog.json`
	##     is THE ONLY RULE IN THE CATALOGUE THAT NAMES `has_cabin`. Through
	##     `VesselCompliance` it sets `registration_ok`, hence `report.ok`, which
	##     gates real player paths: `VesselSpawn.resolve_deployable_record` (the
	##     harbour master's "deploy fleet vessel"), `PlayerSession.persist_vessel_configuration`
	##     (saving a vessel), `ShipwrightNPC._on_commission_requested`, and
	##     `PrebuiltVesselCatalog`'s `compliance_ok` / `is_draft`.
	##   BUT NOTHING THE SHIPPED GAME PRODUCES IS A BRICK-BUILT PASSENGER VESSEL.
	##     All four presets in `resources/data/vessels/prebuilt/` are
	##     cargo/bulk/fishing, the starter grant hands out those same presets, and
	##     the only code that selects `passenger_vessel` is `structure_studio.gd`,
	##     which authors `structure_plan_v1` and is judged by `PlanOutfit`, not by
	##     this function.
	##   `ShipyardBrickEditor` (`:3066`, "Cabin: yes") has the registration picker
	##     that CAN choose `passenger_vessel`, and `open_for_hull` /
	##     `open_for_authoring` have no callers outside that file and its scene is
	##     instantiated nowhere — it is a standalone engine tool. That is not
	##     harmless: in authoring mode `report.ok` is what decides whether
	##     `_on_dev_save_prebuilt` writes an OFFICIAL preset or a draft, and an
	##     official preset is exactly what the shipwright sells and the starter
	##     grant gives away. The wrong yes could not reach a player by itself; it
	##     could get a fake cabin stamped official by someone using the tool.
	##   `HullRegistry.record_has_capability("cabin")` reads it and HAS NO CALLERS
	##     at all (its own header says so; re-grepped, still true).
	##
	## So: a live gate on a player path, reachable only through a registration
	## nothing in the game currently assigns to a brick layout. Named as measured
	## rather than as "harmless" or "critical".
	##
	## WHAT THE SCALE-FREE VERDICT COSTS, stated because it is a real gap: a
	## pocket ONE CELL tall and one cell square, with a door beside it, still
	## reads as a cabin. That is 0.5 m or 1.0 m of headroom, and neither is
	## accommodation. It is a strictly smaller class of wrong answer than the rule
	## it replaces — which needed no pocket at all — and the cell counts are
	## published below so a licence can put a bar on them the day there is one.
	var enclosed := BrickShellClassifier.enclosure(layout, g, 0.0, on_deck_items)
	var caps := {
		"cargo_cells": cargo_used,
		"cargo_budget": cargo_max,
		"exposed_deck_cells": int(budget.get("exposed_deck_cells", 0)),
		"has_cabin": bool(enclosed.get("cabin", false)),
		"has_helm": accepted_helm.size() >= 1,
		"has_crane": accepted_crane.size() >= 1,
		"has_fishing": accepted_fishing.size() >= 1,
		"has_tow": accepted_tow.size() >= 1,
		"doors": door_n,
		"windows": window_n,
		"helms": accepted_helm.size(),
		"brick_count": brick_n,
		"max_stack_y": max_y,
		## The enclosure numbers, in CELLS, so nothing here states a metre size.
		## `cabins` is the count of pockets that pass; `cabin_floor_cells` and
		## `cabin_headroom_cells` are the largest one's plan footprint and tallest
		## vertical run. A `metric_range` rule can name any of them, and the day
		## the brick cell is settled they are what a 1.8 m / 1.2 m² bar is applied
		## to. `PlanOutfit` publishes `cabins` / `cabin_area_m2` / `cabin_why` on
		## its side; `cabin_area_m2` has no honest brick value yet and is
		## deliberately absent rather than present and zero.
		"cabins": int(enclosed.get("cabins", 0)),
		"cabin_floor_cells": int(enclosed.get("floor_cells", 0)),
		"cabin_headroom_cells": int(enclosed.get("headroom_cells", 0)),
		"cabin_why": str(enclosed.get("why", "")),
	}
	var report := _result(errors.is_empty(), errors, warnings, budget, usage, accepted_slots, caps)
	## The cells this walk refused, so `VesselCompliance._measure` skips exactly
	## the same bricks without asking the predicate a second time.
	report["off_grid"] = off_grid
	return report


## One sentence a player can act on: how many, which, and where they should be.
## Capped, so a 300-brick layout pasted onto the wrong hull does not produce a
## 300-line error nobody reads — but the COUNT is always the true count.
static func _off_grid_error(off_grid: Array, grid: DeckGrid) -> String:
	var shown: Array[String] = []
	for i in range(mini(off_grid.size(), 4)):
		var row := off_grid[i] as Dictionary
		shown.append(BrickLayout.off_grid_reason(
			grid, row.get("cell", Vector3i.ZERO) as Vector3i, str(row.get("brick_id", ""))
		))
	var tail := ""
	if off_grid.size() > shown.size():
		tail = " (+%d more)" % (off_grid.size() - shown.size())
	return "%d %s off the deck and %s not fitted: %s%s" % [
		off_grid.size(),
		"brick sits" if off_grid.size() == 1 else "bricks sit",
		"is" if off_grid.size() == 1 else "are",
		" · ".join(shown),
		tail,
	]


static func budget_summary(budget: Dictionary, usage: Dictionary) -> String:
	return "Fishing %d/%d · Cargo %d/%d · Helm %d/%d" % [
		int(usage.get("fishing", 0)),
		int(budget.get("fishing", 0)),
		int(usage.get("cargo_cells", 0)),
		int(budget.get("cargo_cells", 0)),
		int(usage.get("helm", 0)),
		int(budget.get("helm", 0)),
	]


static func _exposed_deck_cells(grid: DeckGrid) -> int:
	if grid == null:
		return 1
	var n := 0
	for ix in range(grid.width):
		for iz in range(grid.length):
			if grid.cell_shape(ix, iz) == DeckGrid.CellShape.FULL:
				n += 1
	return maxi(n, 1)


static func _take_slots(
	candidates: Array[Vector3i],
	max_n: int,
	accepted: Array[Vector3i],
	errors: PackedStringArray,
	label: String,
) -> void:
	for i in range(candidates.size()):
		if accepted.size() < max_n:
			accepted.append(candidates[i])
		else:
			errors.append(
				"%s exceeds hull budget (%d / %d). Remove extras — only accepted mounts go live."
				% [label, candidates.size(), max_n]
			)
			return


static func _result(
	ok: bool,
	errors: PackedStringArray,
	warnings: PackedStringArray,
	budget: Dictionary,
	usage: Dictionary,
	accepted_slots: Dictionary,
	capabilities: Dictionary,
) -> Dictionary:
	return {
		"ok": ok,
		"errors": errors,
		"warnings": warnings,
		"budget": budget,
		"usage": usage,
		"accepted_slots": accepted_slots,
		"capabilities": capabilities,
	}
