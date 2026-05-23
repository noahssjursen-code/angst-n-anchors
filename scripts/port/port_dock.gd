@tool
class_name PortDock
extends Node3D

## Self-contained dock system.
## Local origin: the dock face (where ships come alongside).
## +Z goes inland, -Z goes into water.
## INLAND_DEPTH is the total inland footprint — parent uses it to place
## PortFacilities flush behind without overlap.

enum BerthStatus { FREE = 0, RESERVED = 1, OCCUPIED = 2 }

## Default owner id when no PlayerSession display name is set.
const LOCAL_PLAYER_OWNER := "Captain"

const C_QUAY_EDGE      := Color(0.22, 0.23, 0.26)
const C_EDGE_STRIPE    := Color(0.82, 0.78, 0.20)
const C_BERTH          := Color(0.20, 0.85, 0.35, 0.35)
const C_BERTH_RESERVED := Color(0.95, 0.75, 0.10, 0.40)
const C_BERTH_OCCUPIED := Color(0.90, 0.20, 0.15, 0.40)
const C_BERTH_BORDER   := Color(0.25, 1.00, 0.45, 0.70)
const C_LABEL          := Color(0.30, 1.00, 0.50, 0.90)
const C_CARGO_YARD     := Color(0.34, 0.32, 0.30)
const FUEL_STATION_SCENE  := preload("res://scenes/systems/fuel_station.tscn")
## Main quay deck — lit asphalt probe (adjust in `resources/materials/asphalt_dock.tres`).
const QUAY_BODY_MATERIAL: StandardMaterial3D = preload(
	"res://resources/materials/asphalt_dock.tres"
)


func _editor_berth_overlays_visible() -> bool:
	return Engine.is_editor_hint()


var _berth_data: Array = []

const QUAY_HEIGHT    := 0.6
const QUAY_DEPTH     := 8.0
## Dark lip along the water-facing edge — must not share volume/facets with the main slab or Z‑fights.
const QUAY_LIP_DEPTH := 0.35
const QUAY_LIP_SLAB_GAP := 0.002
## Yellow stripe centred on Z≈0.11, spans ~[0, 0.22]. Lip band ends at QUAY_LIP_DEPTH; slab starts just after.
## Bollard mesh projects toward −Z; centre must sit far enough inland to stay wholly on slab / inside stripe.
const MOORING_BOLLARD_CENTER_Z := QUAY_LIP_DEPTH + QUAY_LIP_SLAB_GAP + 0.42
const BERTH_GAP_M    := 4.0
const BERTH_MARGIN   := 1.5

const CRANE_W        := 6.0
const CRANE_H        := 18.0
const CRANE_D        := 6.0
const CRANE_QUAY_GAP := 3.0
const APRON_GAP      := 2.0
## Apron runs inland (+Z). Keep shallow so the quay does not swallow the town.
const APRON_DEPTH    := 14.0
const APRON_DEPTH_MAX := 16.0
const APRON_CELL_M   := 1.5
## Extra apron cells beyond the ship-class hint for contract staging overflow.
const APRON_STAGING_MARGIN_CELLS := 12
## Per-side inset (m) from the slot edge — keep in sync with gantry roll formula.
const APRON_REACH_INSET := 0.8
## Gantry must cover ship length (bow–stern along the dock face) from midship.
const CRANE_SHIP_LENGTH_FRAC := 0.58

## Total inland footprint from dock face to back of cargo aprons + buffer.
## PortPlot reads this to position PortFacilities without guessing.
const INLAND_DEPTH := QUAY_DEPTH + CRANE_QUAY_GAP + CRANE_D + APRON_GAP + APRON_DEPTH + 3.0

@export var dock_length: float = 80.0:
	set(v): dock_length = v; if is_inside_tree(): _rebuild()

## Port UUID this dock belongs to. Propagated to apron CargoDeckComponents so
## they reject pallets that did not originate here. Set by PortPlot before
## rebuild.
@export var port_id: String = "":
	set(v): port_id = v; if is_inside_tree(): _rebuild()

