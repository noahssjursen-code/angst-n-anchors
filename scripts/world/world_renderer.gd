class_name WorldRenderer
extends Node3D

## Owns the ocean, sky, sun/fill lights, and fog.
## Connects to WeatherLighting and updates all world visuals when weather changes.
## No knowledge of ports, players, or gameplay.

const OCEAN_SHADER   := preload("res://resources/shaders/ocean_waves.gdshader")
const OCEAN_MID_SHADER := preload("res://resources/shaders/ocean_waves_mid.gdshader")
const OCEAN_FAR_SHADER := preload("res://resources/shaders/ocean_waves_far.gdshader")
const OCEAN_HORIZON_SHADER := preload("res://resources/shaders/ocean_horizon.gdshader")
const OCEAN_CLIPMAP_SCRIPT := preload("res://scripts/ocean/ocean_clipmap.gd")
const SKY_SHADER     := preload("res://resources/shaders/sky.gdshader")
const SCREEN_SHADER  := preload("res://resources/shaders/screen_effects.gdshader")
## Base midday water dye — kept darker so the ocean reads as depth, not a bright lagoon.
const C_OCEAN      := Color(0.015, 0.045, 0.075)

const FFT_WATER_SYSTEM_SCRIPT := preload("res://scripts/ocean/fft_water_system.gd")
const OCEAN_WAKE_FIELD_SCRIPT := preload("res://scripts/ocean/ocean_wake_field.gd")

## Clipmap ocean — dense near boat (where quality matters), coarse mid ring,
## cascade-0 horizon beyond. Near density is HIGHER than the old uniform grid.
const NEAR_OCEAN_SIZE         : float = 480.0
const NEAR_OCEAN_SUBDIVISIONS : int   = 400   # ~1.2 m cells
const MID_OCEAN_SIZE          : float = 1500.0
const MID_OCEAN_SUBDIVISIONS  : int   = 280   # ~5.3 m cells outside near
## Keep legacy name for horizon discard math (outer edge of mid ring).
const INNER_OCEAN_SIZE        : float = MID_OCEAN_SIZE
const INNER_OCEAN_SUBDIVISIONS : int  = NEAR_OCEAN_SUBDIVISIONS
const NEAR_DISCARD_HALF : float = NEAR_OCEAN_SIZE * 0.5 - 10.0
## Horizon mesh — far field that samples the largest FFT cascade only (~256 m
## wavelength) for storm swell. 20 km square is "to the horizon" for all
## practical camera positions. Subdivisions chosen so vertex spacing in the
## active-wave ring (camera→wave_fade_far ≈ 5.5 km) stays under cascade-0
## Nyquist (128 m). 20 km / 257 ≈ 78 m/vert — comfortably above Nyquist.
const HORIZON_OCEAN_SIZE        : float = 20000.0
const HORIZON_OCEAN_SUBDIVISIONS : int   = 192
## Half-extent at which the horizon shader stops discarding (must equal half
## the mid mesh size; 15 m extra overlap prevents seam gaps at the boundary under wild storm swells).
const HORIZON_DISCARD_HALF : float = MID_OCEAN_SIZE * 0.5 - 15.0

## Temporary A/B fallback while validating the generated clipmap in builds.
@export var use_legacy_ocean := false
## F6 showcases run with Engine.is_editor_hint() true — set before add_child.
@export var force_runtime_build := false
## Lighting-only showcases/tests can skip FFT allocation and ocean geometry.
## Runtime worlds leave this enabled.
@export var enable_ocean_system := true
## Expensive presentation features remain independently switchable for GPU
## profiling and future quality presets.
@export var enable_ssao := true
@export var enable_glow := true
@export var enable_volumetric_fog := true
@export var enable_weather_post_fx := true

var _ocean_shader_material: ShaderMaterial
var _ocean_mid_material:    ShaderMaterial
var _ocean_far_material:    ShaderMaterial
var _ocean_horizon_material: ShaderMaterial
var _sky_shader_material:   ShaderMaterial
var _environment:           Environment
var _sun:                   DirectionalLight3D
var _fill_light:            DirectionalLight3D
var _moon_light:            DirectionalLight3D
var _screen_material:       ShaderMaterial
var _screen_rect:           ColorRect
var _ocean_mesh:            MeshInstance3D
var _ocean_mesh_mid:        MeshInstance3D
var _ocean_mesh_outer:      MeshInstance3D
var _ocean_clipmap:         OceanClipmap
var _fft_system:            Node # Use Node instead of FFTWaterSystem to avoid unresolved class error without reload
var _wake_field:            OceanWakeField
var _fft_maps_bound:        bool = false
var _ocean_debug_false_color := false
var _camera_water_signed_distance := 10.0
var _underwater_environment_active := false
var _underwater_camera: Camera3D
var _above_water_camera_far := 0.0

## Tracks whether the baked LandField shelter texture is currently bound to
## the ocean shader, so we re-upload exactly once when LandField finishes
## initialising (which happens after WorldRenderer is added).
var _shelter_texture_bound : bool = false


func _ready() -> void:
	add_to_group("world_renderer")
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("register_provider"):
		telemetry.register_provider(&"ocean.geometry", self, &"get_ocean_debug_stats", &"ocean")
		telemetry.register_provider(&"render.lighting", self, &"get_lighting_debug_state", &"render")
	# This script is @tool, but the full runtime ocean must not be built in the
	# editor viewport. Otherwise the editor renders one ocean while the embedded
	# game renders another (measured: ~65% + ~32% GPU on the same card).
	if Engine.is_editor_hint() and not force_runtime_build:
		set_process(false)
		return

	_build_sky()
	if enable_ocean_system:
		_fft_system = FFT_WATER_SYSTEM_SCRIPT.new()
		_fft_system.name = "FFTWaterSystem"
		add_child(_fft_system)
		WaveSurface.fft_system = _fft_system
		_wake_field = OCEAN_WAKE_FIELD_SCRIPT.new() as OceanWakeField
		_wake_field.name = "OceanWakeField"
		add_child(_wake_field)
		_build_ocean()
	_build_screen_effects()
	_connect_weather_lighting()
	_apply_weather_lighting()


