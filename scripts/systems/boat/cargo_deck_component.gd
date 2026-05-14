@tool
class_name CargoDeckComponent
extends Node3D

signal cargo_changed(component: CargoDeckComponent)

## Capacity is area-driven: floor(width / unit_size_x) * floor(length / unit_size_z).
@export var deck_width_m: float = 5.0:
	set(v):
		deck_width_m = maxf(v, 0.25)
		_rebuild_debug_visual()

@export var deck_length_m: float = 8.0:
	set(v):
		deck_length_m = maxf(v, 0.25)
		_rebuild_debug_visual()

@export var unit_size_x_m: float = 1.2:
	set(v):
		unit_size_x_m = maxf(v, 0.05)
		_rebuild_debug_visual()

@export var unit_size_z_m: float = 1.2:
	set(v):
		unit_size_z_m = maxf(v, 0.05)
		_rebuild_debug_visual()

## Optional safety cap in addition to area capacity. 0 = no explicit cap.
@export var max_units_override: int = 0

## If true, adding/removing cargo on this deck adjusts ancestor boat `cargo_mass`.
@export var affects_boat_cargo_mass: bool = true

@export_group("Debug")
@export var show_debug_deck_area: bool = true:
	set(v):
		show_debug_deck_area = v
		_rebuild_debug_visual()

@export var debug_color: Color = Color(0.22, 0.75, 0.33, 0.18):
	set(v):
		debug_color = v
		_rebuild_debug_visual()

@export_group("Visual cargo")
@export var spawn_visual_crates: bool = true
@export_file("*.json")
var visual_crate_mesh_path: String = "res://resources/data/meshes/crate_wooden.json"
@export_range(0.1, 3.0, 0.01) var visual_crate_scale: float = 0.62
@export var visual_crate_tint: Color = Color(0.58, 0.44, 0.31)
@export var visual_crate_height_offset_m: float = 0.16

var _entries: Dictionary = {}
var _next_ticket_id: int = 1
var _deck_mass_kg: float = 0.0
var _debug_mesh: MeshInstance3D
var _visual_root: Node3D
var _entry_visuals: Dictionary = {}


func _ready() -> void:
	_rebuild_debug_visual()


func _exit_tree() -> void:
	if affects_boat_cargo_mass and absf(_deck_mass_kg) > 1e-6:
		_apply_boat_cargo_mass_delta(-_deck_mass_kg)
		_deck_mass_kg = 0.0


func get_capacity_units() -> int:
	var cx := int(floor(deck_width_m / maxf(unit_size_x_m, 0.05)))
	var cz := int(floor(deck_length_m / maxf(unit_size_z_m, 0.05)))
	var area_capacity := maxi(cx * cz, 0)
	if max_units_override > 0:
		return mini(area_capacity, max_units_override)
	return area_capacity


func get_used_units() -> int:
	var used := 0
	for item in _entries.values():
		used += int(item.get("units", 0))
	return used


func get_available_units() -> int:
	return maxi(get_capacity_units() - get_used_units(), 0)


func is_full() -> bool:
	return get_available_units() <= 0


func can_accept(units: int = 1) -> bool:
	if units <= 0:
		return false
	return units <= get_available_units()


## Returns ticket id (>0) on success, -1 on failure.
func add_cargo(
	cargo_id: String,
	units: int = 1,
	mass_kg: float = 0.0,
	world_drop_point: Vector3 = Vector3.INF,
) -> int:
	if not can_accept(units):
		return -1

	var clamped_mass := maxf(mass_kg, 0.0)
	var has_preferred_point := world_drop_point != Vector3.INF
	var preferred_local := Vector3.ZERO
	if has_preferred_point:
		preferred_local = _clamp_to_deck_local(to_local(world_drop_point))
	var slot_idx := _pick_free_slot_index(preferred_local, has_preferred_point)
	if slot_idx < 0:
		return -1
	var local_pos := _slot_local_center(slot_idx)

	var ticket := _next_ticket_id
	_next_ticket_id += 1
	_entries[ticket] = {
		"id": cargo_id,
		"units": units,
		"mass_kg": clamped_mass,
		"local_pos": local_pos,
		"slot_idx": slot_idx,
	}
	if spawn_visual_crates:
		_spawn_entry_visual(ticket, local_pos)

	if affects_boat_cargo_mass and clamped_mass > 0.0:
		_apply_boat_cargo_mass_delta(clamped_mass)
		_deck_mass_kg += clamped_mass

	cargo_changed.emit(self)
	return ticket


