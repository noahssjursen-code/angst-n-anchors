extends SpotLight3D

var elapsed := 1.0
var lenses: Array[StandardMaterial3D] = []

func _ready() -> void:
	rotation.x = -PI*.5
	light_color = Color(1.0,.87,.68)
	light_energy = 28.0
	light_volumetric_fog_energy = .12
	spot_attenuation = 1.0
	spot_range = 28.0
	spot_angle = 62.0
	shadow_enabled = true
	shadow_normal_bias = .25
	shadow_bias = .03
	distance_fade_shadow = 65.0
	distance_fade_enabled = true
	distance_fade_begin = 160.0
	distance_fade_length = 60.0
	# Imported diffuser is one named surface in a shared mesh. Override locally.
	for mesh: MeshInstance3D in get_parent().find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or not source.resource_name.begins_with("Light diffuser"): continue
			var lens := source.duplicate() as StandardMaterial3D
			lens.emission_enabled=true
			lens.emission=light_color
			mesh.set_surface_override_material(surface,lens)
			lenses.append(lens)
	_update()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < .5: return
	elapsed = 0
	_update()

func _update() -> void:
	var daylight := WeatherLighting.daylight_factor()
	visible = daylight < .65
	light_energy = 28.0 * (1.0-smoothstep(.15,.65,daylight))

	for lens in lenses: lens.emission_energy_multiplier=3.0*(light_energy/28.0)
