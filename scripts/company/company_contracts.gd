class_name CompanyContracts
extends RefCounted

## Versioned, JSON-safe contracts shared by local authority today and a future
## server authority. Scene nodes are projections; these dictionaries are truth.

const SCHEMA_VERSION := 1
const STARTING_MARKS := 6400
const STARTER_WAREHOUSE_CAPACITY_UNITS := 24

## The career a new captain starts in when nobody has chosen one: the value the
## onboarding panel opens on, and the one the multiplayer starter-repair path
## grants. It lived as the string "general_cargo" in three separate files, which
## is how "a new player starts on a 28 m coastal trader" survived `hull_15x5`
## landing — the small hull was purchasable and buildable, and no default
## pointed at it (STATE.md item 5).
##
## Changing this changes which BOAT a click-through new player is given AND
## which home ports the picker will accept: `MainMenu._starter_terminal_family`
## maps the career to a required berth family, and `fishing` requires a fish
## landing. Measured over five generated worlds (`tests/_fishport_survey.gd`):
## 115 of 175 ports (65.7%, never fewer than 21 of 35 in a world) offer one, so
## a fishing captain always has a wide choice — but `port-home` itself was
## ineligible in 2 of those 5 worlds, so the named home port is sometimes not
## one of them.
const DEFAULT_STARTER := "fishing"

const STARTER_VESSELS := {
	"fishing": {
		## The 15 m sjark, not the 28 m trawler. `hull_28x10` is still what
		## `fishing_trawler` is built on and the Shipwright still sells it; it is
		## simply no longer what a beginner is handed.
		"prebuilt_id": "sjark_15m",
		"label": "Coastal sjark · 15 m",
		"role": "Harvest fish and land your own catch.",
		"career": "Fishing",
	},
	"general_cargo": {
		"prebuilt_id": "28_10_m",
		"label": "Coastal cargo vessel",
		"role": "Carry provisions and manufactured goods between ports.",
		"career": "General cargo",
	},
	"bulk": {
		"prebuilt_id": "bulk_small",
		"label": "Coastal bulk vessel",
		"role": "Move grain, ore and raw industrial inputs.",
		"career": "Bulk freight",
	},
}


static func starter_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ["fishing", "general_cargo", "bulk"]:
		var option := (STARTER_VESSELS[id] as Dictionary).duplicate(true)
		option["id"] = id
		out.append(option)
	return out


static func new_company(
	company_id: String,
	owner_player_id: String,
	captain_id: String,
	display_name: String,
	home_port_id: String,
	brand_color: Color,
	created_at_unix: int,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": company_id,
		"name": display_name.strip_edges(),
		"owner_type": "player",
		"owner_player_id": owner_player_id,
		"captain_id": captain_id,
		"home_port_id": home_port_id,
		"brand_color": brand_color.to_html(false),
		"created_at_unix": created_at_unix,
		"account": {
			"currency": "MARK",
			"balance_marks": 0,
			"ledger": [],
		},
		"inventory_lots": [],
		"warehouse_leases": [],
		"processed_requests": {},
		"starter_vessel_id": "",
		"onboarding_complete": false,
	}


static func normalize(raw: Dictionary, player_id: String, captain_name: String, home_port_id: String) -> Dictionary:
	var company := raw.duplicate(true)
	if company.is_empty():
		company = new_company(
			"company-%s" % player_id,
			player_id,
			player_id,
			"%s Maritime" % captain_name,
			home_port_id,
			Color("2f7f83"),
			int(Time.get_unix_time_from_system()),
		)
	company["schema_version"] = SCHEMA_VERSION
	company["id"] = str(company.get("id", "company-%s" % player_id))
	company["name"] = str(company.get("name", "%s Maritime" % captain_name))
	company["owner_type"] = str(company.get("owner_type", "player"))
	company["owner_player_id"] = str(company.get("owner_player_id", player_id))
	company["captain_id"] = str(company.get("captain_id", player_id))
	company["home_port_id"] = str(company.get("home_port_id", home_port_id))
	company["brand_color"] = str(company.get("brand_color", "2f7f83"))
	company["created_at_unix"] = int(company.get("created_at_unix", Time.get_unix_time_from_system()))
	company["account"] = _normalize_account(company.get("account", {}) as Dictionary)
	if typeof(company.get("inventory_lots", [])) != TYPE_ARRAY:
		company["inventory_lots"] = []
	if typeof(company.get("warehouse_leases", [])) != TYPE_ARRAY:
		company["warehouse_leases"] = []
	if typeof(company.get("processed_requests", {})) != TYPE_DICTIONARY:
		company["processed_requests"] = {}
	company["starter_vessel_id"] = str(company.get("starter_vessel_id", ""))
	company["onboarding_complete"] = bool(company.get("onboarding_complete", false))
	return company


static func opening_warehouse_lease(company_id: String, home_port_id: String, timestamp: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": "lease-%s-starter" % company_id,
		"company_id": company_id,
		"port_id": home_port_id,
		"kind": "public_warehouse",
		"capacity_units": STARTER_WAREHOUSE_CAPACITY_UNITS,
		"used_units": 0,
		"rent_marks_per_day": 0,
		"status": "active",
		"started_at_unix": timestamp,
	}


static func inventory_lot(
	lot_id: String,
	company_id: String,
	commodity_id: String,
	quantity: float,
	unit: String,
	location_id: String,
	origin_port_id: String,
	acquisition_marks: int,
	storage_units: float,
	timestamp: int,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": lot_id,
		"owner_company_id": company_id,
		"commodity_id": commodity_id,
		"quantity": maxf(quantity, 0.0),
		"reserved_quantity": 0.0,
		"unit": unit,
		"location_id": location_id,
		"origin_port_id": origin_port_id,
		"acquisition_marks": maxi(acquisition_marks, 0),
		"storage_units": maxf(storage_units, 0.0),
		"acquired_at_unix": timestamp,
		"quality": 1.0,
		"status": "stored",
	}


static func transaction(
	entry_id: String,
	request_id: String,
	company_id: String,
	amount_marks: int,
	category: String,
	description: String,
	related_entity_id: String,
	timestamp: int,
	balance_after: int,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": entry_id,
		"request_id": request_id,
		"company_id": company_id,
		"currency": "MARK",
		"amount_marks": amount_marks,
		"category": category,
		"description": description,
		"related_entity_id": related_entity_id,
		"created_at_unix": timestamp,
		"balance_after_marks": balance_after,
	}


static func result_ok(data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": "ok", "data": data.duplicate(true)}


static func result_error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "data": {}}


static func _normalize_account(raw: Dictionary) -> Dictionary:
	var account := raw.duplicate(true)
	account["currency"] = "MARK"
	account["balance_marks"] = int(account.get("balance_marks", 0))
	if typeof(account.get("ledger", [])) != TYPE_ARRAY:
		account["ledger"] = []
	return account
