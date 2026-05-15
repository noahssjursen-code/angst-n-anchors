class_name PlayerData

## Pure data object — no Node, no signals.
## Holds everything that belongs to one player account.
## Serialises cleanly to/from a Dictionary so a future DB layer
## can hydrate or persist it without touching any other game code.

var account_id:   String = ""       # set by auth layer when accounts arrive
var display_name: String = "Captain"
var marks:        int    = 0

## Lifetime stats — useful for profiles and leaderboards later.
var total_marks_earned:  int   = 0
var contracts_completed: int   = 0
var distance_sailed_m:   float = 0.0


func to_dict() -> Dictionary:
	return {
		"account_id":          account_id,
		"display_name":        display_name,
		"marks":               marks,
		"total_marks_earned":  total_marks_earned,
		"contracts_completed": contracts_completed,
		"distance_sailed_m":   distance_sailed_m,
	}


static func from_dict(d: Dictionary) -> PlayerData:
	var pd                  := PlayerData.new()
	pd.account_id           = str(d.get("account_id",          ""))
	pd.display_name         = str(d.get("display_name",        "Captain"))
	pd.marks                = int(d.get("marks",               0))
	pd.total_marks_earned   = int(d.get("total_marks_earned",  0))
	pd.contracts_completed  = int(d.get("contracts_completed", 0))
	pd.distance_sailed_m    = float(d.get("distance_sailed_m", 0.0))
	return pd
