class_name ShipBuilder
extends RefCounted

## Builds a complete playable ship from a template JSON at runtime.
##
## Templates today come from the shipwright NPC, which writes them to
## user://shipwright_orders/<id>.json before calling ShipBuilder.build().
## Each hull JSON (res://resources/data/models/hulls/*.json) declares its own
## `slots`, `cargo_decks`, `lights`, and other attachments; ShipBuilder reads
## all of them and instantiates the right component nodes at the right
## positions + scale.
##
## Usage:
##   var boat := ShipBuilder.build("user://shipwright_orders/coastal_trader.json")
##   get_tree().current_scene.add_child(boat)
##   boat.place_at_waterline(water_y)

const HULL_BASE_DIR       := "res://resources/data/models/hulls/"
## Legacy PackedScene path — kept for fallback while the JSON bridges are
## bedding in. The .tscn loader still works if a JSON for the requested
## key doesn't exist; once all five bridges have shipped as JSON we can
## drop this entirely.
const SUPER_SCENE_DIR     := "res://scenes/shared/superstructures/"
const SUPER_MODEL_DIR     := "res://resources/data/models/superstructures/"
## Applied to the hull `bridge` slot when placing the superstructure (ship-local:
## −Y down, −Z aft). Scaled by the ship template `scale`.
const SUPERSTRUCTURE_OFFSET := Vector3(0.0, -0.3, -1.0)
## Cargo deck must end this far forward of bow reference slots (m at scale 1).
const CARGO_BOW_CLEARANCE_M := 1.5
## Cargo deck stern edge must be at least this far forward of the bridge slot (+Z).
const CARGO_AFT_OF_BRIDGE_M := 3.0
## Mooring cleats: pull toward centerline and away from bow/stern tips (fractions at scale 1).
const MOORING_BEAM_INSET_FRAC := 0.22
const MOORING_END_INSET_FRAC := 0.09
## Funnel / exhaust stack: nudge forward (+Z) in superstructure-local space (m at scale 1).
const FUNNEL_FORWARD_OFFSET_M := 1.2

static func build(template_path: String) -> BoatBody:
	var tmpl := _load_json(template_path)
	if tmpl.is_empty():
		push_error("ShipBuilder: failed to load template: " + template_path)
		return null

	# Telemetry timer — visible in the debug HUD's loading log.
	# Looked up off the main loop because ShipBuilder is RefCounted, no node.
	var loop := Engine.get_main_loop() as SceneTree
	var telemetry: Node = null
	var t_handle: int = 0
	if loop != null and loop.root != null:
		telemetry = loop.root.get_node_or_null("Telemetry")
	var ship_id := template_path.get_file().get_basename()
	if telemetry != null:
		t_handle = telemetry.mark_load_event("ship.build:%s" % ship_id)

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
		var super_node := _build_superstructure(super_key)
		if super_node != null:
			super_node.name = "Superstructure"
			super_node.position = slots["bridge"] + SUPERSTRUCTURE_OFFSET * scale
			gameplay.add_child(super_node)
			_schedule_funnel_nudge(super_node, scale)

	var mooring := MooringComponent.new()
	mooring.name = "MooringComponent"
	gameplay.add_child(mooring)

	_add_mooring_points(gameplay, slots, stations)
	_add_hull_lights(gameplay, hull_data, scale)
	_add_cargo_decks(gameplay, hull_data, tmpl, slots, scale, stations)

	if telemetry != null:
		telemetry.end_load_event(t_handle)

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
	if cfg.has("mass_scale"):
		boat.mass_scale = float(cfg["mass_scale"])
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
## Each entry: { "type": "<nav_port|nav_starboard|nav_masthead|nav_stern|window>",
##               "position": [x, y, z] }.
## Deck/work floods are not spawned. Bridge-mounted lights stay on the
## superstructure scene so they move with the bridge.
static func _add_hull_lights(parent: Node3D, hull_data: Dictionary, scale: float) -> void:
	var lights = hull_data.get("lights", [])
	if typeof(lights) != TYPE_ARRAY:
		return
	for entry in lights:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var type_str := str(entry.get("type", ""))
		if type_str == "work":
			continue
		var type_id := _light_type_from_string(type_str)
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