func get_ocean_debug_stats() -> Dictionary:
	if _ocean_clipmap != null and is_instance_valid(_ocean_clipmap):
		return _ocean_clipmap.get_debug_stats()
	var near_vertices := (NEAR_OCEAN_SUBDIVISIONS + 2) * (NEAR_OCEAN_SUBDIVISIONS + 2)
	var mid_vertices := (MID_OCEAN_SUBDIVISIONS + 2) * (MID_OCEAN_SUBDIVISIONS + 2)
	var horizon_vertices := (HORIZON_OCEAN_SUBDIVISIONS + 2) * (HORIZON_OCEAN_SUBDIVISIONS + 2)
	var near_triangles := 2 * (NEAR_OCEAN_SUBDIVISIONS + 1) * (NEAR_OCEAN_SUBDIVISIONS + 1)
	var mid_triangles := 2 * (MID_OCEAN_SUBDIVISIONS + 1) * (MID_OCEAN_SUBDIVISIONS + 1)
	var horizon_triangles := 2 * (HORIZON_OCEAN_SUBDIVISIONS + 1) * (HORIZON_OCEAN_SUBDIVISIONS + 1)
	return {
		"near_size": NEAR_OCEAN_SIZE,
		"near_subdivisions": NEAR_OCEAN_SUBDIVISIONS,
		"mid_size": MID_OCEAN_SIZE,
		"mid_subdivisions": MID_OCEAN_SUBDIVISIONS,
		"horizon_size": HORIZON_OCEAN_SIZE,
		"horizon_subdivisions": HORIZON_OCEAN_SUBDIVISIONS,
		"vertices": near_vertices + mid_vertices + horizon_vertices,
		"triangles": near_triangles + mid_triangles + horizon_triangles,
	}


func get_lighting_debug_state() -> Dictionary:
	if _environment == null:
		return {}
	return {
		"tonemap_mode": _environment.tonemap_mode,
		"tonemap_exposure": _environment.tonemap_exposure,
		"tonemap_white": _environment.tonemap_white,
		"ssao_enabled": _environment.ssao_enabled,
		"glow_enabled": _environment.glow_enabled,
		"glow_intensity": _environment.glow_intensity,
		"adjustment_contrast": _environment.adjustment_contrast,
		"adjustment_saturation": _environment.adjustment_saturation,
		"fog_density": _environment.fog_density,
		"fog_color": _environment.fog_light_color,
		"volumetric_fog_enabled": _environment.volumetric_fog_enabled,
		"volumetric_fog_density": _environment.volumetric_fog_density,
		"sun_energy": _sun.light_energy if _sun != null else 0.0,
		"moon_energy": _moon_light.light_energy if _moon_light != null else 0.0,
		"ambient_energy": _environment.ambient_light_energy,
		"camera_water_signed_distance": _camera_water_signed_distance,
		"camera_far": (
			get_viewport().get_camera_3d().far
			if get_viewport().get_camera_3d() != null
			else 0.0
		),
	}


func set_ocean_ring_debug(enabled: bool) -> void:
	_ocean_debug_false_color = enabled
	if _ocean_clipmap != null and is_instance_valid(_ocean_clipmap):
		_ocean_clipmap.set_false_color(enabled)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		set_ocean_ring_debug(not _ocean_debug_false_color)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_follow_camera_xz()
	_update_underwater_effect()
	if _ocean_shader_material:
		_ocean_shader_material.set_shader_parameter("wave_time",      WaveSurface.get_sim_time())
		_ocean_shader_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		_ocean_shader_material.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
		WaveSurface.sync_ocean_coupling_to_shader(_ocean_shader_material)
		_sync_land_shelter()
	if _ocean_mid_material:
		_ocean_mid_material.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
		_ocean_mid_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		_ocean_mid_material.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
	if _ocean_far_material:
		_ocean_far_material.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
		_ocean_far_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		_ocean_far_material.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
	if _ocean_horizon_material:
		_ocean_horizon_material.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
		_ocean_horizon_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		_ocean_horizon_material.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
	_bind_fft_maps_once()
	_sync_wake_field()
	if _sky_shader_material:
		_sky_shader_material.set_shader_parameter("sky_time",       WaveSurface.get_sim_time())
		_sky_shader_material.set_shader_parameter("sun_direction",   _celestial_dir(0.0))
		_sky_shader_material.set_shader_parameter("moon_direction",  _celestial_dir(0.5))


func _bind_fft_maps_once() -> void:
	if _fft_maps_bound or _fft_system == null:
		return
	if _fft_system.displacement_map_rd == null or _fft_system.slope_map_rd == null:
		return
	var disp = _fft_system.displacement_map_rd
	var slope = _fft_system.slope_map_rd
	var scales = _fft_system.length_scales
	if _ocean_shader_material:
		_ocean_shader_material.set_shader_parameter("displacement_map", disp)
		_ocean_shader_material.set_shader_parameter("slope_map", slope)
		_ocean_shader_material.set_shader_parameter("length_scales", scales)
	if _ocean_mid_material:
		_ocean_mid_material.set_shader_parameter("displacement_map", disp)
		_ocean_mid_material.set_shader_parameter("slope_map", slope)
		_ocean_mid_material.set_shader_parameter("length_scales", scales)
	if _ocean_far_material:
		_ocean_far_material.set_shader_parameter("displacement_map", disp)
		_ocean_far_material.set_shader_parameter("slope_map", slope)
		_ocean_far_material.set_shader_parameter("length_scales", scales)
	if _ocean_horizon_material:
		_ocean_horizon_material.set_shader_parameter("displacement_map", disp)
		_ocean_horizon_material.set_shader_parameter("slope_map", slope)
		_ocean_horizon_material.set_shader_parameter("length_scale_0", scales.x)
	_fft_maps_bound = true


