class_name PlayerData

## Pure data object — no Node, no signals.
## Holds everything that belongs to one player account.
## Serialises cleanly to/from a Dictionary so a future DB layer
## can hydrate or persist it without touching any other game code.

var account_id:   String = ""       # set by auth layer when accounts arrive
var display_name: String = "Captain"
var marks:        int    = 0
var appearance:   CharacterAppearance = CharacterAppearance.default_appearance()

## Lifetime stats — useful for profiles and leaderboards later.
var total_marks_earned:  int   = 0
var contracts_completed: int   = 0
var distance_sailed_m:   float = 0.0
## Ledger record for the captain's single vessel (template on disk).
## { "uid", "hull_id", "display", "template_path" } — empty when none.
var active_vessel: Dictionary = {}


func owns_hull_id(hull_id: String) -> bool:
	return not active_vessel.is_empty() and str(active_vessel.get("hull_id", "")) == hull_id


func set_active_vessel(record: Dictionary) -> void:
	if typeof(record) != TYPE_DICTIONARY:
		active_vessel = {}
		return
	active_vessel = record.duplicate()


func get_active_vessel_record() -> Dictionary:
	return active_vessel.duplicate() if not active_vessel.is_empty() else {}


func has_active_vessel_record() -> bool:
	return not active_vessel.is_empty()


func repair_save_consistency() -> void:
	# Legacy saves used owned_vessels[] — keep the last entry as the active hull.
	pass


func to_dict() -> Dictionary:
	return {
		"account_id":               account_id,
		"display_name":             display_name,
		"marks":                    marks,
		"total_marks_earned":       total_marks_earned,
		"contracts_completed":      contracts_completed,
		"distance_sailed_m":        distance_sailed_m,
		"active_vessel":            active_vessel.duplicate(),
		"appearance":               appearance.to_dict(),
	}


static func from_dict(d: Dictionary) -> PlayerData:
	var pd                  := PlayerData.new()
	pd.account_id           = str(d.get("account_id",          ""))
	pd.display_name         = str(d.get("display_name",        "Captain"))
	pd.marks                = int(d.get("marks",               0))
	pd.total_marks_earned   = int(d.get("total_marks_earned",  0))
	pd.contracts_completed  = int(d.get("contracts_completed", 0))
	pd.distance_sailed_m         = float(d.get("distance_sailed_m", 0.0))
	var active_raw: Variant = d.get("active_vessel", {})
	if typeof(active_raw) == TYPE_DICTIONARY and not (active_raw as Dictionary).is_empty():
		pd.active_vessel = (active_raw as Dictionary).duplicate()
	else:
		var owned_raw: Variant = d.get("owned_vessels", [])
		if typeof(owned_raw) == TYPE_ARRAY:
			var owned_arr: Array = owned_raw as Array
			if not owned_arr.is_empty():
				var last_entry: Variant = owned_arr[owned_arr.size() - 1]
				if typeof(last_entry) == TYPE_DICTIONARY:
					pd.active_vessel = (last_entry as Dictionary).duplicate()
	pd.appearance = CharacterAppearance.from_dict(d.get("appearance", {}) as Dictionary)
	return pd