## Spawn one cargo deck per ship. Dimensions come from the hull JSON's
## `cargo_decks` entry (prefer `"main"`). The template may pick a name via
## `cargo_decks: ["main"]`, omit the key (same as `["main"]` when present),
## or pass `[]` for no deck.
static func _add_cargo_decks(parent: Node3D, hull_data: Dictionary, tmpl: Dictionary,
		slots: Dictionary, scale: float, stations: HullStations) -> void:
	var def := _pick_cargo_deck_def(hull_data, tmpl)
	if def.is_empty():
		return
	var fitted := _fit_cargo_deck_to_hull(def, slots, scale, stations)
	if fitted.is_empty():
		push_warning("ShipBuilder: no room for cargo deck on hull")
		return
	var deck_name := str(fitted.get("name", "main"))
	var pos_arr = fitted.get("position", [0, 0, 0])
	var pos := Vector3.ZERO
	if typeof(pos_arr) == TYPE_ARRAY and pos_arr.size() >= 3:
		pos = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) * scale
	var deck := CargoDeckComponent.new()
	deck.name = "CargoDeck_" + deck_name
	deck.position = pos
	deck.deck_width_m = float(fitted.get("deck_width", 5.0)) * scale
	deck.deck_length_m = float(fitted.get("deck_length", 8.0)) * scale
	var cell_size := float(fitted.get("cell_size", 1.5)) * scale
	deck.cell_size_x_m = cell_size
	deck.cell_size_z_m = cell_size
	parent.add_child(deck)


## Returns the single hull cargo-deck definition to build, or {} if none.
static func _pick_cargo_deck_def(hull_data: Dictionary, tmpl: Dictionary) -> Dictionary:
	var hull_decks = hull_data.get("cargo_decks", [])
	if typeof(hull_decks) != TYPE_ARRAY:
		hull_decks = []

	var by_name: Dictionary = {}
	for d in hull_decks:
		if typeof(d) == TYPE_DICTIONARY:
			by_name[str(d.get("name", ""))] = d

	var tmpl_decks: Variant = tmpl.get("cargo_decks", null)
	if typeof(tmpl_decks) == TYPE_ARRAY:
		if tmpl_decks.is_empty():
			return {}
		var chosen := str(tmpl_decks[0])
		if by_name.has(chosen):
			return by_name[chosen] as Dictionary
		return {}

	if by_name.has("main"):
		return by_name["main"] as Dictionary
	if hull_decks.size() > 0 and typeof(hull_decks[0]) == TYPE_DICTIONARY:
		return hull_decks[0] as Dictionary
	return {}