func _follow_camera_xz() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _ocean_clipmap != null and is_instance_valid(_ocean_clipmap):
		_ocean_clipmap.follow_camera(cam.global_position)
		# Focus the wake atlas on the same snapped origin as the clipmap so
		# remaps and ocean meshes share one world grid.
		if _wake_field != null:
			_wake_field.set_focus(Vector2(
				_ocean_clipmap.position.x,
				_ocean_clipmap.position.z
			))
		return
	if _wake_field != null:
		_wake_field.set_focus(Vector2(cam.global_position.x, cam.global_position.z))
	if _ocean_mesh == null or not is_instance_valid(_ocean_mesh):
		return
	# Snap to near-ring vertex spacing so screen-space swimming stays locked.
	var grid_size := NEAR_OCEAN_SIZE / float(NEAR_OCEAN_SUBDIVISIONS)
	var px := snappedf(cam.global_position.x, grid_size)
	var pz := snappedf(cam.global_position.z, grid_size)
	_ocean_mesh.position.x = px
	_ocean_mesh.position.z = pz
	if _ocean_mesh_mid != null and is_instance_valid(_ocean_mesh_mid):
		_ocean_mesh_mid.position.x = px
		_ocean_mesh_mid.position.z = pz
	if _ocean_mesh_outer != null and is_instance_valid(_ocean_mesh_outer):
		_ocean_mesh_outer.position.x = px
		_ocean_mesh_outer.position.z = pz


func _update_underwater_effect() -> void:
	if _screen_material == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_restore_underwater_camera_far()
		_camera_water_signed_distance = 10.0
		_screen_material.set_shader_parameter("camera_water_signed_distance", 10.0)
		return

	var surface_height := WaveSurface.WATER_LEVEL
	var surface_normal := Vector3.UP
	# FFT readback is useful only close to the waterline. Deep underwater or
	# high above it, the mean plane is enough and avoids an unnecessary query.
	if absf(camera.global_position.y - WaveSurface.WATER_LEVEL) < 8.0:
		surface_height = WaveSurface.get_base_wave_height_at(
			camera.global_position.x,
			camera.global_position.z,
		)
		surface_normal = WaveSurface.get_surface_normal_at(
			camera.global_position.x,
			camera.global_position.z,
		).normalized()
		if surface_normal.y < 0.15:
			surface_normal = Vector3.UP

	var surface_point := Vector3(
		camera.global_position.x,
		surface_height,
		camera.global_position.z,
	)
	_camera_water_signed_distance = (
		camera.global_position - surface_point
	).dot(surface_normal)
	_update_underwater_environment(camera)

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x < 2.0 or viewport_size.y < 2.0:
		return
	_screen_material.set_shader_parameter(
		"ray_top_left",
		camera.project_ray_normal(Vector2.ZERO),
	)
	_screen_material.set_shader_parameter(
		"ray_top_right",
		camera.project_ray_normal(Vector2(viewport_size.x, 0.0)),
	)
	_screen_material.set_shader_parameter(
		"ray_bottom_left",
		camera.project_ray_normal(Vector2(0.0, viewport_size.y)),
	)
	_screen_material.set_shader_parameter(
		"ray_bottom_right",
		camera.project_ray_normal(viewport_size),
	)
	_screen_material.set_shader_parameter("water_surface_normal", surface_normal)
	_screen_material.set_shader_parameter(
		"camera_water_signed_distance",
		_camera_water_signed_distance,
	)


func _update_underwater_environment(camera: Camera3D) -> void:
	if _environment == null:
		return
	var depth := -_camera_water_signed_distance
	if depth > 0.02:
		var depth_factor := smoothstep(0.02, 2.0, depth)
		_underwater_environment_active = true
		if _underwater_camera != camera:
			_restore_underwater_camera_far()
			_underwater_camera = camera
			_above_water_camera_far = camera.far
		# Hard culling backs up the fog so distant islands/terrain cannot remain
		# readable as silhouettes through the post grade.
		camera.far = minf(
			_above_water_camera_far,
			lerpf(140.0, 65.0, depth_factor),
		)
		# Depth-aware fog supplies actual short visibility range, unlike a flat
		# overlay. Keep volumetrics off: underwater haze should be cheap/stable.
		_environment.fog_enabled = true
		_environment.fog_light_color = Color(0.008, 0.050, 0.026)
		_environment.fog_density = lerpf(0.085, 0.18, depth_factor)
		_environment.fog_aerial_perspective = 1.0
		_environment.fog_sky_affect = 1.0
		_environment.volumetric_fog_enabled = false
	elif _underwater_environment_active:
		_underwater_environment_active = false
		_restore_underwater_camera_far()
		# Restore the current atmospheric weather once, on exit.
		_apply_weather_lighting()


func _restore_underwater_camera_far() -> void:
	if (
		_underwater_camera != null
		and is_instance_valid(_underwater_camera)
		and _above_water_camera_far > 0.0
	):
		_underwater_camera.far = _above_water_camera_far
	_underwater_camera = null
	_above_water_camera_far = 0.0


