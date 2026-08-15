@tool
class_name CargoSlotPadComponent
extends Node3D

## Visible container slot grid on a ship deck. Cells are **0.5 m**
## (`DeckGrid.CELL_M`) — this line said 1 m, which is double, and `cell_size_m`
## is set from `DeckGrid.CELL_M` by `DeckFitout`, so the pad has always drawn
## the 0.5 m cell the comment denied.
## Containers reserve a footprint block (default 4×4 m — two wide on an 8 m pad).

const PAD_GROUP := "cargo_slot_pad"
const YARD_PAD_GROUP := "container_yard_pad"
const MASS_PREFIX := "cargo_pad_"
const SNAP_RADIUS_M := 6.0
## Decorative quay yards cap how many live containers we stamp.
const MAX_DECOR_PREFILL := 28

signal cargo_changed(component: CargoSlotPadComponent)
signal container_landed(component: CargoSlotPadComponent, unit: ContainerUnit)

@export var deck_width_m: float = 8.0:
	set(v):
		deck_width_m = maxf(v, 0.25)
		_rebuild_visual()

@export var deck_length_m: float = 16.0:
	set(v):
		deck_length_m = maxf(v, 0.25)
		_rebuild_visual()

@export var cell_size_m: float = 1.0:
	set(v):
		cell_size_m = maxf(v, 0.2)
		_rebuild_visual()

## When true, each container on this pad adds mass (category cargo) and shifts CoM.
## Loaded cargo should sink the hull slightly; disable for visual-only pads.
@export var affects_boat_cargo_mass: bool = true
## Quay stack yard — same slot tiling as ship pads; joins container_yard_pad.
@export var is_quay_yard_pad: bool = false
@export var pad_color: Color = Color(0.16, 0.18, 0.22, 0.92):
	set(v):
		pad_color = v
		_rebuild_visual()

@export var slot_line_color: Color = Color(0.35, 0.55, 0.78, 0.55):
	set(v):
		slot_line_color = v
		_rebuild_visual()

## Container slot size in pad cells (default 4×4 m). Pad dimensions should be whole multiples.
@export var container_footprint: Vector2i = ContainerUnit.DEFAULT_FOOTPRINT

## cell_idx → ContainerUnit (origin cell owns the unit; footprint cells share it)
var _cells: Dictionary = {}
var _nodes: Dictionary = {} ## origin_idx → ContainerNode
var _visual_root: Node3D
var _container_root: Node3D
var _deck_mass_kg: float = 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(PAD_GROUP)
		if is_quay_yard_pad:
			add_to_group(YARD_PAD_GROUP)
	_rebuild_visual()


func _exit_tree() -> void:
	if affects_boat_cargo_mass:
		var boat := _resolve_boat()
		if boat != null:
			boat.clear_mass_entries(_mass_prefix())
		_deck_mass_kg = 0.0


func get_cols() -> int:
	return maxi(int(floor(deck_width_m / maxf(cell_size_m, 0.2))), 1)


func get_rows() -> int:
	return maxi(int(floor(deck_length_m / maxf(cell_size_m, 0.2))), 1)


func get_slot_footprint() -> Vector2i:
	var fp := container_footprint
	if fp.x < 1 or fp.y < 1:
		fp = ContainerUnit.DEFAULT_FOOTPRINT
	return fp


func get_slot_cols() -> int:
	var fp := get_slot_footprint()
	return maxi(get_cols() / fp.x, 0)


func get_slot_rows() -> int:
	var fp := get_slot_footprint()
	return maxi(get_rows() / fp.y, 0)


func get_max_slots() -> int:
	return get_slot_cols() * get_slot_rows()


func get_free_slot_count(fp: Vector2i = Vector2i.ZERO) -> int:
	var use_fp := fp if fp.x >= 1 and fp.y >= 1 else get_slot_footprint()
	var n := 0
	for origin in _iter_slot_origins(use_fp):
		if _block_free(origin, use_fp):
			n += 1
	return n


func get_containers() -> Array[ContainerUnit]:
	var seen: Dictionary = {}
	var out: Array[ContainerUnit] = []
	for unit in _cells.values():
		if unit == null or not (unit is ContainerUnit):
			continue
		var u := unit as ContainerUnit
		if seen.has(u.id):
			continue
		seen[u.id] = true
		out.append(u)
	return out