## Removes a cargo ticket and returns its data (empty dictionary if missing).
func remove_cargo(ticket_id: int) -> Dictionary:
	if not _entries.has(ticket_id):
		return {}

	var item: Dictionary = _entries[ticket_id]
	_entries.erase(ticket_id)
	_remove_entry_visual(ticket_id)

	var mass_kg := maxf(float(item.get("mass_kg", 0.0)), 0.0)
	if affects_boat_cargo_mass and mass_kg > 0.0:
		_apply_boat_cargo_mass_delta(-mass_kg)
		_deck_mass_kg = maxf(_deck_mass_kg - mass_kg, 0.0)

	cargo_changed.emit(self)
	return item


func clear_all_cargo() -> void:
	var ids := _entries.keys()
	for id in ids:
		remove_cargo(int(id))


func get_entries() -> Dictionary:
	return _entries.duplicate(true)


func contains_world_point(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	return _contains_local(local)


func clamp_world_point_to_deck(world_point: Vector3) -> Vector3:
	return to_global(_clamp_to_deck_local(to_local(world_point)))


func get_world_center() -> Vector3:
	return global_position


func get_nearest_free_slot_world_position(world_point: Vector3) -> Vector3:
	var preferred_local := _clamp_to_deck_local(to_local(world_point))
	var slot_idx := _pick_free_slot_index(preferred_local, true)
	if slot_idx < 0:
		return Vector3.INF
	return to_global(_slot_local_center(slot_idx))


func get_world_corners() -> PackedVector3Array:
	var hx := deck_width_m * 0.5
	var hz := deck_length_m * 0.5
	var out := PackedVector3Array()
	out.push_back(to_global(Vector3(-hx, 0.0, -hz)))
	out.push_back(to_global(Vector3(hx, 0.0, -hz)))
	out.push_back(to_global(Vector3(hx, 0.0, hz)))
	out.push_back(to_global(Vector3(-hx, 0.0, hz)))
	return out


static func get_all_for_ship(ship_root: Node) -> Array[CargoDeckComponent]:
	var out: Array[CargoDeckComponent] = []
	if ship_root == null:
		return out
	for n in ship_root.find_children("*", "CargoDeckComponent", true, false):
		var c := n as CargoDeckComponent
		if c != null:
			out.append(c)
	return out


func _contains_local(local: Vector3) -> bool:
	var hx := deck_width_m * 0.5
	var hz := deck_length_m * 0.5
	return (
		local.x >= -hx
		and local.x <= hx
		and local.z >= -hz
		and local.z <= hz
	)


func _clamp_to_deck_local(local: Vector3) -> Vector3:
	var hx := deck_width_m * 0.5
	var hz := deck_length_m * 0.5
	return Vector3(
		clampf(local.x, -hx, hx),
		0.0,
		clampf(local.z, -hz, hz),
	)


func _resolve_boat_body() -> BoatBody:
	var p: Node = get_parent()
	while p != null:
		var b := p as BoatBody
		if b != null:
			return b
		p = p.get_parent()
	return null


func _apply_boat_cargo_mass_delta(delta_kg: float) -> void:
	var boat := _resolve_boat_body()
	if boat == null:
		return
	boat.cargo_mass = maxf(boat.cargo_mass + delta_kg, 0.0)


func _rebuild_debug_visual() -> void:
	if not is_inside_tree():
		return

	if _debug_mesh == null:
		_debug_mesh = get_node_or_null("DeckAreaDebug") as MeshInstance3D
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "DeckAreaDebug"
		_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_mesh)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			_debug_mesh.owner = get_tree().edited_scene_root

	if not show_debug_deck_area:
		_debug_mesh.visible = false
		return

	var mesh := BoxMesh.new()
	mesh.size = Vector3(deck_width_m, 0.03, deck_length_m)
	_debug_mesh.mesh = mesh
	_debug_mesh.position = Vector3(0.0, 0.015, 0.0)
	_debug_mesh.visible = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = debug_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_debug_mesh.material_override = mat


