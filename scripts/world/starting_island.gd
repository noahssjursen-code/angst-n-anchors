@tool
extends Node3D

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")
const BOAT_SCENE   := preload("res://scenes/boats/test_boat.tscn")
const OCEAN_SHADER := preload("res://resources/shaders/ocean_waves.gdshader")
const SKY_SHADER   := preload("res://resources/shaders/sky.gdshader")
const RAIN_FIELD_SCRIPT    := preload("res://scripts/systems/weather/rain_field.gd")
const WEATHER_HUD_SCRIPT   := preload("res://scripts/systems/weather/weather_hud.gd")
const WEATHER_AUDIO_SCRIPT := preload("res://scripts/systems/audio/weather_audio_system.gd")
const DockFacilitiesScript := preload("res://scripts/systems/dock/dock_facilities.gd")
const WarehouseCargoTestScript := preload("res://scripts/systems/cargo/warehouse_cargo_test.gd")
const WarehouseContractZoneScript := preload("res://scripts/systems/cargo/warehouse_contract_zone.gd")

const C_SAND  := Color(0.82, 0.74, 0.58)
const C_OCEAN := Color(0.10, 0.28, 0.48)

const BERTH_SHIP_POSITION := Vector3(12.5, WaveSurface.WATER_LEVEL, 47.0)
const DOCK_SURFACE_Y := 0.08
const MOORING_BERTH_FRONT_Z := 36.5
const MOORING_BERTH_REAR_Z := 57.5
## Near the land end of `concrete_pier` (deck top at `DOCK_SURFACE_Y`).
const TERMINAL_POSITION := Vector3(4.5, DOCK_SURFACE_Y, 37.8)
## Island-side / approach from sand; XY added to TERMINAL, Y overwritten at spawn (feet on deck).
const PLAYER_SPAWN_OFFSET_FROM_TERMINAL := Vector3(3, 0.0, -15)

const CONCRETE_PIER_MODEL := "res://resources/data/meshes/concrete_pier.json"
const PIER_DECK_TOP_LOCAL_Y := 2.0
const PIER_ABS_SCALE := 1.3
## `concrete_pier` deck narrow half-span is 1.8 m locally; − small inset so bollards sit near rails.
const MOORING_SIDE_OFFSET_FROM_PIER_CENTER_X := 1.8 * PIER_ABS_SCALE - 0.08
const PIER_POSITION := Vector3(5.6, DOCK_SURFACE_Y - PIER_DECK_TOP_LOCAL_Y * PIER_ABS_SCALE, 42.0)
const PIER_ROTATION := Vector3(0.0, 90.0, 0.0)
## Authored deck span along local +X in `concrete_pier.json` (vertices roughly -10..10).
const PIER_DECK_LENGTH_UNSCALED := 20.0
## Extra distance between pier centers along the long axis (m); 0 = flush end-to-end.
const PIER_CHAIN_GAP := 0.0
## Placement of pier 2 along deck local +X (after `PIER_ROTATION`); negate to flip which end hooks to pier 1.
const PIER_CHAIN_SIGN := -1.0

## Inland sand; slab top ≈ y=0. Small +Y clears ground vs floor flicker (z‑fighting).
## Kept south/west of berth (mooring ≈ z 36–57).
const OPEN_WAREHOUSE_MODEL := "res://resources/data/meshes/open_warehouse.json"
const OPEN_WAREHOUSE_ABS_SCALE := 1.0
const OPEN_WAREHOUSE_POSITION := Vector3(-22.0, 0.03, -8.0)
const OPEN_WAREHOUSE_ROTATION := Vector3(0.0, 55.0, 0.0)

var _ocean_shader_material: ShaderMaterial
var _sky_shader_material: ShaderMaterial
var _environment: Environment
var _sun: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _open_warehouse: StaticBody3D
var _warehouse_contract_zone: Node3D

