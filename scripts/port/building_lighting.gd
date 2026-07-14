class_name BuildingLighting
extends Node

## Day/night controller for land-building fixtures. Kept separate from
## ShipLighting so ship group scans cannot claim static port lights.

const UPDATE_INTERVAL_S := 0.5

var _elapsed := UPDATE_INTERVAL_S


func _ready() -> void:
	_apply_scales()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL_S:
		return
	_elapsed = 0.0
	_apply_scales()


func _apply_scales() -> void:
	var weather := get_node_or_null("/root/WeatherLighting")
	var light_scale := 1.0
	var volumetric_scale := 1.0
	if weather != null:
		light_scale = float(weather.call("artificial_light_scale"))
		volumetric_scale = float(weather.call("artificial_volumetric_scale"))
	_apply_node(get_parent(), light_scale, volumetric_scale)


func _apply_node(node: Node, light_scale: float, volumetric_scale: float) -> void:
	if node is Light3D and node.has_meta("building_light_base_energy"):
		var light := node as Light3D
		light.light_energy = float(light.get_meta("building_light_base_energy")) * light_scale
		light.light_volumetric_fog_energy = (
			float(light.get_meta("building_light_base_volumetric", 0.45))
			* volumetric_scale
		)
	if node is MeshInstance3D and node.has_meta("building_lens_base_emission"):
		var mesh := node as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		if material != null:
			var base := float(mesh.get_meta("building_lens_base_emission"))
			material.emission_energy_multiplier = base * light_scale
	for child in node.get_children():
		if child != self:
			_apply_node(child, light_scale, volumetric_scale)
