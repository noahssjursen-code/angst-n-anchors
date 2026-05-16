@tool
class_name PortDock
extends Node3D

## Self-contained dock system.
## Local origin: the dock face (where ships come alongside).
## +Z goes inland, -Z goes into water.
## INLAND_DEPTH is the total inland footprint — parent uses it to place
## PortFacilities flush behind without overlap.

enum BerthStatus { FREE = 0, RESERVED = 1, OCCUPIED = 2 }

const C_QUAY_EDGE      := Color(0.22, 0.23, 0.26)
const C_EDGE_STRIPE    := Color(0.82, 0.78, 0.20)
const C_BERTH          := Color(0.20, 0.85, 0.35, 0.35)
const C_BERTH_RESERVED := Color(0.95, 0.75, 0.10, 0.40)
const C_BERTH_OCCUPIED := Color(0.90, 0.20, 0.15, 0.40)
const C_BERTH_BORDER   := Color(0.25, 1.00, 0.45, 0.70)
const C_LABEL          := Color(0.30, 1.00, 0.50, 0.90)
const C_CARGO_YARD     := Color(0.34, 0.32, 0.30)
const FUEL_STATION_SCENE  := preload("res://scenes/systems/fuel_station.tscn")
const PLAYER_SHIP_SCENE   := preload("res://scenes/boats/test_boat.tscn")
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
const BERTH_GAP_M    := 3.0
const BERTH_MARGIN   := 1.5

const CRANE_W        := 6.0
const CRANE_H        := 18.0
const CRANE_D        := 6.0
const CRANE_QUAY_GAP := 3.0
const APRON_GAP      := 2.0
const APRON_DEPTH    := 14.0

## Total inland footprint from dock face to back of cargo aprons + buffer.
## PortPlot reads this to position PortFacilities without guessing.
const INLAND_DEPTH := QUAY_DEPTH + CRANE_QUAY_GAP + CRANE_D + APRON_GAP + APRON_DEPTH + 3.0

@export var dock_length: float = 80.0:
	set(v): dock_length = v; if is_inside_tree(): _rebuild()

@export var max_ship_class: ShipClass.Type = ShipClass.Type.COASTAL_TRADER:
	set(v): max_ship_class = v; if is_inside_tree(): _rebuild()

@export var berth_types: Array[int] = []:
	set(v): berth_types = v; if is_inside_tree(): _rebuild()

@export var has_fuel_point: bool = true:
	set(v): has_fuel_point = v; if is_inside_tree(): _rebuild()


func _ready() -> void:
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

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


# ── Quay ──────────────────────────────────────────────────────────────────────