func _sync_wake_field() -> void:
	if _wake_field == null or _wake_field.get_wake_texture() == null:
		return
	var texture := _wake_field.get_wake_texture()
	var origin := _wake_field.get_world_origin()
	var extent := _wake_field.get_world_extent()
	var texel_m := extent / float(OceanWakeField.RESOLUTION)
	for material in [_ocean_shader_material, _ocean_mid_material]:
		if material == null:
			continue
		material.set_shader_parameter("wake_field_map", texture)
		material.set_shader_parameter("wake_field_origin", origin)
		material.set_shader_parameter("wake_field_extent", extent)
		material.set_shader_parameter("wake_field_texel_m", texel_m)
		# Keep wake visual contribution modest so FFT water remains the base.
		material.set_shader_parameter("wake_visual_strength", 1.0)


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
	environ.ambient_light_energy = 0.24

	environ.tonemap_mode     = Environment.TONE_MAPPER_ACES
	environ.tonemap_exposure = 1.02
	environ.tonemap_white    = 3.0

	environ.ssao_enabled = enable_ssao
	environ.ssao_radius = 1.35
	environ.ssao_intensity = 0.72
	environ.ssao_power = 1.0
	environ.ssao_detail = 0.28
	environ.glow_enabled = enable_glow
	# Glow should describe a hot lamp lens, never turn fog into a white veil.
	environ.glow_intensity = 0.34
	environ.glow_strength = 0.58
	environ.glow_bloom = 0.025
	environ.glow_hdr_threshold = 1.75
	environ.glow_hdr_scale = 1.15
	environ.ssr_enabled  = false

	environ.adjustment_enabled    = true
	environ.adjustment_brightness = 1.0
	environ.adjustment_contrast   = 1.045
	environ.adjustment_saturation = 1.04

	environ.fog_enabled            = true
	environ.fog_light_color        = Color(0.28, 0.34, 0.42)
	environ.fog_density            = 0.0
	environ.fog_aerial_perspective = 0.0
	environ.fog_sky_affect         = 0.0
	
	# Enable Volumetric Fog for true physical depth and light scattering
	environ.volumetric_fog_enabled = false
	environ.volumetric_fog_density = 0.0
	environ.volumetric_fog_albedo  = Color(0.28, 0.34, 0.42)
	environ.volumetric_fog_emission = Color.BLACK
	environ.volumetric_fog_emission_energy = 0.0
	environ.volumetric_fog_length = 420.0
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
	# 2 cascades over 180 m gives a 90 m near split and 90 m far — plenty for
	# the dock + immediate-water visible foreground. 4 cascades was rendering
	# the shadowmap twice as often as needed for this shadow distance and was
	# a measurable GPU chunk (~0.3-0.6 ms/frame on mid-tier).
	sun.directional_shadow_mode           = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
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

	var moon := DirectionalLight3D.new()
	_moon_light = moon
	moon.name = "MoonLight"
	moon.light_color = Color(0.50, 0.62, 0.88)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

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
	_screen_rect           = rect
	rect.name             = "EffectsRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	var mat               := ShaderMaterial.new()
	mat.shader            = SCREEN_SHADER
	_screen_material      = mat
	rect.material         = mat
	layer.add_child(rect)


func _build_ocean() -> void:
	if use_legacy_ocean:
		_build_legacy_ocean()
		return

	var sm := _make_ocean_material(OCEAN_SHADER, 1.0)
	_ocean_shader_material = sm
	var sm_mid := _make_ocean_material(OCEAN_MID_SHADER, 0.72)
	_ocean_mid_material = sm_mid
	var sm_far := _make_ocean_material(OCEAN_FAR_SHADER, 0.0)
	_ocean_far_material = sm_far
	var sm_horizon := _make_horizon_material()
	_ocean_horizon_material = sm_horizon

	var clipmap := OCEAN_CLIPMAP_SCRIPT.new() as OceanClipmap
	clipmap.name = "OceanClipmap"
	clipmap.position.y = WaveSurface.WATER_LEVEL
	add_child(clipmap)
	clipmap.build([sm, sm_mid, sm_far, sm_horizon])
	_ocean_clipmap = clipmap


func _build_legacy_ocean() -> void:
	var sm := _make_ocean_material(OCEAN_SHADER, 1.0)
	sm.set_shader_parameter("geomorph_strength", 0.0)
	_ocean_shader_material = sm

	var ocean := MeshBuilder.plane(
		Vector2(NEAR_OCEAN_SIZE, NEAR_OCEAN_SIZE),
		C_OCEAN, 0.12,
		NEAR_OCEAN_SUBDIVISIONS, NEAR_OCEAN_SUBDIVISIONS
	)
	ocean.material_override = sm
	ocean.position = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	_ocean_mesh = ocean
	add_child(ocean)

	var sm_mid := _make_ocean_material(OCEAN_SHADER, 1.0)
	sm_mid.set_shader_parameter("discard_half", NEAR_DISCARD_HALF)
	sm_mid.set_shader_parameter("geomorph_strength", 0.0)
	_ocean_mid_material = sm_mid
	var ocean_mid := MeshBuilder.plane(
		Vector2(MID_OCEAN_SIZE, MID_OCEAN_SIZE),
		C_OCEAN, 0.12,
		MID_OCEAN_SUBDIVISIONS, MID_OCEAN_SUBDIVISIONS
	)
	ocean_mid.material_override = sm_mid
	ocean_mid.position = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	_ocean_mesh_mid = ocean_mid
	add_child(ocean_mid)

	var ocean_outer := MeshBuilder.plane(
		Vector2(HORIZON_OCEAN_SIZE, HORIZON_OCEAN_SIZE),
		C_OCEAN, 0.12,
		HORIZON_OCEAN_SUBDIVISIONS, HORIZON_OCEAN_SUBDIVISIONS
	)
	var sm_outer := _make_horizon_material()
	sm_outer.set_shader_parameter("discard_half",    HORIZON_DISCARD_HALF)
	sm_outer.set_shader_parameter("geomorph_strength", 0.0)

	ocean_outer.material_override = sm_outer
	_ocean_horizon_material = sm_outer
	ocean_outer.position = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	_ocean_mesh_outer = ocean_outer
	add_child(ocean_outer)


