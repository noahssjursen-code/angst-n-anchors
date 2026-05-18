@tool
class_name WorldRenderer
extends Node3D

## Owns the ocean, sky, sun/fill lights, and fog.
## Connects to WeatherLighting and updates all world visuals when weather changes.
## No knowledge of ports, players, or gameplay.

const OCEAN_SHADER   := preload("res://resources/shaders/ocean_waves.gdshader")
const OCEAN_HORIZON_SHADER := preload("res://resources/shaders/ocean_horizon.gdshader")
const SKY_SHADER     := preload("res://resources/shaders/sky.gdshader")
const SCREEN_SHADER  := preload("res://resources/shaders/screen_effects.gdshader")
## Base midday water dye — kept darker so the ocean reads as depth, not a bright lagoon.
const C_OCEAN      := Color(0.015, 0.045, 0.075)

const FFT_WATER_SYSTEM_SCRIPT := preload("res://scripts/ocean/fft_water_system.gd")

var _ocean_shader_material: ShaderMaterial
var _ocean_horizon_material: ShaderMaterial
var _sky_shader_material:   ShaderMaterial
var _environment:           Environment
var _sun:                   DirectionalLight3D
var _fill_light:            DirectionalLight3D
var _ocean_mesh:            MeshInstance3D
var _ocean_mesh_outer:      MeshInstance3D
var _fft_system:            Node # Use Node instead of FFTWaterSystem to avoid unresolved class error without reload

## Shader's land_disks[] array bound — must match MAX_LAND_DISKS in ocean_waves.gdshader.
const MAX_LAND_DISKS_SHADER : int = 64
var _last_land_disk_count   : int = -1


func _ready() -> void:
	if not Engine.is_editor_hint():
		_fft_system = FFT_WATER_SYSTEM_SCRIPT.new()
		_fft_system.name = "FFTWaterSystem"
		add_child(_fft_system)
		WaveSurface.fft_system = _fft_system

	_build_sky()
	_build_ocean()
	_build_screen_effects()
	_connect_weather_lighting()
	_apply_weather_lighting()


func _process(_delta: float) -> void:
	_follow_camera_xz()
	if _ocean_shader_material:
		_ocean_shader_material.set_shader_parameter("wave_time",      WaveSurface.get_sim_time())
		_ocean_shader_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		_ocean_shader_material.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
		if _fft_system:
			_ocean_shader_material.set_shader_parameter("displacement_map", _fft_system.displacement_map_rd)
			_ocean_shader_material.set_shader_parameter("slope_map",        _fft_system.slope_map_rd)
			_ocean_shader_material.set_shader_parameter("length_scales",    _fft_system.length_scales)
		WaveSurface.sync_ocean_coupling_to_shader(_ocean_shader_material)
		_sync_land_shelter()
	if _ocean_horizon_material:
		_ocean_horizon_material.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
	if _sky_shader_material:
		_sky_shader_material.set_shader_parameter("sky_time",       WaveSurface.get_sim_time())
		_sky_shader_material.set_shader_parameter("sun_direction",   _celestial_dir(0.0))
		_sky_shader_material.set_shader_parameter("moon_direction",  _celestial_dir(0.5))


