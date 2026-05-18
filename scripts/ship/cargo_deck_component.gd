@tool
class_name CargoDeckComponent
extends Node3D

## Slot-based cargo storage on a ship deck.
## Stores Pallets; each pallet occupies exactly one grid cell.
## Spawns a PalletNode visual so the crane can interact with it.

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

@export var cell_size_x_m: float = 1.5:
	set(v):
		cell_size_x_m = maxf(v, 0.2)
		_rebuild_debug_visual()

@export var cell_size_z_m: float = 1.5:
	set(v):
		cell_size_z_m = maxf(v, 0.2)
		_rebuild_debug_visual()

@export var max_cells_override: int = 0
@export var affects_boat_cargo_mass: bool = true

## When non-empty, the deck only accepts pallets whose origin_port_id matches.
## Used by port apron grids so foreign cargo can't be dumped here. Empty (the
## default) means any pallet is accepted, suitable for ship cargo decks.
@export var required_origin_port_id: String = ""

@export_group("Debug")
@export var show_debug_grid: bool = true:
	set(v):
		show_debug_grid = v
		_rebuild_debug_visual()

@export var debug_color: Color = Color(0.22, 0.75, 0.33, 0.18):
	set(v):
		debug_color = v
		_rebuild_debug_visual()

## How many cargo units stack on one pallet / cell on this ship.
@export_range(1, 12, 1) var units_per_pallet: int = PalletFactory.DEFAULT_UNITS_PER_PALLET

# cell_idx (int) -> Pallet
var _cells: Dictionary = {}
var _deck_mass_kg: float = 0.0
var _debug_root: Node3D
var _pallet_root: Node3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(DECK_GROUP)
	_rebuild_debug_visual()


func _exit_tree() -> void:
	if affects_boat_cargo_mass and absf(_deck_mass_kg) > 1e-6:
		_apply_boat_cargo_mass_delta(-_deck_mass_kg)
		_deck_mass_kg = 0.0


# ── Capacity ──────────────────────────────────────────────────────────────────

func get_cols() -> int:
	return maxi(int(floor(deck_width_m  / maxf(cell_size_x_m, 0.2))), 1)

func get_rows() -> int:
	return maxi(int(floor(deck_length_m / maxf(cell_size_z_m, 0.2))), 1)

func get_capacity() -> int:
	var cap := get_cols() * get_rows()
	if max_cells_override > 0:
		return mini(cap, max_cells_override)
	return cap

func get_used() -> int:
	return _cells.size()

func get_available() -> int:
	return maxi(get_capacity() - get_used(), 0)

func is_full() -> bool:
	return get_available() <= 0

func can_accept(count: int = 1) -> bool:
	return count > 0 and count <= get_available()


## Whether this deck will physically take this specific pallet (capacity +
## origin gate). Called by the crane's release flow before attempting add.
func accepts_pallet(pallet: Pallet) -> bool:
	if pallet == null or is_full():
		return false
	if not required_origin_port_id.is_empty():
		if pallet.origin_port_id != required_origin_port_id:
			return false
	return true


# ── Pallet API ────────────────────────────────────────────────────────────────

## Place a pallet at the nearest free cell to world_hint. Returns cell index (>=0) or -1.
func add_pallet(pallet: Pallet, world_hint: Vector3 = Vector3.INF) -> int:
	if not accepts_pallet(pallet):
		return -1

	var preferred_local := Vector3.ZERO
	var use_hint        := world_hint != Vector3.INF
	if use_hint:
		preferred_local = _clamp_to_grid(to_local(world_hint))

	var cell_idx := _pick_free_cell(preferred_local, use_hint)
	if cell_idx < 0:
		return -1

	_cells[cell_idx] = pallet

	if affects_boat_cargo_mass and pallet.mass_kg > 0.0:
		_apply_boat_cargo_mass_delta(pallet.mass_kg)
		_deck_mass_kg += pallet.mass_kg

	_spawn_pallet_node(cell_idx, pallet)
	cargo_changed.emit(self)
	return cell_idx