var _lightning_light: DirectionalLight3D
var _lightning_flash_rect: ColorRect
var _lightning_cooldown: float = 2.0
var _lightning_phase: int = 0   # 0=idle, 1=flash1, 2=gap, 3=flash2
var _lightning_phase_t: float = 0.0


func _process(delta: float) -> void:
	if _ocean_shader_material:
		_ocean_shader_material.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
		_ocean_shader_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		WaveSurface.sync_ocean_coupling_to_shader(_ocean_shader_material)
	if _sky_shader_material:
		_sky_shader_material.set_shader_parameter("sky_time", WaveSurface.get_sim_time())
		_sky_shader_material.set_shader_parameter("sun_direction",  _celestial_dir(0.0))
		_sky_shader_material.set_shader_parameter("moon_direction", _celestial_dir(0.5))
	if not Engine.is_editor_hint():
		_update_lightning(delta)


# Returns the world-space unit vector pointing FROM the scene TOWARD a celestial body.
# tod_offset 0.0 = sun, 0.5 = moon (placed half a day opposite).
func _celestial_dir(tod_offset: float) -> Vector3:
	var weather := _weather_lighting()
	var tod     := (weather.time_of_day if weather else 0.42) as float
	var t    := fmod(tod + tod_offset, 1.0)
	var elev := -cos(t * TAU)                   # -1 at midnight, +1 at noon
	var x_r  := deg_to_rad(-elev * 55.0)        # matches _sun rotation formula
	var y_r  := deg_to_rad(t * 360.0 - 120.0)
	var rot  := Basis.from_euler(Vector3(x_r, y_r, 0.0))
	return -(rot * Vector3(0.0, 0.0, -1.0))     # direction TO body (negate light ray)


func _ready() -> void:
	# Clear existing generated nodes to avoid duplicates in editor
	for child in get_children():
		if (
			child is MeshInstance3D
			or child is StaticBody3D
			or child is WorldEnvironment
			or child is DirectionalLight3D
			or child.name == "ShipSpawner"
			or child.name == "DockFacilities"
			or child.name.begins_with("ConcretePier")
		):
			child.queue_free()

	_build_sky()
	_build_ocean()
	_build_island()
	_build_open_warehouse()
	_build_dock()
	_build_warehouse_cargo_test()
	_connect_weather_lighting()
	_apply_weather_lighting()
	
	if not Engine.is_editor_hint():
		_spawn_player()
		_spawn_rain_field()
		_spawn_weather_hud()
		_spawn_lightning_system()
		_spawn_ocean_ambient()


func _build_sky() -> void:
	var sky_sm := ShaderMaterial.new()
	sky_sm.shader = SKY_SHADER
	_sky_shader_material = sky_sm

	var sky := Sky.new()
	sky.sky_material        = sky_sm
	sky.radiance_size       = Sky.RADIANCE_SIZE_64

	var environ := Environment.new()
	_environment = environ
	environ.sky = sky
	environ.background_mode      = Environment.BG_SKY
	environ.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environ.ambient_light_energy = 0.18

	# Tonemap — conservative exposure; materials carry brightness, not post.
	environ.tonemap_mode     = Environment.TONE_MAPPER_FILMIC
	environ.tonemap_exposure = 0.95
	environ.tonemap_white    = 6.0

	# SSAO — contact shadows under crates, dock edges, hull against water.
	environ.ssao_enabled   = true
	environ.ssao_radius    = 0.9
	environ.ssao_intensity = 1.4

	# Bloom — only hot highlights (water sparkle, future ship lights).
	environ.glow_enabled    = true
	environ.glow_normalized = false
	environ.glow_intensity  = 0.4
	environ.glow_bloom      = 0.07
	environ.set_glow_level(2, true)
	environ.set_glow_level(3, true)

	# SSR — water reflects nearby geometry.
	environ.ssr_enabled   = true
	environ.ssr_max_steps = 32
	environ.ssr_fade_in   = 0.15
	environ.ssr_fade_out  = 2.0

	# Fog — driven by visibility axis at runtime; disabled until weather sets it.
	environ.fog_enabled            = false
	environ.fog_light_color        = Color(0.82, 0.84, 0.88)
	environ.fog_density            = 0.0
	environ.fog_aerial_perspective = 0.0
	environ.fog_sky_affect         = 1.0

	var world_env := WorldEnvironment.new()
	world_env.environment = environ
	add_child(world_env)

	# Primary sun — warm directional, hard shadows.
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-50, 28, 0)
	sun.light_color    = Color(1.0, 0.92, 0.78)
	sun.light_energy   = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode         = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 180.0
	sun.shadow_bias                     = 0.04
	add_child(sun)

	# Sky fill — cool blue, scene lighting only; must NOT enter sky shader (LIGHT0/1 slots).
	var fill := DirectionalLight3D.new()
	_fill_light = fill
	fill.rotation_degrees = Vector3(40, -160, 0)
	fill.light_color    = Color(0.52, 0.64, 0.90)
	fill.light_energy   = 0.18
	fill.shadow_enabled = false
	fill.sky_mode       = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)

	# Apply initial sky uniforms so the shader has values before first state_changed.
	_apply_weather_lighting()