func _follow_camera_xz() -> void:
	if _ocean_mesh == null or not is_instance_valid(_ocean_mesh):
		return
	# Snap mesh to grid size to prevent vertices from sliding continuously over wave math
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var grid_size := 600.0 / 261.0
	_ocean_mesh.position.x = snappedf(cam.global_position.x, grid_size)
	_ocean_mesh.position.z = snappedf(cam.global_position.z, grid_size)
	
	if _ocean_mesh_outer != null and is_instance_valid(_ocean_mesh_outer):
		_ocean_mesh_outer.position.x = _ocean_mesh.position.x
		_ocean_mesh_outer.position.z = _ocean_mesh.position.z


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
	
	# Enable Volumetric Fog for true physical depth and light scattering
	environ.volumetric_fog_enabled = true
	environ.volumetric_fog_density = 0.005
	environ.volumetric_fog_albedo  = Color(0.58, 0.66, 0.78)
	environ.volumetric_fog_emission = Color(0.02, 0.02, 0.02)
	environ.volumetric_fog_emission_energy = 0.1
	environ.volumetric_fog_length = 320.0
	environ.volumetric_fog_detail_spread = 2.0

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
	var ocean := MeshBuilder.plane(Vector2(600, 600), C_OCEAN, 0.12, 512, 512)
	var sm    := ShaderMaterial.new()
	sm.shader = OCEAN_SHADER
	sm.set_shader_parameter("wave_time",             WaveSurface.get_sim_time())
	sm.set_shader_parameter("water_level",           WaveSurface.WATER_LEVEL)
	
	sm.set_shader_parameter("shallow_albedo",        Vector3(0.015, 0.045, 0.075))
	sm.set_shader_parameter("deep_albedo",           Vector3(0.003, 0.010, 0.020))
	sm.set_shader_parameter("horizon_tint",          Vector3(0.035, 0.065, 0.095))
	sm.set_shader_parameter("fresnel_sky_mix",       0.28)
	sm.set_shader_parameter("fresnel_power",         4.0)
	sm.set_shader_parameter("foam_strength",         0.52)
	sm.set_shader_parameter("foam_steep_start",      0.60)
	sm.set_shader_parameter("foam_steep_end",        0.92)
	sm.set_shader_parameter("near_color_lift",       0.10)
	sm.set_shader_parameter("roughness",             0.35)
	sm.set_shader_parameter("metallic",             0.0)
	sm.set_shader_parameter("specular",             0.15)
	sm.set_shader_parameter("chop_strength",         0.12)
	
	ocean.material_override = sm
	_ocean_shader_material  = sm
	ocean.position          = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	_ocean_mesh             = ocean
	add_child(ocean)

	var ocean_outer := MeshBuilder.plane(Vector2(20000, 20000), C_OCEAN, 0.12, 64, 64)
	var sm_outer    := ShaderMaterial.new()
	sm_outer.shader = OCEAN_HORIZON_SHADER
	sm_outer.set_shader_parameter("water_level",     WaveSurface.WATER_LEVEL)
	sm_outer.set_shader_parameter("shallow_albedo",  Vector3(0.015, 0.045, 0.075))
	sm_outer.set_shader_parameter("deep_albedo",     Vector3(0.003, 0.010, 0.020))
	sm_outer.set_shader_parameter("horizon_tint",    Vector3(0.035, 0.065, 0.095))
	sm_outer.set_shader_parameter("fresnel_sky_mix", 0.28)
	sm_outer.set_shader_parameter("fresnel_power",   4.0)
	sm_outer.set_shader_parameter("near_color_lift", 0.10)
	sm_outer.set_shader_parameter("roughness",       0.35)
	sm_outer.set_shader_parameter("metallic",        0.0)
	sm_outer.set_shader_parameter("specular",        0.15)
	
	ocean_outer.material_override = sm_outer
	_ocean_horizon_material = sm_outer
	ocean_outer.position = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	_ocean_mesh_outer = ocean_outer
	add_child(ocean_outer)


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

	# Optional: Sync FFT parameters based on weather
	if _fft_system:
		var wind_dir : Vector3 = weather.get("wind_dir") if weather else Vector3.RIGHT
		# Spectrum wants a single rotation angle in the XZ plane; positive Z is
		# the FFT's "zero direction", so atan2(x, z) gives wind-blowing-toward.
		var wind_angle := atan2(wind_dir.x, wind_dir.z)
		_fft_system.sync_weather(wind, storm, WaveSurface.short_wave_factor, wind_angle)


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
		
	var base_fog_col = (
		Color(0.06, 0.07, 0.09)
		.lerp(Color(0.58, 0.66, 0.78), daylight)
		.lerp(Color(0.28, 0.30, 0.33), storm * 0.5)
	)
	
	# Traditional Screen-Space Fog (Handles skybox blending and distant occlusion)
	_environment.fog_light_color = base_fog_col
	_environment.fog_density            = lerpf(0.0, 0.025, fog_t * fog_t)
	_environment.fog_aerial_perspective = lerpf(0.0, 0.65, fog_t)
	_environment.fog_sky_affect = lerpf(0.0, 0.85, fog_t * fog_t)

	# Volumetric Fog (Physical 3D depth, light shafts, and realistic thickness)
	_environment.volumetric_fog_albedo = base_fog_col
	# Scale volumetric density aggressively with fog_t
	_environment.volumetric_fog_density = lerpf(0.0, 0.09, fog_t)
	# Push the fog rendering distance out based on visibility
	_environment.volumetric_fog_length = lerpf(480.0, 120.0, fog_t)


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