func _make_ocean_material(shader: Shader, foam_scale: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.set_shader_parameter("wave_time",             WaveSurface.get_sim_time())
	sm.set_shader_parameter("water_level",           WaveSurface.WATER_LEVEL)
	sm.set_shader_parameter("shallow_albedo",        Vector3(0.022, 0.085, 0.130))
	sm.set_shader_parameter("deep_albedo",           Vector3(0.005, 0.022, 0.045))
	sm.set_shader_parameter("sky_top_color",         Vector3(0.07, 0.28, 0.62))
	sm.set_shader_parameter("sky_horizon_color",     Vector3(0.34, 0.54, 0.78))
	sm.set_shader_parameter("sun_direction",         Vector3(0.0, 1.0, 0.0))
	sm.set_shader_parameter("sun_color",             Vector3(1.0, 0.9, 0.8))
	sm.set_shader_parameter("fresnel_sky_mix",       0.52)
	sm.set_shader_parameter("foam_strength",         0.7 * foam_scale)
	sm.set_shader_parameter("foam_steep_start",      0.22)
	sm.set_shader_parameter("foam_steep_end",        0.65)
	sm.set_shader_parameter("near_color_lift",       0.14)
	sm.set_shader_parameter("chop_strength",         0.14)
	sm.set_shader_parameter("glint_strength",        0.55)
	sm.set_shader_parameter("discard_half",          0.0)
	return sm


func _make_horizon_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = OCEAN_HORIZON_SHADER
	sm.set_shader_parameter("water_level",       WaveSurface.WATER_LEVEL)
	sm.set_shader_parameter("shallow_albedo",    Vector3(0.022, 0.085, 0.130))
	sm.set_shader_parameter("deep_albedo",       Vector3(0.005, 0.022, 0.045))
	sm.set_shader_parameter("sky_top_color",     Vector3(0.07, 0.28, 0.62))
	sm.set_shader_parameter("sky_horizon_color", Vector3(0.34, 0.54, 0.78))
	sm.set_shader_parameter("fresnel_sky_mix",   0.52)
	sm.set_shader_parameter("near_color_lift",   0.14)
	sm.set_shader_parameter("glint_strength",    0.18)
	sm.set_shader_parameter("discard_half",      0.0)
	return sm


func _connect_weather_lighting() -> void:
	var weather := _get_weather()
	if weather == null:
		return
	var cb := Callable(self, "_apply_weather_lighting")
	if not weather.is_connected("state_changed", cb):
		weather.connect("state_changed", cb)


func _exit_tree() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("unregister_provider"):
		telemetry.unregister_provider(&"ocean.geometry", self)
		telemetry.unregister_provider(&"render.lighting", self)
	_restore_underwater_camera_far()
	var weather := _get_weather()
	if weather != null:
		var cb := Callable(self, "_apply_weather_lighting")
		if weather.is_connected("state_changed", cb):
			weather.disconnect("state_changed", cb)


func _apply_weather_lighting() -> void:
	var weather := _get_weather()
	var tod   := float(weather.get("time_of_day"))     if weather else 0.42
	var sea   := float(weather.get("sea_state"))       if weather else 0.0
	var air_wind := float(weather.get("wind_force"))   if weather else 0.0
	var vis   := float(weather.get("visibility"))      if weather else 1.0
	var cloud := float(weather.get("cloud_coverage"))  if weather else 0.0
	var rain  := float(weather.get("rain_amount"))     if weather else 0.0
	var storm := float(weather.get("storm_intensity")) if weather else 0.0

	var solar := SolarCycle.sample(tod)
	var daylight := float(solar["daylight"])
	var direct_light := float(solar["direct_light"])
	var fog_t     := 1.0 - vis

	_apply_sun(solar, daylight, direct_light, cloud, storm)
	_apply_exposure(daylight, cloud, storm, fog_t)
	_apply_fog(solar, fog_t, daylight, cloud, storm)
	_apply_sky_shader(solar, daylight, cloud, storm)
	_apply_ocean_shader(solar, daylight, cloud, rain, sea, air_wind, storm, fog_t)
	_apply_screen_effects(daylight, cloud, rain, storm, fog_t)
	Palette.set_wetness(smoothstep(0.08, 0.72, rain))

	# Optional: Sync FFT parameters based on weather
	if _fft_system:
		var wind_dir : Vector3 = weather.get("wind_dir") if weather else Vector3.RIGHT
		# Spectrum wants a single rotation angle in the XZ plane; positive Z is
		# the FFT's "zero direction", so atan2(x, z) gives wind-blowing-toward.
		var wind_angle := atan2(wind_dir.x, wind_dir.z)
		_fft_system.sync_weather(sea, storm, WaveSurface.short_wave_factor, wind_angle)


func _apply_sun(solar: Dictionary, daylight: float, direct_light: float, cloud: float, storm: float) -> void:
	var sun_dir: Vector3 = solar["sun_direction"]
	var moon_dir: Vector3 = solar["moon_direction"]
	var low_sun := _low_sun_factor(solar)
	# Overcast removes hard sunlight, but retaining a broad key keeps hulls,
	# terrain and cranes three-dimensional instead of uniformly grey.
	var sun_energy := (
		1.70 * direct_light
		* lerpf(1.0, 0.50, cloud)
		* lerpf(1.0, 0.78, storm)
	)
	if _sun != null:
		# Sunrise +X (east), noon +Z (south), sunset −X (west).
		# Matches NavigationAxes / chart (+X east, −Z north).
		_sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
		_sun.light_energy     = sun_energy
		var clear_sun := Color(1.0, 0.95, 0.84).lerp(Color(1.0, 0.56, 0.28), low_sun)
		_sun.light_color = clear_sun.lerp(Color(0.72, 0.79, 0.90), storm * 0.48)
	if _fill_light != null:
		# Cloud cover replaces a hard key with broad sky fill. Reducing this under
		# overcast made every north-facing hull and quay collapse to black.
		_fill_light.light_energy = (
			lerpf(0.06, 0.23, daylight)
			* lerpf(0.92, 1.18, cloud)
			* lerpf(1.0, 0.94, storm)
		)
		_fill_light.light_color = (
			Color(0.46, 0.58, 0.86)
			.lerp(Color(0.66, 0.76, 0.94), daylight)
			.lerp(Color(0.82, 0.70, 0.62), low_sun * 0.18)
		)
	if _moon_light != null:
		_moon_light.basis = Basis.looking_at(-moon_dir, Vector3.UP)
		_moon_light.light_energy = (
			0.16 * float(solar["moonlight"]) * lerpf(1.0, 0.38, cloud)
		)
	if _environment != null:
		_environment.ambient_light_energy = (
			lerpf(0.115, 0.36, daylight * daylight)
			* lerpf(1.0, 0.94, cloud)
			* lerpf(1.0, 0.92, storm)
		)
		_environment.ambient_light_color = (
			Color(0.78, 0.86, 1.0)
			.lerp(Color(0.95, 0.97, 1.0), daylight)
			.lerp(Color(1.0, 0.86, 0.74), low_sun * 0.12)
		)


func _apply_exposure(daylight: float, cloud: float, storm: float, fog_t: float) -> void:
	if _environment == null:
		return
	## Deterministic adaptation avoids auto-exposure pumping between reflective
	## ocean, white superstructures, and dark interiors.
	# Preserve a stable black point. Fog and cloud already alter scene luminance;
	# compensating for them here produced the former washed-out grey frame.
	var night_lift := lerpf(1.12, 1.02, daylight)
	var weather_lift := cloud * 0.012 + storm * 0.012
	_environment.tonemap_exposure = clampf(night_lift + weather_lift, 1.0, 1.14)


func _apply_fog(solar: Dictionary, fog_t: float, daylight: float, cloud: float, storm: float) -> void:
	if _environment == null:
		return
		
	var low_sun := _low_sun_factor(solar)
	var base_fog_col := (
		Color(0.025, 0.035, 0.055)
		.lerp(Color(0.34, 0.41, 0.50), daylight)
		.lerp(Color(0.58, 0.34, 0.25), low_sun * lerpf(0.82, 0.26, cloud))
		.lerp(Color(0.16, 0.18, 0.22), storm * 0.55)
	)
	
	# Traditional Screen-Space Fog (Handles skybox blending and distant occlusion)
	# Keep the response soft: haze should read as atmosphere, not a white wall.
	_environment.fog_light_color = base_fog_col
	var distance_haze := pow(fog_t, 2.15)
	_environment.fog_density            = 0.009 * distance_haze
	_environment.fog_aerial_perspective = 0.24 * fog_t
	_environment.fog_sky_affect = 0.30 * distance_haze

	# Volumetric Fog (Physical 3D depth, light shafts, and realistic thickness).
	# Godot runs the full 64³ froxel compute every frame as long as
	# volumetric_fog_enabled = true — density only scales the visible
	# contribution, not the compute cost. In clear weather we'd be paying ~2-4 ms
	# for fog with zero visible effect, so we gate the whole pass on a small
	# density threshold. Mid fog should stay translucent; only dense bands crush.
	const VOLUMETRIC_FOG_START := 0.44
	var vol_amount := smoothstep(VOLUMETRIC_FOG_START, 0.94, fog_t)
	var vol_density := 0.018 * vol_amount
	var want_volumetric := enable_volumetric_fog and fog_t > VOLUMETRIC_FOG_START
	_environment.volumetric_fog_enabled = want_volumetric
	if want_volumetric:
		_environment.volumetric_fog_albedo  = base_fog_col
		_environment.volumetric_fog_density = vol_density
		_environment.volumetric_fog_emission = Color.BLACK
		_environment.volumetric_fog_emission_energy = 0.0
		# Keep fog farther out so near-field ships/ports stay readable.
		_environment.volumetric_fog_length  = lerpf(560.0, 260.0, fog_t)


func _apply_sky_shader(solar: Dictionary, daylight: float, cloud: float, storm: float) -> void:
	if _sky_shader_material == null:
		return
	var low_sun := _low_sun_factor(solar)
	var top_col := (
		Color(0.006, 0.009, 0.028)
		.lerp(Color(0.055, 0.20, 0.48), daylight)
		.lerp(Color(0.075, 0.095, 0.13), cloud)
	)
	var horiz := (
		Color(0.018, 0.016, 0.028)
		.lerp(Color(0.28, 0.43, 0.62), daylight)
		.lerp(Color(0.20, 0.24, 0.29), cloud)
		.lerp(Color(0.72, 0.31, 0.16), low_sun * lerpf(0.90, 0.28, cloud))
	)
	var zenith_deep := (
		Color(0.001, 0.004, 0.022)
		.lerp(Color(0.015, 0.08, 0.38), daylight)
		.lerp(Color(0.05, 0.065, 0.09), storm)
	)
	var ground_c := (
		Color(0.025, 0.028, 0.04)
		.lerp(Color(0.12, 0.115, 0.105), daylight)
		.lerp(Color(0.055, 0.06, 0.075), cloud)
	)
	var sun_col := Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.50, 0.20), low_sun)
	var cloud_lit := (
		Color(0.12, 0.15, 0.22)
		.lerp(Color(0.72, 0.76, 0.81), daylight)
		.lerp(Color(0.78, 0.45, 0.30), low_sun * 0.30)
	)
	var cloud_dark := Color(0.045, 0.055, 0.075).lerp(Color(0.31, 0.34, 0.39), daylight)

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
	_sky_shader_material.set_shader_parameter("cloud_light",       Vector3(cloud_lit.r, cloud_lit.g, cloud_lit.b))
	_sky_shader_material.set_shader_parameter("cloud_dark",        Vector3(cloud_dark.r, cloud_dark.g, cloud_dark.b))
	_sky_shader_material.set_shader_parameter("storm_intensity",   storm)
	_sky_shader_material.set_shader_parameter("sun_color",         Vector3(sun_col.r,  sun_col.g,  sun_col.b))
	_sky_shader_material.set_shader_parameter("star_visibility",   clampf(star_vis, 0.0, 1.0))
	_sky_shader_material.set_shader_parameter("daylight_factor",   daylight)


