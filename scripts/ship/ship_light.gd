@tool
class_name ShipLight
extends Node3D

## A physical ship light fixture — a visible housing mesh plus a Light3D.
## Place as a child of the boat scene (e.g. under ShipGameplay) with an explicit position.
## ShipLighting discovers these by GROUP and drives set_active().

const GROUP := "ship_light"

enum LightType {
	NAV_PORT      = 0,  ## Red port-side running light
	NAV_STARBOARD = 1,  ## Green starboard running light
	NAV_MASTHEAD  = 2,  ## White all-round masthead light (omni, every bearing)
	NAV_STERN     = 3,  ## White stern light (low aft)
	WORK          = 4,  ## White deck / external flood
	WINDOW        = 5,  ## Warm amber cabin / wheelhouse glow
}

@export var light_type: LightType = LightType.NAV_PORT:
	set(v):
		if light_type == v:
			return
		light_type = v
		## Only rebuild after ready — avoids deferred rebuild wiping set_active().
		if is_node_ready():
			_rebuild()

## When false, only the Light3D is created (brick mesh supplies the housing).
@export var build_housing: bool = true
## Spot aim pitch (degrees). 0 = along local −Z (use when parented under a pitched FloodHead).
@export var spot_pitch_deg: float = -45.0
@export var spot_range_m: float = 22.0
@export var spot_energy: float = 55.0
@export var spot_angle_deg: float = 48.0
## Imported fixtures can keep a readable lens without washing nearby bulkheads.
@export var omni_range_scale: float = 1.0
@export var omni_energy_scale: float = 1.0
@export var lens_energy_scale: float = 1.0

var _light: Light3D
var _bulb: OmniLight3D
var _lens_mat: StandardMaterial3D
var _lens_mesh: MeshInstance3D
var _active: bool = false
var _base_energy: float = 0.0
var _base_vol_energy: float = 0.0
var _base_bulb_energy: float = 0.0
var _day_scale: float = 1.0
var _vol_scale: float = 1.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
	_rebuild()
	call_deferred("_bind_brick_lens")


## Called by ShipLighting to turn the light on or off.
func set_active(on: bool) -> void:
	_active = on
	_apply_active()


## Daylight energy / volumetric damp from ShipLighting (preserves night look).
func set_day_scale(light_scale: float, volumetric_scale: float) -> void:
	_day_scale = clampf(light_scale, 0.0, 1.0)
	_vol_scale = clampf(volumetric_scale, 0.0, 1.0)
	_apply_energies()


func _apply_active() -> void:
	if _light != null and is_instance_valid(_light):
		_light.visible = _active
	if _bulb != null and is_instance_valid(_bulb):
		_bulb.visible = _active
	if _lens_mat != null:
		_lens_mat.emission_enabled = _active
		_lens_mat.albedo_color = _lens_mat.emission if _active else _lens_mat.emission.darkened(0.55)
	_apply_energies()


func _apply_energies() -> void:
	var energy_mul := _day_scale if _active else 0.0
	var vol_mul := _vol_scale if _active else 0.0
	if _light != null and is_instance_valid(_light):
		_light.light_energy = _base_energy * energy_mul
		_light.light_volumetric_fog_energy = _base_vol_energy * vol_mul
	if _bulb != null and is_instance_valid(_bulb):
		_bulb.light_energy = _base_bulb_energy * energy_mul
	if _lens_mat != null:
		_lens_mat.emission_energy_multiplier = (
			_lens_on_energy() * lens_energy_scale * energy_mul if _active else 0.0
		)


func _lens_on_energy() -> float:
	match light_type:
		LightType.WORK:
			return 8.0
		LightType.WINDOW:
			return 6.0
		LightType.NAV_PORT, LightType.NAV_STARBOARD:
			return 9.0
		_:
			return 7.0