func _build_ocean() -> void:
	# Vertex waves use effective surface (traveling wave − hull dip) via WaveSurface uniforms.
	# Buoyancy samples the undisturbed wave only — see `WaveSurface.get_buoyancy_surface_height_at`.
	# High tessellation so Gerstner displacement is visibly geometric, not flat-looking.
	var ocean := MeshBuilder.plane(Vector2(600, 600), C_OCEAN, 0.12, 260, 260)
	var sm := ShaderMaterial.new()
	sm.shader = OCEAN_SHADER
	sm.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
	sm.set_shader_parameter("water_level", WaveSurface.WATER_LEVEL)
	sm.set_shader_parameter("amplitude_1", WaveSurface.AMPLITUDE_1)
	sm.set_shader_parameter("frequency_1", WaveSurface.FREQUENCY_1)
	sm.set_shader_parameter("speed_1", WaveSurface.SPEED_1)
	sm.set_shader_parameter("dir_1", WaveSurface.DIR_1)
	sm.set_shader_parameter("steepness_1", WaveSurface.STEEPNESS_1)
	sm.set_shader_parameter("amplitude_2", WaveSurface.AMPLITUDE_2)
	sm.set_shader_parameter("frequency_2", WaveSurface.FREQUENCY_2)
	sm.set_shader_parameter("speed_2", WaveSurface.SPEED_2)
	sm.set_shader_parameter("dir_2", WaveSurface.DIR_2)
	sm.set_shader_parameter("steepness_2", WaveSurface.STEEPNESS_2)
	sm.set_shader_parameter("amplitude_3", WaveSurface.AMPLITUDE_3)
	sm.set_shader_parameter("frequency_3", WaveSurface.FREQUENCY_3)
	sm.set_shader_parameter("speed_3", WaveSurface.SPEED_3)
	sm.set_shader_parameter("dir_3", WaveSurface.DIR_3)
	sm.set_shader_parameter("steepness_3", WaveSurface.STEEPNESS_3)
	sm.set_shader_parameter("amplitude_4", WaveSurface.AMPLITUDE_4)
	sm.set_shader_parameter("frequency_4", WaveSurface.FREQUENCY_4)
	sm.set_shader_parameter("speed_4", WaveSurface.SPEED_4)
	sm.set_shader_parameter("dir_4", WaveSurface.DIR_4)
	sm.set_shader_parameter("steepness_4", WaveSurface.STEEPNESS_4)
	sm.set_shader_parameter("wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
	sm.set_shader_parameter("shallow_albedo", Vector3(0.04, 0.14, 0.28))
	sm.set_shader_parameter("deep_albedo",    Vector3(0.008, 0.025, 0.055))
	sm.set_shader_parameter("horizon_tint",   Vector3(0.10, 0.20, 0.38))
	sm.set_shader_parameter("water_alpha",       0.94)
	sm.set_shader_parameter("fresnel_sky_mix",   0.72)
	sm.set_shader_parameter("fresnel_power",     3.8)
	sm.set_shader_parameter("foam_strength",     0.55)
	sm.set_shader_parameter("foam_steep_start",  0.60)
	sm.set_shader_parameter("foam_steep_end",    0.92)
	sm.set_shader_parameter("near_color_lift",   0.20)
	sm.set_shader_parameter("roughness",         0.07)
	sm.set_shader_parameter("metallic",          0.10)
	sm.set_shader_parameter("specular",          0.92)
	sm.set_shader_parameter("chop_strength",     0.08)
	sm.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
	ocean.material_override = sm
	_ocean_shader_material = sm
	ocean.position = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	add_child(ocean)


func _connect_weather_lighting() -> void:
	var weather := _weather_lighting()
	if weather == null:
		return
	var callable := Callable(self, "_apply_weather_lighting")
	if not weather.is_connected("state_changed", callable):
		weather.connect("state_changed", callable)


func _apply_weather_lighting() -> void:
	var tod  := 0.42
	var wind := 0.0
	var vis  := 1.0
	var weather := _weather_lighting()
	if weather != null:
		tod  = float(weather.get("time_of_day"))
		wind = float(weather.get("wind_force"))
		vis  = float(weather.get("visibility"))

	# Derived scalars
	# elev_norm: -1 at midnight (sun below), 0 at horizon (dawn/dusk), +1 at solar noon.
	var elev_norm  := -cos(tod * TAU)
	var daylight   := smoothstep(-0.18, 0.55, elev_norm)
	var cloud      := float(weather.get("cloud_coverage")) if weather != null else 0.0
	var rain       := float(weather.get("rain_amount"))    if weather != null else 0.0
	var storm      := float(weather.get("storm_intensity")) if weather != null else 0.0
	var fog_t      := 1.0 - vis

	# --- Sun ---
	# Elevation: negative x_rot = sun higher above horizon (matching Godot convention).
	# At noon elev_norm=+1 → x=-55° (55° above horizon).
	# At midnight elev_norm=-1 → x=+55° (below ground, disk invisible in sky shader).
	# Azimuth sweeps 360° over the day: rises east, transits south, sets west.
	if _sun != null:
		_sun.rotation_degrees = Vector3(
			-elev_norm * 55.0,
			tod * 360.0 - 120.0,
			0.0
		)
		# Storm crushes sun further — full overcast is almost no direct light.
		_sun.light_energy = lerpf(0.03, 1.6, daylight) * lerpf(1.0, 0.10, cloud)
		var dawn   := Color(1.0,  0.68, 0.42)
		var noon   := Color(1.0,  0.95, 0.82)
		var stormc := Color(0.48, 0.55, 0.68)
		_sun.light_color = dawn.lerp(noon, daylight).lerp(stormc, storm)

	# --- Fill light ---
	if _fill_light != null:
		# Night fill is nearly zero — moonlight should not bounce off everything.
		_fill_light.light_energy = lerpf(0.18, 0.03, cloud) * lerpf(0.03, 1.0, daylight)

	# --- Ambient ---
	if _environment != null:
		# Squared daylight curve keeps nights very dark and only brightens
		# significantly as the sun rises well above the horizon.
		_environment.ambient_light_energy = (
			lerpf(0.006, 0.22, daylight * daylight) * lerpf(1.0, 0.52, cloud)
		)

	# --- Sky shader uniforms ---
	if _sky_shader_material != null:
		var night_top     := Color(0.006, 0.009, 0.028)   # deep navy-black
		# Calm-clear: deep saturated blue sky.
		var day_top       := Color(0.18,  0.46,  0.78)
		# Full storm: near-black greenish-grey.
		var storm_top     := Color(0.09,  0.10,  0.13)
		var night_horizon := Color(0.018, 0.016, 0.028)  # near-black horizon at night
		# Calm-clear: bright pale horizon.
		var day_horizon   := Color(0.54,  0.74,  0.92)
		# Storm: heavy grey.
		var storm_horizon := Color(0.22,  0.24,  0.28)

		var top_col  := night_top.lerp(day_top, daylight).lerp(storm_top, cloud)
		var horiz    := night_horizon.lerp(day_horizon, daylight).lerp(storm_horizon, cloud)
		var ground_c := (
			Color(0.04, 0.04, 0.05)
			.lerp(Color(0.15, 0.13, 0.11), daylight)
			.lerp(Color(0.06, 0.06, 0.07), cloud)
		)
		_sky_shader_material.set_shader_parameter("sky_top_color",     Vector3(top_col.r, top_col.g, top_col.b))
		_sky_shader_material.set_shader_parameter("sky_horizon_color", Vector3(horiz.r,   horiz.g,   horiz.b))
		_sky_shader_material.set_shader_parameter("sky_ground_color",  Vector3(ground_c.r, ground_c.g, ground_c.b))
		_sky_shader_material.set_shader_parameter("cloud_coverage",    cloud)
		_sky_shader_material.set_shader_parameter("storm_intensity",   storm)
		# Sun disk: warm at dawn, vivid white at noon, pale at night.
		var sun_col := Color(1.0, 0.62, 0.30).lerp(Color(1.0, 0.96, 0.88), daylight)
		_sky_shader_material.set_shader_parameter("sun_color", Vector3(sun_col.r, sun_col.g, sun_col.b))

	# --- Fog (visibility axis) ---
	if _environment != null:
		_environment.fog_enabled = fog_t > 0.04
		if _environment.fog_enabled:
			# Fog colour tracks ambient light so it reads as obscured air, not a
			# white overlay.  Daytime overcast grey, dark at night, mid-grey in storms.
			var day_fog   := Color(0.46, 0.49, 0.54)   # cool medium grey
			var night_fog := Color(0.06, 0.07, 0.09)   # near-black
			var storm_fog := Color(0.28, 0.30, 0.33)   # darker stormy grey
			var fog_col   := night_fog.lerp(day_fog, daylight).lerp(storm_fog, storm * 0.5)
			_environment.fog_light_color = fog_col

			# Cubic curve: almost invisible at low fog_t, builds sharply near max.
			var fog_curve := fog_t * fog_t * fog_t
			_environment.fog_density    = lerpf(0.0, 0.25, fog_curve)

			# Aerial perspective helps geometry dissolve into fog at distance.
			_environment.fog_aerial_perspective = lerpf(0.0, 0.35, fog_t)

			# Keep sky effect very subtle — real fog is IN the air between you
			# and the horizon, not painted on the sky itself.
			_environment.fog_sky_affect = lerpf(0.0, 0.18, fog_t * fog_t)

	# --- Ocean shader ---
	if _ocean_shader_material != null:
		var day_ocean   := C_OCEAN
		var night_ocean := Color(0.020, 0.042, 0.085)
		var storm_ocean := Color(0.050, 0.075, 0.095)
		var ocean_color := night_ocean.lerp(day_ocean, daylight).lerp(storm_ocean, storm)
		var deep      := ocean_color * lerpf(0.22, 0.38, rain)
		var shallow_w := ocean_color * lerpf(0.62, 0.80, rain)
		var horizon_w := ocean_color.lerp(Color(0.18, 0.32, 0.56), lerpf(0.45, 0.28, cloud))
		_ocean_shader_material.set_shader_parameter(
			"shallow_albedo", Vector3(shallow_w.r, shallow_w.g, shallow_w.b))
		_ocean_shader_material.set_shader_parameter(
			"deep_albedo", Vector3(deep.r, deep.g, deep.b))
		_ocean_shader_material.set_shader_parameter(
			"horizon_tint", Vector3(horizon_w.r, horizon_w.g, horizon_w.b))
		_ocean_shader_material.set_shader_parameter(
			"fresnel_sky_mix", lerpf(0.70, 0.42, cloud))
		_ocean_shader_material.set_shader_parameter(
			"wave_energy_multiplier", WaveSurface.get_wave_energy_multiplier())
		_ocean_shader_material.set_shader_parameter("water_alpha",      lerpf(0.92, 0.97, rain))
		var foam_driver := clampf(rain + wind * 0.55, 0.0, 1.0)
		_ocean_shader_material.set_shader_parameter("foam_strength",    lerpf(0.38, 0.92, foam_driver))
		# Squall (wind only) lowers the steepness threshold so whitecaps appear even without rain.
		var steep_driver := clampf(maxf(storm, wind * 0.65), 0.0, 1.0)
		_ocean_shader_material.set_shader_parameter("foam_steep_start", lerpf(0.62, 0.34, steep_driver))
		_ocean_shader_material.set_shader_parameter("foam_steep_end",   lerpf(0.94, 0.62, steep_driver))
		_ocean_shader_material.set_shader_parameter(
			"near_color_lift", lerpf(0.20, 0.08, cloud))
		var rough_driver := clampf(maxf(rain, wind * 0.55), 0.0, 1.0)
		_ocean_shader_material.set_shader_parameter("roughness", lerpf(0.07, 0.32, rough_driver))
		_ocean_shader_material.set_shader_parameter("metallic",  lerpf(0.10, 0.03, rough_driver))


func _spawn_lightning_system() -> void:
	# Scene light — rapid cool-white flash, no shadows (too brief to matter).
	var ll := DirectionalLight3D.new()
	_lightning_light = ll
	ll.name = "LightningLight"
	ll.light_color    = Color(0.80, 0.88, 1.0)
	ll.light_energy   = 0.0
	ll.shadow_enabled = false
	ll.sky_mode       = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	ll.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	add_child(ll)

	# Screen overlay — thin white-blue panel that spikes and fades.
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)
	var rect := ColorRect.new()
	_lightning_flash_rect = rect
	rect.color = Color(0.82, 0.90, 1.0, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rect)


