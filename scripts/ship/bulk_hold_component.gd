@tool
class_name BulkHoldComponent
extends Node3D

## Fixed-size open bulk hold. Inventory lives in `state` — sync that for MP.

const HOLD_GROUP := "bulk_hold"
const DEPTH_SHADER := preload("res://resources/shaders/cargo_hold_depth.gdshader")

signal fill_changed(state: BulkHoldState)

@export var hold_id: String = ""
@export var hold_width_m: float = 6.0:
	set(v):
		hold_width_m = maxf(v, 0.5)
		_sync_capacity_from_geometry()
		_rebuild_visual()

@export var hold_length_m: float = 12.0:
	set(v):
		hold_length_m = maxf(v, 0.5)
		_sync_capacity_from_geometry()
		_rebuild_visual()

@export var hold_depth_m: float = 2.5:
	set(v):
		hold_depth_m = maxf(v, 0.25)
		_sync_capacity_from_geometry()
		_rebuild_visual()

var state := BulkHoldState.new()
## Imported covered holds opt out of cargo handling; legacy open holds default on.
var cargo_accessible := true

var _visual_root: Node3D
var _pit_mesh: MeshInstance3D
var _fill_layer: Node3D
var _fill_layer_commodity := ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(HOLD_GROUP)
	if hold_id.is_empty():
		hold_id = name
	state.hold_id = hold_id
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	_sync_capacity_from_geometry()
	_rebuild_visual()


func configure(
		hold_id_in: String,
		width_m: float,
		length_m: float,
		depth_m: float,
		capacity_tonnes_t: float = -1.0,
) -> void:
	hold_id = hold_id_in.strip_edges()
	if hold_id.is_empty():
		hold_id = name
	state.hold_id = hold_id
	hold_width_m = width_m
	hold_length_m = length_m
	hold_depth_m = depth_m
	if capacity_tonnes_t > 0.0:
		state.capacity_tonnes_t = capacity_tonnes_t
	else:
		_sync_capacity_from_geometry()


func get_state() -> BulkHoldState:
	return state


func apply_state(data: Dictionary) -> void:
	state = BulkHoldState.from_dict(data)
	state.hold_id = hold_id if hold_id.is_empty() else state.hold_id
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	_on_state_changed(state)


func can_accept_commodity(commodity_id: String) -> bool:
	return cargo_accessible and state.can_accept_commodity(commodity_id)


func accept_lot(lot: BulkCargoLot) -> BulkCargoLot:
	if not cargo_accessible: return lot.duplicate_lot() if lot != null else BulkCargoLot.empty()
	var before := state.filled_tonnes_t
	var overflow := state.accept_lot(lot)
	if not is_equal_approx(before, state.filled_tonnes_t):
		fill_changed.emit(state)
	return overflow


func withdraw_lot(max_tonnes_t: float) -> BulkCargoLot:
	if not cargo_accessible: return BulkCargoLot.empty()
	var before := state.filled_tonnes_t
	var taken := state.withdraw_tonnes(max_tonnes_t)
	if not is_equal_approx(before, state.filled_tonnes_t):
		fill_changed.emit(state)
	return taken


func contains_world_point(world_pos: Vector3, vertical_slack_m: float = 1.5) -> bool:
	var local := global_transform.affine_inverse() * world_pos
	var hx := hold_width_m * 0.5 * 0.94
	var hz := hold_length_m * 0.5 * 0.94
	return (
		absf(local.x) <= hx
		and absf(local.z) <= hz
		and absf(local.y) <= vertical_slack_m
	)


## Lip-centre aim point for grab cranes (world space).
func get_crane_aim_global() -> Vector3:
	return global_position + global_basis * Vector3(0.0, 0.2, 0.0)


