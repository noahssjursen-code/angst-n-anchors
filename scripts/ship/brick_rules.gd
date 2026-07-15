class_name BrickRules
extends RefCounted

## Outfit validation for the shipyard. Hard fairness rules live in VesselOutfit;
## this remains the editor-facing entry point.


static func validate(
	layout: BrickLayout,
	grid: DeckGrid,
	_max_height: int = 0,
	_max_bricks: int = 0,
	registration_id: String = "",
) -> Dictionary:
	var hull_id := ""
	if layout != null:
		hull_id = str(layout.hull_id)
	var report := VesselCompliance.validate(layout, hull_id, registration_id, grid)
	## Preserve the historical shape editors expect.
	return {
		"ok": bool(report.get("ok", false)),
		"errors": report.get("errors", PackedStringArray()),
		"warnings": report.get("warnings", PackedStringArray()),
		"capabilities": report.get("capabilities", {}),
		"budget": report.get("budget", {}),
		"usage": report.get("usage", {}),
		"accepted_slots": report.get("accepted_slots", {}),
		"checklist": report.get("checklist", []),
		"registration_ok": report.get("registration_ok", false),
		"registration_id": registration_id,
	}
