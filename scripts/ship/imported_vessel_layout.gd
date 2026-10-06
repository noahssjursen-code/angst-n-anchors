class_name ImportedVesselLayout
extends RefCounted

## Versioned model placements travel in the existing owned-record brick_layout
## field, including captain saves, the company ledger and network JSON.
static func empty(hull_id: String) -> Dictionary:
	return {"format":"imported_models", "version":1, "hull":hull_id, "hull_id":hull_id, "parts":[], "hull_colors":{}}

static func is_imported(layout: Dictionary) -> bool:
	return layout.get("format", "") == "imported_models"

static func valid(layout: Dictionary, hull_id: String, require_helm: bool = false) -> bool:
	if not is_imported(layout) or layout.get("hull") != hull_id or layout.get("hull_id") != hull_id:
		return false
	if not ImportedShipPartsEditor.valid_draft(layout): return false
	return not require_helm or has_capability(layout, "helm")

static func has_capability(layout: Dictionary, capability: String) -> bool:
	var ids: Array[String] = []
	for part: Dictionary in layout.get("parts", []): ids.append(str(part.get("asset_id", "")))
	match capability:
		"helm": return ids.has("helm_chair") and ids.has("helm_wheel") and ids.has("helm_throttle")
		"fishing": return ids.has("trawl_winch") and ids.has("insulated_catch_tank")
		"cargo": return ids.has("container_bed_20ft") or ids.has("cargo_securing_bed_4m") or ids.has("bulk_divider_5m") or ids.has("hold_coaming_6x12")
		"cabin": return ids.has("cabin_door_straight")
	return false