## Clamp deck between bridge and bow, then snap width/length to whole cell counts
## so registered capacity matches the physical grid.
static func _fit_cargo_deck_to_hull(def: Dictionary, slots: Dictionary, scale: float,
		stations: HullStations) -> Dictionary:
	var cell := maxf(float(def.get("cell_size", 1.5)) * scale, 0.2)
	var pos_arr = def.get("position", [0, 0, 0])
	var pos := Vector3.ZERO
	if typeof(pos_arr) == TYPE_ARRAY and pos_arr.size() >= 3:
		pos = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) * scale

	var width := float(def.get("deck_width", 5.0)) * scale
	var length := float(def.get("deck_length", 8.0)) * scale
	if stations != null and stations.beam_m > 0.0:
		width = minf(width, stations.beam_m * 0.88 * scale)

	var bow_limit := -INF
	for key in ["bow_thruster", "nav_light_bow", "mooring_port_fwd", "mooring_stbd_fwd"]:
		if slots.has(key):
			bow_limit = maxf(bow_limit, (slots[key] as Vector3).z)
	if bow_limit == -INF and stations != null and not stations.stations.is_empty():
		var last: Dictionary = stations.stations[stations.stations.size() - 1]
		bow_limit = float(last.get("z", 0.0)) * scale
	bow_limit -= CARGO_BOW_CLEARANCE_M * scale

	var aft_limit := INF
	if slots.has("bridge"):
		aft_limit = (slots["bridge"] as Vector3).z + CARGO_AFT_OF_BRIDGE_M * scale
	elif stations != null and stations.stations.size() > 0:
		var first: Dictionary = stations.stations[0]
		aft_limit = float(first.get("z", 0.0)) * scale + CARGO_AFT_OF_BRIDGE_M * scale

	var span := bow_limit - aft_limit
	if span < cell * 0.5 or bow_limit == -INF or aft_limit == INF:
		return {}

	length = minf(length, span)
	var half := length * 0.5
	var aft_edge := pos.z - half
	var fwd_edge := pos.z + half
	if aft_edge < aft_limit:
		var shift := aft_limit - aft_edge
		aft_edge += shift
		fwd_edge += shift
	if fwd_edge > bow_limit:
		var shift := fwd_edge - bow_limit
		aft_edge -= shift
		fwd_edge -= shift
	length = maxf(fwd_edge - aft_edge, 0.0)
	if length < cell * 0.5:
		return {}

	var cols := maxi(int(floor(width / cell)), 1)
	var rows := maxi(int(floor(length / cell)), 1)
	while rows > 1 and float(rows) * cell > span + 0.001:
		rows -= 1
	width = float(cols) * cell
	length = float(rows) * cell
	half = length * 0.5
	aft_edge = clampf(pos.z - half, aft_limit, bow_limit - length)
	pos.z = aft_edge + half

	return {
		"name": def.get("name", "main"),
		"position": [pos.x / scale, pos.y / scale, pos.z / scale],
		"deck_width": width / scale,
		"deck_length": length / scale,
		"cell_size": def.get("cell_size", 1.5),
	}


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


## Build the superstructure (bridge) node tree for `key`. Tries the JSON
## model first; falls back to the legacy .tscn if the JSON doesn't exist.
##
## JSON path: spawns a ModelAssembler-driven visual + the BridgeInteractable
## + ShipLight nodes positioned via the JSON `slots` dict. This is the
## target architecture.
##
## .tscn path: instantiates a PackedScene with pre-built ShipLight nodes
## inside it (the old format, still in the tree until JSON ships for every
## hull class).
static func _build_superstructure(key: String) -> Node3D:
	var json_path := SUPER_MODEL_DIR + key + ".json"
	if FileAccess.file_exists(json_path):
		return _build_superstructure_from_json(json_path)

	var scene_path := SUPER_SCENE_DIR + key + ".tscn"
	if not ResourceLoader.exists(scene_path):
		push_warning("ShipBuilder: superstructure missing — no JSON at " + json_path
			+ " and no scene at " + scene_path)
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## Construct the bridge node tree from a JSON model file. The JSON declares
## visual `parts` (consumed by ModelAssembler), a `slots` dict of light /
## interactable positions, and an optional `interactable` config block.
static func _build_superstructure_from_json(path: String) -> Node3D:
	var root := Node3D.new()

	var visuals := ModelAssembler.new()
	visuals.name = "BridgeVisuals"
	visuals.build_part_colliders = false
	visuals.model_data_path = path
	root.add_child(visuals)

	var data := _load_json(path)
	if data.is_empty():
		return root

	var slot_data: Variant = data.get("slots", {})
	var slot_dict: Dictionary = slot_data if typeof(slot_data) == TYPE_DICTIONARY else {}

	# BridgeInteractable — boarding zone in front of the deck house.
	var interact := BridgeInteractable.new()
	interact.name = "BridgeInteractable"
	if slot_dict.has("bridge_interactable"):
		var bi_pos = slot_dict["bridge_interactable"]
		if typeof(bi_pos) == TYPE_ARRAY and bi_pos.size() >= 3:
			interact.position = Vector3(float(bi_pos[0]), float(bi_pos[1]), float(bi_pos[2]))
	var iv = data.get("interactable", {})
	if typeof(iv) == TYPE_DICTIONARY:
		var exit_arr = iv.get("exit_deck_offset", null)
		if typeof(exit_arr) == TYPE_ARRAY and exit_arr.size() >= 2:
			interact.exit_deck_offset = Vector2(float(exit_arr[0]), float(exit_arr[1]))
	root.add_child(interact)

	# Spawn the bridge-mounted lights from the JSON slots.
	# Naming convention in slots: light_<type>: [x, y, z]
	# where <type> is nav_port, nav_starboard, nav_masthead, nav_stern, or window.
	for slot_name in slot_dict.keys():
		var key := str(slot_name)
		if not key.begins_with("light_"):
			continue
		var type_str := key.substr("light_".length())
		if type_str == "work":
			continue
		var type_id := _light_type_from_string(type_str)
		if type_id < 0:
			continue
		var pos_arr = slot_dict[slot_name]
		if typeof(pos_arr) != TYPE_ARRAY or pos_arr.size() < 3:
			continue
		var light := ShipLight.new()
		light.name = "ShipLight_" + type_str.capitalize().replace(" ", "")
		light.position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		light.light_type = type_id
		root.add_child(light)

	return root


