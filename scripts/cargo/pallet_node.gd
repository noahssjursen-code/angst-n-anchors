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
		_label.text     = "%s\n×%d" % [pallet.display_name, pallet.units]
		_label.position = Vector3(0.0, 1.2, 0.0)


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
