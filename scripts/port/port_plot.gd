@tool
class_name PortPlot
extends Node3D

## Composition root: positions PortDock (water side) and PortFacilities (land side)
## as a matched pair. Drives both from port_size and plot dimensions.

const C_GROUND := Color(0.28, 0.34, 0.24)

const SHIP_CLASS_BY_SIZE: Dictionary = {
	0: ShipClass.Type.COASTAL_TRADER,
	1: ShipClass.Type.COASTAL_TRADER,
	2: ShipClass.Type.SHORT_SEA_COASTER,
	3: ShipClass.Type.HANDYSIZE_FEEDER,
	4: ShipClass.Type.DEEP_SEA_FREIGHTER,
}

@export var port_id: String = ""

@export var port_label: String = "Port":
	set(v): port_label = v; if is_inside_tree() and not _configuring: _rebuild()

@export var plot_width: float = 80.0:
	set(v): plot_width = v; if is_inside_tree() and not _configuring: _rebuild()

@export var plot_depth: float = 140.0:
	set(v): plot_depth = v; if is_inside_tree() and not _configuring: _rebuild()

@export var port_size: int = 1:
	set(v): port_size = v; if is_inside_tree() and not _configuring: _rebuild()

var _configuring:         bool       = false
var _berth_types_data:    Array[int] = []
var _has_fuel_point_data: bool       = true
var _has_lighthouse_data: bool       = false
var _has_fog_horn_data:   bool       = false
var _layout_seed_data:    int        = 0
var _island_width_data:   float      = 80.0
var _berth_cargo_count:   Dictionary = {}  # berth_index -> pending pickup count


func _ready() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	var hd         := plot_depth * 0.5
	var ship_class := SHIP_CLASS_BY_SIZE.get(clampi(port_size, 0, 4),
		ShipClass.Type.COASTAL_TRADER) as ShipClass.Type

	# Island ground — organic visual mesh, flat-box collision.
	# Visual: polygon built from port dimensions, organic on three sides, straight on water face.
	# Collision: simple box covering the port rectangle (players stay on the port area).
	var poly               := IslandMeshBuilder.build_polygon(_island_width_data, plot_depth, _layout_seed_data)
	var gbody              := StaticBody3D.new()
	gbody.name             = "Ground"
	add_child(gbody)

	var ground               := MeshInstance3D.new()
	ground.name              = "Mesh"
	ground.mesh              = IslandMeshBuilder.to_mesh(poly)
	var gmat                 := StandardMaterial3D.new()
	gmat.albedo_color        = C_GROUND
	gmat.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.cull_mode           = BaseMaterial3D.CULL_DISABLED
	ground.material_override = gmat
	gbody.add_child(ground)

	var gcol  := CollisionShape3D.new()
	gcol.shape = IslandMeshBuilder.to_collision_shape(poly)
	gbody.add_child(gcol)

	var dock              := PortDock.new()
	dock.name             = "PortDock"
	dock.dock_length      = plot_width
	dock.max_ship_class   = ship_class
	dock.berth_types      = _berth_types_data.duplicate()
	dock.has_fuel_point   = _has_fuel_point_data
	dock.position         = Vector3(0.0, 0.0, -hd)
	add_child(dock)

	if not port_label.is_empty():
		var name_lbl           := Label3D.new()
		name_lbl.name          = "PortNameLabel"
		name_lbl.text          = port_label.to_upper()
		name_lbl.pixel_size    = 0.014
		name_lbl.modulate      = Color(0.96, 0.92, 0.78, 0.88)
		name_lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
		name_lbl.no_depth_test = true
		name_lbl.position      = Vector3(0.0, 22.0, -hd)
		add_child(name_lbl)

	var facilities            := PortFacilities.new()
	facilities.name           = "PortFacilities"
	facilities.port_size      = port_size
	facilities.plot_width     = _island_width_data
	facilities.plot_depth     = plot_depth - PortDock.INLAND_DEPTH
	facilities.layout_seed    = _layout_seed_data
	facilities.has_lighthouse = _has_lighthouse_data
	facilities.has_fog_horn   = _has_fog_horn_data
	facilities.position       = Vector3(0.0, 0.0, -hd + PortDock.INLAND_DEPTH)
	add_child(facilities)

	if not Engine.is_editor_hint():
		call_deferred("_build_npcs")

	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


func _build_npcs() -> void:
	var facilities := get_node_or_null("PortFacilities") as PortFacilities
	if facilities == null:
		return

	# facilities.position is in port_plot local space; NPC local positions are
	# relative to facilities, so sum gives the correct port_plot-local position.
	var fpos := facilities.position

	var hm         := HarbourMasterNpc.new()
	hm.name        = "HarbourMasterNpc"
	hm.port_id     = port_id
	hm.position    = fpos + facilities.get_harbour_master_local_pos() + Vector3(0.0, 0.0, -4.5)
	add_child(hm)

	var contract_local := facilities.get_contract_npc_local_pos()
	if contract_local != Vector3.ZERO:
		var cnpc        := ContractNpc.new()
		cnpc.name       = "ContractNpc"
		cnpc.port_id    = port_id
		cnpc.position   = fpos + contract_local + Vector3(-2.0, 0.0, -5.0)
		add_child(cnpc)

	# DeliveryNpc is required at every port — even size-0 ports that have no
	# ShippingAgent. Without it, contracts targeting this port can never be
	# completed. Fall back to the harbour master position when contract_local is
	# ZERO (no ShippingAgent building).
	var delivery_ref := contract_local if contract_local != Vector3.ZERO \
						else facilities.get_harbour_master_local_pos()
	var dnpc        := DeliveryNpc.new()
	dnpc.name       = "DeliveryNpc"
	dnpc.port_id    = port_id
	dnpc.position   = fpos + delivery_ref + Vector3(2.0, 0.0, -5.0)
	add_child(dnpc)

	var sw_local := facilities.get_shipwright_local_pos()
	if sw_local != Vector3.ZERO:
		var sw      := ShipwrightNpc.new()
		sw.name     = "ShipwrightNpc"
		sw.position = fpos + sw_local + Vector3(0.0, 0.0, -5.5)
		add_child(sw)

	if not port_id.is_empty():
		call_deferred("_register_with_registry")


