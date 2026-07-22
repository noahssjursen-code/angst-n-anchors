class_name PlayerData

## Fictional ledger currency — shared by UI formatters and PlayerSession.
const CURRENCY_SYMBOL := "ℳ"
const CURRENCY_NAME   := "Marks"
const NEW_CAPTAIN_STARTING_MARKS := 6400


static func format_money(amount: int) -> String:
	return "%s %d" % [CURRENCY_SYMBOL, amount]


static func new_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		return "%08x-%04x-4000-8000-%012x" % [
			int(Time.get_unix_time_from_system()),
			Time.get_ticks_msec() & 0xffff,
			Time.get_ticks_usec() & 0xffffffffffff,
		]
	# RFC 4122 version 4 + variant bits.
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]


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
## Each entry: { uid, hull_id, registration_id, name, display, shaft_power_kw,
## scene_path?, brick_layout{}, server_vessel_id? }.
## `name`/`display` identify the finished ship; `hull_id` identifies its reusable platform.
var owned_vessels: Array = []
## Hull currently deployed in the world (must match one entry in owned_vessels).
var active_vessel: Dictionary = {}

## Authoritative company/economy aggregate. Kept JSON-safe so the exact same
## contract can be persisted locally or hydrated from a future server.
var company: Dictionary = {}

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

## Save v5 port-operations snapshot. Runtime nodes are projections and are
## rebuilt from this stable call/yard ledger after the matching world loads.
## Shape: { "active_call": Dictionary, "yard_cargo": Array }.
var port_operations_state: Dictionary = {}

## Deprecated compatibility field. Resume-in-vessel persistence was removed;
## old save values are ignored and new saves omit this field.
var ship_runtime_state: Dictionary = {}

## Game time at save (game-hours since the world epoch). Restored to
## WorldClock on load so day/night picks up where it left off instead of
## resetting to noon.
var world_clock_hours: float = -1.0
## World identity associated with coordinate-bearing state:
## { "seed": int, "world_size_m": float, "world_preset": String,
##   "generation_version": int, "weather_generation_version": int,
##   "layout_checksum": String }.
## Empty on legacy saves; those restore using the current world once, then adopt it.
var world_context: Dictionary = {}

## Tutorial hint chain — { hint_id: true } once a hint has fired. Persisted
## so a returning captain doesn't have to skip the same banners again.
var tutorial_seen: Dictionary = {}

## True after the captain commissions their one free small fishing trawler.
var starter_trawler_claimed: bool = false

## Captain-chosen home quay. Defaults to the world seed's first coastal port.
var home_port_id: String = "port-home"


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


