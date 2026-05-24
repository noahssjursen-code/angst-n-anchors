class_name PlayerData

## Fictional ledger currency — shared by UI formatters and PlayerSession.
const CURRENCY_SYMBOL := "ℳ"
const CURRENCY_NAME   := "Marks"
const NEW_CAPTAIN_STARTING_MARKS := 6400


static func format_money(amount: int) -> String:
	return "%s %d" % [CURRENCY_SYMBOL, amount]


## Pure data object — no Node, no signals.
## Holds everything that belongs to one player account.
## Serialises cleanly to/from a Dictionary so a future DB layer
## can hydrate or persist it without touching any other game code.

var account_id:   String = ""       # set by auth layer when accounts arrive
var captain_id:   String = ""       # Postgres captain UUID when playing on MP server
var display_name: String = "Captain"
var marks:        int    = 0
var appearance:   CharacterAppearance = CharacterAppearance.default_appearance()

## Lifetime stats — useful for profiles and leaderboards later.
var total_marks_earned:  int   = 0
var contracts_completed: int   = 0
var distance_sailed_m:   float = 0.0
## Ledger records for every hull the captain owns.
## Each entry: { uid, hull_id, display, template_path, server_vessel_id?,
##   crew[], autonomous_active, autonomous_active_at, home_port_id,
##   visit_port_id?, expense_per_day, pending_earnings, last_collected_at,
##   last_accrual_at, sim_version }.
## See AutonomousVesselRecord for the canonical autonomous / NPC-sim shape.
var owned_vessels: Array = []
## Hull currently deployed in the world (must match one entry in owned_vessels).
var active_vessel: Dictionary = {}

const LEGACY_STARTER_TEMPLATE_PATH := "user://shipwright_orders/starter_cargo_ship.json"
const LEGACY_STARTER_HULL_ID := "cargo_ship"

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

## Tutorial hint chain — { hint_id: true } once a hint has fired. Persisted
## so a returning captain doesn't have to skip the same banners again.
var tutorial_seen: Dictionary = {}

## True after the captain commissions their one free small fishing trawler.
var starter_trawler_claimed: bool = false


func owns_hull_id(hull_id: String) -> bool:
	for entry_raw in owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		if str((entry_raw as Dictionary).get("hull_id", "")) == hull_id:
			return true
	return false


## Merge `patch` onto `existing` — keys in patch win; omitted fleet fields are kept.
## Prevents partial writes (deploy snapshot, crane earnings tick) from wiping routes.
static func merge_vessel_record(existing: Dictionary, patch: Dictionary) -> Dictionary:
	if existing.is_empty():
		return patch.duplicate(true)
	if patch.is_empty():
		return existing.duplicate(true)
	var merged := existing.duplicate(true)
	for key in patch:
		merged[key] = patch[key]
	return merged


func upsert_owned_vessel(record: Dictionary) -> void:
	if record.is_empty():
		return
	var uid := str(record.get("uid", ""))
	if uid.is_empty():
		return
	for i in range(owned_vessels.size()):
		var existing_raw: Variant = owned_vessels[i]
		if typeof(existing_raw) != TYPE_DICTIONARY:
			continue
		if str((existing_raw as Dictionary).get("uid", "")) == uid:
			owned_vessels[i] = merge_vessel_record(existing_raw as Dictionary, record)
			_mirror_active_vessel_from_owned(uid)
			return
	owned_vessels.append(record.duplicate(true))
	_mirror_active_vessel_from_owned(uid)


func _mirror_active_vessel_from_owned(uid: String) -> void:
	if str(active_vessel.get("uid", "")) != uid:
		return
	var fresh := find_owned_vessel(uid)
	if not fresh.is_empty():
		active_vessel = fresh


func find_owned_vessel(uid: String) -> Dictionary:
	for entry_raw in owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if str(entry.get("uid", "")) == uid:
			return entry.duplicate()
	return {}


func find_owned_by_server_id(server_id: String) -> Dictionary:
	if server_id.is_empty():
		return {}
	for entry_raw in owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if str(entry.get("server_vessel_id", "")) == server_id:
			return entry.duplicate()
	return {}


func get_harbour_vessel_records() -> Array:
	var out: Array = []
	for entry_raw in owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if is_legacy_starter_vessel(entry):
			continue
		var resolved := AutonomousVesselLoader.resolve_deployable_record(entry)
		if resolved.is_empty():
			continue
		out.append(resolved)
	return out


static func is_vessel_on_npc_run(record: Dictionary) -> bool:
	return bool(record.get("autonomous_active", false))


func get_deployable_vessels() -> Array:
	var out: Array = []
	for entry_raw in get_harbour_vessel_records():
		var entry := entry_raw as Dictionary
		if is_vessel_on_npc_run(entry):
			continue
		out.append(entry)
	return out


