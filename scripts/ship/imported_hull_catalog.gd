class_name ImportedHullCatalog
extends RefCounted
## Authoring/playtest platforms only; not the owned-fleet hull registry.
const ENTRIES := {
	"catamaran_36x11": {"label":"36.5 × 11 m catamaran", "loa_m":36.5, "beam_m":11.0, "depth_m":3.2, "draft_m":1.55, "displacement_t":160.0, "demihull_beam_m":2.4, "demihull_spacing_m":8.6, "split_hull_collision":true, "default_shaft_power_kw":3600.0, "fuel_l":6000.0, "mounts":"mounts_cat36.json", "rising":false, "mooring_inset":4.80, "mooring_guide":5.34, "mooring_stations":[-14.0,16.0], "reference_z":15.0, "material_context":"composite_ferry", "angular_damping":.25, "physics":{"harbour_drag_rate":.035,"hull_speed_fn":.72,"wave_making_peak_coeff":.0021,"frictional_coeff":.0025,"form_factor":1.06,"lateral_drag_coeff":2.4,"yaw_drag_coeff":8.0,"hull_center_of_mass":Vector3(0,2.4,0),"propeller_position":Vector3(0,1.05,18.50),"rudder_position":Vector3(0,1.65,19.05),"rudder_area_m2":2.0,"max_rudder_angle_deg":25.0,"tunnel_thruster_force_n":24000.0,"wind_frontal_area_m2":55.0,"wind_lateral_area_m2":150.0,"wind_center_of_effort":Vector3(0,4.5,0)}},
	"hull_88x14": {"label":"88 × 14 m", "loa_m":88.0, "beam_m":14.0, "depth_m":5.6, "draft_m":3.3, "displacement_t":1850.0, "form":"full_bodied", "default_shaft_power_kw":5600.0, "fuel_l":26000.0, "mounts":"mounts_88m.json", "rising":false, "mooring_inset":6.30, "mooring_guide":6.84, "mooring_stations":[-31.0,42.0], "reference_z":33.5, "container_beds":{"lanes":[-4.5,-1.5,1.5,4.5], "first_bay":-29.25, "bay_pitch":6.5, "bay_count":10}, "angular_damping":.22, "physics":{"harbour_drag_rate":.012,"hull_speed_fn":.30,"wave_making_peak_coeff":.012, "propeller_position":Vector3(0,2,42.42), "rudder_position":Vector3(0,2.3,43.78), "rudder_area_m2":5.6, "tunnel_thruster_force_n":110000.0, "wind_frontal_area_m2":110.0, "wind_lateral_area_m2":360.0, "wind_center_of_effort":Vector3(0,7,3)}},
	"trawler_hull_14m": {"label":"14 × 5 m", "loa_m":14.0, "beam_m":5.0, "depth_m":2.92, "draft_m":1.6, "displacement_t":58.0, "default_shaft_power_kw":300.0, "fuel_l":600.0, "mounts":"mounts_14m.json", "rising":true, "mooring_inset":1.95, "mooring_guide":2.34, "mooring_stations":[-2.8,6.0], "reference_z":2.4},
	"hull_24x8": {"label":"24 × 8 m", "loa_m":24.0, "beam_m":8.0, "depth_m":3.6, "draft_m":2.0, "displacement_t":180.0, "default_shaft_power_kw":700.0, "fuel_l":1800.0, "mounts":"mounts_24m.json", "rising":false, "mooring_inset":3.45, "mooring_guide":3.84, "mooring_stations":[-5.1,10.8], "reference_z":7.0, "coaming":"hold_coaming_5x8", "hatch":"hatch_cover_5x4", "hatch_stations":[-2.0,2.0]},
	"hull_32x10": {"label":"32 × 10 m", "loa_m":32.0, "beam_m":10.0, "depth_m":4.5, "draft_m":2.6, "displacement_t":420.0, "default_shaft_power_kw":1100.0, "fuel_l":4500.0, "mounts":"mounts_32m.json", "rising":false, "mooring_inset":4.45, "mooring_guide":4.84, "mooring_stations":[-7.0,14.0], "reference_z":10.0, "coaming":"hold_coaming_6x12", "hatch":"hatch_cover_6x3", "hatch_stations":[-4.5,-1.5,1.5,4.5]},
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
	SurfaceMaterialLibrary.apply(hull, str(ENTRIES[id].get("material_context", "hull")))
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