func _update_lightning(delta: float) -> void:
	var storm := 0.0
	var w := _weather_lighting()
	if w:
		storm = float(w.get("storm_intensity"))

	# Kill everything when not stormy enough.
	if storm < 0.20:
		if _lightning_light:   _lightning_light.light_energy = 0.0
		if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
		_lightning_phase    = 0
		_lightning_cooldown = randf_range(2.0, 6.0)
		return

	if _lightning_phase == 0:
		_lightning_cooldown -= delta
		if _lightning_cooldown <= 0.0:
			# Randomise the strike direction for variety.
			if _lightning_light:
				_lightning_light.rotation_degrees = Vector3(
					randf_range(-70.0, -30.0),
					randf_range(0.0, 360.0),
					0.0
				)
			_lightning_phase   = 1
			_lightning_phase_t = 0.0
			# More frequent at higher storm; still irregular.
			_lightning_cooldown = randf_range(1.5, 10.0) / storm
		return

	_lightning_phase_t += delta

	match _lightning_phase:
		1: # First flash — sharp spike then quick fade.
			var t    := minf(_lightning_phase_t / 0.07, 1.0)
			var fade := 1.0 - t
			if _lightning_light:   _lightning_light.light_energy = fade * 9.0 * storm
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.40 * storm
			if _lightning_phase_t > 0.07:
				_lightning_phase   = 2
				_lightning_phase_t = 0.0

		2: # Brief dark gap between the two flashes.
			if _lightning_light:   _lightning_light.light_energy = 0.0
			if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
			if _lightning_phase_t > 0.05:
				_lightning_phase   = 3
				_lightning_phase_t = 0.0

		3: # Second flash — dimmer, slightly longer.
			var t    := minf(_lightning_phase_t / 0.10, 1.0)
			var fade := 1.0 - t
			if _lightning_light:   _lightning_light.light_energy = fade * 5.5 * storm
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.24 * storm
			if _lightning_phase_t > 0.10:
				if _lightning_light:   _lightning_light.light_energy = 0.0
				if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
				_lightning_phase = 0


