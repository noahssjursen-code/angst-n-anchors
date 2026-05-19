@tool
class_name PortPlot
extends Node3D

## Composition root: positions PortDock (water side) and PortFacilities (land side)
## as a matched pair. Drives both from port_size and plot dimensions.

const SHIP_CLASS_BY_SIZE: Dictionary = {
	0: ShipClass.Type.COASTAL_TRADER,
	1: ShipClass.Type.COASTAL_TRADER,
	2: ShipClass.Type.SHORT_SEA_COASTER,
	3: ShipClass.Type.HANDYSIZE_FEEDER,
	4: ShipClass.Type.DEEP_SEA_FREIGHTER,
}

## Extra flat terrain extending beyond the facilities footprint on all sides,
## so noise hills never bleed into building collision. Combined with
## IslandMeshBuilder.PAD_BLEND_M, this gives buildings ~8 m of pad + ~10 m of
## ramp before the noise terrain reaches full height.
const PAD_SAFE_MARGIN: float = 8.0

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

	# Island ground — heightmapped terrain with a flat port pad stamped along the
	# water face. Pad sized to the *island* width (facilities span the full island,
	# not just the dock-length), plus a safe margin so hills don't grow into the
	# outermost buildings (warehouses at the flanks, lighthouse at the inland edge).
	# See IslandMeshBuilder for the height function.
	var pad_w              := _island_width_data + 2.0 * PAD_SAFE_MARGIN
	var pad_d              := plot_depth + 2.0 * PAD_SAFE_MARGIN
	var poly               := IslandMeshBuilder.build_polygon(_island_width_data, plot_depth, _layout_seed_data)
	var gbody              := StaticBody3D.new()
	gbody.name             = "Ground"
	add_child(gbody)

	var ground               := MeshInstance3D.new()
	ground.name              = "Mesh"
	ground.mesh              = IslandMeshBuilder.to_mesh(poly, pad_w, pad_d, _layout_seed_data)
	var gmat                 := StandardMaterial3D.new()
	gmat.albedo_color        = Color.WHITE
	gmat.vertex_color_use_as_albedo = true
	gmat.shading_mode        = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	gmat.roughness           = 0.92
	# Cull back faces — the terrain is a closed surface viewed from above.
	# CULL_DISABLED rendered both sides, which combined with the (now-fixed)
	# downward winding made the island look like translucent crystal facets.
	gmat.cull_mode           = BaseMaterial3D.CULL_BACK
	ground.material_override = gmat
	gbody.add_child(ground)

	var gcol  := CollisionShape3D.new()
	gcol.shape = IslandMeshBuilder.to_collision_shape(poly, pad_w, pad_d, _layout_seed_data)
	gbody.add_child(gcol)

	var dock              := PortDock.new()
	dock.name             = "PortDock"
	dock.port_id          = port_id
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

	_build_trees(poly, pad_w, pad_d)

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

	# (DeliveryNpc retired — the apron CargoDeckComponent now handles delivery
	# directly when the crane releases a pallet whose destination matches the
	# port. See CargoDeckComponent.accepts_delivery / deliver_pallet.)

	var sw_local := facilities.get_shipwright_local_pos()
	if sw_local != Vector3.ZERO:
		var sw      := ShipwrightNpc.new()
		sw.name     = "ShipwrightNpc"
		sw.position = fpos + sw_local + Vector3(0.0, 0.0, -5.5)
		add_child(sw)

	_build_walkers(fpos)

	if not port_id.is_empty():
		call_deferred("_register_with_registry")


