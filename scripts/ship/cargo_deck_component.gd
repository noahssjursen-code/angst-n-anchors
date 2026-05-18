@tool
class_name CargoDeckComponent
extends Node3D

## Slot-based cargo storage on a ship deck.
## Spawns CargoPickup nodes as visuals so the player unloads with the same
## E-to-pick-up mechanic used everywhere else — no special unload code needed.

const DECK_GROUP := "cargo_deck"

signal cargo_changed(component: CargoDeckComponent)

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

@export var max_units_override: int = 0
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
@export_file("*.json") var visual_crate_mesh_path: String = "res://resources/data/meshes/props/crate_wooden.json"
@export_range(0.1, 3.0, 0.01) var visual_crate_scale: float = 0.62
@export var visual_crate_height_offset_m: float = 0.16

var _entries: Dictionary  = {}   # ticket_id -> { item, local_pos, slot_idx }
var _next_ticket_id: int  = 1
var _deck_mass_kg: float  = 0.0
var _deck_visual: Node3D
var _visual_root: Node3D
var _entry_pickups: Dictionary = {}   # ticket_id -> CargoPickup


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(DECK_GROUP)
	_rebuild_debug_visual()


func _exit_tree() -> void:
	if affects_boat_cargo_mass and absf(_deck_mass_kg) > 1e-6:
		_apply_boat_cargo_mass_delta(-_deck_mass_kg)
		_deck_mass_kg = 0.0


# ── Capacity ──────────────────────────────────────────────────────────────────

func get_capacity_units() -> int:
	var cx           := int(floor(deck_width_m  / maxf(unit_size_x_m, 0.05)))
	var cz           := int(floor(deck_length_m / maxf(unit_size_z_m, 0.05)))
	var area_capacity := maxi(cx * cz, 0)
	if max_units_override > 0:
		return mini(area_capacity, max_units_override)
	return area_capacity


func get_used_units() -> int:
	return _entries.size()


func get_available_units() -> int:
	return maxi(get_capacity_units() - get_used_units(), 0)


func is_full() -> bool:
	return get_available_units() <= 0


func can_accept(units: int = 1) -> bool:
	return units > 0 and units <= get_available_units()


# ── Cargo API ─────────────────────────────────────────────────────────────────

## Returns ticket id (>0) on success, -1 on failure.
func add_cargo(item: CargoItem, world_drop_point: Vector3 = Vector3.INF) -> int:
	if item == null or not can_accept(1):
		return -1

	var has_preferred  := world_drop_point != Vector3.INF
	var preferred_local := Vector3.ZERO
	if has_preferred:
		preferred_local = _clamp_to_deck_local(to_local(world_drop_point))

	var slot_idx := _pick_free_slot_index(preferred_local, has_preferred)
	if slot_idx < 0:
		return -1

	var local_pos := _slot_local_center(slot_idx)
	var ticket    := _next_ticket_id
	_next_ticket_id += 1

	_entries[ticket] = {
		"item":      item,
		"local_pos": local_pos,
		"slot_idx":  slot_idx,
	}

	if spawn_visual_crates:
		_spawn_entry_pickup(ticket, item, local_pos)

	if affects_boat_cargo_mass and item.mass_kg > 0.0:
		_apply_boat_cargo_mass_delta(item.mass_kg)
		_deck_mass_kg += item.mass_kg

	cargo_changed.emit(self)
	return ticket


## Removes a cargo entry by ticket and returns the CargoItem (null if not found).
func remove_cargo(ticket_id: int) -> CargoItem:
	if not _entries.has(ticket_id):
		return null

	var entry: Dictionary = _entries[ticket_id]
	_entries.erase(ticket_id)
	_remove_entry_pickup(ticket_id)

	var item := entry.get("item") as CargoItem
	if item != null and affects_boat_cargo_mass and item.mass_kg > 0.0:
		_apply_boat_cargo_mass_delta(-item.mass_kg)
		_deck_mass_kg = maxf(_deck_mass_kg - item.mass_kg, 0.0)

	cargo_changed.emit(self)
	return item


func clear_all_cargo() -> void:
	for id in _entries.keys().duplicate():
		remove_cargo(int(id))