func _weather_lighting() -> Node:
	return get_node_or_null("/root/WeatherLighting")


func _build_island() -> void:
	# Flat walkable island — top surface at y = 0
	var ground := MeshBuilder.static_box(Vector3(80, 2, 60), C_SAND)
	ground.position = Vector3(0, -1.0, 0)
	add_child(ground)


func _build_open_warehouse() -> void:
	var warehouse := StaticBody3D.new()
	warehouse.name = "OpenWarehouse"
	add_child(warehouse)
	warehouse.position = OPEN_WAREHOUSE_POSITION
	warehouse.rotation_degrees = OPEN_WAREHOUSE_ROTATION
	_open_warehouse = warehouse

	var assembler := ModelAssembler.new()
	assembler.model_data_path = OPEN_WAREHOUSE_MODEL
	assembler.absolute_scale = OPEN_WAREHOUSE_ABS_SCALE
	assembler.collision_parent_path = NodePath("..")
	assembler.build_part_colliders = true
	warehouse.add_child(assembler)

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			warehouse.owner = esc
			assembler.owner = esc
	_build_warehouse_contract_zone()


func _build_warehouse_contract_zone() -> void:
	if _open_warehouse == null or not is_instance_valid(_open_warehouse):
		return
	var old := _open_warehouse.get_node_or_null("ContractZone")
	if old != null:
		old.queue_free()

	var zone := WarehouseContractZoneScript.new()
	zone.name = "ContractZone"
	zone.position = Vector3(0.0, 0.03, -0.6)
	zone.set("zone_width_m", 6.2)
	zone.set("zone_length_m", 8.4)
	zone.set("slot_size_x_m", 1.2)
	zone.set("slot_size_z_m", 1.2)
	zone.set("show_debug_area", true)
	zone.set("debug_color", Color(0.18, 0.76, 0.30, 0.25))
	_open_warehouse.add_child(zone)
	_warehouse_contract_zone = zone

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			zone.owner = esc