## Fill yard slots. Prefer `fill_fraction` (0–1 of capacity); else exact `count`.
func prefill_general_cargo(
		count: int = -1,
		origin_port_id: String = "",
		fill_fraction: float = -1.0,
) -> void:
	var n := count
	if fill_fraction >= 0.0:
		n = int(round(float(get_max_slots()) * clampf(fill_fraction, 0.0, 1.0)))
	if not affects_boat_cargo_mass:
		n = mini(maxi(n, 0), MAX_DECOR_PREFILL)
	for _i in range(maxi(n, 0)):
		var unit := ContainerFactory.make_one(origin_port_id, "", "provisions")
		if add_container(unit) < 0:
			break


func clear_all() -> void:
	for node in _nodes.values():
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
	_nodes.clear()
	_cells.clear()
	_refresh_mass()
	cargo_changed.emit(self)


func add_container(unit: ContainerUnit, world_hint: Vector3 = Vector3.INF) -> int:
	if unit == null:
		return -1
	var fp := unit.footprint
	if fp.x < 1 or fp.y < 1:
		fp = ContainerUnit.DEFAULT_FOOTPRINT
	var preferred := Vector2.ZERO
	var use_hint := false
	if world_hint != Vector3.INF:
		var local := to_local(world_hint)
		preferred = Vector2(local.x, local.z)
		use_hint = true
	var origin := _find_free_block(fp, preferred, use_hint)
	if origin < 0:
		return -1
	for cell_idx in _block_cells(origin, fp):
		_cells[cell_idx] = unit
	_spawn_node(origin, unit)
	_refresh_mass()
	container_landed.emit(self, unit)
	cargo_changed.emit(self)
	return origin


func place_container_node(node: ContainerNode, world_hint: Vector3 = Vector3.INF) -> int:
	if node == null or node.unit == null:
		return -1
	var unit := node.unit
	var fp := unit.footprint
	if fp.x < 1 or fp.y < 1:
		fp = ContainerUnit.DEFAULT_FOOTPRINT
		unit.footprint = fp
	var preferred := Vector2.ZERO
	var use_hint := false
	if world_hint != Vector3.INF:
		var local := to_local(world_hint)
		preferred = Vector2(local.x, local.z)
		use_hint = true
	var origin := _find_free_block(fp, preferred, use_hint)
	if origin < 0:
		return -1
	for cell_idx in _block_cells(origin, fp):
		_cells[cell_idx] = unit
	if _container_root == null:
		_container_root = Node3D.new()
		_container_root.name = "Containers"
		add_child(_container_root)
	if node.get_parent() != _container_root:
		node.reparent(_container_root, true)
	node.position = _cell_center_local(origin, fp)
	node.position.y = ContainerNode.floor_offset_y()
	node.rotation = Vector3.ZERO
	_nodes[origin] = node
	_refresh_mass()
	container_landed.emit(self, unit)
	cargo_changed.emit(self)
	return origin


func take_container_node(node: ContainerNode) -> ContainerUnit:
	if node == null:
		return null
	var origin := _origin_for_node(node)
	if origin < 0:
		return node.unit
	var unit: ContainerUnit = _cells.get(origin) as ContainerUnit
	var fp := unit.footprint if unit != null else ContainerUnit.DEFAULT_FOOTPRINT
	for cell_idx in _block_cells(origin, fp):
		_cells.erase(cell_idx)
	_nodes.erase(origin)
	_refresh_mass()
	cargo_changed.emit(self)
	return unit


func contains_node(node: ContainerNode) -> bool:
	return _origin_for_node(node) >= 0


func contains_world_point(world_pos: Vector3) -> bool:
	var local := to_local(world_pos)
	var half_w := deck_width_m * 0.5
	var half_l := deck_length_m * 0.5
	return absf(local.x) <= half_w + 0.05 and absf(local.z) <= half_l + 0.05


func try_place_container_node(node: ContainerNode, world_pos: Vector3) -> bool:
	if node == null or not contains_world_point(world_pos):
		return false
	return place_container_node(node, world_pos) >= 0


static func find_nearest_pad(
	tree: SceneTree,
	world_pos: Vector3,
	max_dist_m: float = SNAP_RADIUS_M,
) -> CargoSlotPadComponent:
	if tree == null:
		return null
	var best: CargoSlotPadComponent = null
	var best_d := max_dist_m
	for node in tree.get_nodes_in_group(PAD_GROUP):
		if node is not CargoSlotPadComponent:
			continue
		var pad := node as CargoSlotPadComponent
		if pad.contains_world_point(world_pos):
			return pad
		var local := pad.to_local(world_pos)
		var half_w := pad.deck_width_m * 0.5
		var half_l := pad.deck_length_m * 0.5
		var dx := maxf(absf(local.x) - half_w, 0.0)
		var dz := maxf(absf(local.z) - half_l, 0.0)
		var edge_dist := sqrt(dx * dx + dz * dz)
		if edge_dist < best_d:
			best_d = edge_dist
			best = pad
	return best