func _register_with_registry() -> void:
	var registry  := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	var facilities := get_node_or_null("PortFacilities") as PortFacilities
	var spawn_pos  := facilities.get_spawn_position() if facilities != null else global_position
	registry.register_port(port_id, port_label, global_position, spawn_pos)
	if not registry.contract_accepted.is_connected(_on_contract_accepted):
		registry.contract_accepted.connect(_on_contract_accepted)
	_respawn_pending_cargo(registry)


func _respawn_pending_cargo(registry: Node) -> void:
	var dock := get_node_or_null("PortDock") as PortDock
	if dock == null:
		return
	var berth_idx := dock.find_occupied_berth()
	if berth_idx == -1:
		return
	for contract in registry.get_accepted_contracts():
		var c := contract as Contract
		if c == null or c.origin_port_id != port_id:
			continue
		var remaining := c.quantity - c.delivered_count
		if remaining <= 0:
			continue
		# Count pallets already staged on this apron.
		var already_staged := 0
		for child in get_children():
			var pn := child as PalletNode
			if pn != null and pn.pallet != null and pn.pallet.contract_id == c.id:
				already_staged += pn.pallet.units
		var in_transit := _count_in_transit(c.id)
		var units_to_spawn := remaining - already_staged - in_transit
		if units_to_spawn <= 0:
			continue
		var pallets := PalletFactory.split(c, PalletFactory.DEFAULT_UNITS_PER_PALLET)
		# Filter to only the missing units by trimming already-covered pallets.
		var covered := already_staged + in_transit
		var spawn_pallets: Array[Pallet] = []
		for p in pallets:
			if covered >= (p as Pallet).units:
				covered -= (p as Pallet).units
				continue
			spawn_pallets.append(p as Pallet)
		if spawn_pallets.is_empty():
			continue
		_stage_pallets_on_apron(dock, berth_idx, spawn_pallets)


func _count_in_transit(contract_id: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var dc := node as CargoDeckComponent
		if dc == null:
			continue
		for p in dc.get_all_pallets():
			if (p as Pallet).contract_id == contract_id:
				count += (p as Pallet).units
	return count


## Called after a ship berths so cargo for accepted contracts can be staged.
func respawn_staged_cargo() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry != null:
		_respawn_pending_cargo(registry)


func _on_contract_accepted(contract: Contract, pallets: Array[Pallet]) -> void:
	if contract.origin_port_id != port_id:
		return
	var dock := get_node_or_null("PortDock") as PortDock
	if dock == null:
		return
	var berth_idx := dock.find_occupied_berth()
	if berth_idx == -1:
		return  # no ship berthed, nowhere to stage cargo
	_stage_pallets_on_apron(dock, berth_idx, pallets)


func _stage_pallets_on_apron(dock: PortDock, berth_idx: int, pallets: Array[Pallet]) -> void:
	dock.set_berth_has_cargo(berth_idx, true)
	var cur := int(_berth_cargo_count.get(berth_idx, 0))
	_berth_cargo_count[berth_idx] = cur + pallets.size()
	var positions := dock.get_berth_apron_positions(berth_idx, pallets.size())
	for i in range(pallets.size()):
		var node      := PalletNode.new()
		node.name     = "ApronPallet_" + pallets[i].id.left(8)
		add_child(node)
		node.global_position = positions[i] if i < positions.size() else dock.get_spawn_position()
		node.setup(pallets[i])
		node.grabbed.connect(_on_apron_pallet_grabbed.bind(berth_idx))


func _on_apron_pallet_grabbed(node: PalletNode, berth_idx: int) -> void:
	_berth_cargo_count[berth_idx] = (int(_berth_cargo_count.get(berth_idx, 1))) - 1
	if int(_berth_cargo_count.get(berth_idx, 0)) <= 0:
		_berth_cargo_count.erase(berth_idx)
		var dock := get_node_or_null("PortDock") as PortDock
		if dock != null:
			dock.set_berth_has_cargo(berth_idx, false)
	node.grabbed.disconnect(_on_apron_pallet_grabbed)


## Wire a PortData record into this plot. Triggers one rebuild.
## Call before or after add_child — both are safe.
func configure(data: PortData) -> void:
	_configuring             = true
	port_id                  = data.port_id
	port_label               = data.display_name
	port_size                = data.size
	plot_width               = data.dock_length
	_island_width_data       = data.island_width
	_berth_types_data        = data.berth_types.duplicate()
	_has_fuel_point_data     = data.has_fuel_point
	_has_lighthouse_data     = data.has_lighthouse
	_has_fog_horn_data       = data.has_fog_horn
	_layout_seed_data        = data.layout_seed
	_configuring             = false
	rotation.y               = data.rotation_y
	if is_inside_tree():
		_rebuild()


func get_spawn_position() -> Vector3:
	var dock := get_node_or_null("PortDock") as PortDock
	return dock.get_spawn_position() if dock != null else global_position


func _own_subtree(node: Node, esc: Node) -> void:
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
