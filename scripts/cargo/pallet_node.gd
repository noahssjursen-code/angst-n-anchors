class_name PalletNode
extends Node3D

## World-space representation of a Pallet sitting on a grid cell.
## The crane will grab this node to move it between apron and deck.
##
## Geometry comes from ModelAssembler-loaded JSON models under
## `resources/data/models/cargo/`. Each footprint has its own pallet model
## (pallet_1x1, pallet_1x2, pallet_2x2, pallet_2x3 — others rotated). Cargo
## per cell is picked from a per-commodity library (provisions has barrel /
## produce-crate / hay-bales / amphora variants; other commodities still
## use a placeholder block until their own JSON models land).

const GROUP := "pallet_node"

## One pallet JSON per canonical footprint shape. Other orientations
## (e.g. 2×1, 3×2) load the smaller-dim-first variant and rotate 90° at
## instantiation.
const PALLET_MODELS := {
	Vector2i(1, 1): "res://resources/data/models/cargo/pallet_1x1.json",
	Vector2i(1, 2): "res://resources/data/models/cargo/pallet_1x2.json",
	Vector2i(2, 2): "res://resources/data/models/cargo/pallet_2x2.json",
	Vector2i(2, 3): "res://resources/data/models/cargo/pallet_2x3.json",
}

const MODEL_PROVISIONS := [
	"res://resources/data/models/cargo/provisions_barrel.json",
	"res://resources/data/models/cargo/provisions_produce_pile.json",
	"res://resources/data/models/cargo/provisions_hay_bales.json",
	"res://resources/data/models/cargo/provisions_amphora.json",
]

signal grabbed(node: PalletNode)
signal released(node: PalletNode)

var pallet: Pallet = null
var cell_w: float  = 1.5
var cell_d: float  = 1.5
## Footprint to draw in this node's LOCAL frame. Usually the deck-local
## footprint (= pallet.footprint maybe with X/Z swapped if the deck is
## rotated 90° from world). Defaults to pallet.footprint when setup is
## called without an override.
var _display_fp: Vector2i = Vector2i(1, 1)

var _mesh_root: Node3D
var _label: Label3D
var _sockets: Array[PalletAttachPoint] = []

## Pickup-ready indicator: a thin pulsing gold disc that wraps the pallet.
## Hidden by default; the crane toggles it when this is the highlighted pallet.
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _highlighted: bool = false
var _halo_phase: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)


func setup(p: Pallet, cell_width: float = 1.5, cell_depth: float = 1.5,
		display_fp: Vector2i = Vector2i.ZERO) -> void:
	pallet = p
	cell_w = cell_width
	cell_d = cell_depth
	if display_fp.x > 0 and display_fp.y > 0:
		_display_fp = display_fp
	elif p != null and p.footprint.x > 0 and p.footprint.y > 0:
		_display_fp = p.footprint
	else:
		_display_fp = Vector2i(1, 1)
	_build()


func _build() -> void:
	if _mesh_root != null and is_instance_valid(_mesh_root):
		_mesh_root.queue_free()

	_mesh_root          = Node3D.new()
	_mesh_root.name     = "PalletMesh"
	add_child(_mesh_root)

	_build_pallet_base()

	# Cargo: one model per cell so items don't smear into a single blob.
	# Provisions randomises across barrel / crate / sack / amphora cluster.
	if pallet != null and pallet.units > 0:
		_build_per_cell_cargo()

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
	_build_halo()


func set_highlighted(on: bool) -> void:
	_highlighted = on
	if _halo != null:
		_halo.visible = on


func _build_halo() -> void:
	if _halo != null and is_instance_valid(_halo):
		_halo.queue_free()
	_halo = MeshInstance3D.new()
	_halo.name = "PickupHalo"
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(maxf(cell_w, cell_d) * 0.50, 0.5)
	torus.outer_radius = torus.inner_radius + 0.18
	torus.rings = 32
	torus.ring_segments = 8
	_halo.mesh = torus
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0.0, 0.04, 0.0)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.no_depth_test = true
	_halo_mat.albedo_color = Color(1.0, 0.84, 0.18, 0.6)
	_halo_mat.emission_enabled = true
	_halo_mat.emission = Color(1.0, 0.84, 0.18)
	_halo_mat.emission_energy_multiplier = 1.6
	_halo.material_override = _halo_mat
	_halo.visible = _highlighted
	add_child(_halo)


