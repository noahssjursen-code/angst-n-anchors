class_name PalletNode
extends Node3D

## World-space representation of a Pallet sitting on a grid cell.
## The crane will grab this node to move it between apron and deck.

const GROUP := "pallet_node"

signal grabbed(node: PalletNode)
signal released(node: PalletNode)

var pallet: Pallet = null
var cell_w: float  = 1.5
var cell_d: float  = 1.5

var _mesh_root: Node3D
var _label: Label3D
var _sockets: Array[PalletAttachPoint] = []


func _ready() -> void:
	add_to_group(GROUP)


func setup(p: Pallet, cell_width: float = 1.5, cell_depth: float = 1.5) -> void:
	pallet = p
	cell_w = cell_width
	cell_d = cell_depth
	_build()


func _build() -> void:
	if _mesh_root != null and is_instance_valid(_mesh_root):
		_mesh_root.queue_free()

	_mesh_root          = Node3D.new()
	_mesh_root.name     = "PalletMesh"
	add_child(_mesh_root)

	var pallet_h   := 0.14
	var base_pad   := 0.10
	var w          := cell_w - base_pad
	var d          := cell_d - base_pad

	# Wooden pallet base — one stretched pad across the full footprint.
	_box(_mesh_root, Vector3(w, pallet_h, d),
		 Vector3(0.0, pallet_h * 0.5, 0.0),
		 Color(0.55, 0.38, 0.22))

	# Cargo: one model per cell so items don't smear into a single blob.
	# Provisions randomises across barrel / crate / sack / jug-cluster.
	if pallet != null and pallet.units > 0:
		_build_per_cell_cargo(pallet_h)

	# Label floating above
	if _label == null:
		_label             = Label3D.new()
		_label.name        = "PalletLabel"
		_label.font_size   = 64
		_label.pixel_size  = 0.004
		_label.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.modulate    = Color.WHITE
		add_child(_label)

	if pallet != null:
		var dest_name := _destination_display()
		var dest_line := "→ %s" % dest_name if not dest_name.is_empty() else ""
		var gold_line := "%d ℳ" % pallet.value_gold if pallet.value_gold > 0 else ""
		var lines     := PackedStringArray()
		lines.append("%s ×%d" % [pallet.display_name, pallet.units])
		if not dest_line.is_empty():
			lines.append(dest_line)
		if not gold_line.is_empty():
			lines.append(gold_line)
		_label.text     = "\n".join(lines)
		_label.position = Vector3(0.0, 1.35, 0.0)

	_build_attach_sockets()


func _destination_display() -> String:
	if pallet == null or pallet.destination_port_id.is_empty():
		return ""
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return ""
	return str(registry.call("get_port_display_name", pallet.destination_port_id))


func _build_attach_sockets() -> void:
	for s in _sockets:
		if is_instance_valid(s):
			s.queue_free()
	_sockets.clear()

	# Sockets sit at the outer corners of the (possibly multi-cell) footprint.
	# cell_w/cell_d already encode the full extent (set by CargoDeckComponent
	# as cell_size × footprint dim), so this scales for 1×1, 1×4, 2×2, …
	var inset := 0.18
	var hx    := cell_w * 0.5 - inset
	var hz    := cell_d * 0.5 - inset
	var y     := 0.18  # just above the pallet base
	var corners := [
		Vector3(-hx, y, -hz),
		Vector3( hx, y, -hz),
		Vector3( hx, y,  hz),
		Vector3(-hx, y,  hz),
	]
	for i in corners.size():
		var sock := PalletAttachPoint.new()
		sock.name = "Socket%d" % i
		sock.corner_index = i
		sock.pallet_node = self
		sock.position = corners[i]
		add_child(sock)
		_sockets.append(sock)


func _commodity_color() -> Color:
	if pallet == null:
		return Color(0.6, 0.6, 0.6)
	match pallet.commodity:
		"grain":      return Color(0.90, 0.78, 0.30)
		"timber":     return Color(0.52, 0.33, 0.18)
		"iron_ore":   return Color(0.50, 0.42, 0.38)
		"coal":       return Color(0.20, 0.20, 0.22)
		"provisions": return Color(0.72, 0.30, 0.22)
		_:            return Color(0.60, 0.60, 0.60)


func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi               := MeshInstance3D.new()
	var mesh             := BoxMesh.new()
	mesh.size            = size
	mi.mesh              = mesh
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = color
	mi.material_override = mat
	mi.position          = pos
	root.add_child(mi)


# ── Per-cell cargo placement ──────────────────────────────────────────────────

## Lays out `pallet.units` cargo items across the footprint, one item per cell,
## with visible gaps between cells. Uses a per-pallet RNG seeded by pallet.id
## so the layout is stable across visual rebuilds.
func _build_per_cell_cargo(base_y: float) -> void:
	if pallet == null:
		return
	var fp_w := maxi(pallet.footprint.x, 1)
	var fp_h := maxi(pallet.footprint.y, 1)
	var cell_real_w := cell_w / float(fp_w)
	var cell_real_d := cell_d / float(fp_h)
	var total_w := cell_w
	var total_d := cell_d

	# Deterministic per-pallet RNG so re-renders keep the same layout.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pallet.id) if not pallet.id.is_empty() else 0

	var remaining := pallet.units
	# Iterate by row then column; fills left-to-right, front-to-back.
	for row in fp_h:
		for col in fp_w:
			if remaining <= 0:
				return
			var lx := -total_w * 0.5 + cell_real_w * (float(col) + 0.5)
			var lz := -total_d * 0.5 + cell_real_d * (float(row) + 0.5)
			var item_pos := Vector3(lx, base_y, lz)
			_build_cargo_item(item_pos, cell_real_w, cell_real_d, rng)
			remaining -= 1


