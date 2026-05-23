class_name StarterVessel
extends RefCounted

## The 13 m Coastal Trader is the smallest hull — always free at the harbour master.
## Not sold at the shipwright; captains can request another anytime.

const ENTRY: Dictionary = {
	"id":               "cargo_ship",
	"display":          "Twin-Deck Cargo Coaster  •  20 m",
	"ship_class_label": "Coastal Trader",
	"hull_file":        "hull_cargo_ship.json",
	"superstructure":   "",
}

const TEMPLATE_PATH := "user://shipwright_orders/starter_cargo_ship.json"


static func ensure_template_file() -> String:
	if FileAccess.file_exists(TEMPLATE_PATH):
		return TEMPLATE_PATH
	return write_template_file()


static func build_template(entry: Dictionary = {}) -> Dictionary:
	if entry.is_empty():
		entry = HullRegistry.get_by_id("cargo_ship")
	var hull_path: String = ShipBuilder.HULL_BASE_DIR + str(entry.get("hull_file", ""))
	var hull_data: Dictionary = JsonUtil.load(hull_path)
	var stations: HullStations = HullStations.from_hull_json(hull_data, 10)
	var s: float = ShipBuilder.HULL_WORLD_SCALE
	var displacement_kg: float = maxf(stations.displacement_volume_m3 * s * s * s * 1025.0, 1000.0)
	var propulsion_thrust: float = displacement_kg * 0.7
	var bow_ratio: float = clampf(0.40 - (stations.length_m * s) / 200.0, 0.10, 0.40)
	var bow_thrust: float = propulsion_thrust * bow_ratio
	var rudder_torque: float = 0.0275 * pow(propulsion_thrust, 4.0 / 3.0)
	var cam_dist: float = stations.length_m * s * 1.45 + 11.0
	var cam_height: float = stations.length_m * s * 0.36 + 4.0

	return {
		"display_name":   str(entry.get("display", "Coastal Trader")),
		"hull":           str(entry.get("hull_file", "")),
		"scale":          1.0,
		"superstructure": str(entry.get("superstructure", "")),
		"physics": {
			"auto_mass_from_hull":    true,
			"design_draft_fraction":  0.45,
			"mass_scale":             1.28,
		},
		"buoyancy": {
			"heave_damping_per_m2": 11000.0,
		},
		"hydrodynamics": {
			"frictional_coeff":       0.0025,
			"form_factor":            1.20,
			"wave_making_peak_coeff": 0.005,
			"hull_speed_fn":          0.40,
			"lateral_drag_coeff":     2.0,
			"yaw_drag_coeff":         5.0,
		},
		"propulsion": {
			"max_thrust":         propulsion_thrust,
			"reverse_multiplier": 0.45,
		},
		"rudder": {
			"max_torque":              rudder_torque,
			"speed_factor":            0.65,
			"min_effectiveness_floor": 0.38,
			"rudder_flow_gate":        0.25,
			"sideslip_rudder_weight":  0.55,
		},
		"bow_thruster": {
			"max_thrust": bow_thrust,
		},
		"camera": {
			"follow_distance": cam_dist,
			"follow_height":   cam_height,
		},
	}


static func write_template_file() -> String:
	DirAccess.make_dir_recursive_absolute("user://shipwright_orders")
	var f := FileAccess.open(TEMPLATE_PATH, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(build_template()))
	f.close()
	return TEMPLATE_PATH


static func set_active_vessel_record(session: Node) -> void:
	if session == null or session.get("data") == null:
		return
	ensure_template_file()
	session.data.set_active_vessel({
		"uid":           "cargo_ship_active",
		"hull_id":       "cargo_ship",
		"display":       "Twin-Deck Cargo Coaster  •  20 m",
		"template_path": TEMPLATE_PATH,
	})
	if session.has_method("save_now"):
		session.call("save_now")