static func find_yard_pad(tree: SceneTree) -> CargoSlotPadComponent:
	return find_nearest_yard_pad(tree, Vector3.INF)


## Prefer the yard closest to `near_world` (crane / hook). Falls back to first yard.
static func find_nearest_yard_pad(
		tree: SceneTree,
		near_world: Vector3 = Vector3.INF,
		berth_id: String = "",
		equipment_id: String = "",
) -> CargoSlotPadComponent:
	if tree == null:
		return null
	var best: CargoSlotPadComponent = null
	var best_d := INF
	var use_near := near_world != Vector3.INF
	for node in tree.get_nodes_in_group(YARD_PAD_GROUP):
		if node is not CargoSlotPadComponent:
			continue
		var pad := node as CargoSlotPadComponent
		if not berth_id.is_empty() and str(pad.get_meta("berth_id", "")) != berth_id:
			continue
		if not equipment_id.is_empty() \
				and str(pad.get_meta("equipment_id", "")) != equipment_id:
			continue
		if not use_near:
			return pad
		var d := pad.global_position.distance_squared_to(near_world)
		if d < best_d:
			best_d = d
			best = pad
	return best


static func is_on_ship_pad(node: ContainerNode) -> bool:
	var pad := find_pad_for_node(node)
	return pad != null and not pad.is_quay_yard_pad


static func is_on_yard_pad(node: ContainerNode) -> bool:
	var pad := find_pad_for_node(node)
	return pad != null and pad.is_quay_yard_pad


static func find_pad_for_node(node: ContainerNode) -> CargoSlotPadComponent:
	if node == null:
		return null
	var n: Node = node
	while n != null:
		if n is CargoSlotPadComponent:
			return n as CargoSlotPadComponent
		n = n.get_parent()
	return null


func remove_container_at(origin_idx: int) -> ContainerUnit:
	if not _nodes.has(origin_idx):
		return null
	var unit: ContainerUnit = null
	if _cells.has(origin_idx):
		unit = _cells[origin_idx] as ContainerUnit
	var fp := unit.footprint if unit != null else ContainerUnit.DEFAULT_FOOTPRINT
	for cell_idx in _block_cells(origin_idx, fp):
		_cells.erase(cell_idx)
	var node: Node = _nodes.get(origin_idx) as Node
	_nodes.erase(origin_idx)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_refresh_mass()
	cargo_changed.emit(self)
	return unit


func find_free_slot(fp: Vector2i = Vector2i.ZERO) -> int:
	var use_fp := fp if fp.x >= 1 and fp.y >= 1 else get_slot_footprint()
	return _find_free_block(use_fp, Vector2.ZERO, false)


func slot_drop_world_for_free(fp: Vector2i = Vector2i.ZERO) -> Vector3:
	var use_fp := fp if fp.x >= 1 and fp.y >= 1 else get_slot_footprint()
	var origin := _find_free_block(use_fp, Vector2.ZERO, false)
	if origin < 0:
		return Vector3.INF
	return to_global(_cell_center_local(origin, use_fp))


func iter_container_nodes() -> Array[ContainerNode]:
	var out: Array[ContainerNode] = []
	var seen: Dictionary = {}
	for node in _nodes.values():
		if node == null or not (node is ContainerNode):
			continue
		var cn := node as ContainerNode
		if seen.has(cn.get_instance_id()):
			continue
		seen[cn.get_instance_id()] = true
		out.append(cn)
	return out


func _iter_slot_origins(fp: Vector2i) -> Array[int]:
	var cols := get_cols()
	var rows := get_rows()
	var out: Array[int] = []
	for r in range(0, rows - fp.y + 1, fp.y):
		for c in range(0, cols - fp.x + 1, fp.x):
			out.append(r * cols + c)
	return out


func _find_free_block(fp: Vector2i, preferred_local: Vector2, use_hint: bool) -> int:
	if fp.x < 1 or fp.y < 1:
		fp = get_slot_footprint()
	var best := -1
	var best_dist := INF
	for origin in _iter_slot_origins(fp):
		if not _block_free(origin, fp):
			continue
		if not use_hint:
			return origin
		var center := _cell_center_local(origin, fp)
		var d := preferred_local.distance_squared_to(Vector2(center.x, center.z))
		if d < best_dist:
			best_dist = d
			best = origin
	return best


func _block_free(origin: int, fp: Vector2i) -> bool:
	for idx in _block_cells(origin, fp):
		if _cells.has(idx):
			return false
	return true