func set_active_vessel(record: Dictionary) -> void:
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		active_vessel = {}
		return
	var uid := str(record.get("uid", ""))
	var owned := find_owned_vessel(uid)
	var merged := merge_vessel_record(owned, record) if not owned.is_empty() else record.duplicate(true)
	active_vessel = merged.duplicate(true)
	upsert_owned_vessel(merged)


func get_active_vessel_record() -> Dictionary:
	return active_vessel.duplicate() if not active_vessel.is_empty() else {}


func has_active_vessel_record() -> bool:
	return not active_vessel.is_empty()


static func is_legacy_starter_vessel(record: Dictionary) -> bool:
	if record.is_empty():
		return false
	var path := str(record.get("template_path", ""))
	var hull_id := str(record.get("hull_id", ""))
	if path == LEGACY_STARTER_TEMPLATE_PATH:
		return true
	return hull_id == LEGACY_STARTER_HULL_ID and path.ends_with("starter_cargo_ship.json")


## True when the harbour master can deploy at least one owned hull.
func can_deploy_at_harbour() -> bool:
	return not get_deployable_vessels().is_empty()


func repair_save_consistency() -> void:
	if is_legacy_starter_vessel(active_vessel):
		active_vessel = {}
	var cleaned: Array = []
	for entry_raw in owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if is_legacy_starter_vessel(entry):
			continue
		cleaned.append(entry.duplicate())
	owned_vessels = cleaned
	if not active_vessel.is_empty() and not is_legacy_starter_vessel(active_vessel):
		var active_uid := str(active_vessel.get("uid", ""))
		var owned := find_owned_vessel(active_uid)
		if owned.is_empty():
			upsert_owned_vessel(active_vessel)
		else:
			upsert_owned_vessel(merge_vessel_record(owned, active_vessel))
	elif not owned_vessels.is_empty() and active_vessel.is_empty():
		var last_raw: Variant = owned_vessels[owned_vessels.size() - 1]
		if typeof(last_raw) == TYPE_DICTIONARY:
			active_vessel = (last_raw as Dictionary).duplicate()


func to_dict() -> Dictionary:
	return {
		"account_id":               account_id,
		"captain_id":               captain_id,
		"display_name":             display_name,
		"marks":                    marks,
		"total_marks_earned":       total_marks_earned,
		"contracts_completed":      contracts_completed,
		"distance_sailed_m":        distance_sailed_m,
		"owned_vessels":            owned_vessels.duplicate(true),
		"active_vessel":            active_vessel.duplicate(),
		"appearance":               appearance.to_dict(),
		# v2 additions
		"accepted_contracts":       accepted_contracts.duplicate(true),
		"ship_runtime_state":       _ship_runtime_to_dict(),
		"world_clock_hours":        world_clock_hours,
		"tutorial_seen":            tutorial_seen.duplicate(),
		"starter_trawler_claimed":  starter_trawler_claimed,
	}


static func from_dict(d: Dictionary) -> PlayerData:
	var pd                  := PlayerData.new()
	pd.account_id           = str(d.get("account_id",          ""))
	pd.captain_id           = str(d.get("captain_id",          ""))
	pd.display_name         = str(d.get("display_name",        "Captain"))
	pd.marks                = int(d.get("marks",               0))
	pd.total_marks_earned   = int(d.get("total_marks_earned",  0))
	pd.contracts_completed  = int(d.get("contracts_completed", 0))
	pd.distance_sailed_m         = float(d.get("distance_sailed_m", 0.0))
	var owned_raw: Variant = d.get("owned_vessels", [])
	if typeof(owned_raw) == TYPE_ARRAY:
		for entry_raw in owned_raw as Array:
			if typeof(entry_raw) == TYPE_DICTIONARY:
				pd.owned_vessels.append((entry_raw as Dictionary).duplicate())
	var active_raw: Variant = d.get("active_vessel", {})
	if typeof(active_raw) == TYPE_DICTIONARY and not (active_raw as Dictionary).is_empty():
		pd.active_vessel = (active_raw as Dictionary).duplicate()
	pd.appearance = CharacterAppearance.from_dict(d.get("appearance", {}) as Dictionary)
	# v2 additions — default to empty / sentinel for v1 saves (forward compat).
	var contracts_raw: Variant = d.get("accepted_contracts", [])
	if typeof(contracts_raw) == TYPE_ARRAY:
		pd.accepted_contracts = (contracts_raw as Array).duplicate(true)
	var ship_raw: Variant = d.get("ship_runtime_state", {})
	if typeof(ship_raw) == TYPE_DICTIONARY:
		pd.ship_runtime_state = _ship_runtime_from_dict(ship_raw as Dictionary)
	pd.world_clock_hours = float(d.get("world_clock_hours", -1.0))
	var tut_raw: Variant = d.get("tutorial_seen", {})
	if typeof(tut_raw) == TYPE_DICTIONARY:
		pd.tutorial_seen = (tut_raw as Dictionary).duplicate()
	pd.starter_trawler_claimed = bool(d.get("starter_trawler_claimed", false))
	pd.repair_save_consistency()
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
