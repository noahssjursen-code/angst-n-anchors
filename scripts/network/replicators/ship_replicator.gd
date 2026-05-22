extends Node3D

## Replicates remote ships in-world with smooth movement.

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

const REMOTE_SHIP_ROOT_NAME := "RemoteShips"
const REMOTE_SHIP_PREFIX := "RemoteShip_"
const REMOTE_SHIP_LABEL_NAME := "ShipNameLabel"
const REMOTE_SHIP_TEMPLATE_DIR := "user://remote_ship_templates"

@export var remote_ship_position_smoothness: float = 12.0
@export var remote_ship_yaw_smoothness: float = 14.0
@export var remote_ship_nameplate_height_extra: float = 4.0

const HULL_CATALOG: Dictionary = {
	"coastal_trader": {
		"id":               "coastal_trader",
		"display":          "Coastal Trader",
		"ship_class_label": "Coastal Trader",
		"hull_file":        "hull_coastal_trader.json",
		"superstructure":   "bridge_coastal_trader",
	},
	"coastal_trader_long": {
		"id":               "coastal_trader_long",
		"display":          "Coastal Trader, Extended",
		"ship_class_label": "Coastal Trader",
		"hull_file":        "hull_coastal_trader_long.json",
		"superstructure":   "bridge_coastal_trader",
	},
	"cargo_ship": {
		"id":               "cargo_ship",
		"display":          "Twin-Deck Cargo Coaster",
		"ship_class_label": "Coastal Trader",
		"hull_file":        "hull_cargo_ship.json",
		"superstructure":   "bridge_cargo_ship",
	},
	"short_sea_coaster": {
		"id":               "short_sea_coaster",
		"display":          "Short Sea Coaster",
		"ship_class_label": "Short Sea Coaster",
		"hull_file":        "hull_short_sea_coaster.json",
		"superstructure":   "bridge_short_sea_coaster",
	},
	"short_sea_coaster_long": {
		"id":               "short_sea_coaster_long",
		"display":          "Short Sea Coaster, Extended",
		"ship_class_label": "Short Sea Coaster",
		"hull_file":        "hull_short_sea_coaster_long.json",
		"superstructure":   "bridge_short_sea_coaster",
	},
	"handysize_feeder": {
		"id":               "handysize_feeder",
		"display":          "Handysize Feeder",
		"ship_class_label": "Handysize Feeder",
		"hull_file":        "hull_handysize_feeder.json",
		"superstructure":   "bridge_handysize_feeder",
	},
	"handysize_feeder_long": {
		"id":               "handysize_feeder_long",
		"display":          "Handysize Feeder, Extended",
		"ship_class_label": "Handysize Feeder",
		"hull_file":        "hull_handysize_feeder_long.json",
		"superstructure":   "bridge_handysize_feeder",
	},
	"deep_sea_freighter": {
		"id":               "deep_sea_freighter",
		"display":          "Deep Sea Freighter",
		"ship_class_label": "Deep Sea Freighter",
		"hull_file":        "hull_deep_sea_freighter.json",
		"superstructure":   "bridge_deep_sea_freighter",
	},
	"deep_sea_freighter_long": {
		"id":               "deep_sea_freighter_long",
		"display":          "Deep Sea Freighter, Extended",
		"ship_class_label": "Deep Sea Freighter",
		"hull_file":        "hull_deep_sea_freighter_long.json",
		"superstructure":   "bridge_deep_sea_freighter",
	},
	"large_freighter": {
		"id":               "large_freighter",
		"display":          "Large Freighter",
		"ship_class_label": "Deep Sea Freighter",
		"hull_file":        "hull_large.json",
		"superstructure":   "bridge_deep_sea_freighter",
	},
}

const HULL_LENGTH_M_BY_ID := {
	"coastal_trader":          13.0,
	"coastal_trader_long":     15.0,
	"cargo_ship":              20.0,
	"short_sea_coaster":       22.0,
	"short_sea_coaster_long":  25.0,
	"handysize_feeder":        35.0,
	"handysize_feeder_long":   40.0,
	"deep_sea_freighter":      50.0,
	"deep_sea_freighter_long": 60.0,
	"large_freighter":         60.0,
}
const DEFAULT_HULL_LENGTH_M := 13.0

var _remote_ships: Dictionary = {}
var _piloting_player_ids: Dictionary = {}


func apply_ships(ships_list: Array) -> void:
	_piloting_player_ids.clear()
	var visible_ids: Dictionary = {}
	var manager := get_parent()
	
	for s_data: Dictionary in ships_list:
		var s_id: String = s_data.get("ship_id", "")
		if s_id.is_empty():
			continue
			
		# Skip ships we own/manage locally (authoritative)
		if manager != null and manager.has_method("is_local_ship") and manager.call("is_local_ship", s_id):
			continue
			
		visible_ids[s_id] = true
		var pilot_id: String = s_data.get("pilot_id", "")
		if not pilot_id.is_empty():
			_piloting_player_ids[pilot_id] = true
			
		_upsert_ship(s_id, s_data)
		
	# Clean up missing ships
	for known_id_variant in _remote_ships.keys():
		var known_id := String(known_id_variant)
		if not visible_ids.has(known_id):
			var state: Dictionary = _remote_ships[known_id]
			var node_val: Variant = state.get("node", null)
			if is_instance_valid(node_val):
				node_val.queue_free()
			_remote_ships.erase(known_id)
			
	# Update remote pilot visibilities via manager
	if manager != null and manager.has_method("apply_pilot_visibilities"):
		manager.call("apply_pilot_visibilities", _piloting_player_ids)


