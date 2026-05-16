@tool
class_name WorldRenderer
extends Node3D

## Owns the ocean, sky, sun/fill lights, and fog.
## Connects to WeatherLighting and updates all world visuals when weather changes.
## No knowledge of ports, players, or gameplay.

const OCEAN_SHADER   := preload("res://resources/shaders/ocean_waves.gdshader")
const SKY_SHADER     := preload("res://resources/shaders/sky.gdshader")
const SCREEN_SHADER  := preload("res://resources/shaders/screen_effects.gdshader")
## Base midday water dye — kept darker so the ocean reads as depth, not a bright lagoon.
const C_OCEAN      := Color(0.038, 0.085, 0.128)

var _ocean_shader_material: ShaderMaterial
var _sky_shader_material:   ShaderMaterial
var _environment:           Environment
var _sun:                   DirectionalLight3D
var _fill_light:            DirectionalLight3D
var _ocean_mesh:            MeshInstance3D


func _ready() -> void:
	_build_sky()
	_build_ocean()
	_build_screen_effects()
	_connect_weather_lighting()
	_apply_weather_lighting()


func _process(_delta: float) -> void:
	_follow_camera_xz()
	if _ocean_shader_material:
		_ocean_shader_material.set_shader_parameter("wave_time",      WaveSurface.get_sim_time())
		_ocean_shader_material.set_shader_parameter("wave_intensity",  WaveSurface.wave_intensity)
		WaveSurface.sync_ocean_coupling_to_shader(_ocean_shader_material)
	if _sky_shader_material:
		_sky_shader_material.set_shader_parameter("sky_time",       WaveSurface.get_sim_time())
		_sky_shader_material.set_shader_parameter("sun_direction",   _celestial_dir(0.0))
		_sky_shader_material.set_shader_parameter("moon_direction",  _celestial_dir(0.5))


func _follow_camera_xz() -> void:
	if _ocean_mesh == null or not is_instance_valid(_ocean_mesh):
		return
	# The shader reads world-space XZ via MODEL_MATRIX, so moving the mesh with
	# the camera keeps the full mesh over visible water without changing wave math.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_ocean_mesh.position.x = cam.global_position.x
	_ocean_mesh.position.z = cam.global_position.z


func _build_sky() -> void:
	var sky_sm := ShaderMaterial.new()
	sky_sm.shader        = SKY_SHADER
	_sky_shader_material = sky_sm

	var sky := Sky.new()
	sky.sky_material  = sky_sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var environ := Environment.new()
	_environment = environ
	environ.sky                  = sky
	environ.background_mode      = Environment.BG_SKY
	environ.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environ.ambient_light_energy = 0.18

	environ.tonemap_mode     = Environment.TONE_MAPPER_FILMIC
	environ.tonemap_exposure = 0.95
	environ.tonemap_white    = 6.0

	environ.ssao_enabled = false
	environ.glow_enabled = false
	environ.ssr_enabled  = false

	environ.adjustment_enabled    = true
	environ.adjustment_brightness = 1.02
	environ.adjustment_contrast   = 1.05
	environ.adjustment_saturation = 0.93

	environ.fog_enabled            = true
	environ.fog_light_color        = Color(0.58, 0.66, 0.78)
	environ.fog_density            = 0.005
	environ.fog_aerial_perspective = 0.12
	environ.fog_sky_affect         = 0.6

	var world_env := WorldEnvironment.new()
	world_env.environment = environ
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees                  = Vector3(-50, 28, 0)
	sun.light_color                       = Color(1.0, 0.92, 0.78)
	sun.light_energy                      = 1.5
	sun.shadow_enabled                    = true
	sun.directional_shadow_mode           = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance   = 180.0
	sun.shadow_bias                       = 0.04
	add_child(sun)

	var fill := DirectionalLight3D.new()
	_fill_light = fill
	fill.rotation_degrees = Vector3(40, -160, 0)
	fill.light_color      = Color(0.52, 0.64, 0.90)
	fill.light_energy     = 0.18
	fill.shadow_enabled   = false
	fill.sky_mode         = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)

	# Apply initial sky uniforms so the shader has values before the ocean is ready.
	_apply_weather_lighting()


func _build_screen_effects() -> void:
	if Engine.is_editor_hint():
		return
	var layer      := CanvasLayer.new()
	layer.name     = "ScreenEffects"
	layer.layer    = -10
	add_child(layer)

	var rect              := ColorRect.new()
	rect.name             = "EffectsRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	var mat               := ShaderMaterial.new()
	mat.shader            = SCREEN_SHADER
	rect.material         = mat
	layer.add_child(rect)