func _build_quay() -> void:
	var lip_half := QUAY_LIP_DEPTH * 0.5
	# Lip centres on the band [0, QUAY_LIP_DEPTH]; slab starts after tiny gap → no overlapping coplanar faces.
	var slab_z_half := (QUAY_DEPTH - QUAY_LIP_DEPTH - QUAY_LIP_SLAB_GAP) * 0.5
	var slab_centre_z := QUAY_LIP_DEPTH + QUAY_LIP_SLAB_GAP + slab_z_half
	var slab_size_z := slab_z_half * 2.0

	var size := Vector3(dock_length, QUAY_HEIGHT, slab_size_z)
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
	var count     : int   = ShipClass.berth_count(dock_length, max_ship_class, BERTH_GAP_M)
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
	var bz      : float = -ship_beam * 0.5
	var crane_z : float = QUAY_DEPTH + CRANE_QUAY_GAP + CRANE_D * 0.5
	var apron_z : float = QUAY_DEPTH + CRANE_QUAY_GAP + CRANE_D + APRON_GAP + APRON_DEPTH * 0.5

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

	_berth_data.append({
		"status":      BerthStatus.FREE,
		"reserved_by": "",
		"cargo_type":  cargo_type,
		"fill":        fill,
		"has_cargo":   false,
		"cx":          cx,
		"slot_w":      slot_w,
		"apron_z":     apron_z,   # dock-local Z centre of this berth's apron
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
		_:                             _crane_general(index, cx, crane_z)

	_box(Vector3(slot_w - 0.4, 0.12, APRON_DEPTH),
		 Vector3(cx, 0.06, apron_z), C_CARGO_YARD, "Apron%d" % index)


# ── Crane types ───────────────────────────────────────────────────────────────

func _crane_general(index: int, cx: float, crane_z: float) -> void:
	var col := CargoBerthType.crane_color(CargoBerthType.Type.GENERAL)
	_box(Vector3(CRANE_W, CRANE_H, CRANE_D), Vector3(cx, CRANE_H * 0.5, crane_z), col, "Crane%d" % index)
	_box(Vector3(2.0, 1.5, 8.0), Vector3(cx, CRANE_H - 1.0, crane_z - 5.0), col.lightened(0.15), "CraneBoom%d" % index)
	_label("General  #%d" % (index + 1), Vector3(cx, CRANE_H + 1.2, crane_z),
		   Color(1.0, 1.0, 1.0, 0.90), 0.44, "LabelCrane%d" % index)


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
func get_berth_apron_positions(berth_index: int, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if n <= 0 or berth_index < 0 or berth_index >= _berth_data.size():
		return out
	var b       := _berth_data[berth_index] as Dictionary
	var cx      := float(b["cx"])
	var slot_w  := float(b["slot_w"])
	var apron_z := float(b["apron_z"])
	var apron_w := slot_w - 0.4
	var cols    := maxi(int(apron_w / 1.5), 1)
	for i in range(n):
		var col := i % cols
		var row := i / cols
		var x   := cx - apron_w * 0.5 + 1.5 * (float(col) + 0.5)
		var z   := apron_z - APRON_DEPTH * 0.4 + 1.5 * float(row)
		out.append(to_global(Vector3(x, QUAY_HEIGHT + 0.05, z)))
	return out


func get_spawn_position() -> Vector3:
	return to_global(Vector3(0.0, QUAY_HEIGHT + 0.1, QUAY_DEPTH * 0.5))

func can_dock(ship_type: ShipClass.Type) -> bool:
	return ShipClass.fits(ship_type, max_ship_class)

func berth_count() -> int:
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
	_update_berth_color(index)

func get_berth_spawn_transform(index: int) -> Transform3D:
	var count  := ShipClass.berth_count(dock_length, max_ship_class, BERTH_GAP_M)
	var slot_w := dock_length / float(count)
	var cx     := -dock_length * 0.5 + slot_w * (float(index) + 0.5)
	var beam   := ShipClass.beam(max_ship_class)

	# Dock runs along local +X. Ship berths alongside (length parallel to dock).
	# Bow faces +X — ship forward is -Z local, so ship_z column = -dock_x.
	# ship_x derived by right-hand rule (up × ship_z) to keep basis orthogonal.
	var local_pos  := Vector3(cx, WaveSurface.WATER_LEVEL, -beam * 0.5)
	var dock_x     := global_transform.basis.x.normalized()
	var ship_z     := -dock_x
	var ship_y     := Vector3.UP
	var ship_x     := ship_y.cross(ship_z).normalized()
	var ship_basis := Basis(ship_x, ship_y, ship_z)
	return Transform3D(ship_basis, to_global(local_pos))


func spawn_player_ship(index: int) -> Node3D:
	if index < 0 or index >= _berth_data.size():
		return null

	var ship := PLAYER_SHIP_SCENE.instantiate() as Node3D
	if ship == null:
		return null

	var t     := get_berth_spawn_transform(index)
	ship.name = "PlayerShip"

	var plot := get_parent()
	if plot == null:
		ship.queue_free()
		return null
	plot.add_child(ship)
	ship.global_transform = t

	if ship.has_method("place_at_waterline"):
		ship.call("place_at_waterline", WaveSurface.WATER_LEVEL, 0.45)

	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null:
		# Deferred so berth transform / waterline settle before cleat ↔ bollard pairing.
		mooring.call_deferred("auto_moor", mooring.get_tree())

	var b       := _berth_data[index] as Dictionary
	b["status"] = BerthStatus.OCCUPIED
	_update_berth_color(index)

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
