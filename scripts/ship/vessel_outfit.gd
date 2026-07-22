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
	var wall_n := 0
	var window_n := 0
	var brick_n := layout.count()
	var max_y := 0

	for item in layout.iter_primary_cells():
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		if not BrickCatalog.has(brick_id):
			continue
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
		if BrickCatalog.has_tag(brick_id, "wall") or BrickCatalog.has_tag(brick_id, "solid"):
			wall_n += 1
		if BrickCatalog.has_tag(brick_id, "window"):
			window_n += 1

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
	var caps := {
		"cargo_cells": cargo_used,
		"cargo_budget": cargo_max,
		"exposed_deck_cells": int(budget.get("exposed_deck_cells", 0)),
		"has_cabin": door_n >= 1 or wall_n >= 8,
		"has_helm": accepted_helm.size() >= 1,
		"has_crane": accepted_crane.size() >= 1,
		"has_fishing": accepted_fishing.size() >= 1,
		"has_tow": accepted_tow.size() >= 1,
		"doors": door_n,
		"windows": window_n,
		"helms": accepted_helm.size(),
		"brick_count": brick_n,
		"max_stack_y": max_y,
	}
	return _result(errors.is_empty(), errors, warnings, budget, usage, accepted_slots, caps)


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
