class_name ShipBuilder
extends RefCounted

## Builds a complete playable ship from a template JSON at runtime.
##
## Template files live in res://resources/data/ships/*.json.
## Each hull JSON (res://resources/data/models/hulls/*.json) carries a "slots"
## section that defines named attachment points at scale=1; ShipBuilder multiplies
## those by the template's "scale" field when placing superstructures and mooring
## points.
##
## Usage:
##   var boat := ShipBuilder.build("res://resources/data/ships/fuel_tanker.json")
##   get_tree().current_scene.add_child(boat)
##   boat.place_at_waterline(water_y)

const HULL_BASE_DIR  := "res://resources/data/models/hulls/"
const SUPER_BASE_DIR := "res://scenes/shared/superstructures/"
const SHIPS_BASE_DIR := "res://resources/data/ships/"

static func build(template_path: String) -> BoatBody:
	var tmpl := _load_json(template_path)
	if tmpl.is_empty():
		push_error("ShipBuilder: failed to load template: " + template_path)
		return null

	var hull_path  := _resolve_hull_path(str(tmpl.get("hull", "")), template_path)
	var hull_data  := _load_json(hull_path)
	var scale      := float(tmpl.get("scale", 1.0))
	var slots      := _read_slots(hull_data, scale)

	# Strip-theory hull data, derived once from the hull JSON. Shared between BoatBody
	# (for displacement-based mass), StripBuoyancyComponent, and HydrodynamicsComponent.
	var stations := HullStations.from_hull_json(hull_data, 10)

	var boat := BoatBody.new()
	boat.name = str(tmpl.get("display_name", "Ship")).replace(" ", "")
	boat.hull_stations = stations
	boat.mesh_scale = scale

	_apply_physics(boat, tmpl.get("physics", {}))

	var model_json_path := _hull_to_model_path(hull_path, tmpl, template_path)
	boat.model_data_path = model_json_path

	boat.add_child(_make_strip_buoyancy(tmpl.get("buoyancy", {}), stations, scale))
	boat.add_child(_make_hydrodynamics(tmpl.get("hydrodynamics", {}), stations, scale))
	boat.add_child(_make_propulsion(tmpl.get("propulsion", {}), slots))
	boat.add_child(_make_rudder(tmpl.get("rudder", {})))
	boat.add_child(_make_bow_thruster(tmpl.get("bow_thruster", {}), slots))
	boat.add_child(_make_controller())
	boat.add_child(_make_camera(tmpl.get("camera", {})))
	boat.add_child(_make_lighting_controller())

	var gameplay := Node3D.new()
	gameplay.name = "ShipGameplay"
	boat.add_child(gameplay)

	var super_key := str(tmpl.get("superstructure", ""))
	if not super_key.is_empty() and slots.has("bridge"):
		var super_node := _instantiate_superstructure(super_key)
		if super_node != null:
			super_node.name = "Superstructure"
			super_node.position = slots["bridge"]
			gameplay.add_child(super_node)

	var mooring := MooringComponent.new()
	mooring.name = "MooringComponent"
	gameplay.add_child(mooring)

	_add_mooring_points(gameplay, slots, stations)
	_add_hull_lights(gameplay, hull_data, scale)
	_add_cargo_decks(gameplay, hull_data, tmpl, slots, scale)

	return boat