func _build_warehouse_cargo_test() -> void:
	if Engine.is_editor_hint():
		return
	if _open_warehouse == null or not is_instance_valid(_open_warehouse):
		return

	var existing := get_node_or_null("WarehouseCargoTest")
	if existing != null:
		existing.queue_free()

	var cargo_test := WarehouseCargoTestScript.new()
	cargo_test.name = "WarehouseCargoTest"
	add_child(cargo_test)
	cargo_test.warehouse_root_path = cargo_test.get_path_to(_open_warehouse)
	if _warehouse_contract_zone != null and is_instance_valid(_warehouse_contract_zone):
		cargo_test.contract_zone_path = cargo_test.get_path_to(_warehouse_contract_zone)
	var spawner := get_node_or_null("DockFacilities/ShipSpawner")
	if spawner != null:
		cargo_test.ship_spawner_path = cargo_test.get_path_to(spawner)
	cargo_test.call_deferred("refresh_demo_contract")


func _build_dock() -> void:
	_build_concrete_piers()

	var moorings := PackedVector3Array()
	var sz := DOCK_SURFACE_Y
	var sx := _mooring_starboard_row_world_x()
	var px := _mooring_port_row_world_x()

	moorings.push_back(Vector3(sx, sz, MOORING_BERTH_FRONT_Z))
	moorings.push_back(Vector3(sx, sz, MOORING_BERTH_REAR_Z))
	moorings.push_back(Vector3(px, sz, MOORING_BERTH_FRONT_Z))
	moorings.push_back(Vector3(px, sz, MOORING_BERTH_REAR_Z))

	var sea_ext_star := _extended_pier_pair_at_row_world_x(sx)
	for i in sea_ext_star.size():
		moorings.push_back(sea_ext_star[i])
	var sea_ext_port := _extended_pier_pair_at_row_world_x(px)
	for i in sea_ext_port.size():
		moorings.push_back(sea_ext_port[i])

	DockFacilitiesScript.attach(
		self,
		moorings,
		TERMINAL_POSITION,
		180.0,
		BERTH_SHIP_POSITION,
		BOAT_SCENE,
	)


