class_name DestinationBeacon
extends Node3D

## A tall gold light column rising from a port. Visible only when at least one
## accepted contract has destination_port_id == this beacon's port_id, so the
## player can see at a glance where to deliver from anywhere on the map.

const BEAM_HEIGHT  := 220.0
const BASE_RADIUS  := 2.4
const TIP_RADIUS   := 0.35
const BEAM_COLOR   := Color(1.0, 0.82, 0.18)

var port_id: String = ""

var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _registry: Node
var _phase: float = 0.0


func _ready() -> void:
	_registry = get_node_or_null("/root/ContractRegistry")
	_build()
	if _registry != null:
		_registry.contract_accepted.connect(_refresh_deferred)
		_registry.contract_completed.connect(_refresh_deferred)
		_registry.unit_delivered.connect(_refresh_deferred)
	_refresh()


func _exit_tree() -> void:
	if _registry == null:
		return
	if _registry.contract_accepted.is_connected(_refresh_deferred):
		_registry.contract_accepted.disconnect(_refresh_deferred)
	if _registry.contract_completed.is_connected(_refresh_deferred):
		_registry.contract_completed.disconnect(_refresh_deferred)
	if _registry.unit_delivered.is_connected(_refresh_deferred):
		_registry.unit_delivered.disconnect(_refresh_deferred)


func _build() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius    = TIP_RADIUS
	cyl.bottom_radius = BASE_RADIUS
	cyl.height        = BEAM_HEIGHT
	cyl.radial_segments = 18
	_beam.mesh        = cyl
	_beam.position.y  = BEAM_HEIGHT * 0.5
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.28)
	mat.emission_enabled = true
	mat.emission = BEAM_COLOR
	mat.emission_energy_multiplier = 2.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = mat
	add_child(_beam)

	# Soft halo ring at the base for visibility up close.
	_ring = MeshInstance3D.new()
	_ring.name = "Halo"
	var torus := TorusMesh.new()
	torus.inner_radius = 3.5
	torus.outer_radius = 4.8
	_ring.mesh = torus
	_ring.position.y = 0.1
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.55)
	rmat.emission_enabled = true
	rmat.emission = BEAM_COLOR
	rmat.emission_energy_multiplier = 2.0
	_ring.material_override = rmat
	add_child(_ring)

	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_phase = fmod(_phase + delta * 1.4, TAU)
	var pulse := 0.65 + 0.35 * sin(_phase)
	if _beam != null and _beam.material_override is StandardMaterial3D:
		(_beam.material_override as StandardMaterial3D).emission_energy_multiplier = 1.5 + pulse * 1.8


func _refresh_deferred(_a = null, _b = null) -> void:
	_refresh.call_deferred()


func _refresh() -> void:
	if _registry == null or port_id.is_empty():
		visible = false
		return
	var accepted: Array = _registry.call("get_accepted_contracts")
	var match_count := 0
	for c in accepted:
		var contract := c as Contract
		if contract != null and contract.destination_port_id == port_id:
			match_count += 1
	visible = match_count > 0