@export var max_ship_class: ShipClass.Type = ShipClass.Type.COASTAL_TRADER:
	set(v): max_ship_class = v; if is_inside_tree(): _rebuild()

@export var berth_types: Array[int] = []:
	set(v): berth_types = v; if is_inside_tree(): _rebuild()

@export var has_fuel_point: bool = true:
	set(v): has_fuel_point = v; if is_inside_tree(): _rebuild()


func _ready() -> void:
	add_to_group("port_docks")
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	_build_quay()
	_build_berths()
	if has_fuel_point:
		_build_fuel_point()

	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


# ── Quay ──────────────────────────────────────────────────────────────────────

## Visual-only padding added around the functional slab footprint. Does NOT
## affect dock_length, crane Z, apron Z or any other gameplay measurements —
## just gives the concrete a bit of border so cranes don't sit on the very edge.
const QUAY_SLAB_PAD_Z := 2.0
const QUAY_SLAB_PAD_X := 1.5


func _build_quay() -> void:
	var lip_half := QUAY_LIP_DEPTH * 0.5
	# Slab spans from just behind the lip past the back of the apron (+ pad
	# so the apron isn't flush with the concrete edge).
	var slab_back := QUAY_DEPTH + CRANE_QUAY_GAP + CRANE_D + APRON_GAP + APRON_DEPTH + QUAY_SLAB_PAD_Z
	var slab_front := QUAY_LIP_DEPTH + QUAY_LIP_SLAB_GAP
	var slab_size_z := slab_back - slab_front
	var slab_z_half := slab_size_z * 0.5
	var slab_centre_z := slab_front + slab_z_half

	var size := Vector3(dock_length + QUAY_SLAB_PAD_X * 2.0, QUAY_HEIGHT, slab_size_z)
	var body := StaticBody3D.new()
	body.name            = "Quay"
	body.position        = Vector3(0.0, QUAY_HEIGHT * 0.5, slab_centre_z)
	var mi               := MeshInstance3D.new()
	mi.name              = "Mesh"
	var mesh             := BoxMesh.new()
	mesh.size            = size
	mi.mesh              = mesh
	mi.material_override = QUAY_BODY_MATERIAL
	body.add_child(mi)
	var col              := CollisionShape3D.new()
	var box              := BoxShape3D.new()
	box.size             = size
	col.shape            = box
	body.add_child(col)
	add_child(body)

	# Dark leading edge where quay meets water
	_box(Vector3(dock_length, QUAY_HEIGHT, QUAY_LIP_DEPTH),
		 Vector3(0.0, QUAY_HEIGHT * 0.5, lip_half),
		 C_QUAY_EDGE, "QuayLip")

	# Safety stripe along dock face
	_box(Vector3(dock_length, 0.04, 0.22),
		 Vector3(0.0, QUAY_HEIGHT + 0.02, 0.11),
		 C_EDGE_STRIPE, "DockStripe")

	# Mooring bollards — docking_bollard mesh + `dock_mooring_bollard` group for MooringComponent
	var n_posts := maxi(2, int(dock_length / 8.0))
	var spacing   := dock_length / float(n_posts)
	for i in range(n_posts):
		var bx   := -dock_length * 0.5 + spacing * (float(i) + 0.5)
		var post := MooringPost.new()
		post.name = "DockMooringPost%d" % i
		post.position = Vector3(bx, QUAY_HEIGHT, MOORING_BOLLARD_CENTER_Z)
		# Default docking bollard mesh uses Y=90°; dock quay wants +90° on local Y.
		post.bollard_rotation_degrees = Vector3(0.0, 180.0, 0.0)
		add_child(post)
# ── Berths ────────────────────────────────────────────────────────────────────