func get_all_items() -> Array[CargoItem]:
	var out: Array[CargoItem] = []
	for entry in _entries.values():
		var item := entry.get("item") as CargoItem
		if item != null:
			out.append(item)
	return out


# ── Spatial helpers ───────────────────────────────────────────────────────────

func contains_world_point(world_point: Vector3) -> bool:
	return _contains_local(to_local(world_point))


func get_world_center() -> Vector3:
	return global_position


func get_nearest_free_slot_world_position(world_point: Vector3) -> Vector3:
	var preferred_local := _clamp_to_deck_local(to_local(world_point))
	var slot_idx        := _pick_free_slot_index(preferred_local, true)
	if slot_idx < 0:
		return Vector3.INF
	return to_global(_slot_local_center(slot_idx))


func get_world_corners() -> PackedVector3Array:
	var hx  := deck_width_m  * 0.5
	var hz  := deck_length_m * 0.5
	var out := PackedVector3Array()
	out.push_back(to_global(Vector3(-hx, 0.0, -hz)))
	out.push_back(to_global(Vector3( hx, 0.0, -hz)))
	out.push_back(to_global(Vector3( hx, 0.0,  hz)))
	out.push_back(to_global(Vector3(-hx, 0.0,  hz)))
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


# ── Internal: slots ───────────────────────────────────────────────────────────

func _contains_local(local: Vector3) -> bool:
	var hx := deck_width_m  * 0.5
	var hz := deck_length_m * 0.5
	return local.x >= -hx and local.x <= hx and local.z >= -hz and local.z <= hz


func _clamp_to_deck_local(local: Vector3) -> Vector3:
	var hx := deck_width_m  * 0.5
	var hz := deck_length_m * 0.5
	return Vector3(clampf(local.x, -hx, hx), 0.0, clampf(local.z, -hz, hz))


func _slot_local_center(slot_idx: int) -> Vector3:
	var cols       := maxi(int(floor(deck_width_m  / maxf(unit_size_x_m, 0.05))), 1)
	var rows       := maxi(int(floor(deck_length_m / maxf(unit_size_z_m, 0.05))), 1)
	var idx        := mini(maxi(slot_idx, 0), cols * rows - 1)
	var x_idx      := idx % cols
	var z_idx      := int(floor(float(idx) / float(cols)))
	var step_x     := deck_width_m  / float(cols)
	var step_z     := deck_length_m / float(rows)
	var x          := -deck_width_m  * 0.5 + step_x * (float(x_idx) + 0.5)
	var z          := -deck_length_m * 0.5 + step_z * (float(z_idx) + 0.5)
	return Vector3(x, 0.0, z)


func _pick_free_slot_index(preferred_local: Vector3, use_preferred: bool) -> int:
	var capacity := get_capacity_units()
	if capacity <= 0:
		return -1
	var occupied: Dictionary = {}
	for entry in _entries.values():
		occupied[int(entry.get("slot_idx", -1))] = true

	var best_idx  := -1
	var best_dist := INF
	for idx in range(capacity):
		if occupied.has(idx):
			continue
		if not use_preferred:
			return idx
		var d2 := preferred_local.distance_squared_to(_slot_local_center(idx))
		if d2 < best_dist:
			best_dist = d2
			best_idx  = idx
	return best_idx


# ── Internal: visuals ─────────────────────────────────────────────────────────

func _ensure_visual_root() -> Node3D:
	if _visual_root != null and is_instance_valid(_visual_root):
		return _visual_root
	_visual_root = get_node_or_null("CargoVisuals") as Node3D
	if _visual_root == null:
		_visual_root      = Node3D.new()
		_visual_root.name = "CargoVisuals"
		add_child(_visual_root)
	return _visual_root


func _spawn_entry_pickup(ticket_id: int, item: CargoItem, local_pos: Vector3) -> void:
	var root := _ensure_visual_root()
	if root == null:
		return

	var pickup              := CargoPickup.new()
	pickup.name             = "DeckCargo_%d" % ticket_id
	pickup.mesh_path        = visual_crate_mesh_path
	pickup.mesh_scale       = visual_crate_scale
	root.add_child(pickup)
	pickup.position         = local_pos + Vector3(0.0, visual_crate_height_offset_m, 0.0)
	pickup.setup(item)
	pickup.picked_up.connect(_on_deck_cargo_picked_up.bind(ticket_id))
	_entry_pickups[ticket_id] = pickup