static func _apply_physics(boat: BoatBody, cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	if cfg.has("auto_mass_from_hull"):
		boat.auto_mass_from_hull = bool(cfg["auto_mass_from_hull"])
	if cfg.has("hull_mass"):
		boat.hull_mass = float(cfg["hull_mass"])
	if cfg.has("design_draft_fraction"):
		boat.design_draft_fraction = float(cfg["design_draft_fraction"])
	if cfg.has("engine_mass"):
		boat.engine_mass = float(cfg["engine_mass"])
	if cfg.has("keel_ballast_mass"):
		boat.keel_ballast_mass = float(cfg["keel_ballast_mass"])
	if cfg.has("fuel_stores_mass"):
		boat.fuel_stores_mass = float(cfg["fuel_stores_mass"])
	if cfg.has("center_of_mass_depth_fraction"):
		boat.center_of_mass_depth_fraction = float(cfg["center_of_mass_depth_fraction"])
	if cfg.has("artificial_keel_extra_depth"):
		boat.artificial_keel_extra_depth = float(cfg["artificial_keel_extra_depth"])
	if cfg.has("linear_damp_coeff"):
		boat.linear_damp_coeff = float(cfg["linear_damp_coeff"])
	if cfg.has("angular_damp_coeff"):
		boat.angular_damp_coeff = float(cfg["angular_damp_coeff"])


static func _make_strip_buoyancy(
	cfg: Dictionary, stations: HullStations, scale: float
) -> StripBuoyancyComponent:
	var c := StripBuoyancyComponent.new()
	c.name = "StripBuoyancyComponent"
	c.hull_stations = stations
	c.mesh_scale = scale
	if cfg.has("water_density"):
		c.water_density = float(cfg["water_density"])
	if cfg.has("buoyancy_multiplier"):
		c.buoyancy_multiplier = float(cfg["buoyancy_multiplier"])
	if cfg.has("heave_damping_per_m2"):
		c.heave_damping_per_m2 = float(cfg["heave_damping_per_m2"])
	return c


static func _make_hydrodynamics(
	cfg: Dictionary, stations: HullStations, scale: float
) -> HydrodynamicsComponent:
	var c := HydrodynamicsComponent.new()
	c.name = "HydrodynamicsComponent"
	c.hull_stations = stations
	c.mesh_scale = scale
	if cfg.has("water_density"):
		c.water_density = float(cfg["water_density"])
	if cfg.has("frictional_coeff"):
		c.frictional_coeff = float(cfg["frictional_coeff"])
	if cfg.has("form_factor"):
		c.form_factor = float(cfg["form_factor"])
	if cfg.has("wave_making_peak_coeff"):
		c.wave_making_peak_coeff = float(cfg["wave_making_peak_coeff"])
	if cfg.has("hull_speed_fn"):
		c.hull_speed_fn = float(cfg["hull_speed_fn"])
	if cfg.has("lateral_drag_coeff"):
		c.lateral_drag_coeff = float(cfg["lateral_drag_coeff"])
	if cfg.has("yaw_drag_coeff"):
		c.yaw_drag_coeff = float(cfg["yaw_drag_coeff"])
	if cfg.has("wind_frontal_area"):
		c.wind_frontal_area = float(cfg["wind_frontal_area"])
	if cfg.has("wind_lateral_area"):
		c.wind_lateral_area = float(cfg["wind_lateral_area"])
	if cfg.has("wind_drag_coeff"):
		c.wind_drag_coeff = float(cfg["wind_drag_coeff"])
	if cfg.has("air_density"):
		c.air_density = float(cfg["air_density"])
	return c


static func _make_propulsion(cfg: Dictionary, slots: Dictionary) -> PropulsionComponent:
	var c := PropulsionComponent.new()
	c.name = "PropulsionComponent"
	if cfg.has("max_thrust"):
		c.max_thrust = float(cfg["max_thrust"])
	if cfg.has("reverse_multiplier"):
		c.reverse_multiplier = float(cfg["reverse_multiplier"])
	if slots.has("propulsion"):
		c.stern_offset = slots["propulsion"]
	return c


static func _make_rudder(cfg: Dictionary) -> RudderComponent:
	var c := RudderComponent.new()
	c.name = "RudderComponent"
	if cfg.has("max_torque"):
		c.max_torque = float(cfg["max_torque"])
	if cfg.has("speed_factor"):
		c.speed_factor = float(cfg["speed_factor"])
	if cfg.has("min_effectiveness_floor"):
		c.min_effectiveness_floor = float(cfg["min_effectiveness_floor"])
	if cfg.has("rudder_flow_gate"):
		c.rudder_flow_gate = float(cfg["rudder_flow_gate"])
	if cfg.has("sideslip_rudder_weight"):
		c.sideslip_rudder_weight = float(cfg["sideslip_rudder_weight"])
	return c


static func _make_bow_thruster(cfg: Dictionary, slots: Dictionary) -> BowThrusterComponent:
	var c := BowThrusterComponent.new()
	c.name = "BowThrusterComponent"
	if cfg.has("max_thrust"):
		c.max_thrust = float(cfg["max_thrust"])
	if slots.has("bow_thruster"):
		c.bow_offset = slots["bow_thruster"]
	if slots.has("propulsion"):
		c.stern_offset = slots["propulsion"]
	return c


static func _make_controller() -> BoatController:
	var c := BoatController.new()
	c.name = "BoatController"
	return c


## Lighting controller — discovers ShipLight nodes anywhere under the boat
## (in group "ship_light") and drives presets via the L key. Auto-engages
## nav lights at night and in fog.
static func _make_lighting_controller() -> ShipLighting:
	var c := ShipLighting.new()
	c.name = "ShipLighting"
	return c


## Spawn hull-mounted lights declared in the hull JSON's `lights` array.
## Each entry: { "type": "<nav_port|nav_starboard|nav_masthead|nav_stern|work|window>",
##               "position": [x, y, z] }.
## Bridge-mounted lights (e.g. masthead, window) stay on the superstructure
## scene so they move with the bridge.
static func _add_hull_lights(parent: Node3D, hull_data: Dictionary, scale: float) -> void:
	var lights = hull_data.get("lights", [])
	if typeof(lights) != TYPE_ARRAY:
		return
	for entry in lights:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var type_id := _light_type_from_string(str(entry.get("type", "")))
		if type_id < 0:
			continue
		var pos_arr = entry.get("position", [0, 0, 0])
		if typeof(pos_arr) != TYPE_ARRAY or pos_arr.size() < 3:
			continue
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) * scale
		var light := ShipLight.new()
		light.name = "HullLight_%s" % str(entry.get("type", "")).capitalize()
		light.position = pos
		light.light_type = type_id
		parent.add_child(light)


