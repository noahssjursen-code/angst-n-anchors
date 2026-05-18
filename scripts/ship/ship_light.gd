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
	NAV_MASTHEAD  = 2,  ## White masthead steaming light (high, forward arc)
	NAV_STERN     = 3,  ## White stern light (low aft)
	WORK          = 4,  ## White deck flood
	WINDOW        = 5,  ## Warm amber cabin / wheelhouse glow
}

@export var light_type: LightType = LightType.NAV_PORT:
	set(v):
		light_type = v
		_rebuild()

var _light:    Light3D
var _lens_mat: StandardMaterial3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
	_rebuild()


## Called by ShipLighting to turn the light on or off.
func set_active(on: bool) -> void:
	if _light != null and is_instance_valid(_light):
		_light.visible = on
	if _lens_mat != null:
		_lens_mat.emission_enabled = on


func _rebuild() -> void:
	if not is_inside_tree():
		call_deferred("_rebuild")
		return

	_light    = null
	_lens_mat = null

	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	match light_type:
		LightType.NAV_PORT:
			_load_model("res://resources/data/lights/nav_light_port.json",
					"lens", Color(0.65, 0.04, 0.04))
			_light = _make_omni(Color(1.0, 0.05, 0.05), 8.0, 5.0, 3.0)
		LightType.NAV_STARBOARD:
			_load_model("res://resources/data/lights/nav_light_starboard.json",
					"lens", Color(0.04, 0.60, 0.08))
			_light = _make_omni(Color(0.05, 1.0, 0.15), 8.0, 5.0, 3.0)
		LightType.NAV_MASTHEAD:
			_load_model("res://resources/data/lights/nav_light_masthead.json",
					"glass_panel", Color(0.88, 0.88, 0.82))
			_light = _make_omni(Color(1.0, 1.0, 0.95), 15.0, 6.0, 4.0)
		LightType.NAV_STERN:
			_load_model("res://resources/data/lights/nav_light_stern.json",
					"glass_band", Color(0.90, 0.88, 0.80))
			_light = _make_omni(Color(1.0, 1.0, 0.95), 10.0, 4.0, 2.5)
		LightType.WORK:
			_load_model("res://resources/data/lights/work_light.json",
					"lens_face", Color(0.92, 0.90, 0.82))
			_light = _make_spot_down(30.0, 80.0, 70.0)
		LightType.WINDOW:
			_light = _make_omni(Color(1.0, 0.80, 0.50), 6.0, 1.5, 0.4)

	if _light != null:
		_light.visible = false

	if Engine.is_editor_hint() and get_tree() != null:
		var esc: Node = get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


# --- Model loading ---

func _load_model(path: String, lens_part: String, lens_color: Color) -> void:
	var assembler := ModelAssembler.new()
	assembler.name = "Model"
	assembler.model_data_path = path
	add_child(assembler)
	# add_child triggers assembler._ready() → rebuild() synchronously, so parts are ready now

	var mt := assembler.get_part(lens_part) as MeshTransformer
	if mt == null:
		return
	var mi := _find_mesh_instance(mt)
	if mi == null:
		return
	_lens_mat = _emissive_mat(lens_color)
	mi.material_override = _lens_mat


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


# --- Material helpers ---

func _emissive_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = color
	mat.roughness                  = 0.1
	mat.emission_enabled           = false  # toggled by set_active()
	mat.emission                   = color
	mat.emission_energy_multiplier = 2.5
	return mat


# --- Light helpers ---

func _make_omni(color: Color, range_m: float, energy: float, vol_energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color                 = color
	light.omni_range                  = range_m
	light.light_energy                = energy
	light.light_volumetric_fog_energy = vol_energy
	light.shadow_enabled              = false
	add_child(light)
	return light


func _make_spot_down(range_m: float, energy: float, angle_deg: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.rotation_degrees            = Vector3(-90.0, 0.0, 0.0)
	light.light_color                 = Color(1.0, 0.97, 0.90)
	light.spot_range                  = range_m
	light.light_energy                = energy
	light.light_volumetric_fog_energy = energy * 0.25
	light.spot_angle                  = angle_deg
	light.spot_angle_attenuation      = 0.8
	light.shadow_enabled              = false
	add_child(light)
	return light


func _own_subtree(node: Node, esc: Node) -> void:
	if node != esc:
		node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