func _apply_screen_effects(daylight: float, cloud: float, rain: float, storm: float, fog_t: float) -> void:
	if _screen_material == null:
		return
	if _screen_rect != null:
		_screen_rect.visible = enable_weather_post_fx
	var active := 1.0 if enable_weather_post_fx else 0.0
	_screen_material.set_shader_parameter("outline_strength", lerpf(0.025, 0.04, daylight) * active)
	_screen_material.set_shader_parameter("grain_strength", lerpf(0.012, 0.024, 1.0 - daylight) * active)
	_screen_material.set_shader_parameter("vignette_strength", lerpf(0.045, 0.085, storm) * active)
	_screen_material.set_shader_parameter("weather_desaturation", clampf(cloud * 0.015 + storm * 0.055 + fog_t * 0.025, 0.0, 0.085) * active)
	_screen_material.set_shader_parameter("rain_cool_shift", rain * 0.018 * active)
	_screen_material.set_shader_parameter("shadow_coolness", lerpf(0.035, 0.065, cloud) * active)
	_screen_material.set_shader_parameter("highlight_warmth", lerpf(0.035, 0.012, cloud) * active)
	_screen_material.set_shader_parameter("weather_contrast", (0.018 + storm * 0.012) * active)


## Binds LandField's baked shelter texture to the ocean shader. The texture is
## generated once at world init from the island disks, so this runs exactly
## once when LandField finishes initialising (WorldRenderer is added to the
## scene first). Steady-state per-frame cost is one bool compare.
func _sync_land_shelter() -> void:
	if _ocean_shader_material == null:
		return
	if _shelter_texture_bound:
		return
	var tex := LandField.get_baked_shelter_texture()
	if tex == null:
		return
	_ocean_shader_material.set_shader_parameter("land_shelter_map",    tex)
	_ocean_shader_material.set_shader_parameter("land_shelter_origin", LandField.get_baked_world_origin())
	_ocean_shader_material.set_shader_parameter("land_shelter_size",   LandField.get_baked_world_size())
	if _ocean_mid_material != null:
		_ocean_mid_material.set_shader_parameter("land_shelter_map",    tex)
		_ocean_mid_material.set_shader_parameter("land_shelter_origin", LandField.get_baked_world_origin())
		_ocean_mid_material.set_shader_parameter("land_shelter_size",   LandField.get_baked_world_size())
	if _ocean_far_material != null:
		_ocean_far_material.set_shader_parameter("land_shelter_map",    tex)
		_ocean_far_material.set_shader_parameter("land_shelter_origin", LandField.get_baked_world_origin())
		_ocean_far_material.set_shader_parameter("land_shelter_size",   LandField.get_baked_world_size())
	if _ocean_horizon_material != null:
		_ocean_horizon_material.set_shader_parameter("land_shelter_map",    tex)
		_ocean_horizon_material.set_shader_parameter("land_shelter_origin", LandField.get_baked_world_origin())
		_ocean_horizon_material.set_shader_parameter("land_shelter_size",   LandField.get_baked_world_size())
	_shelter_texture_bound = true