## Spawn cargo decks. Source of truth for deck dimensions is the hull JSON's
## `cargo_decks` array; entries look like:
##   {"name": "main", "position": [0, 1.05, 0],
##    "deck_width": 2.8, "deck_length": 6.5, "cell_size": 1.0}
##
## The template can still filter which decks to enable by listing names in
## its own `cargo_decks` array (legacy contract). If the template omits the
## key, every hull-declared deck is added — which is what new commissions do.
## If the template provides an empty list, no decks are added (used by very
## small launches that shouldn't carry cargo).
static func _add_cargo_decks(parent: Node3D, hull_data: Dictionary, tmpl: Dictionary,
		slots: Dictionary, scale: float) -> void:
	var hull_decks = hull_data.get("cargo_decks", [])
	if typeof(hull_decks) != TYPE_ARRAY:
		hull_decks = []

	# Build a name → hull-deck-def lookup so the template can filter by name.
	var by_name: Dictionary = {}
	for d in hull_decks:
		if typeof(d) == TYPE_DICTIONARY:
			by_name[str(d.get("name", ""))] = d

	var tmpl_decks: Variant = tmpl.get("cargo_decks", null)
	var names_to_build: Array = []
	if tmpl_decks == null:
		# Template did not specify — use everything the hull declares.
		for d in hull_decks:
			if typeof(d) == TYPE_DICTIONARY:
				names_to_build.append(str(d.get("name", "")))
	elif typeof(tmpl_decks) == TYPE_ARRAY:
		for entry in tmpl_decks:
			names_to_build.append(str(entry))

	for deck_name in names_to_build:
		if not by_name.has(deck_name):
			# Legacy fallback: deck_name is a slot key with no dimensions —
			# use defaults sized for that slot's position.
			if slots.has(deck_name):
				var legacy := CargoDeckComponent.new()
				legacy.name = "CargoDeck_" + deck_name
				legacy.position = slots[deck_name]
				parent.add_child(legacy)
			continue
		var def: Dictionary = by_name[deck_name]
		var pos_arr = def.get("position", [0, 0, 0])
		var pos := Vector3.ZERO
		if typeof(pos_arr) == TYPE_ARRAY and pos_arr.size() >= 3:
			pos = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) * scale
		var deck := CargoDeckComponent.new()
		deck.name = "CargoDeck_" + deck_name
		deck.position = pos
		deck.deck_width_m = float(def.get("deck_width", 5.0)) * scale
		deck.deck_length_m = float(def.get("deck_length", 8.0)) * scale
		var cell_size := float(def.get("cell_size", 1.5)) * scale
		deck.cell_size_x_m = cell_size
		deck.cell_size_z_m = cell_size
		parent.add_child(deck)