func _build_ocean() -> void:
	var ocean := MeshBuilder.plane(Vector2(600, 600), C_OCEAN, 0.12, 260, 260)
	var sm    := ShaderMaterial.new()
	sm.shader = OCEAN_SHADER
	sm.set_shader_parameter("wave_time",             WaveSurface.get_sim_time())
	sm.set_shader_parameter("water_level",           WaveSurface.WATER_LEVEL)
	sm.set_shader_parameter("amplitude_1",           WaveSurface.AMPLITUDE_1)
	sm.set_shader_parameter("frequency_1",           WaveSurface.FREQUENCY_1)
	sm.set_shader_parameter("speed_1",               WaveSurface.SPEED_1)
	sm.set_shader_parameter("dir_1",                 WaveSurface.DIR_1)
	sm.set_shader_parameter("steepness_1",           WaveSurface.STEEPNESS_1)
	sm.set_shader_parameter("amplitude_2",           WaveSurface.AMPLITUDE_2)
	sm.set_shader_parameter("frequency_2",           WaveSurface.FREQUENCY_2)
	sm.set_shader_parameter("speed_2",               WaveSurface.SPEED_2)
	sm.set_shader_parameter("dir_2",                 WaveSurface.DIR_2)
	sm.set_shader_parameter("steepness_2",           WaveSurface.STEEPNESS_2)
	sm.set_shader_parameter("amplitude_3",           WaveSurface.AMPLITUDE_3)
	sm.set_shader_parameter("frequency_3",           WaveSurface.FREQUENCY_3)
	sm.set_shader_parameter("speed_3",               WaveSurface.SPEED_3)
	sm.set_shader_parameter("dir_3",                 WaveSurface.DIR_3)
	sm.set_shader_parameter("steepness_3",           WaveSurface.STEEPNESS_3)
	sm.set_shader_parameter("amplitude_4",           WaveSurface.AMPLITUDE_4)
	sm.set_shader_parameter("frequency_4",           WaveSurface.FREQUENCY_4)
	sm.set_shader_parameter("speed_4",               WaveSurface.SPEED_4)
	sm.set_shader_parameter("dir_4",                 WaveSurface.DIR_4)
	sm.set_shader_parameter("steepness_4",           WaveSurface.STEEPNESS_4)
	sm.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
	sm.set_shader_parameter("shallow_albedo",        Vector3(0.028, 0.074, 0.118))
	sm.set_shader_parameter("deep_albedo",           Vector3(0.006, 0.018, 0.036))
	sm.set_shader_parameter("horizon_tint",          Vector3(0.068, 0.118, 0.172))
	sm.set_shader_parameter("water_alpha",           0.94)
	sm.set_shader_parameter("fresnel_sky_mix",       0.62)
	sm.set_shader_parameter("fresnel_power",         3.8)
	sm.set_shader_parameter("foam_strength",         0.52)
	sm.set_shader_parameter("foam_steep_start",      0.60)
	sm.set_shader_parameter("foam_steep_end",        0.92)
	sm.set_shader_parameter("near_color_lift",       0.14)
	sm.set_shader_parameter("roughness",             0.14)
	sm.set_shader_parameter("metallic",             0.02)
	sm.set_shader_parameter("specular",             0.56)
	sm.set_shader_parameter("chop_strength",         0.12)
	sm.set_shader_parameter("wave_intensity",        WaveSurface.wave_intensity)
	ocean.material_override = sm
	_ocean_shader_material  = sm
	ocean.position          = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	_ocean_mesh             = ocean
	add_child(ocean)


func _connect_weather_lighting() -> void:
	var weather := _get_weather()
	if weather == null:
		return
	var cb := Callable(self, "_apply_weather_lighting")
	if not weather.is_connected("state_changed", cb):
		weather.connect("state_changed", cb)


func _apply_weather_lighting() -> void:
	var weather := _get_weather()
	var tod   := float(weather.get("time_of_day"))     if weather else 0.42
	var wind  := float(weather.get("wind_force"))      if weather else 0.0
	var vis   := float(weather.get("visibility"))      if weather else 1.0
	var cloud := float(weather.get("cloud_coverage"))  if weather else 0.0
	var rain  := float(weather.get("rain_amount"))     if weather else 0.0
	var storm := float(weather.get("storm_intensity")) if weather else 0.0

	var elev_norm := -cos(tod * TAU)
	var daylight  := smoothstep(-0.18, 0.55, elev_norm)
	var fog_t     := 1.0 - vis

	_apply_sun(tod, daylight, cloud, storm)
	_apply_fog(fog_t, daylight, storm)
	_apply_sky_shader(daylight, cloud, storm)
	_apply_ocean_shader(daylight, cloud, rain, wind, storm, fog_t)