func _mooring_starboard_row_world_x() -> float:
	return PIER_POSITION.x + MOORING_SIDE_OFFSET_FROM_PIER_CENTER_X


func _mooring_port_row_world_x() -> float:
	return PIER_POSITION.x - MOORING_SIDE_OFFSET_FROM_PIER_CENTER_X


## Two bollards on the chained slab for one outboard row (same Z layout as berth ends).
func _extended_pier_pair_at_row_world_x(world_x_row: float) -> PackedVector3Array:
	var axial := _pier_world_long_axis()
	var along := axial * (_pier_center_to_center() * 0.32)
	var pier2 := _second_pier_center()

	var xa := world_x_row
	var ys := DOCK_SURFACE_Y

	var pa := pier2 + along
	var pb := pier2 - along
	pa.x = xa
	pb.x = xa
	pa.y = ys
	pb.y = ys

	var out := PackedVector3Array()
	out.push_back(pa)
	out.push_back(pb)
	return out


func _spawn_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	var spawn_position := TERMINAL_POSITION + PLAYER_SPAWN_OFFSET_FROM_TERMINAL
	spawn_position.y = DOCK_SURFACE_Y + 0.02
	player.position = spawn_position
	add_child(player)


func _spawn_rain_field() -> void:
	var rain_field := RAIN_FIELD_SCRIPT.new() as Node3D
	rain_field.name = "RainField"
	add_child(rain_field)


