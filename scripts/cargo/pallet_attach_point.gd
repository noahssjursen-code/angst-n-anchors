class_name PalletAttachPoint
extends Area3D

## One of the four chain-attachment sockets on a Pallet. Sits at a corner of the
## pallet, slightly above the deck. While the crane has highlighting enabled,
## the socket renders a glowing ring; clicking it (LMB raycast hit) tells the
## crane to attach one chain to this point.

const GROUP := "pallet_attach_point"
const RADIUS := 0.32

signal clicked(socket: PalletAttachPoint)

## The PalletNode this socket belongs to.
var pallet_node: Node3D = null
## 0..3 — used by the crane to track which corner is which.
var corner_index: int = 0

var _ring: MeshInstance3D
var _attached: bool = false
var _highlighted: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	input_ray_pickable = true
	monitoring = false  # we don't need physics overlap, just raycast picks

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	_ring.mesh = mesh
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	_apply_material()
	input_event.connect(_on_input_event)


func set_highlighted(on: bool) -> void:
	if _highlighted == on:
		return
	_highlighted = on
	_ring.visible = on or _attached
	_apply_material()


func set_attached(on: bool) -> void:
	_attached = on
	_ring.visible = _highlighted or _attached
	_apply_material()


func is_attached() -> bool:
	return _attached


func _on_input_event(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _shape_idx: int) -> void:
	if not _highlighted:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


func _apply_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	if _attached:
		mat.albedo_color = Color(0.30, 0.95, 0.45, 0.85)
		mat.emission_enabled = true
		mat.emission = Color(0.30, 0.95, 0.45)
		mat.emission_energy_multiplier = 1.5
	elif _highlighted:
		mat.albedo_color = Color(1.0, 0.85, 0.20, 0.65)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.20)
		mat.emission_energy_multiplier = 1.2
	else:
		mat.albedo_color = Color(0.6, 0.6, 0.6, 0.4)
	_ring.material_override = mat