static func _schedule_funnel_nudge(super_root: Node3D, scale: float) -> void:
	var delta_z := FUNNEL_FORWARD_OFFSET_M * scale
	Callable(ShipBuilder, "_nudge_funnel_parts").call_deferred(super_root, delta_z)


static func _nudge_funnel_parts(super_root: Node3D, delta_z: float) -> void:
	if super_root == null or not is_instance_valid(super_root) or absf(delta_z) < 1e-6:
		return
	for part_name in [
		"ModelPart_funnel",
		"ModelPart_funnel_cap",
		"ModelPart_exhaust_stack",
		"ExhaustStack",
	]:
		var part := super_root.find_child(part_name, true, false) as Node3D
		if part != null:
			part.position.z += delta_z


static func _add_mooring_points(parent: Node3D, slots: Dictionary, stations: HullStations) -> void:
	# Scale the visible bollard to the hull. The natural docking_bollard model
	# is ~0.8 m wide and reads correctly on a 20–30 m coaster at scale 1.0.
	# Linearly interpolate so a 13 m launch gets a smaller cleat and a 60 m
	# freighter gets a chunkier one — keeps the visual proportion sensible.
	var hull_length : float = stations.length_m if stations != null else 18.0
	var t           : float = clampf((hull_length - 13.0) / 47.0, 0.0, 1.0)
	var bollard_scale : float = lerpf(0.7, 1.5, t)

	var pairs := [
		["mooring_port_fwd",  "port",      "bow"],
		["mooring_stbd_fwd",  "starboard", "bow"],
		["mooring_port_aft",  "port",      "stern"],
		["mooring_stbd_aft",  "starboard", "stern"],
	]
	for pair in pairs:
		var slot_name: String = pair[0]
		if not slots.has(slot_name):
			continue
		var mp := MooringPoint.new()
		mp.name = "MooringPoint_" + slot_name.capitalize().replace(" ", "")
		mp.position = _adjust_mooring_position(slots[slot_name], slot_name, stations)
		mp.set("side",    pair[1])
		mp.set("station", pair[2])
		mp.set("bollard_scale", bollard_scale)
		parent.add_child(mp)


## Pull cleats inboard and away from the bow/stern tips. Authored hull slots sit
## on the sheer line past the hull mesh; this keeps bollards on the deck edge.
static func _adjust_mooring_position(pos: Vector3, slot_name: String,
		stations: HullStations) -> Vector3:
	var out := pos
	var beam_pull := absf(out.x) * MOORING_BEAM_INSET_FRAC
	if out.x < -0.01:
		out.x = minf(out.x + beam_pull, -0.15)
	elif out.x > 0.01:
		out.x = maxf(out.x - beam_pull, 0.15)

	var length_pull := 0.8
	if stations != null and stations.length_m > 0.0:
		length_pull = stations.length_m * MOORING_END_INSET_FRAC
	if slot_name.contains("fwd"):
		out.z -= length_pull
	elif slot_name.contains("aft"):
		out.z += length_pull
	return out


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


## Forwarded to JsonUtil so callers that still go through ShipBuilder._load_json
## (shipwright_npc, starter_vessel, etc.) keep working. New code should call
## JsonUtil.load() directly.
static func _load_json(path: String) -> Dictionary:
	return JsonUtil.load(path)