## Pushes LandField's island disks into the ocean shader so per-vertex wave
## amplitude fades to zero inside / very near land. Lazy: re-binds only when
## the island count actually changes (world rebuild, hot-reload), so the
## per-frame cost is one int compare in steady state. Falls back to "open
## ocean everywhere" if LandField hasn't been initialised yet.
func _sync_land_shelter() -> void:
	if _ocean_shader_material == null:
		return
	var n := LandField.get_island_count()
	if n == _last_land_disk_count:
		return
	_last_land_disk_count = n
	var disks := LandField.get_disks_packed(MAX_LAND_DISKS_SHADER)
	_ocean_shader_material.set_shader_parameter("land_disks",       disks)
	_ocean_shader_material.set_shader_parameter("land_disk_count",  disks.size())
	_ocean_shader_material.set_shader_parameter("shelter_falloff_m", LandField.SHELTER_FALLOFF_M)


func _apply_ocean_shader(daylight: float, cloud: float, rain: float, wind: float, storm: float, fog_t: float) -> void:
	if _ocean_shader_material == null:
		return
	var fog_w := fog_t * fog_t
	var ocean_color := (
		Color(0.007, 0.015, 0.025)
		.lerp(C_OCEAN, daylight)
		.lerp(Color(0.025, 0.035, 0.045), storm)
	)
	var deep      := ocean_color * lerpf(0.15, 0.25, rain)
	var shallow_w := ocean_color * lerpf(0.40, 0.60, rain)
	var horizon_w := ocean_color.lerp(Color(0.06, 0.10, 0.20), lerpf(0.40, 0.24, cloud))
	## Low visibility → flat, desaturated swell (no horizon glitter).
	var fog_murk := Color(0.030, 0.035, 0.040)
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
	var fres_cloud := lerpf(0.48, 0.26, cloud)
	var fres_blend := lerpf(fres_cloud, fres_cloud * 0.72, fog_w)
	_ocean_shader_material.set_shader_parameter("fresnel_sky_mix",        fres_blend * 0.86)
	_ocean_shader_material.set_shader_parameter("foam_strength",          lerpf(0.38, 0.92, foam_driver))
	_ocean_shader_material.set_shader_parameter("foam_steep_start",       lerpf(0.62, 0.34, steep_driver))
	_ocean_shader_material.set_shader_parameter("foam_steep_end",         lerpf(0.94, 0.62, steep_driver))
	var near_lift := lerpf(0.14, 0.052, cloud) * lerpf(1.0, 0.42, fog_w)
	_ocean_shader_material.set_shader_parameter("near_color_lift",        near_lift)
	_ocean_shader_material.set_shader_parameter("chop_strength", chop_val)
	var spec_drive := lerpf(0.36, 0.48, daylight) * lerpf(1.0, 0.88, rough_driver)
	spec_drive *= lerpf(1.0, 0.88, clampf(rain + cloud * 0.35, 0.0, 1.0))
	_ocean_shader_material.set_shader_parameter("specular", spec_drive)
	_ocean_shader_material.set_shader_parameter("roughness",              lerpf(0.20, 0.48, rough_driver))
	_ocean_shader_material.set_shader_parameter("metallic",               lerpf(0.01, 0.03, rough_driver))

	if _ocean_horizon_material != null:
		_ocean_horizon_material.set_shader_parameter("shallow_albedo",         Vector3(shallow_w.r, shallow_w.g, shallow_w.b))
		_ocean_horizon_material.set_shader_parameter("deep_albedo",            Vector3(deep.r,      deep.g,      deep.b))
		_ocean_horizon_material.set_shader_parameter("horizon_tint",           Vector3(horizon_w.r, horizon_w.g, horizon_w.b))
		_ocean_horizon_material.set_shader_parameter("fresnel_sky_mix",        fres_blend * 0.86)
		_ocean_horizon_material.set_shader_parameter("near_color_lift",        near_lift)
		_ocean_horizon_material.set_shader_parameter("specular", spec_drive)
		_ocean_horizon_material.set_shader_parameter("roughness",              lerpf(0.20, 0.48, rough_driver))
		_ocean_horizon_material.set_shader_parameter("metallic",               lerpf(0.01, 0.03, rough_driver))


func _celestial_dir(tod_offset: float) -> Vector3:
	var weather := _get_weather()
	var tod     := float(weather.get("time_of_day")) if weather else 0.42
	var t       := fmod(tod + tod_offset, 1.0)
	var elev    := -cos(t * TAU)
	var rot     := Basis.from_euler(Vector3(deg_to_rad(-elev * 55.0), deg_to_rad(t * 360.0 - 120.0), 0.0))
	return -(rot * Vector3(0.0, 0.0, -1.0))


func _get_weather() -> Node:
	return get_node_or_null("/root/WeatherLighting")