func _apply_sun(tod: float, daylight: float, cloud: float, storm: float) -> void:
	var elev_norm := -cos(tod * TAU)
	if _sun != null:
		_sun.rotation_degrees = Vector3(-elev_norm * 55.0, tod * 360.0 - 120.0, 0.0)
		_sun.light_energy     = lerpf(0.03, 1.6, daylight) * lerpf(1.0, 0.10, cloud)
		_sun.light_color      = (
			Color(1.0, 0.68, 0.42)
			.lerp(Color(1.0, 0.95, 0.82), daylight)
			.lerp(Color(0.48, 0.55, 0.68), storm)
		)
	if _fill_light != null:
		_fill_light.light_energy = lerpf(0.18, 0.03, cloud) * lerpf(0.03, 1.0, daylight)
	if _environment != null:
		_environment.ambient_light_energy = (
			lerpf(0.006, 0.22, daylight * daylight) * lerpf(1.0, 0.52, cloud)
		)


func _apply_fog(fog_t: float, daylight: float, storm: float) -> void:
	if _environment == null:
		return
	_environment.fog_light_color = (
		Color(0.06, 0.07, 0.09)
		.lerp(Color(0.58, 0.66, 0.78), daylight)
		.lerp(Color(0.28, 0.30, 0.33), storm * 0.5)
	)
	_environment.fog_density            = 0.005 + lerpf(0.0, 0.25, fog_t * fog_t * fog_t)
	_environment.fog_aerial_perspective = 0.12  + lerpf(0.0, 0.35, fog_t)
	# Clear air: leave the procedural sky intact; fog only eats the dome when visibility drops.
	_environment.fog_sky_affect = lerpf(0.11, 0.58, fog_t * fog_t)


func _apply_sky_shader(daylight: float, cloud: float, storm: float) -> void:
	if _sky_shader_material == null:
		return
	var top_col := (
		Color(0.006, 0.009, 0.028)
		.lerp(Color(0.07, 0.28, 0.62), daylight)
		.lerp(Color(0.09, 0.10, 0.13), cloud)
	)
	var horiz := (
		Color(0.018, 0.016, 0.028)
		.lerp(Color(0.34, 0.54, 0.78), daylight)
		.lerp(Color(0.22, 0.24, 0.28), cloud)
	)
	var zenith_deep := (
		Color(0.001, 0.004, 0.022)
		.lerp(Color(0.015, 0.08, 0.38), daylight)
		.lerp(Color(0.05, 0.065, 0.09), storm)
	)
	var ground_c := (
		Color(0.04, 0.04, 0.05)
		.lerp(Color(0.15, 0.13, 0.11), daylight)
		.lerp(Color(0.06, 0.06, 0.07), cloud)
	)
	var sun_col := Color(1.0, 0.62, 0.30).lerp(Color(1.0, 0.96, 0.88), daylight)

	# Inverse of scripted daylight curve — brightest stars at full night; clouds/storm occlude Milky-Way fantasies cheaply.
	var star_vis := pow(clampf(1.0 - daylight, 0.0, 1.0), 0.78)
	star_vis *= lerpf(1.0, 0.1, cloud)
	star_vis *= lerpf(1.0, 0.52, storm)

	_sky_shader_material.set_shader_parameter("sky_top_color",     Vector3(top_col.r,  top_col.g,  top_col.b))
	_sky_shader_material.set_shader_parameter("sky_horizon_color", Vector3(horiz.r,    horiz.g,    horiz.b))
	_sky_shader_material.set_shader_parameter("sky_ground_color",  Vector3(ground_c.r, ground_c.g, ground_c.b))
	_sky_shader_material.set_shader_parameter("sky_zenith_deep",   Vector3(zenith_deep.r, zenith_deep.g, zenith_deep.b))
	var zen_mix := lerpf(0.16, 0.48, daylight) * lerpf(1.0, 0.45, cloud) * lerpf(1.0, 0.55, storm)
	_sky_shader_material.set_shader_parameter("sky_zenith_mix",    zen_mix)
	_sky_shader_material.set_shader_parameter("cloud_coverage",    cloud)
	_sky_shader_material.set_shader_parameter("storm_intensity",   storm)
	_sky_shader_material.set_shader_parameter("sun_color",         Vector3(sun_col.r,  sun_col.g,  sun_col.b))
	_sky_shader_material.set_shader_parameter("star_visibility",   clampf(star_vis, 0.0, 1.0))


