class_name DevelopmentFleet
extends RefCounted

## Explicitly opted-in local captains only. Stock grants are append-only; yard
## edits, vessel identities, cargo and the selected ship survive catalog updates.
const REVIEW_RECIPES := [{
	"id": "coastal_express", "name": "Coastal Express",
	"path": "res://resources/models/examples/coastal_express_recipe.json",
}]


static func catalog_entries() -> Array[Dictionary]:
	var entries := PrebuiltVesselCatalog.catalog_entries()
	# Completed arrangements still under gameplay review need not be put on sale
	# just to make them available to the development captain.
	for recipe in REVIEW_RECIPES:
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(recipe.path))
		layout["format"] = "imported_models"
		layout["hull_id"] = str(layout.get("hull", ""))
		if not ImportedVesselLayout.valid(layout, layout.hull_id, true):
			push_warning("DevelopmentFleet: invalid review vessel " + str(recipe.id))
			continue
		entries.append({"prebuilt_id": recipe.id, "prebuilt_name": recipe.name,
			"hull_id": layout.hull_id, "prebuilt_layout": layout})
	return entries


static func synchronize(player: PlayerData) -> int:
	if not is_development(player):
		return 0
	return grant_missing(player, catalog_entries())


static func is_development(player: PlayerData) -> bool:
	return player != null and bool(player.company.get("development_captain", false))


static func configure_home_port(definitions: Array[PortDefinition], player: PlayerData) -> void:
	if not is_development(player): return
	for definition in definitions:
		if definition.port_id == player.home_port_id:
			definition.development_facilities = true
			return


static func grant_missing(player: PlayerData, entries: Array[Dictionary]) -> int:
	if not is_development(player):
		return 0
	var grants: Dictionary = player.company.get("development_fleet", {}).duplicate(true)
	var added := 0
	for entry in entries:
		var stock_id := str(entry.get("prebuilt_id", ""))
		if stock_id.is_empty() or grants.has(stock_id):
			continue
		var vessel_name := str(entry.get("prebuilt_name", "Vessel"))
		var record := VesselSpawn.resolve_deployable_record({
			"uid": VesselSpawn.new_vessel_uid(str(entry.hull_id)),
			"hull_id": entry.hull_id, "name": vessel_name, "display": vessel_name,
			"registration_id": entry.get("registration_id", ""),
			"shaft_power_kw": entry.get("shaft_power_kw", 1.0),
			"brick_layout": entry.prebuilt_layout.duplicate(true),
		})
		if record.is_empty():
			push_warning("DevelopmentFleet: skipped incomplete vessel " + stock_id)
			continue
		player.upsert_owned_vessel(record)
		grants[stock_id] = str(record.uid)
		if player.active_vessel.is_empty():
			player.set_active_vessel(record)
		added += 1
	player.company["development_fleet"] = grants
	player.company["tablet_received"] = true
	return added


static func existing_captain_id() -> String:
	# Read without activating any slot or redirecting the current session's saves.
	for entry in LocalCaptainStore.list_captains():
		var path := LocalCaptainStore.captain_dir(str(entry.id)).path_join("player.json")
		if not FileAccess.file_exists(path):
			continue
		var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if envelope is Dictionary and bool(envelope.get("player", {}).get("company", {}).get("development_captain", false)):
			return str(entry.id)
	return ""