func _rebuild() -> void:
	if not is_inside_tree():
		return

	_light = null
	_bulb = null
	_lens_mat = null
	_lens_mesh = null
	_base_energy = 0.0
	_base_vol_energy = 0.0
	_base_bulb_energy = 0.0

	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	match light_type:
		LightType.NAV_PORT:
			if build_housing:
				_load_model("res://resources/data/lights/nav_light_port.json",
						"lens", Color(0.65, 0.04, 0.04))
			_light = _make_omni(Color(1.0, 0.08, 0.06), 6.0, 3.5, 1.2)
			_bulb = _make_bulb(Color(1.0, 0.2, 0.15), 0.9, 2.2)
		LightType.NAV_STARBOARD:
			if build_housing:
				_load_model("res://resources/data/lights/nav_light_starboard.json",
						"lens", Color(0.04, 0.60, 0.08))
			_light = _make_omni(Color(0.08, 1.0, 0.2), 6.0, 3.5, 1.2)
			_bulb = _make_bulb(Color(0.2, 1.0, 0.3), 0.9, 2.2)
		LightType.NAV_MASTHEAD:
			if build_housing:
				_load_model("res://resources/data/lights/nav_light_masthead.json",
						"glass_panel", Color(0.88, 0.88, 0.82))
			## Point light — masthead / all-round white must read from every bearing.
			## Stronger fill so a deck-mounted lantern still washes the topsides.
			_light = _make_omni(Color(1.0, 1.0, 0.95), 22.0, 8.0, 2.4)
			_bulb = _make_bulb(Color(1.0, 0.98, 0.9), 1.6, 3.5)
		LightType.NAV_STERN:
			if build_housing:
				_load_model("res://resources/data/lights/nav_light_stern.json",
						"glass_band", Color(0.90, 0.88, 0.80))
			_light = _make_omni(Color(1.0, 1.0, 0.95), 8.0, 3.5, 1.2)
			_bulb = _make_bulb(Color(1.0, 0.98, 0.9), 1.0, 2.2)
		LightType.WORK:
			if build_housing:
				_load_model("res://resources/data/lights/work_light.json",
						"lens_face", Color(0.92, 0.90, 0.82))
			## Spot only — no omni bulb (omni paints fake white rings on the mount face).
			_light = _make_spot(spot_pitch_deg, spot_range_m, spot_energy, spot_angle_deg)
			_bulb = null
		LightType.WINDOW:
			## Warm pool under the fixture; tiny bulb only for the glass, not the bulkhead.
			_light = _make_omni(Color(1.0, 0.78, 0.45), 5.5, 3.2, 1.8)
			_bulb = _make_bulb(Color(1.0, 0.8, 0.45), 0.28, 2.0)
			if _bulb != null:
				_bulb.position = Vector3(0.0, -0.08, 0.0)

	## Restore on/off after rebuild (gather may have already called set_active).
	_apply_active()

	if Engine.is_editor_hint() and get_tree() != null:
		var esc: Node = get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


func _bind_brick_lens() -> void:
	## Brick fixtures name the glowing face "Lens" under the parent visual.
	if build_housing or _lens_mat != null:
		return
	var host := get_parent() as Node
	if host == null:
		return
	var lens := _find_named_mesh(host, "Lens")
	if lens == null:
		## FloodHead parent — lens is a sibling; also try grandparent visual.
		var grand := host.get_parent()
		if grand != null:
			lens = _find_named_mesh(grand, "Lens")
	if lens == null:
		return
	_lens_mesh = lens
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var col := Color(0.95, 0.9, 0.7)
	match light_type:
		LightType.NAV_PORT:
			col = Color(0.9, 0.12, 0.08)
		LightType.NAV_STARBOARD:
			col = Color(0.1, 0.85, 0.2)
		LightType.WINDOW:
			col = Color(1.0, 0.78, 0.45)
		_:
			col = Color(0.98, 0.94, 0.8)
	_lens_mat = _emissive_mat(col)
	lens.material_override = _lens_mat
	_apply_active()