## JSON parses every number as a float. Compare persisted structures
## semantically so 90 and 90.0 are the same layout.
static func json_equivalent(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) \
			and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		var ad := a as Dictionary
		var bd := b as Dictionary
		if ad.size() != bd.size():
			return false
		for key in ad:
			if not bd.has(key) or not json_equivalent(ad[key], bd[key]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		var aa := a as Array
		var ba := b as Array
		if aa.size() != ba.size():
			return false
		for i in range(aa.size()):
			if not json_equivalent(aa[i], ba[i]):
				return false
		return true
	return a == b


## Strip a vessel ledger row down to JSON-safe fields only.
## Catalog entries carry Color / enum Variants that must never hit player.json.
static func ledger_vessel_record(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {}
	var hull_id := str(record.get("hull_id", "fishing_trawler_small")).strip_edges()
	if hull_id.is_empty():
		hull_id = "fishing_trawler_small"
	var scene_path := str(record.get("scene_path", record.get("template_path", ""))).strip_edges()
	if scene_path.is_empty():
		scene_path = HullRegistry.scene_path_for(hull_id)
	var layout_raw: Variant = record.get("brick_layout", {})
	var layout: Dictionary = {}
	if typeof(layout_raw) == TYPE_DICTIONARY:
		layout = (layout_raw as Dictionary).duplicate(true)
	if layout.is_empty():
		layout = {"hull_id": hull_id, "cells": {}}
	var out := {
		"uid": str(record.get("uid", "")).strip_edges(),
		"hull_id": hull_id,
		"registration_id": str(record.get("registration_id", "review_required")).strip_edges(),
		"name": str(record.get("name", "")).strip_edges(),
		"display": str(record.get("display", "")).strip_edges(),
		"shaft_power_kw": maxf(float(record.get(
			"shaft_power_kw",
			HullRegistry.get_by_id(hull_id).get("default_shaft_power_kw", 1.0)
		)), 1.0),
		"brick_layout": layout,
	}
	## New records spawn by hull_id. Keep scene_path only for frozen hand-scene hulls.
	if not scene_path.is_empty():
		out["scene_path"] = scene_path
	var server_id := str(record.get("server_vessel_id", "")).strip_edges()
	if not server_id.is_empty():
		out["server_vessel_id"] = server_id
	var layout_hash := str(record.get("layout_hash", "")).strip_edges()
	if not layout_hash.is_empty():
		out["layout_hash"] = layout_hash
	return out


func upsert_owned_vessel(record: Dictionary) -> void:
	if record.is_empty():
		return
	var uid := str(record.get("uid", ""))
	if uid.is_empty():
		return
	var normalized := ledger_vessel_record(VesselSpawn.normalize_record(record))
	if normalized.is_empty() or str(normalized.get("uid", "")).is_empty():
		return
	for i in range(owned_vessels.size()):
		var existing_raw: Variant = owned_vessels[i]
		if typeof(existing_raw) != TYPE_DICTIONARY:
			continue
		if str((existing_raw as Dictionary).get("uid", "")) == uid:
			owned_vessels[i] = ledger_vessel_record(
				VesselSpawn.normalize_record(
					merge_vessel_record(existing_raw as Dictionary, normalized)
				)
			)
			_mirror_active_vessel_from_owned(uid)
			return
	owned_vessels.append(normalized)
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
		var resolved := VesselSpawn.resolve_deployable_record(entry)
		if resolved.is_empty():
			continue
		out.append(resolved)
	return out


static func is_vessel_on_npc_run(_record: Dictionary) -> bool:
	# Autonomous NPC fleet removed — vessels are never "on a run".
	return false


func get_deployable_vessels() -> Array:
	return get_harbour_vessel_records()


func set_active_vessel(record: Dictionary) -> void:
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		active_vessel = {}
		return
	var uid := str(record.get("uid", ""))
	var owned := find_owned_vessel(uid)
	var merged := merge_vessel_record(owned, record) if not owned.is_empty() else record.duplicate(true)
	active_vessel = ledger_vessel_record(VesselSpawn.normalize_record(merged))
	upsert_owned_vessel(active_vessel)


func get_active_vessel_record() -> Dictionary:
	return active_vessel.duplicate() if not active_vessel.is_empty() else {}


func has_active_vessel_record() -> bool:
	return not active_vessel.is_empty()


static func is_legacy_starter_vessel(record: Dictionary) -> bool:
	if record.is_empty():
		return false
	var path := str(record.get("scene_path", record.get("template_path", "")))
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
	var active_server_id := str(active_vessel.get("server_vessel_id", ""))
	var active_uid := str(active_vessel.get("uid", ""))
	var cleaned: Array = []
	var seen_uids: Dictionary = {}
	for entry_raw in owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if is_legacy_starter_vessel(entry):
			continue
		var normalized := ledger_vessel_record(VesselSpawn.normalize_record(entry))
		var uid := str(normalized.get("uid", ""))
		var uid_collides := uid.is_empty() or seen_uids.has(uid)
		if uid_collides:
			var server_id := str(normalized.get("server_vessel_id", ""))
			uid = (
				"server_%s" % server_id
				if not server_id.is_empty()
				else VesselSpawn.new_vessel_uid(str(normalized.get("hull_id", "fishing_trawler_small")))
			)
			normalized["uid"] = uid
		seen_uids[uid] = true
		cleaned.append(normalized)
	owned_vessels = cleaned
	if not active_vessel.is_empty() and not is_legacy_starter_vessel(active_vessel):
		# Server ID is immutable and disambiguates old second-resolution UID
		# collisions. Only fall back to UID for offline/local vessels.
		var owned := (
			find_owned_by_server_id(active_server_id)
			if not active_server_id.is_empty()
			else find_owned_vessel(active_uid)
		)
		if owned.is_empty():
			upsert_owned_vessel(active_vessel)
		else:
			var repaired_active := active_vessel.duplicate(true)
			repaired_active["uid"] = str(owned.get("uid", active_uid))
			upsert_owned_vessel(merge_vessel_record(owned, repaired_active))
			active_vessel = find_owned_vessel(str(owned.get("uid", active_uid)))
	elif not owned_vessels.is_empty() and active_vessel.is_empty():
		var last_raw: Variant = owned_vessels[owned_vessels.size() - 1]
		if typeof(last_raw) == TYPE_DICTIONARY:
			active_vessel = ledger_vessel_record(VesselSpawn.normalize_record(last_raw as Dictionary))


func to_dict() -> Dictionary:
	var owned_out: Array = []
	for entry_raw in owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var safe := ledger_vessel_record(entry_raw as Dictionary)
		if not safe.is_empty() and not str(safe.get("uid", "")).is_empty():
			owned_out.append(safe)
	var active_out := ledger_vessel_record(active_vessel) if not active_vessel.is_empty() else {}
	return {
		"account_id":               account_id,
		"captain_id":               captain_id,
		"display_name":             display_name,
		"marks":                    marks,
		"total_marks_earned":       total_marks_earned,
		"contracts_completed":      contracts_completed,
		"distance_sailed_m":        distance_sailed_m,
		"owned_vessels":            owned_out,
		"active_vessel":            active_out,
		"company":                  company.duplicate(true),
		"appearance":               appearance.to_dict(),
		# v2 additions
		"accepted_contracts":       accepted_contracts.duplicate(true),
		"port_operations_state":    port_operations_state.duplicate(true),
		"world_clock_hours":        world_clock_hours,
		"world_context":            world_context.duplicate(),
		"tutorial_seen":            tutorial_seen.duplicate(),
		"starter_trawler_claimed":  starter_trawler_claimed,
		"home_port_id":             home_port_id,
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
				pd.owned_vessels.append(VesselSpawn.normalize_record(entry_raw as Dictionary))
	var active_raw: Variant = d.get("active_vessel", {})
	if typeof(active_raw) == TYPE_DICTIONARY and not (active_raw as Dictionary).is_empty():
		pd.active_vessel = VesselSpawn.normalize_record(active_raw as Dictionary)
	var company_raw: Variant = d.get("company", {})
	if typeof(company_raw) == TYPE_DICTIONARY:
		pd.company = (company_raw as Dictionary).duplicate(true)
	pd.appearance = CharacterAppearance.from_dict(d.get("appearance", {}) as Dictionary)
	# v2 additions — default to empty / sentinel for v1 saves (forward compat).
	var contracts_raw: Variant = d.get("accepted_contracts", [])
	if typeof(contracts_raw) == TYPE_ARRAY:
		pd.accepted_contracts = (contracts_raw as Array).duplicate(true)
	var port_ops_raw: Variant = d.get("port_operations_state", {})
	if typeof(port_ops_raw) == TYPE_DICTIONARY:
		pd.port_operations_state = (port_ops_raw as Dictionary).duplicate(true)
	pd.ship_runtime_state = {}
	pd.world_clock_hours = float(d.get("world_clock_hours", -1.0))
	var world_context_raw: Variant = d.get("world_context", {})
	if typeof(world_context_raw) == TYPE_DICTIONARY:
		pd.world_context = (world_context_raw as Dictionary).duplicate()
	var tut_raw: Variant = d.get("tutorial_seen", {})
	if typeof(tut_raw) == TYPE_DICTIONARY:
		pd.tutorial_seen = (tut_raw as Dictionary).duplicate()
	pd.starter_trawler_claimed = bool(d.get("starter_trawler_claimed", false))
	var home_port := str(d.get("home_port_id", "port-home")).strip_edges()
	pd.home_port_id = home_port if not home_port.is_empty() else "port-home"
	# Save v6 migration: existing captains receive a compatible company wrapper
	# around their current balance and fleet without receiving another vessel.
	if pd.company.is_empty() and not pd.account_id.is_empty():
		pd.company = CompanyContracts.normalize({}, pd.account_id, pd.display_name, pd.home_port_id)
		var account := pd.company.get("account", {}) as Dictionary
		account["balance_marks"] = pd.marks
		if pd.marks != 0:
			account["ledger"] = [CompanyContracts.transaction(
				"migration-%s" % pd.account_id,
				"save-v6-migration",
				str(pd.company.get("id", "")),
				pd.marks,
				"legacy_balance_migration",
				"Balance carried forward from the legacy captain ledger",
				pd.account_id,
				int(Time.get_unix_time_from_system()),
				pd.marks,
			)]
		pd.company["account"] = account
		pd.company["warehouse_leases"] = [CompanyContracts.opening_warehouse_lease(
			str(pd.company.get("id", "")), pd.home_port_id, int(Time.get_unix_time_from_system())
		)]
		pd.company["onboarding_complete"] = not pd.owned_vessels.is_empty()
	pd.repair_save_consistency()
	return pd