func _build_berths() -> void:
	_berth_data.clear()

	var ship_len  : float = ShipClass.max_length(max_ship_class)
	var ship_beam : float = ShipClass.beam(max_ship_class)
	var count     : int   = berth_types.size() if berth_types.size() > 0 else ShipClass.berth_count(
		dock_length, max_ship_class, BERTH_GAP_M
	)
	count = maxi(count, 1)
	var slot_w    : float = dock_length / float(count)

	for i in range(count):
		var cx         : float = -dock_length * 0.5 + slot_w * (float(i) + 0.5)
		var cargo_type : int   = berth_types[i] if i < berth_types.size() else CargoBerthType.Type.GENERAL
		_build_berth_slot(i, cx, slot_w, ship_beam, cargo_type)

	var summary := "%s  ·  %d berth%s  ·  max %.0f m" % [
		ShipClass.display_name(max_ship_class), count, "s" if count != 1 else "", ship_len
	]
	var sum_lbl := _label(summary, Vector3(0.0, 4.5, -ship_beam - 1.0), C_LABEL, 0.65, "LabelSummary")
	sum_lbl.visible = _editor_berth_overlays_visible()


func _build_berth_slot(index: int, cx: float, slot_w: float, ship_beam: float, cargo_type: int) -> void:
	var ship_len := ShipClass.max_length(max_ship_class)
	var cargo    := _berth_cargo_layout(slot_w, ship_len, ship_beam, max_ship_class)
	var apron_w_reach: float = cargo["apron_w"]
	var apron_depth: float = cargo["apron_depth"]
	var bz      : float = -ship_beam * 0.5
	var crane_z : float = QUAY_DEPTH + CRANE_QUAY_GAP + CRANE_D * 0.5
	var apron_z : float = QUAY_DEPTH + CRANE_QUAY_GAP + CRANE_D + APRON_GAP + apron_depth * 0.5

	# Berth water indicator
	var fill               := MeshInstance3D.new()
	fill.name              = "Berth%d" % index
	fill.position          = Vector3(cx, 0.02, bz)
	var mesh               := PlaneMesh.new()
	mesh.size              = Vector2(slot_w - BERTH_MARGIN * 2.0, ship_beam)
	fill.mesh              = mesh
	var mat                := StandardMaterial3D.new()
	mat.albedo_color       = C_BERTH
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode          = BaseMaterial3D.CULL_DISABLED
	fill.material_override = mat
	add_child(fill)
	fill.visible = _editor_berth_overlays_visible()

	# Apron cargo grid — sized for this port's ship class + staging margin.
	var apron_deck := CargoDeckComponent.new()
	apron_deck.name                       = "ApronDeck%d" % index
	# Sits just above the concrete pad (which is 0.12 m tall starting at Y=0).
	# Apron deck sits just above the quay surface.
	apron_deck.position                   = Vector3(cx, QUAY_HEIGHT + 0.001, apron_z)
	apron_deck.deck_width_m               = apron_w_reach
	apron_deck.deck_length_m              = apron_depth
	apron_deck.cell_size_x_m              = APRON_CELL_M
	apron_deck.cell_size_z_m              = APRON_CELL_M
	apron_deck.affects_boat_cargo_mass    = false
	apron_deck.port_id                    = port_id
	apron_deck.debug_color                = Color(0.85, 0.55, 0.18, 0.20)
	apron_deck.debug_grid_y_offset        = 0.0   # grid lies flat on the quay
	add_child(apron_deck)
	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			_own_subtree(apron_deck, esc)

	_berth_data.append({
		"status":      BerthStatus.FREE,
		"reserved_by": "",
		"owner_id":    "",
		"ship":        null,
		"cargo_type":  cargo_type,
		"fill":        fill,
		"has_cargo":   false,
		"cx":          cx,
		"slot_w":      slot_w,
		"apron_z":     apron_z,
		"apron_w":     apron_w_reach,
		"apron_depth": apron_depth,
		"apron_deck":  apron_deck,
	})

	for sx in [-1.0, 1.0]:
		var edge               := MeshInstance3D.new()
		edge.name              = "BerthEdge%d_%d" % [index, int(sx)]
		edge.position          = Vector3(cx + sx * (slot_w * 0.5 - BERTH_MARGIN), 0.03, bz)
		var emesh              := BoxMesh.new()
		emesh.size             = Vector3(0.3, 0.08, ship_beam)
		edge.mesh              = emesh
		var emat               := StandardMaterial3D.new()
		emat.albedo_color      = C_BERTH_BORDER
		emat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
		edge.material_override = emat
		add_child(edge)
		edge.visible = _editor_berth_overlays_visible()

	var type_str : String = CargoBerthType.display_name(cargo_type as CargoBerthType.Type)
	var berth_lbl := _label("#%d  %s" % [index + 1, type_str],
			Vector3(cx, 1.2, -ship_beam - 0.5),
			C_LABEL, 0.48, "LabelBerth%d" % index)
	berth_lbl.visible = _editor_berth_overlays_visible()

	match cargo_type:
		CargoBerthType.Type.BULK:      _crane_bulk(index, cx, crane_z)
		CargoBerthType.Type.CONTAINER: _crane_container(index, cx, slot_w, crane_z)
		_:                             _crane_general(index, cx, cargo, crane_z, apron_z, apron_depth, ship_beam)

	# Quay slab already covers this area (extended in _build_quay) — no
	# per-berth asphalt strip needed.


