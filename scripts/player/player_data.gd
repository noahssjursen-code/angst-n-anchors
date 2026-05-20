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
## True after the complimentary coastal trader has been commissioned once.
var shipwright_starter_used: bool = false
## Commissioned hulls the harbour master can bring alongside.
## Each entry: { "uid", "hull_id", "display", "template_path" }.
var owned_vessels: Array = []


func owns_hull_id(hull_id: String) -> bool:
	for raw in owned_vessels:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if str((raw as Dictionary).get("hull_id", "")) == hull_id:
			return true
	return false


func add_owned_vessel(record: Dictionary) -> void:
	owned_vessels.append(record)


func get_owned_vessel_records() -> Array:
	var out: Array = []
	for raw in owned_vessels:
		if typeof(raw) == TYPE_DICTIONARY:
			out.append((raw as Dictionary).duplicate())
	return out


func repair_save_consistency() -> void:
	# Older saves may have marked the starter used without recording ownership.
	if shipwright_starter_used and not owns_hull_id("coastal_trader"):
		shipwright_starter_used = false


func to_dict() -> Dictionary:
	return {
		"account_id":               account_id,
		"display_name":             display_name,
		"marks":                    marks,
		"total_marks_earned":       total_marks_earned,
		"contracts_completed":      contracts_completed,
		"distance_sailed_m":        distance_sailed_m,
		"shipwright_starter_used":  shipwright_starter_used,
		"owned_vessels":            owned_vessels.duplicate(),
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
	pd.shipwright_starter_used   = bool(d.get("shipwright_starter_used", false))
	var owned_raw: Variant = d.get("owned_vessels", [])
	if typeof(owned_raw) == TYPE_ARRAY:
		pd.owned_vessels = (owned_raw as Array).duplicate()
	pd.appearance = CharacterAppearance.from_dict(d.get("appearance", {}) as Dictionary)
	pd.repair_save_consistency()
	return pd