func _upsert_ship(ship_id: String, s_data: Dictionary) -> void:
	var state: Dictionary = _remote_ships.get(ship_id, {})
	var node_val: Variant = state.get("node", null)
	var node: Node3D = null
	if is_instance_valid(node_val):
		node = node_val as Node3D
	
	var target_pos := Vector3(s_data.get("x", 0.0), s_data.get("y", 0.0), s_data.get("z", 0.0))
	var target_yaw := float(s_data.get("yaw", 0.0))
	var hull_id: String = s_data.get("hull_id", "")
	
	if node == null or not is_instance_valid(node):
		node = _spawn_remote_ship_node(ship_id, hull_id)
		if node != null:
			add_child(node)
			node.global_position = target_pos
			_set_node_global_yaw(node, target_yaw)
			state["node"] = node
			state["target_position"] = target_pos
			state["target_yaw"] = target_yaw
			state["hull_id"] = hull_id
	else:
		state["target_position"] = target_pos
		state["target_yaw"] = target_yaw
		
	_remote_ships[ship_id] = state


func _spawn_remote_ship_node(ship_id: String, hull_id: String) -> Node3D:
	var template_path := _ensure_remote_ship_template(hull_id)
	if template_path.is_empty():
		push_warning("ShipReplicator: Unknown hull_id=%s — cannot render remote ship %s" % [hull_id, ship_id])
		return null
		
	var ship := ShipBuilder.build(template_path)
	if ship == null:
		push_warning("ShipReplicator: ShipBuilder.build failed for hull_id=%s ship_id=%s" % [hull_id, ship_id])
		return null
		
	ship.name = "%s%s" % [REMOTE_SHIP_PREFIX, ship_id]
	_strip_ship_for_remote(ship)
	_build_nameplate(ship, ship_id, hull_id)
	
	return ship


func _ensure_remote_ship_template(hull_id: String) -> String:
	if not HULL_CATALOG.has(hull_id):
		return ""
	DirAccess.make_dir_recursive_absolute(REMOTE_SHIP_TEMPLATE_DIR)
	var path := "%s/%s.json" % [REMOTE_SHIP_TEMPLATE_DIR, hull_id]
	if FileAccess.file_exists(path):
		return path
		
	var entry: Dictionary = HULL_CATALOG[hull_id]
	var tmpl := StarterVessel.build_template(entry)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(tmpl))
		f.close()
		return path
	return ""


func _strip_ship_for_remote(ship: BoatBody) -> void:
	var to_remove: Array[Node] = []
	_collect_remote_strip_targets(ship, to_remove)
	for n in to_remove:
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()
		
	ship.freeze = true
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	for c in ship.get_children():
		_disable_physics_in_subtree(c)


func _collect_remote_strip_targets(n: Node, out: Array[Node]) -> void:
	if n.is_in_group(VehicleGroups.SHIP_OWNER_ONLY):
		out.append(n)
		return
	for c in n.get_children():
		_collect_remote_strip_targets(c, out)


func _disable_physics_in_subtree(n: Node) -> void:
	n.set_physics_process(false)
	for c in n.get_children():
		_disable_physics_in_subtree(c)


func _build_nameplate(ship: Node3D, ship_id: String, hull_id: String) -> void:
	var label := Label3D.new()
	label.name = REMOTE_SHIP_LABEL_NAME
	label.text = "%s (%s)" % [ship_id, hull_id.capitalize()]
	label.font_size = 64
	label.pixel_size = 0.015
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.96, 0.92, 0.78, 0.95)
	
	var length_m := float(HULL_LENGTH_M_BY_ID.get(hull_id, DEFAULT_HULL_LENGTH_M))
	label.position = Vector3(0.0, remote_ship_nameplate_height_extra + length_m * 0.05, 0.0)
	ship.add_child(label)


func interpolate(delta: float) -> void:
	if _remote_ships.is_empty():
		return
		
	var pos_alpha := 1.0 - exp(-remote_ship_position_smoothness * delta)
	var yaw_alpha := 1.0 - exp(-remote_ship_yaw_smoothness * delta)
	
	for id_variant in _remote_ships.keys():
		var ship_id := String(id_variant)
		var state: Dictionary = _remote_ships[ship_id]
		var node_val: Variant = state.get("node", null)
		if node_val == null or not is_instance_valid(node_val):
			continue
		var node := node_val as Node3D
			
		var target_pos: Vector3 = state.get("target_position", node.global_position)
		var target_yaw: float = state.get("target_yaw", _node_global_yaw_rad(node))
		
		node.global_position = node.global_position.lerp(target_pos, pos_alpha)
		var new_yaw := lerp_angle(_node_global_yaw_rad(node), target_yaw, yaw_alpha)
		_set_node_global_yaw(node, new_yaw)
		
		# Keep WalkDeck (the AnimatableBody3D the remote player stands on)
		# in lockstep with the hull. BoatBody normally does this from
		# _integrate_forces, but frozen bodies don't get that callback.
		if node.has_method("_sync_walk_deck_transform"):
			node.call("_sync_walk_deck_transform")


func _node_global_yaw_rad(node: Node3D) -> float:
	var basis := node.global_transform.basis
	return atan2(basis.z.x, basis.z.z)


func _set_node_global_yaw(node: Node3D, yaw_rad: float) -> void:
	var pos := node.global_position
	node.global_transform.basis = Basis.from_euler(Vector3(0.0, yaw_rad, 0.0))
	node.global_position = pos


func get_remote_ships() -> Dictionary:
	return _remote_ships


func clear_all() -> void:
	for id_variant in _remote_ships.keys():
		var state: Dictionary = _remote_ships[id_variant]
		var node_val: Variant = state.get("node", null)
		if is_instance_valid(node_val):
			node_val.queue_free()
	_remote_ships.clear()