## Apron width/depth and gantry reach for a berth slot. Ship length runs along
## the dock face (gantry X); apron depth runs inland (trolley +Z) — keep depth small.
static func _berth_cargo_layout(
		slot_w: float,
		ship_len: float,
		ship_beam: float,
		max_class: ShipClass.Type,
) -> Dictionary:
	var target_cells := ShipClass.cargo_cells(max_class) + APRON_STAGING_MARGIN_CELLS
	# Prefer a wide, shallow apron (along-shore × inland) so capacity grows +X not +Z.
	var min_cols := maxi(int(ceil(sqrt(float(target_cells) * 1.35))), 4)
	var min_apron_w := float(min_cols) * APRON_CELL_M
	var apron_w := clampf(
		maxf(maxf(slot_w - 2.0 * APRON_REACH_INSET, min_apron_w), ship_beam + 8.0),
		APRON_CELL_M * 2.0,
		slot_w - 0.5,
	)
	var cols := maxi(int(floor(apron_w / APRON_CELL_M)), 2)
	var rows_needed := maxi(int(ceil(float(target_cells) / float(cols))), 3)
	var apron_depth := clampf(
		float(rows_needed) * APRON_CELL_M,
		APRON_DEPTH * 0.85,
		APRON_DEPTH_MAX,
	)
	var roll_slot := maxf(slot_w * 0.5 - APRON_REACH_INSET, 2.0)
	var roll_ship := ship_len * CRANE_SHIP_LENGTH_FRAC + 4.0
	var gantry_roll := maxf(roll_slot, roll_ship)
	return {
		"apron_w": apron_w,
		"apron_depth": apron_depth,
		"gantry_roll": gantry_roll,
	}


## Trolley Z limits in crane-local space: −Z toward ship, +Z toward apron back.
static func _crane_trolley_limits(
		crane_z: float,
		apron_z: float,
		apron_depth: float,
		ship_beam: float,
) -> Vector2:
	var ship_edge_z := -ship_beam - 3.0
	var trolley_min := ship_edge_z - crane_z - 3.0
	var apron_back_z := apron_z + apron_depth * 0.5 + 2.0
	var trolley_max := apron_back_z - crane_z + 2.0
	if trolley_max <= trolley_min + 6.0:
		trolley_max = trolley_min + 28.0
	return Vector2(trolley_min, trolley_max)


# ── Crane types ───────────────────────────────────────────────────────────────

func _crane_general(
		index: int,
		cx: float,
		cargo: Dictionary,
		crane_z: float,
		apron_z: float,
		apron_depth: float,
		ship_beam: float,
) -> void:
	var crane                 := GantryCrane.new()
	crane.name                = "Crane%d" % index
	crane.position            = Vector3(cx, QUAY_HEIGHT, crane_z)
	crane.berth_index         = index
	crane.gantry_roll_range_x = float(cargo["gantry_roll"])
	var trolley_limits        := _crane_trolley_limits(crane_z, apron_z, apron_depth, ship_beam)
	crane.trolley_min_z       = trolley_limits.x
	crane.trolley_max_z       = trolley_limits.y
	add_child(crane)
	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			_own_subtree(crane, esc)