func _apply_ocean_shader(
		solar: Dictionary,
		daylight: float,
		cloud: float,
		rain: float,
		sea_state: float,
		air_wind: float,
		storm: float,
		fog_t: float,
) -> void:
	if _ocean_shader_material == null:
		return
	var fog_w := fog_t * fog_t
	## Teal-absorbing ocean body — not pitch black (black + gloss = plastic).
	var ocean_color := (
		Color(0.012, 0.035, 0.055)
		.lerp(Color(0.018, 0.055, 0.085), daylight)
		.lerp(Color(0.028, 0.040, 0.050), storm)
	)
	var deep      := ocean_color * lerpf(0.45, 0.65, rain)
	var shallow_w := ocean_color * lerpf(1.35, 1.85, rain)

	var fog_murk := Color(0.035, 0.040, 0.048)
	shallow_w = shallow_w.lerp(fog_murk.lightened(0.05), fog_w * 0.55)
	deep      = deep.lerp(fog_murk.darkened(0.08), fog_w * 0.60)

	var foam_driver  := clampf(rain * 0.45 + sea_state * 0.72 + storm * 0.25, 0.0, 1.0)
	var steep_driver := clampf(maxf(sea_state * 0.82, storm * 0.55), 0.0, 1.0)

	## Capillary chop stays subtle — high gain reads as hammered metal up close.
	var chop_val := lerpf(0.10, 0.22, clampf(air_wind * 0.85 + sea_state * 0.28 + rain * 0.18, 0.0, 1.0))
	chop_val *= lerpf(1.0, 0.72, fog_w)

	var low_sun := _low_sun_factor(solar)
	var top_col := (
		Color(0.006, 0.009, 0.028)
		.lerp(Color(0.07, 0.28, 0.62), daylight)
		.lerp(Color(0.09, 0.10, 0.13), cloud)
	)
	var horiz := (
		Color(0.018, 0.016, 0.028)
		.lerp(Color(0.34, 0.54, 0.78), daylight)
		.lerp(Color(0.22, 0.24, 0.28), cloud)
		.lerp(Color(0.62, 0.28, 0.14), low_sun * lerpf(0.66, 0.18, cloud))
	)

	var sun_dir := _celestial_dir(0.0)
	## Chromaticity only. Direct-light energy belongs to the DirectionalLight3D;
	## multiplying it into the ocean glint a second time blew out noon highlights.
	var sun_col := Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.50, 0.20), low_sun)

	_ocean_shader_material.set_shader_parameter("shallow_albedo",     Vector3(shallow_w.r, shallow_w.g, shallow_w.b))
	_ocean_shader_material.set_shader_parameter("deep_albedo",        Vector3(deep.r, deep.g, deep.b))
	_ocean_shader_material.set_shader_parameter("sky_top_color",      Vector3(top_col.r, top_col.g, top_col.b))
	_ocean_shader_material.set_shader_parameter("sky_horizon_color",  Vector3(horiz.r, horiz.g, horiz.b))
	_ocean_shader_material.set_shader_parameter("sun_direction",      sun_dir)
	_ocean_shader_material.set_shader_parameter("sun_color",          Vector3(sun_col.r, sun_col.g, sun_col.b))

	## Fresnel sky mix — reflective at graze, never a full-face mirror.
	var fres_blend := lerpf(0.58, 0.36, cloud) * lerpf(1.0, 0.55, fog_w)
	_ocean_shader_material.set_shader_parameter("fresnel_sky_mix", fres_blend)
	_ocean_shader_material.set_shader_parameter("foam_strength",    lerpf(0.55, 1.05, foam_driver))
	_ocean_shader_material.set_shader_parameter("foam_steep_start", lerpf(0.26, 0.14, steep_driver))
	_ocean_shader_material.set_shader_parameter("foam_steep_end",   lerpf(0.70, 0.45, steep_driver))
	var near_lift := lerpf(0.16, 0.05, cloud) * lerpf(1.0, 0.40, fog_w)
	_ocean_shader_material.set_shader_parameter("near_color_lift", near_lift)
	_ocean_shader_material.set_shader_parameter("chop_strength",   chop_val)
	## Soft glitter — not silver sheets. Dies under overcast / fog.
	var glint := 0.55 * lerpf(1.0, 0.08, cloud) * lerpf(1.0, 0.0, fog_w) * lerpf(0.15, 1.0, daylight)
	_ocean_shader_material.set_shader_parameter("glint_strength", glint)

	if _ocean_mid_material != null:
		_ocean_mid_material.set_shader_parameter("shallow_albedo",     Vector3(shallow_w.r, shallow_w.g, shallow_w.b))
		_ocean_mid_material.set_shader_parameter("deep_albedo",        Vector3(deep.r, deep.g, deep.b))
		_ocean_mid_material.set_shader_parameter("sky_top_color",      Vector3(top_col.r, top_col.g, top_col.b))
		_ocean_mid_material.set_shader_parameter("sky_horizon_color",  Vector3(horiz.r, horiz.g, horiz.b))
		_ocean_mid_material.set_shader_parameter("sun_direction",      sun_dir)
		_ocean_mid_material.set_shader_parameter("sun_color",          Vector3(sun_col.r, sun_col.g, sun_col.b))
		_ocean_mid_material.set_shader_parameter("fresnel_sky_mix", fres_blend)
		_ocean_mid_material.set_shader_parameter("foam_strength",    lerpf(0.55, 1.05, foam_driver) * 0.72)
		_ocean_mid_material.set_shader_parameter("foam_steep_start", lerpf(0.26, 0.14, steep_driver))
		_ocean_mid_material.set_shader_parameter("foam_steep_end",   lerpf(0.70, 0.45, steep_driver))
		_ocean_mid_material.set_shader_parameter("near_color_lift", near_lift)
		_ocean_mid_material.set_shader_parameter("chop_strength",   chop_val)
		_ocean_mid_material.set_shader_parameter("glint_strength", glint)

	if _ocean_far_material != null:
		_ocean_far_material.set_shader_parameter("shallow_albedo",     Vector3(shallow_w.r, shallow_w.g, shallow_w.b))
		_ocean_far_material.set_shader_parameter("deep_albedo",        Vector3(deep.r, deep.g, deep.b))
		_ocean_far_material.set_shader_parameter("sky_top_color",      Vector3(top_col.r, top_col.g, top_col.b))
		_ocean_far_material.set_shader_parameter("sky_horizon_color",  Vector3(horiz.r, horiz.g, horiz.b))
		_ocean_far_material.set_shader_parameter("sun_direction",      sun_dir)
		_ocean_far_material.set_shader_parameter("sun_color",          Vector3(sun_col.r, sun_col.g, sun_col.b))
		_ocean_far_material.set_shader_parameter("fresnel_sky_mix",    fres_blend)
		_ocean_far_material.set_shader_parameter("near_color_lift",    near_lift)
		_ocean_far_material.set_shader_parameter("glint_strength",     glint * 0.55)

	if _ocean_horizon_material != null:
		_ocean_horizon_material.set_shader_parameter("shallow_albedo",    Vector3(shallow_w.r, shallow_w.g, shallow_w.b))
		_ocean_horizon_material.set_shader_parameter("deep_albedo",       Vector3(deep.r, deep.g, deep.b))
		_ocean_horizon_material.set_shader_parameter("sky_top_color",     Vector3(top_col.r, top_col.g, top_col.b))
		_ocean_horizon_material.set_shader_parameter("sky_horizon_color", Vector3(horiz.r, horiz.g, horiz.b))
		_ocean_horizon_material.set_shader_parameter("sun_direction",     sun_dir)
		_ocean_horizon_material.set_shader_parameter("sun_color",         Vector3(sun_col.r, sun_col.g, sun_col.b))
		_ocean_horizon_material.set_shader_parameter("fresnel_sky_mix",   fres_blend)
		_ocean_horizon_material.set_shader_parameter("near_color_lift",   near_lift)
		_ocean_horizon_material.set_shader_parameter("glint_strength",    glint * 0.32)


func _low_sun_factor(solar: Dictionary) -> float:
	var altitude := float(solar.get("altitude_degrees", 45.0))
	var direct := float(solar.get("direct_light", 0.0))
	return (1.0 - smoothstep(6.0, 32.0, altitude)) * smoothstep(0.02, 0.55, direct)


func _celestial_dir(tod_offset: float) -> Vector3:
	var weather := _get_weather()
	var tod     := float(weather.get("time_of_day")) if weather else 0.42
	var solar := SolarCycle.sample(tod)
	if is_equal_approx(absf(tod_offset), 0.5):
		return solar["moon_direction"] as Vector3
	if is_zero_approx(tod_offset):
		return solar["sun_direction"] as Vector3
	return SolarCycle.sample(wrapf(tod + tod_offset, 0.0, 1.0))["sun_direction"] as Vector3


func _get_weather() -> Node:
	return get_node_or_null("/root/WeatherLighting")