func _find_named_mesh(node: Node, mesh_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == mesh_name:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_named_mesh(child, mesh_name)
		if found != null:
			return found
	return null


# --- Model loading ---

func _load_model(path: String, lens_part: String, lens_color: Color) -> void:
	var assembler := ModelAssembler.new()
	assembler.name = "Model"
	assembler.model_data_path = path
	add_child(assembler)

	var mt := assembler.get_part(lens_part) as MeshTransformer
	if mt == null:
		return
	var mi := _find_mesh_instance(mt)
	if mi == null:
		return
	_lens_mat = _emissive_mat(lens_color)
	_lens_mesh = mi
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _lens_mat


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


# --- Material helpers ---

func _emissive_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.55)
	mat.roughness = 0.2
	mat.metallic = 0.0
	mat.metallic_specular = 0.6
	mat.emission_enabled = false
	mat.emission = color
	mat.emission_energy_multiplier = 0.0
	return mat


# --- Light helpers ---

func _make_omni(color: Color, range_m: float, energy: float, vol_energy: float) -> OmniLight3D:
	range_m *= omni_range_scale
	energy *= omni_energy_scale
	vol_energy *= omni_energy_scale
	var light := OmniLight3D.new()
	light.name = "Fill"
	light.light_color = color
	light.omni_range = range_m
	light.omni_attenuation = 1.5
	_base_energy = energy
	# The lens/glow handles long-range recognition. Keep only enough volumetric
	# injection to reveal nearby moisture without turning the complete ship into
	# a luminous fog ball.
	_base_vol_energy = minf(vol_energy, 0.6)
	light.light_energy = energy * _day_scale
	light.light_volumetric_fog_energy = _base_vol_energy * _vol_scale
	light.light_specular = 0.7
	light.light_size = 0.1
	light.shadow_enabled = false
	add_child(light)
	return light


func _make_bulb(color: Color, range_m: float, energy: float) -> OmniLight3D:
	range_m *= omni_range_scale
	energy *= omni_energy_scale
	## Tiny near-field glow for the lens glass only — keep range tiny to avoid wall rings.
	var light := OmniLight3D.new()
	light.name = "Bulb"
	light.light_color = color
	light.omni_range = range_m
	light.omni_attenuation = 3.5
	_base_bulb_energy = energy
	light.light_energy = energy * _day_scale
	light.light_volumetric_fog_energy = 0.0
	light.light_specular = 0.2
	light.light_size = 0.02
	light.shadow_enabled = false
	add_child(light)
	return light


func _make_spot(pitch_deg: float, range_m: float, energy: float, angle_deg: float) -> SpotLight3D:
	## SpotLight looks down local −Z; pitch −45 throws toward deck along brick −Z.
	var light := SpotLight3D.new()
	light.name = "Beam"
	light.rotation_degrees = Vector3(pitch_deg, 0.0, 0.0)
	## Sit just past the lens face so housing geometry cannot self-shadow the cone.
	light.position = Vector3(0.0, 0.0, -0.08)
	light.light_color = Color(1.0, 0.96, 0.88)
	light.spot_range = range_m
	light.spot_attenuation = 1.25
	_base_energy = energy
	_base_vol_energy = clampf(energy * 0.055, 1.5, 3.5)
	light.light_energy = energy * _day_scale
	light.light_volumetric_fog_energy = _base_vol_energy * _vol_scale
	light.spot_angle = angle_deg
	light.spot_angle_attenuation = 1.8
	light.light_specular = 0.85
	light.light_size = 0.15
	light.shadow_enabled = true
	light.shadow_bias = 0.06
	light.shadow_normal_bias = 1.2
	light.shadow_blur = 1.5
	add_child(light)
	return light


func _make_spot_down(range_m: float, energy: float, angle_deg: float) -> SpotLight3D:
	return _make_spot(-90.0, range_m, energy, angle_deg)


func _own_subtree(node: Node, esc: Node) -> void:
	if node != esc:
		node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
