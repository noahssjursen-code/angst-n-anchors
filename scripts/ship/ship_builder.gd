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

	var boat := BoatBody.new()
	boat.name = str(tmpl.get("display_name", "Ship")).replace(" ", "")

	_apply_physics(boat, tmpl.get("physics", {}))

	var model_json_path := _hull_to_model_path(hull_path, tmpl, template_path)
	boat.model_data_path = model_json_path
	boat.mesh_scale = scale

	boat.add_child(_make_buoyancy(tmpl.get("buoyancy", {})))
	boat.add_child(_make_hydrodynamics(tmpl.get("hydrodynamics", {})))
	boat.add_child(_make_propulsion(tmpl.get("propulsion", {}), slots))
	boat.add_child(_make_rudder(tmpl.get("rudder", {})))
	boat.add_child(_make_bow_thruster(tmpl.get("bow_thruster", {}), slots))
	boat.add_child(_make_controller())
	boat.add_child(_make_camera(tmpl.get("camera", {})))

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

	_add_mooring_points(gameplay, slots)

	for deck_slot in tmpl.get("cargo_decks", []):
		var slot_name := str(deck_slot)
		if slots.has(slot_name):
			var deck := CargoDeckComponent.new()
			deck.name = "CargoDeck_" + slot_name
			deck.position = slots[slot_name]
			gameplay.add_child(deck)

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


static func _make_buoyancy(cfg: Dictionary) -> BuoyancyComponent:
	var c := BuoyancyComponent.new()
	c.name = "BuoyancyComponent"
	if cfg.has("block_coefficient"):
		c.block_coefficient = float(cfg["block_coefficient"])
	if cfg.has("vertical_damping"):
		c.vertical_damping = float(cfg["vertical_damping"])
	if cfg.has("wave_influence_scale"):
		c.wave_influence_scale = float(cfg["wave_influence_scale"])
	if cfg.has("fall_gravity_multiplier"):
		c.fall_gravity_multiplier = float(cfg["fall_gravity_multiplier"])
	if cfg.has("buoyancy_multiplier"):
		c.buoyancy_multiplier = float(cfg["buoyancy_multiplier"])
	return c


static func _make_hydrodynamics(cfg: Dictionary) -> HydrodynamicsComponent:
	var c := HydrodynamicsComponent.new()
	c.name = "HydrodynamicsComponent"
	if cfg.has("forward_drag_coeff"):
		c.forward_drag_coeff = float(cfg["forward_drag_coeff"])
	if cfg.has("lateral_drag_coeff"):
		c.lateral_drag_coeff = float(cfg["lateral_drag_coeff"])
	if cfg.has("rotational_drag_coeff"):
		c.rotational_drag_coeff = float(cfg["rotational_drag_coeff"])
	if cfg.has("orbital_flow_scale"):
		c.orbital_flow_scale = float(cfg["orbital_flow_scale"])
	if cfg.has("bulk_horizontal_drag"):
		c.bulk_horizontal_drag = float(cfg["bulk_horizontal_drag"])
	if cfg.has("draft_fraction"):
		c.draft_fraction = float(cfg["draft_fraction"])
	if cfg.has("wave_influence_scale"):
		c.wave_influence_scale = float(cfg["wave_influence_scale"])
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


static func _add_mooring_points(parent: Node3D, slots: Dictionary) -> void:
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