## Remove the pallet at cell_idx. Returns the Pallet or null.
func remove_pallet(cell_idx: int) -> Pallet:
	if not _cells.has(cell_idx):
		return null

	var pallet := _cells[cell_idx] as Pallet
	_cells.erase(cell_idx)
	_remove_pallet_node(cell_idx)

	if pallet != null and affects_boat_cargo_mass and pallet.mass_kg > 0.0:
		_apply_boat_cargo_mass_delta(-pallet.mass_kg)
		_deck_mass_kg = maxf(_deck_mass_kg - pallet.mass_kg, 0.0)

	cargo_changed.emit(self)
	return pallet


func clear_all() -> void:
	for idx in _cells.keys().duplicate():
		remove_pallet(int(idx))


func get_all_pallets() -> Array[Pallet]:
	var out: Array[Pallet] = []
	for v in _cells.values():
		var p := v as Pallet
		if p != null:
			out.append(p)
	return out


func get_pallet_at_cell(cell_idx: int) -> Pallet:
	return _cells.get(cell_idx, null) as Pallet

## Remove whichever cell holds this exact Pallet resource. Returns the Pallet or null.
func remove_pallet_by_resource(pallet: Pallet) -> Pallet:
	for idx in _cells.keys():
		if _cells[idx] == pallet:
			return remove_pallet(int(idx))
	return null


# ── Spatial helpers ───────────────────────────────────────────────────────────

func get_cell_world_center(cell_idx: int) -> Vector3:
	return to_global(_cell_local_center(cell_idx))

func get_nearest_free_cell_world(world_point: Vector3) -> Vector3:
	var preferred := _clamp_to_grid(to_local(world_point))
	var idx       := _pick_free_cell(preferred, true)
	if idx < 0:
		return Vector3.INF
	return to_global(_cell_local_center(idx))

func contains_world_point(world_point: Vector3) -> bool:
	var l  := to_local(world_point)
	var hx := deck_width_m  * 0.5
	var hz := deck_length_m * 0.5
	return l.x >= -hx and l.x <= hx and l.z >= -hz and l.z <= hz

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


# ── Internal: grid math ───────────────────────────────────────────────────────

func _cell_local_center(cell_idx: int) -> Vector3:
	var cols:  int = get_cols()
	var rows:  int = get_rows()
	var idx:   int = clampi(cell_idx, 0, cols * rows - 1)
	var col:   int = idx % cols
	var row:   int = idx / cols
	var step_x := deck_width_m  / float(cols)
	var step_z := deck_length_m / float(rows)
	var x      := -deck_width_m  * 0.5 + step_x * (float(col) + 0.5)
	var z      := -deck_length_m * 0.5 + step_z * (float(row) + 0.5)
	return Vector3(x, 0.0, z)

func _clamp_to_grid(local: Vector3) -> Vector3:
	var hx := deck_width_m  * 0.5
	var hz := deck_length_m * 0.5
	return Vector3(clampf(local.x, -hx, hx), 0.0, clampf(local.z, -hz, hz))

func _pick_free_cell(preferred_local: Vector3, use_preferred: bool) -> int:
	var capacity := get_capacity()
	if capacity <= 0:
		return -1
	var best_idx  := -1
	var best_dist := INF
	for idx in range(capacity):
		if _cells.has(idx):
			continue
		if not use_preferred:
			return idx
		var d2 := preferred_local.distance_squared_to(_cell_local_center(idx))
		if d2 < best_dist:
			best_dist = d2
			best_idx  = idx
	return best_idx


# ── Internal: pallet visuals ──────────────────────────────────────────────────

func _ensure_pallet_root() -> Node3D:
	if _pallet_root != null and is_instance_valid(_pallet_root):
		return _pallet_root
	_pallet_root = get_node_or_null("PalletVisuals") as Node3D
	if _pallet_root == null:
		_pallet_root      = Node3D.new()
		_pallet_root.name = "PalletVisuals"
		add_child(_pallet_root)
	return _pallet_root


func _spawn_pallet_node(cell_idx: int, pallet: Pallet) -> void:
	var root := _ensure_pallet_root()
	if root == null:
		return
	var node                := PalletNode.new()
	node.name               = "Pallet_%d" % cell_idx
	root.add_child(node)
	node.position           = _cell_local_center(cell_idx)
	node.setup(pallet, cell_size_x_m, cell_size_z_m)


