class_name PlayerVessel
extends RefCounted

## One captain, one hull in the world. Replace or recall — never duplicate.

const GROUP := "player_boat"


static func mark_player_ship(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if not ship.is_in_group(GROUP):
		ship.add_to_group(GROUP)


static func unmark_player_ship(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if ship.is_in_group(GROUP):
		ship.remove_from_group(GROUP)


static func find_active_ship(tree: SceneTree) -> BoatBody:
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(GROUP):
		var ship := node as BoatBody
		if ship != null and is_instance_valid(ship):
			return ship
	return _find_legacy_player_ship(tree)


static func despawn_all_ships(tree: SceneTree, except: BoatBody = null) -> void:
	if tree == null:
		return
	var to_remove: Array[BoatBody] = []
	for node in tree.get_nodes_in_group(GROUP):
		var ship := node as BoatBody
		if ship != null and is_instance_valid(ship) and ship != except:
			to_remove.append(ship)
	var legacy := _find_legacy_player_ship(tree)
	if legacy != null and legacy != except and legacy not in to_remove:
		to_remove.append(legacy)
	for ship in to_remove:
		_prepare_despawn(ship, tree)
		ship.free()


static func unregister_ship_from_docks(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var port_id := str(ship.get_meta("harbour_port_id", ""))
	if port_id.is_empty():
		return
	var harbour := HarbourRegistry.controller(port_id)
	if harbour != null:
		harbour.unplug_ship(ship)


static func replace_before_spawn(tree: SceneTree) -> void:
	despawn_all_ships(tree)


static func _find_legacy_player_ship(tree: SceneTree) -> BoatBody:
	if tree == null or tree.root == null:
		return null
	for node in tree.root.find_children("PlayerShip", "BoatBody", true, false):
		var ship := node as BoatBody
		if ship != null and is_instance_valid(ship):
			mark_player_ship(ship)
			return ship
	return null


static func _prepare_despawn(ship: BoatBody, _tree: SceneTree) -> void:
	unmark_player_ship(ship)
	unregister_ship_from_docks(ship)
	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null:
		mooring.release_mooring()