## Builds one cargo item centered on `pos`, fitting within cell_w × cell_d with
## inter-cell padding. Dispatches to commodity-specific variant or a default
## colored box.
func _build_cargo_item(pos: Vector3, c_w: float, c_d: float, rng: RandomNumberGenerator) -> void:
	var pad := 0.20
	var item_w := maxf(c_w - pad, 0.15)
	var item_d := maxf(c_d - pad, 0.15)

	match pallet.commodity:
		"provisions":
			_build_provisions_item(pos, item_w, item_d, rng)
		"timber":
			_build_timber_item(pos, item_w, item_d)
		_:
			# Default: a single tidy colored box per cell.
			var h := 0.55
			_box(_mesh_root, Vector3(item_w, h, item_d),
					pos + Vector3(0.0, h * 0.5, 0.0),
					_commodity_color())


# ── Provisions variants ───────────────────────────────────────────────────────

func _build_provisions_item(pos: Vector3, w: float, d: float, rng: RandomNumberGenerator) -> void:
	match rng.randi() % 4:
		0: _build_crate(pos, w, d)
		1: _build_barrel(pos, w, d)
		2: _build_sack(pos, w, d)
		_: _build_jug_cluster(pos, w, d)


func _build_crate(pos: Vector3, w: float, d: float) -> void:
	var h := 0.55
	var wood := Color(0.62, 0.45, 0.26)
	# Main box.
	_box(_mesh_root, Vector3(w, h, d), pos + Vector3(0.0, h * 0.5, 0.0), wood)
	# Dark rim/bands along the top and bottom edges for a crate look.
	var rim := wood.darkened(0.45)
	var rim_t := 0.04
	_box(_mesh_root, Vector3(w + 0.01, rim_t, d + 0.01),
			pos + Vector3(0.0, rim_t * 0.5, 0.0), rim)
	_box(_mesh_root, Vector3(w + 0.01, rim_t, d + 0.01),
			pos + Vector3(0.0, h - rim_t * 0.5, 0.0), rim)


func _build_barrel(pos: Vector3, w: float, d: float) -> void:
	var h := 0.62
	var radius := mini_dim(w, d) * 0.45
	var wood := Color(0.42, 0.25, 0.14)
	var band := Color(0.78, 0.66, 0.40)

	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = radius * 0.95
	bm.bottom_radius = radius * 0.95
	bm.height = h
	bm.radial_segments = 12
	body.mesh = bm
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.material_override = _mat(wood)
	body.position = pos + Vector3(0.0, h * 0.5, 0.0)
	_mesh_root.add_child(body)

	# Two metal bands.
	for ratio in [0.28, 0.72]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = radius * 1.02
		rm.bottom_radius = radius * 1.02
		rm.height = 0.04
		rm.radial_segments = 12
		ring.mesh = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.material_override = _mat(band, 0.4, 0.6)
		ring.position = pos + Vector3(0.0, h * float(ratio), 0.0)
		_mesh_root.add_child(ring)


func _build_sack(pos: Vector3, w: float, d: float) -> void:
	var canvas := Color(0.82, 0.74, 0.58)
	# Lower wider chunk + smaller upper for a "sack tied at top" silhouette.
	var lower_h := 0.45
	var upper_h := 0.20
	_box(_mesh_root, Vector3(w * 0.95, lower_h, d * 0.95),
			pos + Vector3(0.0, lower_h * 0.5, 0.0), canvas)
	_box(_mesh_root, Vector3(w * 0.55, upper_h, d * 0.55),
			pos + Vector3(0.0, lower_h + upper_h * 0.5, 0.0), canvas.darkened(0.08))
	# Tiny tie at the very top.
	_box(_mesh_root, Vector3(w * 0.18, 0.06, d * 0.18),
			pos + Vector3(0.0, lower_h + upper_h + 0.03, 0.0), Color(0.35, 0.25, 0.18))


func _build_jug_cluster(pos: Vector3, w: float, d: float) -> void:
	# Four small clay jugs in a 2×2 cluster.
	var jug_h := 0.42
	var jug_r := mini_dim(w, d) * 0.18
	var clay := Color(0.36, 0.22, 0.16)
	var offsets := [
		Vector3(-w * 0.22, 0.0, -d * 0.22),
		Vector3( w * 0.22, 0.0, -d * 0.22),
		Vector3(-w * 0.22, 0.0,  d * 0.22),
		Vector3( w * 0.22, 0.0,  d * 0.22),
	]
	for off in offsets:
		var jug := MeshInstance3D.new()
		var jm := CylinderMesh.new()
		jm.top_radius = jug_r * 0.6
		jm.bottom_radius = jug_r
		jm.height = jug_h
		jm.radial_segments = 8
		jug.mesh = jm
		jug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		jug.material_override = _mat(clay, 0.7, 0.0)
		jug.position = pos + off + Vector3(0.0, jug_h * 0.5, 0.0)
		_mesh_root.add_child(jug)


# ── Timber: a stack of planks per cell ────────────────────────────────────────

func _build_timber_item(pos: Vector3, w: float, d: float) -> void:
	var wood_a := Color(0.55, 0.36, 0.20)
	var wood_b := Color(0.48, 0.30, 0.16)
	var plank_h := 0.08
	var planks := 6
	for i in planks:
		var c := wood_a if i % 2 == 0 else wood_b
		_box(_mesh_root, Vector3(w, plank_h, d * 0.92),
				pos + Vector3(0.0, plank_h * (float(i) + 0.5), 0.0), c)


# ── Tiny helpers ──────────────────────────────────────────────────────────────

func mini_dim(a: float, b: float) -> float:
	return a if a < b else b


func _mat(col: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	m.metallic = metallic
	return m
