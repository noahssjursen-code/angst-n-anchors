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

# ── Save format v2 additions (introduced Phase 4 of the overnight refactor) ──
##
## Snapshot of accepted contracts. Each entry: { "id", "taken_count",
## "delivered_count" }. On load, ContractRegistry replays the accept then sets
## counts. Any in-transit units (`taken > delivered`) are treated as forfeit
## (rolled back to taken=delivered) so the world stays consistent — the
## player loses cargo that was in their hold on quit, which matches the
## existing "ship despawn forfeits cargo" rule.
var accepted_contracts: Array = []

## Runtime state of the captain's ship for resume-where-you-left-off saves.
## { "world_pos": Vector3, "yaw": float, "throttle_stage_idx": int }.
## Empty when no ship is in the world at save time.
var ship_runtime_state: Dictionary = {}

## Game time at save (game-hours since the world epoch). Restored to
## WorldClock on load so day/night picks up where it left off instead of
## resetting to noon.
var world_clock_hours: float = -1.0


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
		# v2 additions
		"accepted_contracts":       accepted_contracts.duplicate(true),
		"ship_runtime_state":       _ship_runtime_to_dict(),
		"world_clock_hours":        world_clock_hours,
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
	# v2 additions — default to empty / sentinel for v1 saves (forward compat).
	var contracts_raw: Variant = d.get("accepted_contracts", [])
	if typeof(contracts_raw) == TYPE_ARRAY:
		pd.accepted_contracts = (contracts_raw as Array).duplicate(true)
	var ship_raw: Variant = d.get("ship_runtime_state", {})
	if typeof(ship_raw) == TYPE_DICTIONARY:
		pd.ship_runtime_state = _ship_runtime_from_dict(ship_raw as Dictionary)
	pd.world_clock_hours = float(d.get("world_clock_hours", -1.0))
	return pd


# ── v2 helpers ───────────────────────────────────────────────────────────────

func _ship_runtime_to_dict() -> Dictionary:
	if ship_runtime_state.is_empty():
		return {}
	var pos: Variant = ship_runtime_state.get("world_pos", Vector3.ZERO)
	if typeof(pos) == TYPE_VECTOR3:
		var v: Vector3 = pos
		return {
			"world_pos":          [v.x, v.y, v.z],
			"yaw":                float(ship_runtime_state.get("yaw", 0.0)),
			"throttle_stage_idx": int(ship_runtime_state.get("throttle_stage_idx", 1)),
		}
	# Already serialised form.
	return ship_runtime_state.duplicate()


static func _ship_runtime_from_dict(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var pos_raw: Variant = d.get("world_pos", null)
	var pos := Vector3.ZERO
	if typeof(pos_raw) == TYPE_ARRAY and (pos_raw as Array).size() >= 3:
		var arr := pos_raw as Array
		pos = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return {
		"world_pos":          pos,
		"yaw":                float(d.get("yaw", 0.0)),
		"throttle_stage_idx": int(d.get("throttle_stage_idx", 1)),
	}