func _process(delta: float) -> void:
	# Hide the floating commodity / destination / value label while the player
	# is helming a boat — it's clutter when sailing past port cargo.
	if _label != null:
		_label.visible = BoatController.helmed_count == 0

	if not _highlighted or _halo == null or _halo_mat == null:
		return
	_halo_phase = fmod(_halo_phase + delta * 3.0, TAU)
	var pulse := 0.6 + 0.4 * sin(_halo_phase)
	_halo_mat.emission_energy_multiplier = 1.0 + pulse * 1.5
	_halo.scale.x = 1.0 + pulse * 0.05
	_halo.scale.z = 1.0 + pulse * 0.05


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

	var inset := 0.18
	var hx    := cell_w * 0.5 - inset
	var hz    := cell_d * 0.5 - inset
	var y     := 0.18
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


# ── JSON model loading ────────────────────────────────────────────────────────

## Loads a JSON-defined model via ModelAssembler at `local_pos` (within
## _mesh_root). Returns null when the path is missing on disk — protects
## against stale references after rename / delete.
func _spawn_model(model_path: String, local_pos: Vector3) -> ModelAssembler:
	if not FileAccess.file_exists(model_path):
		push_warning("PalletNode: model not found: " + model_path)
		return null
	var node := ModelAssembler.new()
	node.model_data_path = model_path
	node.position = local_pos
	_mesh_root.add_child(node)
	return node


# ── Pallet base — one model per footprint, optionally rotated 90° ────────────

func _build_pallet_base() -> void:
	if pallet == null:
		return
	var fp_x := maxi(_display_fp.x, 1)
	var fp_z := maxi(_display_fp.y, 1)
	# Pick the canonical (small-dim, large-dim) key. If the actual footprint is
	# wider than deep, rotate the model 90° around Y at instantiation.
	var key := Vector2i(mini(fp_x, fp_z), maxi(fp_x, fp_z))
	var path: String = PALLET_MODELS.get(key, PALLET_MODELS[Vector2i(1, 1)])
	var asm := _spawn_model(path, Vector3.ZERO)
	if asm != null and fp_x > fp_z:
		asm.rotation.y = PI * 0.5


# ── Per-cell cargo placement ──────────────────────────────────────────────────

## Lays out `pallet.units` cargo items across the footprint, one item per cell.
## Layout is deterministic per pallet (seeded by pallet.id) so visuals are
## stable across rebuilds.
func _build_per_cell_cargo() -> void:
	if pallet == null:
		return
	var fp_w := maxi(_display_fp.x, 1)
	var fp_h := maxi(_display_fp.y, 1)
	var cell_real_w := cell_w / float(fp_w)
	var cell_real_d := cell_d / float(fp_h)
	var base_y := 0.14   # top of the pallet section deck

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pallet.id) if not pallet.id.is_empty() else 0

	var remaining := pallet.units
	for row in fp_h:
		for col in fp_w:
			if remaining <= 0:
				return
			var lx := -cell_w * 0.5 + cell_real_w * (float(col) + 0.5)
			var lz := -cell_d * 0.5 + cell_real_d * (float(row) + 0.5)
			_build_cargo_item(Vector3(lx, base_y, lz), cell_real_w, cell_real_d, rng)
			remaining -= 1


func _build_cargo_item(pos: Vector3, c_w: float, c_d: float, rng: RandomNumberGenerator) -> void:
	match pallet.commodity:
		"provisions":
			# Pick one of the four provisions JSON models per cell.
			var path: String = MODEL_PROVISIONS[rng.randi() % MODEL_PROVISIONS.size()]
			_spawn_model(path, pos)
		_:
			# Other commodities have no JSON models yet — drop a tidy
			# placeholder cube per cell. Replace when their models land.
			var pad := 0.2
			var h := 0.55
			var w := maxf(c_w - pad, 0.15)
			var d := maxf(c_d - pad, 0.15)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(w, h, d)
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.albedo_color = _commodity_color()
			mi.material_override = mat
			mi.position = pos + Vector3(0.0, h * 0.5, 0.0)
			_mesh_root.add_child(mi)
