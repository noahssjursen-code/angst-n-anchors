class_name ShipData
extends RefCounted

## `hull_health` and `fuel` lived here too, set to 1.0 by
## `GameState._on_helm_on` and read by nothing — deleted 2026-08-16 with their
## `ShipState` twins. `BoatBody` owns fuel; nothing owns hull condition.
##
## `to_dict` / `from_dict` have NO CALLER outside this file: a captain's save
## carries no vessel runtime state at all (`SAVE_FORMAT.md` — "New saves omit
## `ship_runtime_state`", and `PlayerSession`, `LocalPlayerView` and
## `harbour_master_npc` all clear it), so this record is built fresh at every
## helm-on and thrown away at helm-off. They are left standing rather than
## deleted because the round trip is correct and costs nothing; they are named
## here so nobody reads them as evidence that a ship is persisted.
var ship_id:      String       = ""
var display_name: String       = "Unnamed Vessel"


func to_dict() -> Dictionary:
	return {
		"ship_id":      ship_id,
		"display_name": display_name,
	}


static func from_dict(d: Dictionary) -> ShipData:
	var s          := ShipData.new()
	s.ship_id      = str(d.get("ship_id",      ""))
	s.display_name = str(d.get("display_name", "Unnamed Vessel"))
	return s