func _crane_bulk(index: int, cx: float, crane_z: float) -> void:
	var col := CargoBerthType.crane_color(CargoBerthType.Type.BULK)
	_box(Vector3(7.0, 12.0, 7.0), Vector3(cx, 6.0, crane_z), col, "Crane%d" % index)
	_box(Vector3(4.5, 1.5, 12.0), Vector3(cx, 13.5, crane_z - 4.0), col.lightened(0.10), "CraneBoom%d" % index)
	_box(Vector3(3.5, 3.0, 3.5), Vector3(cx, 10.0, crane_z - 7.0), col.darkened(0.15), "CraneGrab%d" % index)
	_label("Bulk  #%d" % (index + 1), Vector3(cx, 15.5, crane_z),
		   Color(1.0, 1.0, 1.0, 0.90), 0.44, "LabelCrane%d" % index)


func _crane_container(index: int, cx: float, slot_w: float, crane_z: float) -> void:
	var col      := CargoBerthType.crane_color(CargoBerthType.Type.CONTAINER)
	var leg_span : float = minf(slot_w * 0.42, 18.0)
	var h        : float = 24.0
	_box(Vector3(2.5, h, 2.5), Vector3(cx - leg_span, h * 0.5, crane_z), col, "CraneLegL%d" % index)
	_box(Vector3(2.5, h, 2.5), Vector3(cx + leg_span, h * 0.5, crane_z), col, "CraneLegR%d" % index)
	_box(Vector3(leg_span * 2.0 + 2.5, 2.5, 2.5), Vector3(cx, h, crane_z), col, "CraneBeam%d" % index)
	_box(Vector3(2.5, 2.0, 10.0), Vector3(cx, h - 1.0, crane_z - 6.0), col.lightened(0.15), "CraneBoom%d" % index)
	_label("Container  #%d" % (index + 1), Vector3(cx, h + 1.5, crane_z),
		   Color(1.0, 1.0, 1.0, 0.90), 0.44, "LabelCrane%d" % index)


# ── Fuel point ────────────────────────────────────────────────────────────────

func _build_fuel_point() -> void:
	var station      := FUEL_STATION_SCENE.instantiate()
	station.name     = "FuelStation"
	# Sit on quay surface, inset from right end.
	# Model pad spans X: -3.2 to +4.2 relative to its origin, so offset 5 m from dock edge.
	station.position = Vector3(dock_length * 0.5 - 5.0, QUAY_HEIGHT + 0.1, QUAY_DEPTH * 0.5)
	add_child(station)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _box(size: Vector3, pos: Vector3, color: Color, node_name: String) -> MeshInstance3D:
	var mi               := MeshInstance3D.new()
	mi.name              = "Mesh"
	var mesh             := BoxMesh.new()
	mesh.size            = size
	mi.mesh              = mesh
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = color
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	var body             := StaticBody3D.new()
	body.name            = node_name
	body.position        = pos
	var col              := CollisionShape3D.new()
	var box              := BoxShape3D.new()
	box.size             = size
	col.shape            = box
	body.add_child(mi)
	body.add_child(col)
	add_child(body)
	return mi


func _label(text: String, pos: Vector3, color: Color, font_size: float, node_name: String) -> Label3D:
	var lbl           := Label3D.new()
	lbl.name          = node_name
	lbl.text          = text
	lbl.position      = pos
	lbl.modulate      = color
	lbl.pixel_size    = font_size * 0.005
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.double_sided  = true
	add_child(lbl)
	return lbl


func _own_subtree(node: Node, esc: Node) -> void:
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)


# ── Runtime API ───────────────────────────────────────────────────────────────

static func local_player_owner_id() -> String:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var ps := (tree as SceneTree).root.get_node_or_null("PlayerSession")
		if ps != null and ps.get("data") != null:
			var player_name: String = ps.data.display_name
			if not player_name.is_empty():
				return player_name
	return LOCAL_PLAYER_OWNER