static func _light_type_from_string(s: String) -> int:
	match s:
		"nav_port":      return ShipLight.LightType.NAV_PORT
		"nav_starboard": return ShipLight.LightType.NAV_STARBOARD
		"nav_masthead":  return ShipLight.LightType.NAV_MASTHEAD
		"nav_stern":     return ShipLight.LightType.NAV_STERN
		"work":          return ShipLight.LightType.WORK
		"window":        return ShipLight.LightType.WINDOW
		_:               return -1


static func _make_camera(cfg: Dictionary) -> BoatCamera:
	var c := BoatCamera.new()
	c.name = "BoatCamera"
	if cfg.has("follow_distance"):
		c.set("follow_distance", float(cfg["follow_distance"]))
	if cfg.has("follow_height"):
		c.set("follow_height", float(cfg["follow_height"]))
	return c


static func _instantiate_superstructure(key: String) -> Node3D:
	var path := SUPER_BASE_DIR + key + ".tscn"
	if not ResourceLoader.exists(path):
		push_warning("ShipBuilder: superstructure scene not found: " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


static func _add_mooring_points(parent: Node3D, slots: Dictionary, stations: HullStations) -> void:
	# Scale the visible bollard to the hull. The natural docking_bollard model
	# is ~0.8 m wide and reads correctly on a 20–30 m coaster at scale 1.0.
	# Linearly interpolate so a 13 m launch gets a smaller cleat and a 60 m
	# freighter gets a chunkier one — keeps the visual proportion sensible.
	var hull_length : float = stations.length_m if stations != null else 18.0
	var t           : float = clampf((hull_length - 13.0) / 47.0, 0.0, 1.0)
	var bollard_scale : float = lerpf(0.7, 1.5, t)

	var pairs := [
		["mooring_port_fwd",  "port",      "fwd"],
		["mooring_stbd_fwd",  "starboard",  "fwd"],
		["mooring_port_aft",  "port",      "aft"],
		["mooring_stbd_aft",  "starboard",  "aft"],
	]
	for pair in pairs:
		var slot_name: String = pair[0]
		if not slots.has(slot_name):
			continue
		var mp := MooringPoint.new()
		mp.name = "MooringPoint_" + slot_name.capitalize().replace(" ", "")
		mp.position = slots[slot_name]
		mp.set("side",    pair[1])
		mp.set("station", pair[2])
		mp.set("bollard_scale", bollard_scale)
		parent.add_child(mp)


static func _read_slots(hull_data: Dictionary, scale: float) -> Dictionary:
	var out: Dictionary = {}
	if not hull_data.has("slots"):
		return out
	var raw = hull_data["slots"]
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key in raw.keys():
		var v = raw[key]
		if typeof(v) == TYPE_ARRAY and v.size() >= 3:
			out[key] = Vector3(float(v[0]), float(v[1]), float(v[2])) * scale
	return out


static func _hull_to_model_path(hull_path: String, tmpl: Dictionary, template_path: String) -> String:
	var hull_key := str(tmpl.get("hull", ""))
	var scale    := float(tmpl.get("scale", 1.0))

	# Write a minimal ship model JSON that wraps the hull at the given scale.
	# Use user:// scratch space so we never pollute res://.
	var model_name := template_path.get_file().get_basename()
	var scratch    := "user://ship_builder_cache/" + model_name + ".json"

	DirAccess.make_dir_recursive_absolute("user://ship_builder_cache")

	var data := JSON.stringify({
		"name": model_name,
		"parts": [{
			"name": "hull",
			"model": hull_path,
			"position": [0, 0, 0],
			"scale": scale
		}]
	})
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	if f == null:
		push_error("ShipBuilder: could not write scratch model to " + scratch)
		return hull_path
	f.store_string(data)
	f.close()

	return scratch


static func _resolve_hull_path(hull_ref: String, template_path: String) -> String:
	if hull_ref.begins_with("res://") or hull_ref.begins_with("user://"):
		return hull_ref
	var base := template_path.get_base_dir()
	var local := base.path_join(hull_ref)
	if FileAccess.file_exists(local):
		return local
	var models := HULL_BASE_DIR + hull_ref
	if FileAccess.file_exists(models):
		return models
	return local


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ShipBuilder: file not found: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ShipBuilder: JSON parse error in " + path)
		return {}
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data
