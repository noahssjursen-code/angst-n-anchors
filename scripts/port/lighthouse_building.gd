@tool
class_name LighthouseBuilding
extends Node3D

## Procedural lighthouse. Rotating beam uses volumetric spotlights.

const MODEL_PATH := "res://resources/data/models/buildings/lighthouse_building.json"

@export var sweep_speed_hz: float = 15.0 / 360.0

var assembler: ModelAssembler
var _rotor: Node3D
var _spot1: SpotLight3D
var _spot2: SpotLight3D
var _omni: OmniLight3D
var _beam_mi1: MeshInstance3D
var _beam_mi2: MeshInstance3D
var _beam_mat: ShaderMaterial
## Tracks whether the lighthouse contribution is currently "on" so we can
## set node.visible exactly when it transitions — keeps the per-frame
## branch cheap (one bool compare) instead of poking visibility every tick.
var _is_active: bool = false

const BEAM_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform float energy = 1.0;
uniform float fog_density = 0.0;

varying float v_length_factor;
varying vec3 v_world_pos;

void vertex() {
	// UV.y is 0 at the far end (top_radius) and 1 at the origin (bottom_radius)
	v_length_factor = UV.y;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist_to_cam = length(CAMERA_POSITION_WORLD - v_world_pos);
	
	// Don't obstruct view when the player is VERY close to the lighthouse
	float cam_fade = clamp((dist_to_cam - 20.0) / 100.0, 0.0, 1.0);
	
	// Fade out towards the end of the beam. Higher power means it drops off faster for a stronger gradient.
	float length_fade = pow(v_length_factor, 3.0);
	
	// When fog is high, the beam is actually MORE visible because there's more particulate to reflect it!
	float fog_boost = 1.0 + fog_density * 3.0;
	
	// Also fade it out VERY far away so it doesn't just pop out of existence
	float max_dist_fade = 1.0 - clamp((dist_to_cam - 3000.0) / 1000.0, 0.0, 1.0);
	
	ALBEDO = beam_color.rgb * energy * fog_boost;
	// Significantly lower base alpha so it's a dim, atmospheric cone instead of a solid shape
	ALPHA = beam_color.a * length_fade * cam_fade * max_dist_fade * 0.015 * fog_boost;
}
"""

func _ready() -> void:
	_build()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _rotor == null:
		return
	_rotor.rotate_y(TAU * sweep_speed_hz * delta)

	var weather = get_node_or_null("/root/WeatherLighting")
	if weather == null:
		return

	var fog = float(weather.get("fog_density"))
	var time = float(weather.get("time_of_day"))

	# Night factor: time_of_day is 0.0 to 1.0. 0.5 is noon.
	var dist_from_noon = abs(time - 0.5)
	var night_factor = smoothstep(0.15, 0.35, dist_from_noon)
	var fog_factor = smoothstep(0.1, 0.4, fog)
	var raw_factor: float = night_factor + fog_factor

	# Toggle hard off when contribution would be invisible — kills the spotlight
	# contribution to volumetric fog (each spot was injecting up to 1500 units
	# of fog energy over a 4 km range, very expensive) and stops the alpha-blended
	# beam meshes from drawing transparent overdraw across the screen. Threshold
	# matches the old 0.05 clamp floor: at high noon with no fog the lighthouse
	# was only contributing 5% energy anyway, which is below visual perception
	# through the existing dim/grade pipeline.
	var should_be_active: bool = raw_factor > 0.04
	if should_be_active != _is_active:
		_is_active = should_be_active
		if _spot1: _spot1.visible = should_be_active
		if _spot2: _spot2.visible = should_be_active
		if _omni:  _omni.visible  = should_be_active
		if _beam_mi1: _beam_mi1.visible = should_be_active
		if _beam_mi2: _beam_mi2.visible = should_be_active

	if not _is_active:
		return

	var active_factor = clampf(raw_factor, 0.05, 1.0)
	if _spot1:
		_spot1.light_energy = 400.0 * active_factor
		_spot1.light_volumetric_fog_energy = 1500.0 * active_factor
	if _spot2:
		_spot2.light_energy = 400.0 * active_factor
		_spot2.light_volumetric_fog_energy = 1500.0 * active_factor
	if _omni:
		_omni.light_energy = 20.0 * active_factor
		_omni.light_volumetric_fog_energy = 5.0 * active_factor
	if _beam_mat:
		_beam_mat.set_shader_parameter("energy", 1.0 * active_factor)
		_beam_mat.set_shader_parameter("fog_density", fog)

func _build() -> void:
	if assembler != null:
		assembler.queue_free()

	for child in get_children():
		if child is ModelAssembler or child.name == "LightRotor" or child.name == "LanternOmni":
			if Engine.is_editor_hint():
				child.free()
			else:
				child.queue_free()

	assembler = ModelAssembler.new()
	assembler.name = "LighthouseModel"
	assembler.model_data_path = MODEL_PATH
	assembler.build_part_colliders = not Engine.is_editor_hint()
	add_child(assembler)

	_rotor = Node3D.new()
	_rotor.name = "LightRotor"
	_rotor.position.y = 22.0
	add_child(_rotor)
	
	_beam_mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = BEAM_SHADER
	_beam_mat.shader = shader
	
	var beam_mesh = CylinderMesh.new()
	beam_mesh.top_radius = 25.0
	beam_mesh.bottom_radius = 0.2
	beam_mesh.height = 3000.0
	beam_mesh.radial_segments = 16
	beam_mesh.rings = 1
	
	_beam_mi1 = MeshInstance3D.new()
	_beam_mi1.name = "BeamMesh1"
	_beam_mi1.mesh = beam_mesh
	_beam_mi1.material_override = _beam_mat
	# Move the center of the 3000m cylinder so the top (Y=1500) starts at Z=0
	_beam_mi1.position = Vector3(0, 0, -1500.0)
	_beam_mi1.rotation_degrees = Vector3(-90, 0, 0)
	_rotor.add_child(_beam_mi1)

	_beam_mi2 = MeshInstance3D.new()
	_beam_mi2.name = "BeamMesh2"
	_beam_mi2.mesh = beam_mesh
	_beam_mi2.material_override = _beam_mat
	_beam_mi2.position = Vector3(0, 0, 1500.0)
	_beam_mi2.rotation_degrees = Vector3(90, 0, 0)
	_rotor.add_child(_beam_mi2)

	# Two sweeping spotlights for volumetric fog interaction
	_spot1 = SpotLight3D.new()
	_spot1.name = "Spot1"
	_spot1.spot_range = 4000.0
	_spot1.spot_angle = 1.0
	_spot1.light_energy = 400.0
	_spot1.light_volumetric_fog_energy = 1500.0
	_spot1.light_color = Color(1.0, 0.97, 0.88)
	_spot1.shadow_enabled = false
	# Offset outward so they don't clip inside the lantern glass and cause crazy bloom
	_spot1.position = Vector3(0, 0, -1.8)
	_spot1.rotation_degrees = Vector3(0, 0, 0)
	_rotor.add_child(_spot1)
	
	_spot2 = SpotLight3D.new()
	_spot2.name = "Spot2"
	_spot2.spot_range = 4000.0
	_spot2.spot_angle = 1.0
	_spot2.light_energy = 400.0
	_spot2.light_volumetric_fog_energy = 1500.0
	_spot2.light_color = Color(1.0, 0.97, 0.88)
	_spot2.shadow_enabled = false
	# Offset outward so they don't clip inside the lantern glass
	_spot2.position = Vector3(0, 0, 1.8)
	_spot2.rotation_degrees = Vector3(0, 180, 0)
	_rotor.add_child(_spot2)

	# Warm close-range glow visible from any angle.
	_omni = OmniLight3D.new()
	_omni.name                        = "LanternOmni"
	_omni.omni_range                  = 50.0
	_omni.light_energy                = 20.0
	_omni.light_color                 = Color(1.0, 0.92, 0.72)
	_omni.light_volumetric_fog_energy = 5.0
	_omni.position.y                  = 22.0
	add_child(_omni)

	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)

func _own_subtree(node: Node, esc: Node) -> void:
	if node != esc:
		node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