func _spawn_weather_hud() -> void:
	var hud := WEATHER_HUD_SCRIPT.new()
	hud.name = "WeatherHUD"
	add_child(hud)


func _spawn_ocean_ambient() -> void:
	var ambient := WEATHER_AUDIO_SCRIPT.new()
	ambient.name = "WeatherAudio"
	add_child(ambient)


func _build_concrete_piers() -> void:
	_build_concrete_pier_instance(PIER_POSITION, "")
	_build_concrete_pier_instance(_second_pier_center(), "2")


func _pier_world_long_axis() -> Vector3:
	var r := Vector3(
		deg_to_rad(PIER_ROTATION.x),
		deg_to_rad(PIER_ROTATION.y),
		deg_to_rad(PIER_ROTATION.z),
	)
	return Basis.from_euler(r).x.normalized()


func _pier_center_to_center() -> float:
	return PIER_DECK_LENGTH_UNSCALED * PIER_ABS_SCALE + PIER_CHAIN_GAP


func _second_pier_center() -> Vector3:
	var p := (
		PIER_POSITION
		+ _pier_world_long_axis() * _pier_center_to_center() * PIER_CHAIN_SIGN
	)
	p.y = PIER_POSITION.y
	return p


func _build_concrete_pier_instance(center: Vector3, name_suffix: String) -> void:
	var pier := StaticBody3D.new()
	pier.name = "ConcretePier" + name_suffix
	add_child(pier)
	pier.position = center
	pier.rotation_degrees = PIER_ROTATION

	var assembler := ModelAssembler.new()
	assembler.model_data_path = CONCRETE_PIER_MODEL
	assembler.absolute_scale = PIER_ABS_SCALE
	assembler.collision_parent_path = NodePath("..")
	assembler.build_part_colliders = true
	pier.add_child(assembler)

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			pier.owner = esc
			assembler.owner = esc