func _remove_pallet_node(cell_idx: int) -> void:
	var root := _ensure_pallet_root()
	if root == null:
		return
	var node := root.get_node_or_null("Pallet_%d" % cell_idx) as Node
	if node != null and is_instance_valid(node):
		node.queue_free()


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


# ── Internal: debug grid visual ───────────────────────────────────────────────

func _rebuild_debug_visual() -> void:
	if not is_inside_tree():
		return
	if _debug_root != null and is_instance_valid(_debug_root):
		_debug_root.queue_free()
		_debug_root = null
	if not show_debug_grid:
		return

	_debug_root          = Node3D.new()
	_debug_root.name     = "DeckGrid"
	_debug_root.position = Vector3(0.0, 0.06, 0.0)
	add_child(_debug_root)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_debug_root.owner = get_tree().edited_scene_root

	var cols   := get_cols()
	var rows   := get_rows()
	var hx     := deck_width_m  * 0.5
	var hz     := deck_length_m * 0.5
	var step_x := deck_width_m  / float(cols)
	var step_z := deck_length_m / float(rows)
	var thick  := 0.04
	var h      := 0.01
	var mat    := _grid_material()

	# Cell-dividing lines along X (rows of Z-running lines)
	for col in range(cols + 1):
		var x := -hx + step_x * float(col)
		_line(_debug_root, Vector3(x, 0.0, -hz), Vector3(x, 0.0, hz), thick, h, mat)

	# Cell-dividing lines along Z (cols of X-running lines)
	for row in range(rows + 1):
		var z := -hz + step_z * float(row)
		_line(_debug_root, Vector3(-hx, 0.0, z), Vector3(hx, 0.0, z), thick, h, mat)

	# Corner L-brackets for visual anchoring
	var arm   := clampf(minf(hx, hz) * 0.25, 0.3, 1.2)
	var thick2 := 0.12
	var mat2   := _hazard_material()
	_add_corner(_debug_root, -hx, -hz,  1.0,  1.0, arm, thick2, h * 2.0, mat2)
	_add_corner(_debug_root,  hx, -hz, -1.0,  1.0, arm, thick2, h * 2.0, mat2)
	_add_corner(_debug_root, -hx,  hz,  1.0, -1.0, arm, thick2, h * 2.0, mat2)
	_add_corner(_debug_root,  hx,  hz, -1.0, -1.0, arm, thick2, h * 2.0, mat2)

	var label              := Label3D.new()
	label.text             = "CARGO %dx%d" % [cols, rows]
	label.font_size        = 80
	label.pixel_size       = 0.004
	label.modulate         = Color(0.95, 0.82, 0.0)
	label.billboard        = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees = Vector3(-90.0, 0.0, 180.0)
	label.position         = Vector3(0.0, 0.012, 0.0)
	label.shaded           = false
	_debug_root.add_child(label)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		label.owner = get_tree().edited_scene_root


func _line(root: Node3D, a: Vector3, b: Vector3, thick: float, h: float, mat: Material) -> void:
	var mid    := (a + b) * 0.5
	var length := a.distance_to(b)
	var mi               := MeshInstance3D.new()
	var mesh             := BoxMesh.new()
	var is_z             := absf(b.z - a.z) > absf(b.x - a.x)
	mesh.size            = Vector3(thick, h, length) if is_z else Vector3(length, h, thick)
	mi.mesh              = mesh
	mi.material_override = mat
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position          = Vector3(mid.x, h * 0.5, mid.z)
	root.add_child(mi)


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


func _grid_material() -> StandardMaterial3D:
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = debug_color
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode        = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test    = true
	return mat


func _hazard_material() -> ShaderMaterial:
	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\nvoid fragment() {\n\tfloat s = fract((UV.x + UV.y) * 5.0);\n\tALBEDO = s > 0.5 ? vec3(0.95, 0.82, 0.0) : vec3(0.06, 0.06, 0.06);\n}"
	mat.shader = shader
	return mat