func _remove_entry_pickup(ticket_id: int) -> void:
	if not _entry_pickups.has(ticket_id):
		return
	var node := _entry_pickups[ticket_id] as Node
	_entry_pickups.erase(ticket_id)
	if node != null and is_instance_valid(node):
		node.queue_free()


func _on_deck_cargo_picked_up(_item: CargoItem, ticket_id: int) -> void:
	# Player picked a visual crate off the deck — remove the cargo entry.
	remove_cargo(ticket_id)


# ── Internal: boat mass ───────────────────────────────────────────────────────

func _resolve_boat_body() -> BoatBody:
	var p: Node = get_parent()
	while p != null:
		if p is BoatBody:
			return p as BoatBody
		p = p.get_parent()
	return null


func _apply_boat_cargo_mass_delta(delta_kg: float) -> void:
	var boat := _resolve_boat_body()
	if boat != null:
		boat.cargo_mass = maxf(boat.cargo_mass + delta_kg, 0.0)


# ── Internal: debug visual ────────────────────────────────────────────────────

func _rebuild_debug_visual() -> void:
	if not is_inside_tree():
		return
	if _deck_visual != null and is_instance_valid(_deck_visual):
		_deck_visual.queue_free()
		_deck_visual = null
	if not show_debug_deck_area:
		return

	_deck_visual          = Node3D.new()
	_deck_visual.name     = "DeckMarkers"
	_deck_visual.position = Vector3(0.0, 0.075, 0.0)
	add_child(_deck_visual)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_deck_visual.owner = get_tree().edited_scene_root

	var hx      := deck_width_m  * 0.5
	var hz      := deck_length_m * 0.5
	var arm     := clampf(minf(hx, hz) * 0.35, 0.5, 1.6)
	var thick   := 0.14
	var h       := 0.015
	var mat     := _hazard_material()

	_add_corner(_deck_visual, -hx, -hz,  1.0,  1.0, arm, thick, h, mat)
	_add_corner(_deck_visual,  hx, -hz, -1.0,  1.0, arm, thick, h, mat)
	_add_corner(_deck_visual, -hx,  hz,  1.0, -1.0, arm, thick, h, mat)
	_add_corner(_deck_visual,  hx,  hz, -1.0, -1.0, arm, thick, h, mat)

	var label                  := Label3D.new()
	label.text                 = "CARGO"
	label.font_size            = 96
	label.pixel_size           = 0.004
	label.modulate             = Color(0.95, 0.82, 0.0)
	label.billboard            = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees     = Vector3(-90.0, 0.0, 180.0)
	label.position             = Vector3(0.0, 0.016, 0.0)
	label.shaded               = false
	_deck_visual.add_child(label)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		label.owner = get_tree().edited_scene_root


func _add_corner(root: Node3D, cx: float, cz: float, sx: float, sz: float,
		arm: float, thick: float, h: float, mat: Material) -> void:
	var mi_x               := MeshInstance3D.new()
	var mesh_x             := BoxMesh.new()
	mesh_x.size            = Vector3(arm, h, thick)
	mi_x.mesh              = mesh_x
	mi_x.material_override = mat
	mi_x.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi_x.position          = Vector3(cx + sx * arm * 0.5, h * 0.5, cz)
	root.add_child(mi_x)

	var mi_z               := MeshInstance3D.new()
	var mesh_z             := BoxMesh.new()
	mesh_z.size            = Vector3(thick, h, arm)
	mi_z.mesh              = mesh_z
	mi_z.material_override = mat
	mi_z.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi_z.position          = Vector3(cx, h * 0.5, cz + sz * arm * 0.5)
	root.add_child(mi_z)


func _hazard_material() -> ShaderMaterial:
	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\nvoid fragment() {\n\tfloat s = fract((UV.x + UV.y) * 5.0);\n\tALBEDO = s > 0.5 ? vec3(0.95, 0.82, 0.0) : vec3(0.06, 0.06, 0.06);\n}"
	mat.shader = shader
	return mat
