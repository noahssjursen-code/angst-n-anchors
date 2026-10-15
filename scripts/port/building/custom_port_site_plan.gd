class_name CustomPortSitePlan
extends RefCounted

## Creates an empty workshop document from an indexed coast parcel. This is not
## a land purchase or ownership check; live authority must grant the chosen plot.
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const WORLD_POLICY = preload("res://scripts/port/building/custom_port_world_policy.gd")
const ORIGIN_GRID_M := 4.0


static func plan(plot_id: String, index: CoastalPlotIndex, world: Dictionary,
		port_id: String, owner: String, name: String) -> Dictionary:
	if port_id.strip_edges().is_empty() or owner.strip_edges().is_empty():
		return _failure("invalid_identity", "A harbour and its owner need an identity.")
	if index == null:
		return _failure("invalid_plot_index", "The coastline index is unavailable.")
	var expected := _canonical_world(world)
	if expected.is_empty():
		return _failure("invalid_world", "The world identity is incomplete or inconsistent.")
	var indexed_world := _canonical_world(index.world_identity)
	if indexed_world.is_empty():
		return _failure("invalid_plot_index", "The coastline index has no valid world identity.")
	if expected != indexed_world:
		return _failure("world_mismatch", "This coastline belongs to a different world.")
	if world.has("world_size_m") and (not _finite_number(world.world_size_m)
			or float(world.world_size_m) != float(index.world_identity.get("world_size_m", -1.0))):
		return _failure("world_mismatch", "The coastline world size does not match.")
	# Boundaries are always looked up here. No supplied rectangle is accepted.
	var plot := index.get_plot(plot_id)
	if plot.is_empty():
		return _failure("unknown_plot", "Choose a coastline plot from this world.")
	var bounds: Dictionary = plot.get("bounds", {})
	for key in ["x", "z", "size_m"]:
		if not _finite_number(bounds.get(key)):
			return _failure("invalid_plot_index", "The indexed plot has invalid bounds.")
	var size_m := float(bounds.size_m)
	if size_m <= 0.0:
		return _failure("invalid_plot_index", "The indexed plot has no area.")
	var origin_x := snappedf(float(bounds.x) + size_m * 0.5, ORIGIN_GRID_M)
	var origin_z := snappedf(float(bounds.z) + size_m * 0.5, ORIGIN_GRID_M)
	var deck_height := WORLD_POLICY.DECK_HEIGHT_ABOVE_SEA_M
	var deck_y := WaveSurface.WATER_LEVEL + deck_height
	var snapshot := {
		"schema_version": STATE.FORMAT_VERSION,
		"id": port_id,
		"name": name.strip_edges() if not name.strip_edges().is_empty() else "New harbour",
		"owner_company_id": owner,
		"world": indexed_world,
		"origin_m": [origin_x, deck_y, origin_z],
		"deck_height_above_sea_m": deck_height,
		"revision": 0,
		"plots": [{"id": plot.id, "owner_company_id": owner,
			"rect_m": [float(bounds.x) - origin_x, float(bounds.z) - origin_z, size_m, size_m]}],
		"placements": [], "stores": [], "vessels": [], "reservations": [],
		"receipts": {}, "water_regions": [],
	}
	var state := STATE.from_dict(snapshot, indexed_world)
	if not state.validation_errors.is_empty():
		return {"ok": false, "code": "invalid_document", "errors": state.validation_errors.duplicate()}
	var result := {"ok": true, "code": "planned", "snapshot": state.to_dict(), "plot": plot}
	# The weighted shoreline centroid is a camera hint, never a walkable spawn.
	var anchor: Variant = plot.get("shore_anchor")
	if anchor is Array and anchor.size() == 2 and _finite_number(anchor[0]) and _finite_number(anchor[1]):
		result.shore_anchor_m = [float(anchor[0]), deck_y, float(anchor[1])]
	return result


static func _canonical_world(value: Dictionary) -> Dictionary:
	for key in ["seed", "generation_version"]:
		if not _finite_number(value.get(key)) or float(value[key]) != floorf(float(value[key])):
			return {}
	var checksum: Variant = value.get("checksum", value.get("layout_checksum"))
	if not checksum is String or checksum.strip_edges().is_empty():
		return {}
	if value.has("layout_checksum") and value.layout_checksum != checksum:
		return {}
	# JSON decoding turns integers into floats. Canonical identity deliberately
	# contains the three world keys used by CustomPortState, not index metadata.
	return {"seed": float(value.seed), "generation_version": float(value.generation_version), "checksum": checksum}


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "errors": [message]}