func _block_cells(origin: int, fp: Vector2i) -> Array[int]:
	var cols := get_cols()
	var ox := origin % cols
	var oz := int(origin / cols)
	var out: Array[int] = []
	for dz in range(fp.y):
		for dx in range(fp.x):
			out.append((oz + dz) * cols + (ox + dx))
	return out


func _cell_center_local(origin: int, fp: Vector2i) -> Vector3:
	var cols := get_cols()
	var ox := origin % cols
	var oz := int(origin / cols)
	var half_w := deck_width_m * 0.5
	var half_l := deck_length_m * 0.5
	var x0 := -half_w + (float(ox) + float(fp.x) * 0.5) * cell_size_m
	var z0 := -half_l + (float(oz) + float(fp.y) * 0.5) * cell_size_m
	return Vector3(x0, 0.0, z0)


func _spawn_node(origin: int, unit: ContainerUnit) -> void:
	var node := ContainerNode.new()
	node.name = "Container_%s" % unit.id
	if _container_root == null:
		_container_root = Node3D.new()
		_container_root.name = "Containers"
		add_child(_container_root)
	_container_root.add_child(node)
	node.position = _cell_center_local(origin, unit.footprint)
	node.position.y = ContainerNode.floor_offset_y()
	## Quay yards still skip boat mass, but containers must block walking.
	node.setup(unit, false)
	_nodes[origin] = node


func _origin_for_node(node: ContainerNode) -> int:
	for origin in _nodes.keys():
		if _nodes[origin] == node:
			return int(origin)
	return -1


func _rebuild_visual() -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()
	_visual_root = Node3D.new()
	_visual_root.name = "PadVisual"
	add_child(_visual_root)
	## Deck plate
	var plate := MeshBuilder.box(
		Vector3(deck_width_m, 0.06, deck_length_m),
		pad_color,
		0.95,
		0.0,
	)
	plate.name = "Plate"
	plate.position = Vector3(0.0, -0.03, 0.0)
	_visual_root.add_child(plate)
	## Slot grid lines + container bay outlines — merged to cut draw calls.
	var cols := get_cols()
	var rows := get_rows()
	var half_w := deck_width_m * 0.5
	var half_l := deck_length_m * 0.5
	var line_y := 0.02
	var line_parts: Array = []
	for c in range(cols + 1):
		var x := -half_w + float(c) * cell_size_m
		line_parts.append({
			"size": Vector3(0.03, 0.02, deck_length_m),
			"position": Vector3(x, line_y, 0.0),
		})
	for r in range(rows + 1):
		var z := -half_l + float(r) * cell_size_m
		line_parts.append({
			"size": Vector3(deck_width_m, 0.02, 0.03),
			"position": Vector3(0.0, line_y, z),
		})
	if not line_parts.is_empty():
		var lines := MeshBuilder.merged_boxes(line_parts, slot_line_color, 1.0, 0.0)
		lines.name = "GridLines"
		_visual_root.add_child(lines)
	var fp := get_slot_footprint()
	var bay_w := float(fp.x) * cell_size_m
	var bay_l := float(fp.y) * cell_size_m
	var mark_parts: Array = []
	for origin in _iter_slot_origins(fp):
		var center := _cell_center_local(origin, fp)
		mark_parts.append({
			"size": Vector3(bay_w * 0.98, 0.015, bay_l * 0.98),
			"position": Vector3(center.x, -0.01, center.z),
		})
	if not mark_parts.is_empty():
		var mark_color := Color(slot_line_color.r, slot_line_color.g, slot_line_color.b, 0.22)
		var marks := MeshBuilder.merged_boxes(mark_parts, mark_color, 1.0, 0.0)
		marks.name = "SlotMarks"
		_visual_root.add_child(marks)


func _refresh_mass() -> void:
	if not affects_boat_cargo_mass:
		return
	var boat := _resolve_boat()
	if boat == null:
		return
	boat.clear_mass_entries(_mass_prefix())
	_deck_mass_kg = 0.0
	var i := 0
	for origin in _nodes.keys():
		var node := _nodes[origin] as ContainerNode
		if node == null or not is_instance_valid(node) or node.unit == null:
			continue
		var kg := maxf(node.unit.mass_kg, 0.0)
		_deck_mass_kg += kg
		boat.set_mass_entry(
			"%s%d" % [_mass_prefix(), i],
			kg,
			boat.to_local(node.global_position),
			"cargo",
		)
		i += 1


func _mass_prefix() -> String:
	return MASS_PREFIX + name + "_"


func _resolve_boat() -> BoatBody:
	var n: Node = self
	while n != null:
		if n is BoatBody:
			return n as BoatBody
		n = n.get_parent()
	return null
