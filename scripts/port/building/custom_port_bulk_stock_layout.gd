extends RefCounted
## Deterministic visual bays within an installed receiving pad. Lots retain
## their authority identities; only equal commodities share a visible heap.
## Catalog commodities reserve stable spaces even while a bay is empty.

static func project(store: Dictionary, pad_size: Vector2, catalog_commodities: Array = []) -> Dictionary:
	var commodities: Array[String] = []
	for raw in catalog_commodities + store.get("accepted_commodities", []):
		var id := str(raw)
		if not id.is_empty() and not commodities.has(id): commodities.append(id)
	for lot in store.get("lots", []):
		if CustomPortState._handling_mode(lot) != "bulk": continue
		var id := str(lot.commodity_id)
		if not commodities.has(id): commodities.append(id)
	commodities.sort()
	var result := {}
	if commodities.is_empty() or pad_size.x <= 0 or pad_size.y <= 0: return result
	var columns := clampi(ceili(sqrt(commodities.size() * pad_size.x / pad_size.y)), 1, commodities.size())
	var rows := ceili(float(commodities.size()) / columns)
	var cell := pad_size / Vector2(columns, rows)
	for index in commodities.size():
		var commodity := commodities[index]
		var center := -pad_size * .5 + cell * (Vector2(index % columns, index / columns) + Vector2(.5, .5))
		var mass := 0.0
		var lot_ids: Array[String] = []
		for lot in store.get("lots", []):
			if str(lot.commodity_id) != commodity or CustomPortState._handling_mode(lot) != "bulk": continue
			mass += float(lot.quantity) * float(lot.unit_mass_kg)
			lot_ids.append(str(lot.id))
		lot_ids.sort()
		result[commodity] = {"position_m":Vector3(center.x,.05,center.y),
			"size_m":Vector3(cell.x*.72,4.5,cell.y*.72), "mass_kg":mass, "lot_ids":lot_ids,
			"bay_m":Rect2(center-cell*.5,cell)}
	return result


static func fill_scale(mass: float, capacity: float) -> Vector3:
	var ratio := clampf(mass / maxf(capacity, 1), 0, 1)
	return Vector3(pow(ratio, 1.0/3.0), pow(ratio, 2.0/3.0), pow(ratio, 1.0/3.0))
