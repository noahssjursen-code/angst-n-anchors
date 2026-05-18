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
	var stack_h    := 0.70
	var pad        := 0.10
	var w          := cell_w - pad
	var d          := cell_d - pad

	# Pallet base
	_box(_mesh_root, Vector3(w, pallet_h, d),
		 Vector3(0.0, pallet_h * 0.5, 0.0),
		 Color(0.55, 0.38, 0.22))

	# Cargo stack on top (height scales with unit count)
	if pallet != null and pallet.units > 0:
		var fill  := clampf(float(pallet.units) / float(maxi(pallet.max_units, 1)), 0.15, 1.0)
		var sh    := stack_h * fill
		_box(_mesh_root, Vector3(w * 0.88, sh, d * 0.88),
			 Vector3(0.0, pallet_h + sh * 0.5, 0.0),
			 _commodity_color())

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
