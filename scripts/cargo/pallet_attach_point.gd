class_name PalletAttachPoint
extends Node3D

## A passive visual marker at one corner of a Pallet showing where a chain
## attaches. Not interactive — the crane decides when to engage via a key
## press, not by clicking. This node just lights up to give visual feedback.

const GROUP := "pallet_attach_point"

## The PalletNode this socket belongs to.
var pallet_node: Node3D = null
## 0..3 — used by the crane to position chains consistently.
var corner_index: int = 0

var _ring: MeshInstance3D
var _highlighted: bool = false
var _attached: bool = false


func _ready() -> void:
	add_to_group(GROUP)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	mesh.radial_segments = 16
	mesh.rings = 8
	_ring.mesh = mesh
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_apply_material()


func set_highlighted(on: bool) -> void:
	if _highlighted == on:
		return
	_highlighted = on
	_apply_material()


func set_attached(on: bool) -> void:
	if _attached == on:
		return
	_attached = on
	_apply_material()


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
		mat.albedo_color = Color(1.0, 0.85, 0.20, 0.75)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.20)
		mat.emission_energy_multiplier = 1.4
	else:
		mat.albedo_color = Color(0.80, 0.80, 0.85, 0.28)
	_ring.material_override = mat