## Aim toward a crane so parallel grabs work different ends of a long hatch.
func get_crane_aim_toward(world_hint: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * world_hint
	var hx := hold_width_m * 0.5 * 0.7
	var hz := hold_length_m * 0.5 * 0.7
	local.x = clampf(local.x, -hx, hx)
	local.z = clampf(local.z, -hz, hz)
	local.y = 0.2
	return global_transform * local


## High approach point — slew here first, then plumb hoist straight down.
func get_crane_approach_high_global(clearance_m: float = 5.5) -> Vector3:
	return get_crane_aim_global() + Vector3(0.0, clearance_m, 0.0)


func get_crane_bounds_global() -> Dictionary:
	var lip := get_crane_aim_global()
	var hx := hold_width_m * 0.5
	var hz := hold_length_m * 0.5
	var basis := global_basis
	return {
		"center": lip,
		"half_extents": Vector3(hx, 0.15, hz),
		"corner_x": basis.x,
		"corner_z": basis.z,
	}


static func get_all_for_ship(boat: Node) -> Array[BulkHoldComponent]:
	var out: Array[BulkHoldComponent] = []
	if boat == null:
		return out
	for n in boat.find_children("*", "BulkHoldComponent", true, false):
		var hold := n as BulkHoldComponent
		if hold != null:
			out.append(hold)
	return out


static func find_accepting_hold_at(world_pos: Vector3, lot: BulkCargoLot) -> BulkHoldComponent:
	if lot == null or lot.is_empty():
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var best: BulkHoldComponent = null
	var best_dist := INF
	for node in tree.get_nodes_in_group(HOLD_GROUP):
		if node is not BulkHoldComponent:
			continue
		var hold := node as BulkHoldComponent
		if not hold.contains_world_point(world_pos):
			continue
		if not hold.can_accept_commodity(lot.commodity_id):
			continue
		if hold.state.available_tonnes_t() <= BulkCargoLot.TONNES_EPS:
			continue
		var dist := hold.global_position.distance_squared_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = hold
	return best


static func find_filled_hold_at(
		world_pos: Vector3,
		commodity_id: String = "",
) -> BulkHoldComponent:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var cid := commodity_id.strip_edges()
	var best: BulkHoldComponent = null
	var best_dist := INF
	for node in tree.get_nodes_in_group(HOLD_GROUP):
		if node is not BulkHoldComponent:
			continue
		var hold := node as BulkHoldComponent
		if hold.state.is_empty():
			continue
		if not hold.cargo_accessible: continue
		if not cid.is_empty() and hold.state.commodity_id != cid:
			continue
		if not hold.contains_world_point(world_pos):
			continue
		var dist := hold.global_position.distance_squared_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = hold
	return best


func _sync_capacity_from_geometry() -> void:
	state.capacity_tonnes_t = BulkCargoRules.hold_capacity_tonnes(
		hold_width_m,
		hold_length_m,
		hold_depth_m,
		state.commodity_id if not state.is_empty() else "iron_ore",
	)


func _on_state_changed(_state: BulkHoldState) -> void:
	_update_fill_visual()


func _inner_fill_size() -> Vector3:
	var rim_t := 0.14
	var w := maxf(hold_width_m - rim_t * 2.0, 0.2) * 0.90
	var l := maxf(hold_length_m - rim_t * 2.0, 0.2) * 0.90
	var h := maxf(hold_depth_m * 0.85, 0.15)
	return Vector3(w, h, l)


func _clear_fill_layer() -> void:
	if _fill_layer != null and is_instance_valid(_fill_layer):
		_fill_layer.queue_free()
	_fill_layer = null
	_fill_layer_commodity = ""


func _update_fill_visual() -> void:
	if _pit_mesh != null and is_instance_valid(_pit_mesh):
		var mat := _pit_mesh.material_override as ShaderMaterial
		if mat != null:
			var ratio := state.fill_ratio()
			mat.set_shader_parameter("pit_depth", lerpf(0.92, 0.35, ratio))
			mat.set_shader_parameter(
				"hold_color",
				Color(0.02, 0.02, 0.035).lerp(Color(0.05, 0.04, 0.03), ratio * 0.65),
			)
	_update_cargo_fill_layer()


func _update_cargo_fill_layer() -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	var ratio := state.fill_ratio()
	if ratio <= BulkCargoLot.TONNES_EPS or state.commodity_id.is_empty():
		_clear_fill_layer()
		return
	var commodity := state.commodity_id
	if (
		_fill_layer == null
		or not is_instance_valid(_fill_layer)
		or _fill_layer_commodity != commodity
	):
		_clear_fill_layer()
		_fill_layer = OreMoundBuilder.build_mound(commodity, _inner_fill_size(), hash(hold_id))
		_fill_layer.name = "FillLayer"
		_fill_layer_commodity = commodity
		_visual_root.add_child(_fill_layer)
	_fill_layer.scale = Vector3(1.0, ratio, 1.0)
	_fill_layer.visible = true


static func build_visual(
		width_m: float,
		length_m: float,
		depth_m: float,
		preview: bool = false,
		fill_ratio: float = 0.0,
) -> Node3D:
	var root := Node3D.new()
	root.name = "BulkHoldVisual"

	var rim_h := 0.22
	var rim_t := 0.14
	var rim_col := Color(0.07, 0.07, 0.08)
	var hx := width_m * 0.5
	var hz := length_m * 0.5
	var inner_w := maxf(width_m - rim_t * 2.0, 0.2)
	var inner_l := maxf(length_m - rim_t * 2.0, 0.2)
	var ratio := clampf(fill_ratio, 0.0, 1.0)

	var pit := MeshInstance3D.new()
	pit.name = "Pit"
	var pit_mesh := BoxMesh.new()
	pit_mesh.size = Vector3(inner_w * 0.98, 0.04, inner_l * 0.98)
	pit.mesh = pit_mesh
	pit.position = Vector3(0.0, -0.02, 0.0)
	var pit_mat := ShaderMaterial.new()
	pit_mat.shader = DEPTH_SHADER
	pit_mat.set_shader_parameter("hold_color", Color(0.02, 0.02, 0.035))
	pit_mat.set_shader_parameter("rim_strength", 0.78 if preview else 0.72)
	pit_mat.set_shader_parameter("pit_depth", lerpf(0.92, 0.35, ratio))
	pit.material_override = pit_mat
	root.add_child(pit)

	_add_coaming_wall(root, Vector3(0.0, rim_h * 0.5, -hz + rim_t * 0.5), Vector3(width_m, rim_h, rim_t), rim_col)
	_add_coaming_wall(root, Vector3(0.0, rim_h * 0.5, hz - rim_t * 0.5), Vector3(width_m, rim_h, rim_t), rim_col)
	_add_coaming_wall(root, Vector3(-hx + rim_t * 0.5, rim_h * 0.5, 0.0), Vector3(rim_t, rim_h, length_m), rim_col)
	_add_coaming_wall(root, Vector3(hx - rim_t * 0.5, rim_h * 0.5, 0.0), Vector3(rim_t, rim_h, length_m), rim_col)

	var lip := MeshBuilder.box(
		Vector3(width_m * 1.02, 0.03, length_m * 1.02),
		Color(0.05, 0.05, 0.06),
		0.9,
		0.05,
	)
	lip.position = Vector3(0.0, 0.015, 0.0)
	root.add_child(lip)

	var shadow := MeshBuilder.box(
		Vector3(inner_w * 0.72, maxf(depth_m * 0.12, 0.08), inner_l * 0.72),
		Color(0.01, 0.01, 0.015),
		1.0,
		0.0,
	)
	shadow.position = Vector3(0.0, -maxf(depth_m * 0.06, 0.04), 0.0)
	root.add_child(shadow)

	return root


func _rebuild_visual() -> void:
	_clear_fill_layer()
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()
		_visual_root = null
	_pit_mesh = null
	_visual_root = build_visual(
		hold_width_m,
		hold_length_m,
		hold_depth_m,
		Engine.is_editor_hint(),
		state.fill_ratio(),
	)
	_visual_root.name = "Visual"
	add_child(_visual_root)
	_pit_mesh = _visual_root.get_node_or_null("Pit") as MeshInstance3D
	_update_fill_visual()


static func _add_coaming_wall(
		root: Node3D,
		pos: Vector3,
		size: Vector3,
		color: Color,
) -> void:
	var wall := MeshBuilder.box(size, color, 0.88, 0.08)
	wall.position = pos
	root.add_child(wall)