func _build_trees(poly: PackedVector2Array, pad_w: float, pad_d: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _layout_seed_data ^ 0x74726565  # "tree" XOR'd so placement differs from layout

	var aabb_min := Vector2( INF,  INF)
	var aabb_max := Vector2(-INF, -INF)
	for p in poly:
		aabb_min.x = minf(aabb_min.x, p.x)
		aabb_min.y = minf(aabb_min.y, p.y)
		aabb_max.x = maxf(aabb_max.x, p.x)
		aabb_max.y = maxf(aabb_max.y, p.y)

	var n_trees     : int   = 10 + port_size * 8
	var pad_hw      : float = pad_w * 0.5
	var pad_hd      : float = pad_d * 0.5
	var excl_margin : float = 4.0  # extra buffer inside pad edge before trees begin

	var placed   := 0
	var attempts := 0
	while placed < n_trees and attempts < n_trees * 25:
		attempts += 1
		var x  := rng.randf_range(aabb_min.x, aabb_max.x)
		var z  := rng.randf_range(aabb_min.y, aabb_max.y)
		var p2 := Vector2(x, z)
		if not Geometry2D.is_point_in_polygon(p2, poly):
			continue
		# Keep trees outside the flat pad + margin
		if absf(x) < pad_hw + excl_margin and absf(z) < pad_hd + excl_margin:
			continue
		var h := IslandMeshBuilder.get_height_at(p2, poly, pad_w, pad_d, _layout_seed_data)
		if h < 1.0:  # skip beach / near-shore
			continue
		_place_tree(Vector3(x, h, z), rng)
		placed += 1


func _place_tree(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var s   : float = rng.randf_range(0.75, 1.35)
	var rot : float = rng.randf_range(0.0, TAU)

	var root      := Node3D.new()
	root.name      = "Tree"
	root.position  = pos
	root.rotation.y = rot
	add_child(root)

	# Trunk
	var trunk_mesh              := CylinderMesh.new()
	trunk_mesh.top_radius       = 0.20 * s
	trunk_mesh.bottom_radius    = 0.28 * s
	trunk_mesh.height           = 3.2  * s
	var trunk_mat               := StandardMaterial3D.new()
	trunk_mat.albedo_color      = Color(0.22, 0.13, 0.07)
	trunk_mat.roughness         = 0.92
	var trunk_mi                := MeshInstance3D.new()
	trunk_mi.mesh               = trunk_mesh
	trunk_mi.material_override  = trunk_mat
	trunk_mi.position           = Vector3(0.0, 1.6 * s, 0.0)
	root.add_child(trunk_mi)

	# Foliage — three stacked cones, widest at base
	var foliage_color := Color(0.07, 0.17, 0.05)
	var layers : Array[Array] = [
		[2.6 * s, 0.0, 4.2 * s, 2.2 * s],   # [bot_r, top_r, height, centre_y]
		[1.9 * s, 0.0, 3.4 * s, 5.0 * s],
		[1.1 * s, 0.0, 2.6 * s, 7.2 * s],
	]
	for layer in layers:
		var cone_mesh              := CylinderMesh.new()
		cone_mesh.bottom_radius    = layer[0]
		cone_mesh.top_radius       = layer[1]
		cone_mesh.height           = layer[2]
		var cone_mat               := StandardMaterial3D.new()
		cone_mat.albedo_color      = foliage_color
		cone_mat.roughness         = 0.88
		var cone_mi                := MeshInstance3D.new()
		cone_mi.mesh               = cone_mesh
		cone_mi.material_override  = cone_mat
		cone_mi.position           = Vector3(0.0, layer[3], 0.0)
		root.add_child(cone_mi)


## Spawn the port's ambient walkers. Each one is deterministic from
## (layout_seed, npc_index), so two clients with the same world see the same
## people walking the same loops — zero replication. Walker count scales
## with port_size; positions are local to the port plot so the walkers move
## with the port if it ever gets re-placed.
func _build_walkers(facilities_pos: Vector3) -> void:
	var count := AmbientPopulation.walker_count_for_size(port_size)
	if count <= 0:
		return
	# Walker loops are anchored at the port-plot origin (where the island is
	# centred) and sized to the island's half-width.
	var radius := _island_width_data * 0.5
	for i in range(count):
		var walker := WalkingNpc.new()
		walker.name          = "Walker_%d" % i
		walker.port_seed     = _layout_seed_data
		walker.npc_index     = i
		walker.port_radius   = radius
		# Loops are computed at the patrol origin (0,0); the walker adds this
		# anchor each frame to land in port-plot local space.
		walker.anchor_offset = facilities_pos
		add_child(walker)


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
	var apron := dock.get_berth_apron_deck(berth_idx)
	if apron == null:
		return
	for contract in registry.get_accepted_contracts():
		var c := contract as Contract
		if c == null or c.origin_port_id != port_id:
			continue
		# Pallets that SHOULD currently exist somewhere = accepted but not yet
		# delivered. Anything missing gets re-spawned on the apron.
		var in_play := c.taken_count - c.delivered_count
		if in_play <= 0:
			continue
		var already_staged := 0
		for p in apron.get_all_pallets():
			if (p as Pallet).contract_id == c.id:
				already_staged += (p as Pallet).units
		var elsewhere := _count_in_transit(c.id) - already_staged
		var units_to_spawn := in_play - already_staged - elsewhere
		if units_to_spawn <= 0:
			continue
		# Build a batch contract for splitting just the missing units.
		var batch := Contract.new()
		batch.id                  = c.id
		batch.commodity           = c.commodity
		batch.display_name        = c.display_name
		batch.quantity            = units_to_spawn
		batch.mass_per_unit_kg    = c.mass_per_unit_kg
		batch.reward_gold         = c.reward_per_unit() * units_to_spawn
		batch.origin_port_id      = c.origin_port_id
		batch.destination_port_id = c.destination_port_id
		_stage_pallets_on_apron(dock, berth_idx, PalletFactory.split(batch))


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
	var apron := dock.get_berth_apron_deck(berth_idx)
	if apron == null:
		return
	# Listen once per apron — the deck is the source of truth for "has cargo".
	if not apron.cargo_changed.is_connected(_on_apron_changed):
		apron.cargo_changed.connect(_on_apron_changed.bind(dock, berth_idx))
	for p in pallets:
		# add_pallet picks the nearest free cell and spawns the visual itself.
		# Passing INF lets the deck choose any free cell.
		apron.add_pallet(p)
	_on_apron_changed(apron, dock, berth_idx)


func _on_apron_changed(apron: CargoDeckComponent, dock: PortDock, berth_idx: int) -> void:
	if apron == null or dock == null:
		return
	dock.set_berth_has_cargo(berth_idx, apron.get_used() > 0)


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
