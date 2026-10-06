class_name ImportedHullCatalog
extends RefCounted
## Authoring/playtest platforms only; not the owned-fleet hull registry.
const ENTRIES := {
	"trawler_hull_14m": {"label":"14 × 5 m", "loa_m":14.0, "beam_m":5.0, "depth_m":2.92, "draft_m":1.6, "displacement_t":58.0, "default_shaft_power_kw":300.0, "fuel_l":600.0, "mounts":"mounts_14m.json", "rising":true},
	"hull_24x8": {"label":"24 × 8 m", "loa_m":24.0, "beam_m":8.0, "depth_m":3.6, "draft_m":2.0, "displacement_t":180.0, "default_shaft_power_kw":700.0, "fuel_l":1800.0, "mounts":"mounts_24m.json", "rising":false},
}

static func has(id: String) -> bool:
	return ENTRIES.has(id)

static func directory(id: String) -> String:
	assert(has(id))
	return "res://resources/models/vessels/" + id + "/"

static func outline(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(directory(id) + "deck_outline.json"))

static func instantiate(id: String) -> Node3D:
	var hull := (load(directory(id) + id + ".glb") as PackedScene).instantiate() as Node3D
	hull.add_child(ShipDriveVisual.new(ENTRIES[id]["mounts"]))
	return hull

static func make_grid(id: String) -> DeckGrid:
	var data := outline(id)
	var grid := DeckGrid.from_hull(data.length_m, data.beam_m, data.deck_y, 0, .1)
	for p in data.outline_xz: grid.deck_polygon.append(Vector2(p[0],p[1]))
	for ring in data.get("openings_xz", []):
		var polygon := PackedVector2Array()
		for p in ring: polygon.append(Vector2(p[0],p[1]))
		grid.deck_openings.append(polygon)
	return grid

static func rail_recipes(id: String) -> Dictionary:
	var result := {}
	for variant in ["rail_flat", "rail_rising", "halfwall_flat", "halfwall_rising"]:
		var folder := ImportedShipPartsEditor.ROOT if id == "trawler_hull_14m" else directory(id)
		var filename: String = variant if ENTRIES[id].rising else variant.replace("rising","flat")
		result[variant] = JSON.parse_string(FileAccess.get_file_as_string(folder + filename + "_assembly.json"))["placements"]
	return result