func _slot_local_center(slot_idx: int) -> Vector3:
	var cols := maxi(int(floor(deck_width_m / maxf(unit_size_x_m, 0.05))), 1)
	var rows := maxi(int(floor(deck_length_m / maxf(unit_size_z_m, 0.05))), 1)
	var clamped_idx := mini(maxi(slot_idx, 0), cols * rows - 1)

	var x_idx := clamped_idx % cols
	var z_idx := int(floor(float(clamped_idx) / float(maxi(cols, 1))))
	var step_x := deck_width_m / float(cols)
	var step_z := deck_length_m / float(rows)
	var x := -deck_width_m * 0.5 + step_x * (float(x_idx) + 0.5)
	var z := -deck_length_m * 0.5 + step_z * (float(z_idx) + 0.5)
	return Vector3(x, 0.0, z)


func _pick_free_slot_index(preferred_local: Vector3, use_preferred: bool) -> int:
	var capacity := get_capacity_units()
	if capacity <= 0:
		return -1
	var occupied: Dictionary = {}
	for item in _entries.values():
		var idx := int(item.get("slot_idx", -1))
		if idx >= 0:
			occupied[idx] = true

	var best_idx := -1
	var best_dist := INF
	for idx in range(capacity):
		if occupied.has(idx):
			continue
		if not use_preferred:
			return idx
		var center := _slot_local_center(idx)
		var d2 := preferred_local.distance_squared_to(center)
		if d2 < best_dist:
			best_dist = d2
			best_idx = idx
	return best_idx


func _ensure_visual_root() -> Node3D:
	if _visual_root != null and is_instance_valid(_visual_root):
		return _visual_root
	_visual_root = get_node_or_null("CargoVisuals") as Node3D
	if _visual_root == null:
		_visual_root = Node3D.new()
		_visual_root.name = "CargoVisuals"
		add_child(_visual_root)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			_visual_root.owner = get_tree().edited_scene_root
	return _visual_root


func _spawn_entry_visual(ticket_id: int, local_pos: Vector3) -> void:
	var root := _ensure_visual_root()
	if root == null:
		return

	var cargo := Node3D.new()
	cargo.name = "Cargo_%d" % ticket_id
	root.add_child(cargo)
	cargo.position = local_pos + Vector3(0.0, visual_crate_height_offset_m, 0.0)

	if _json_root_has_parts(visual_crate_mesh_path):
		var assembler := ModelAssembler.new()
		assembler.name = "CrateModel"
		assembler.model_data_path = visual_crate_mesh_path
		assembler.absolute_scale = visual_crate_scale
		assembler.build_part_colliders = false
		cargo.add_child(assembler)
	else:
		var transformer_script := load("res://scripts/systems/mesh_transformer.gd")
		var transformer := Node3D.new()
		transformer.set_script(transformer_script)
		transformer.name = "MeshTransformer"
		transformer.set("mesh_data_path", visual_crate_mesh_path)
		transformer.set("absolute_scale", visual_crate_scale)
		transformer.set("mesh_color", visual_crate_tint)
		transformer.set("create_collision", false)
		cargo.add_child(transformer)

	_entry_visuals[ticket_id] = cargo


func _remove_entry_visual(ticket_id: int) -> void:
	if not _entry_visuals.has(ticket_id):
		return
	var n := _entry_visuals[ticket_id] as Node
	_entry_visuals.erase(ticket_id)
	if n != null and is_instance_valid(n):
		n.queue_free()


func _json_root_has_parts(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var data = json.get_data()
	return typeof(data) == TYPE_DICTIONARY and data.has("parts")