## Returns the index of the occupied berth (player's ship), or -1 if none.
func find_occupied_berth() -> int:
	for i in range(_berth_data.size()):
		if int((_berth_data[i] as Dictionary)["status"]) == BerthStatus.OCCUPIED:
			return i
	return -1


## Marks a berth as having cargo staged (true) or clear (false).
func set_berth_has_cargo(berth_index: int, has_cargo: bool) -> void:
	if berth_index < 0 or berth_index >= _berth_data.size():
		return
	(_berth_data[berth_index] as Dictionary)["has_cargo"] = has_cargo


## Returns n world-space positions within berth_index's cargo apron, in a grid.
## Uses the exact cx/slot_w/apron_z recorded when the berth geometry was built —
## same slot, same crane, same apron.
## Returns the CargoDeckComponent acting as this berth's apron grid, or null.
func get_berth_apron_deck(berth_index: int) -> CargoDeckComponent:
	if berth_index < 0 or berth_index >= _berth_data.size():
		return null
	var b := _berth_data[berth_index] as Dictionary
	return b.get("apron_deck", null) as CargoDeckComponent


func get_berth_apron_positions(berth_index: int, n: int, offset: int = 0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if n <= 0 or berth_index < 0 or berth_index >= _berth_data.size():
		return out
	var b       := _berth_data[berth_index] as Dictionary
	var cx      := float(b["cx"])
	var slot_w  := float(b["slot_w"])
	var apron_z := float(b["apron_z"])
	var apron_w := float(b.get("apron_w", maxf(slot_w - 2.0 * APRON_REACH_INSET, 1.5)))
	var apron_depth := float(b.get("apron_depth", APRON_DEPTH))
	var cols    := maxi(int(apron_w / APRON_CELL_M), 1)
	for i in range(n):
		var idx := i + offset
		var col := idx % cols
		var row := idx / cols
		var x   := cx - apron_w * 0.5 + APRON_CELL_M * (float(col) + 0.5)
		var z   := apron_z - apron_depth * 0.4 + APRON_CELL_M * float(row)
		out.append(to_global(Vector3(x, QUAY_HEIGHT + 0.05, z)))
	return out


func get_spawn_position() -> Vector3:
	return to_global(Vector3(0.0, QUAY_HEIGHT + 0.1, QUAY_DEPTH * 0.5))

func can_dock(ship_type: ShipClass.Type) -> bool:
	return ShipClass.fits(ship_type, max_ship_class)

func berth_count() -> int:
	if berth_types.size() > 0:
		return berth_types.size()
	return ShipClass.berth_count(dock_length, max_ship_class, BERTH_GAP_M)

func get_berths() -> Array:
	return _berth_data.duplicate()

func get_accepted_cargo_types() -> Array[int]:
	var seen: Dictionary = {}
	for b in _berth_data:
		seen[(b as Dictionary)["cargo_type"]] = true
	var out: Array[int] = []
	for k in seen.keys():
		out.append(int(k))
	return out

func reserve_berth(index: int, player_name: String) -> bool:
	if index < 0 or index >= _berth_data.size():
		return false
	var b := _berth_data[index] as Dictionary
	if int(b["status"]) != BerthStatus.FREE:
		return false
	b["status"]      = BerthStatus.RESERVED
	b["reserved_by"] = player_name
	_update_berth_color(index)
	return true

func release_berth(index: int) -> void:
	if index < 0 or index >= _berth_data.size():
		return
	var b            := _berth_data[index] as Dictionary
	b["status"]      = BerthStatus.FREE
	b["reserved_by"] = ""
	b["owner_id"]    = ""
	b["ship"]        = null
	_update_berth_color(index)


func register_ship_at_berth(index: int, ship: BoatBody, owner_id: String = "") -> bool:
	if index < 0 or index >= _berth_data.size() or ship == null:
		return false
	unregister_ship(ship)
	var b := _berth_data[index] as Dictionary
	var st := int(b["status"])
	if st == BerthStatus.FREE:
		pass
	elif st == BerthStatus.RESERVED:
		var who := str(b["reserved_by"])
		if not who.is_empty() and owner_id != "" and who != owner_id:
			return false
	else:
		var existing: BoatBody = b.get("ship", null) as BoatBody
		if existing != null and existing != ship:
			return false
	b["ship"]     = ship
	b["owner_id"] = owner_id if not owner_id.is_empty() else LOCAL_PLAYER_OWNER
	b["status"]   = BerthStatus.OCCUPIED
	b["reserved_by"] = ""
	_update_berth_color(index)
	return true


func unregister_ship(ship: BoatBody) -> void:
	if ship == null:
		return
	for i in range(_berth_data.size()):
		var b := _berth_data[i] as Dictionary
		if b.get("ship", null) as BoatBody == ship:
			b["ship"]     = null
			b["owner_id"] = ""
			b["status"]   = BerthStatus.FREE
			b["reserved_by"] = ""
			_update_berth_color(i)


func find_berth_index_at_position(world_pos: Vector3) -> int:
	if _berth_data.is_empty():
		return -1
	var local := to_local(world_pos)
	var best_i := -1
	var best_d := INF
	for i in range(_berth_data.size()):
		var b := _berth_data[i] as Dictionary
		var cx: float = float(b["cx"])
		var half: float = float(b["slot_w"]) * 0.5
		if absf(local.x - cx) <= half:
			return i
		var d := absf(local.x - cx)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func find_player_berth(owner_id: String) -> int:
	if owner_id.is_empty():
		return -1
	for i in range(_berth_data.size()):
		var b := _berth_data[i] as Dictionary
		if int(b["status"]) != BerthStatus.OCCUPIED:
			continue
		if str(b.get("owner_id", "")) == owner_id:
			return i
	return -1


func get_ship_at_berth(index: int) -> BoatBody:
	if index < 0 or index >= _berth_data.size():
		return null
	return (_berth_data[index] as Dictionary).get("ship", null) as BoatBody


func berth_has_ship(index: int) -> bool:
	if index < 0 or index >= _berth_data.size():
		return false
	var b := _berth_data[index] as Dictionary
	return int(b["status"]) == BerthStatus.OCCUPIED and b.get("ship", null) != null


func berth_reference_local_midship(index: int) -> Vector3:
	# Must match _build_berths() / PortExpander slot centres — not ShipClass.berth_count().
	if index >= 0 and index < _berth_data.size():
		var b := _berth_data[index] as Dictionary
		var cx: float = float(b["cx"])
		var beam_m := ShipClass.beam(max_ship_class)
		return Vector3(cx, WaveSurface.WATER_LEVEL, -beam_m * 0.5)
	var count := maxi(berth_count(), 1)
	var slot_w := dock_length / float(count)
	var cx := -dock_length * 0.5 + slot_w * (float(index) + 0.5)
	var beam_m := ShipClass.beam(max_ship_class)
	return Vector3(cx, WaveSurface.WATER_LEVEL, -beam_m * 0.5)


func berth_nominal_half_beam_m() -> float:
	return ShipClass.beam(max_ship_class) * 0.5


func get_berth_spawn_transform(index: int) -> Transform3D:
	var local_pos := berth_reference_local_midship(index)
	var dock_x    := global_transform.basis.x.normalized()
	var ship_z    := -dock_x
	var ship_y    := Vector3.UP
	var ship_x    := ship_y.cross(ship_z).normalized()
	var ship_basis := Basis(ship_x, ship_y, ship_z)
	return Transform3D(ship_basis, to_global(local_pos))


func spawn_player_ship(index: int, ship_scene_path: String = "") -> Node3D:
	if index < 0 or index >= _berth_data.size():
		return null

	var tree := get_tree()
	if tree != null:
		PlayerVessel.replace_before_spawn(tree)

	var path := ship_scene_path.strip_edges()
	if path.is_empty():
		push_error("PortDock: no ship path provided to spawn_player_ship")
		return null

	var ship: Node3D = null
	if path.ends_with(".json"):
		ship = ShipBuilder.build(path)
		if ship == null:
			push_error("PortDock: ShipBuilder failed to build: %s" % path)
			return null
	else:
		if not ResourceLoader.exists(path):
			push_error("PortDock: ship scene missing: %s" % path)
			return null
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("PortDock: not a PackedScene: %s" % path)
			return null
		ship = packed.instantiate() as Node3D
		if ship == null:
			push_error("PortDock: ship scene root must be Node3D: %s" % path)
			return null

	var t := get_berth_spawn_transform(index)
	ship.name = "PlayerShip"

	var plot := get_parent()
	if plot == null:
		ship.queue_free()
		return null
	plot.add_child(ship)

	var berth_draft_frac: float = 0.45
	var body := ship as BoatBody
	if body != null:
		berth_draft_frac = body.design_draft_fraction
		body.snap_to_transform(t)
		body.place_at_waterline(WaveSurface.WATER_LEVEL, berth_draft_frac)
		body.fit_to_port_berth(self, index)
	elif ship.has_method("place_at_waterline"):
		ship.global_transform = t
		ship.call("place_at_waterline", WaveSurface.WATER_LEVEL, berth_draft_frac)
	else:
		ship.global_transform = t

	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null:
		# Deferred so berth transform / waterline settle before cleat ↔ bollard pairing.
		mooring.call_deferred("auto_moor", mooring.get_tree())

	register_ship_at_berth(
		index, body if body != null else ship as BoatBody, local_player_owner_id()
	)

	if body != null:
		PlayerVessel.mark_player_ship(body)
		# After the player's ship is marked, ask LocalPlayerView to apply any
		# saved runtime state (fuel level, throttle stage). World-load tries
		# this earlier but no ship existed yet; this is the actual moment
		# where the active vessel exists.
		var view := get_tree().root.get_node_or_null("LocalPlayerView")
		if view != null and view.has_method("apply_runtime_state_to_active_ship"):
			view.call_deferred("apply_runtime_state_to_active_ship")

	return ship


## Move an existing player ship onto a reserved berth (no new build).
func assign_existing_ship_to_berth(index: int, ship: BoatBody) -> bool:
	if index < 0 or index >= _berth_data.size() or ship == null:
		return false
	var plot := get_parent()
	if plot == null:
		return false

	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null:
		mooring.release_mooring()

	if ship.get_parent() != plot:
		ship.reparent(plot)

	var berth_xform := get_berth_spawn_transform(index)
	ship.snap_to_transform(berth_xform)
	ship.place_at_waterline(WaveSurface.WATER_LEVEL, ship.design_draft_fraction)
	ship.fit_to_port_berth(self, index)

	if mooring != null:
		mooring.call_deferred("auto_moor", mooring.get_tree())

	return register_ship_at_berth(index, ship, local_player_owner_id())


## Place an already-built BoatBody at a berth. Caller must have called reserve_berth() first.
func place_ship_at_berth(index: int, ship: BoatBody) -> BoatBody:
	var tree := get_tree()
	if tree != null:
		PlayerVessel.despawn_all_ships(tree, ship)
	if index < 0 or index >= _berth_data.size():
		return null
	var t    := get_berth_spawn_transform(index)
	ship.name = "PlayerShip"
	var plot := get_parent()
	if plot == null:
		return null
	plot.add_child(ship)
	ship.snap_to_transform(t)
	ship.place_at_waterline(WaveSurface.WATER_LEVEL, ship.design_draft_fraction)
	ship.fit_to_port_berth(self, index)
	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null:
		mooring.call_deferred("auto_moor", mooring.get_tree())
	register_ship_at_berth(index, ship, local_player_owner_id())
	PlayerVessel.mark_player_ship(ship)
	return ship


func _update_berth_color(index: int) -> void:
	var b    := _berth_data[index] as Dictionary
	var fill := b["fill"] as MeshInstance3D
	if fill == null or not is_instance_valid(fill):
		return
	var mat := fill.material_override as StandardMaterial3D
	if mat == null:
		return
	match int(b["status"]):
		BerthStatus.FREE:     mat.albedo_color = C_BERTH
		BerthStatus.RESERVED: mat.albedo_color = C_BERTH_RESERVED
		BerthStatus.OCCUPIED: mat.albedo_color = C_BERTH_OCCUPIED