func _apply_ocean_shader(daylight: float, cloud: float, rain: float, wind: float, storm: float, fog_t: float) -> void:
	if _ocean_shader_material == null:
		return
	var fog_w := fog_t * fog_t
	var ocean_color := (
		Color(0.014, 0.028, 0.048)
		.lerp(C_OCEAN, daylight)
		.lerp(Color(0.042, 0.058, 0.072), storm)
	)
	var deep      := ocean_color * lerpf(0.20, 0.36, rain)
	var shallow_w := ocean_color * lerpf(0.54, 0.74, rain)
	var horizon_w := ocean_color.lerp(Color(0.10, 0.18, 0.34), lerpf(0.40, 0.24, cloud))
	## Low visibility → flat, desaturated swell (no horizon glitter).
	var fog_murk := Color(0.046, 0.050, 0.054)
	shallow_w = shallow_w.lerp(fog_murk.lightened(0.04), fog_w * 0.88)
	deep      = deep.lerp(fog_murk.darkened(0.12), fog_w * 0.94)
	horizon_w = horizon_w.lerp(fog_murk.lightened(0.08), fog_w * 0.72)
	var foam_driver  := clampf(rain + wind * 0.55, 0.0, 1.0)
	var steep_driver := clampf(maxf(storm, wind * 0.65), 0.0, 1.0)
	var rough_driver := clampf(maxf(rain,  wind * 0.55) + fog_w * 0.35, 0.0, 1.0)

	var chop_val := lerpf(0.10, 0.26, clampf(wind * 1.02 + storm * 0.40 + rain * 0.22, 0.0, 1.0))
	chop_val *= lerpf(1.0, 0.78, fog_w)

	_ocean_shader_material.set_shader_parameter("shallow_albedo",         Vector3(shallow_w.r, shallow_w.g, shallow_w.b))
	_ocean_shader_material.set_shader_parameter("deep_albedo",            Vector3(deep.r,      deep.g,      deep.b))
	_ocean_shader_material.set_shader_parameter("horizon_tint",           Vector3(horizon_w.r, horizon_w.g, horizon_w.b))
	var fres_cloud := lerpf(0.58, 0.34, cloud)
	_ocean_shader_material.set_shader_parameter("fresnel_sky_mix",        lerpf(fres_cloud, fres_cloud * 0.72, fog_w))
	_ocean_shader_material.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
	_ocean_shader_material.set_shader_parameter("water_alpha",            lerpf(0.92, 0.97, rain))
	_ocean_shader_material.set_shader_parameter("foam_strength",          lerpf(0.38, 0.92, foam_driver))
	_ocean_shader_material.set_shader_parameter("foam_steep_start",       lerpf(0.62, 0.34, steep_driver))
	_ocean_shader_material.set_shader_parameter("foam_steep_end",         lerpf(0.94, 0.62, steep_driver))
	var near_lift := lerpf(0.14, 0.052, cloud) * lerpf(1.0, 0.42, fog_w)
	_ocean_shader_material.set_shader_parameter("near_color_lift",        near_lift)
	_ocean_shader_material.set_shader_parameter("chop_strength", chop_val)
	var spec_drive := lerpf(0.43, 0.58, daylight) * lerpf(1.0, 0.90, rough_driver)
	spec_drive *= lerpf(1.0, 0.92, clampf(rain + cloud * 0.35, 0.0, 1.0))
	_ocean_shader_material.set_shader_parameter("specular", spec_drive)
	_ocean_shader_material.set_shader_parameter("roughness",              lerpf(0.13, 0.40, rough_driver))
	_ocean_shader_material.set_shader_parameter("metallic",               lerpf(0.02, 0.04, rough_driver))


func _celestial_dir(tod_offset: float) -> Vector3:
	var weather := _get_weather()
	var tod     := float(weather.get("time_of_day")) if weather else 0.42
	var t       := fmod(tod + tod_offset, 1.0)
	var elev    := -cos(t * TAU)
	var rot     := Basis.from_euler(Vector3(deg_to_rad(-elev * 55.0), deg_to_rad(t * 360.0 - 120.0), 0.0))
	return -(rot * Vector3(0.0, 0.0, -1.0))


func _get_weather() -> Node:
	return get_node_or_null("/root/WeatherLighting")
