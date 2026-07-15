class_name AttachmentCatalog
extends RefCounted

## LEGACY / QUARANTINED socket registry. Deck bricks and DeckFitout own active
## ship equipment; do not add store-ship content to this catalog.

const ENTRIES: Dictionary = {
	"cargo_deck_grid": {
		"kind": "cargo",
		"display": "Cargo deck grid",
		"script": "res://scripts/ship/attachments/cargo_deck_grid.gd",
	},
	"trawl_system": {
		"kind": "fishing",
		"display": "Trawl system",
		"script": "res://scripts/ship/attachments/trawl_system.gd",
	},
	"mooring_cleat": {
		"kind": "mooring",
		"display": "Mooring cleat",
		"script": "res://scripts/ship/attachments/mooring_cleat.gd",
	},
	"nav_light_port": {
		"kind": "light",
		"display": "Port nav light",
		"script": "res://scripts/ship/attachments/nav_light_fixture.gd",
		"light_type": 0,
	},
	"nav_light_starboard": {
		"kind": "light",
		"display": "Starboard nav light",
		"script": "res://scripts/ship/attachments/nav_light_fixture.gd",
		"light_type": 1,
	},
	"nav_light_bow": {
		"kind": "light",
		"display": "Bow masthead light",
		"script": "res://scripts/ship/attachments/nav_light_fixture.gd",
		"light_type": 2,
	},
	"nav_light_stern": {
		"kind": "light",
		"display": "Stern light",
		"script": "res://scripts/ship/attachments/nav_light_fixture.gd",
		"light_type": 3,
	},
	"ship_crane_small": {
		"kind": "crane",
		"display": "Ship deck crane",
		"script": "res://scripts/ship/attachments/ship_crane_small.gd",
	},
}


static func has(attachment_id: String) -> bool:
	return ENTRIES.has(attachment_id.strip_edges())


static func get_entry(attachment_id: String) -> Dictionary:
	var id := attachment_id.strip_edges()
	if not ENTRIES.has(id):
		return {}
	return (ENTRIES[id] as Dictionary).duplicate(true)


static func kind_of(attachment_id: String) -> String:
	return str(get_entry(attachment_id).get("kind", ""))


static func create(attachment_id: String) -> VesselAttachment:
	var entry := get_entry(attachment_id)
	if entry.is_empty():
		push_error("AttachmentCatalog: unknown attachment `%s`" % attachment_id)
		return null
	var script_path := str(entry.get("script", ""))
	var script := load(script_path) as GDScript
	if script == null:
		push_error("AttachmentCatalog: missing script %s" % script_path)
		return null
	var node = script.new()
	if node is VesselAttachment:
		var att := node as VesselAttachment
		if att.has_method("configure_from_catalog"):
			att.call("configure_from_catalog", entry)
		return att
	push_error("AttachmentCatalog: script is not VesselAttachment: %s" % script_path)
	if node is Node:
		(node as Node).queue_free()
	return null
