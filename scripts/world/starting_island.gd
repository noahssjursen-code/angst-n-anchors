@tool
extends Node3D

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")
const BOAT_SCENE   := preload("res://scenes/boats/test_boat.tscn")
const OCEAN_SHADER := preload("res://resources/shaders/ocean_waves.gdshader")
const RAIN_FIELD_SCRIPT := preload("res://scripts/systems/weather/rain_field.gd")
const DockFacilitiesScript := preload("res://scripts/systems/dock/dock_facilities.gd")

const C_SAND  := Color(0.82, 0.74, 0.58)
const C_OCEAN := Color(0.10, 0.28, 0.48)

const BERTH_SHIP_POSITION := Vector3(11.0, WaveSurface.WATER_LEVEL, 47.0)
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

var _ocean_shader_material: ShaderMaterial
var _sky_material: ProceduralSkyMaterial
var _environment: Environment
var _sun: DirectionalLight3D


func _process(_delta: float) -> void:
	if _ocean_shader_material:
		_ocean_shader_material.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
		_ocean_shader_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		WaveSurface.sync_ocean_coupling_to_shader(_ocean_shader_material)


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
	_build_dock()
	_connect_weather_lighting()
	_apply_weather_lighting()
	
	if not Engine.is_editor_hint():
		_spawn_player()
		_spawn_rain_field()


func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	_sky_material = sky_mat
	sky_mat.sky_top_color     = Color(0.26, 0.46, 0.70)
	sky_mat.sky_horizon_color = Color(0.65, 0.78, 0.90)
	sky_mat.ground_bottom_color  = Color(0.16, 0.14, 0.12)
	sky_mat.ground_horizon_color = Color(0.48, 0.44, 0.36)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var environ := Environment.new()
	_environment = environ
	environ.sky = sky
	environ.background_mode      = Environment.BG_SKY
	environ.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environ.ambient_light_energy = 0.5
	environ.tonemap_mode         = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = environ
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-50, 28, 0)
	sun.light_color    = Color(1.0, 0.94, 0.82)
	sun.light_energy   = 1.8
	sun.shadow_enabled = true
	add_child(sun)


func _build_ocean() -> void:
	# Vertex waves use effective surface (traveling wave − hull dip) via WaveSurface uniforms.
	# Buoyancy samples the undisturbed wave only — see `WaveSurface.get_buoyancy_surface_height_at`.
	var ocean := MeshBuilder.plane(Vector2(600, 600), C_OCEAN, 0.12, 96, 96)
	var sm := ShaderMaterial.new()
	sm.shader = OCEAN_SHADER
	sm.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
	sm.set_shader_parameter("water_level", WaveSurface.WATER_LEVEL)
	sm.set_shader_parameter("amplitude_1", WaveSurface.AMPLITUDE_1)
	sm.set_shader_parameter("frequency_1", WaveSurface.FREQUENCY_1)
	sm.set_shader_parameter("speed_1", WaveSurface.SPEED_1)
	sm.set_shader_parameter("dir_1", WaveSurface.DIR_1)
	sm.set_shader_parameter("amplitude_2", WaveSurface.AMPLITUDE_2)
	sm.set_shader_parameter("frequency_2", WaveSurface.FREQUENCY_2)
	sm.set_shader_parameter("speed_2", WaveSurface.SPEED_2)
	sm.set_shader_parameter("dir_2", WaveSurface.DIR_2)
	var deep: Color = C_OCEAN.darkened(0.72)
	var shallow_water: Color = C_OCEAN.darkened(0.35)
	var horizon_grey := Color(0.22, 0.26, 0.30)
	var horizon_water: Color = C_OCEAN.lerp(horizon_grey, 0.55)
	var shallow_rgb := Vector3(shallow_water.r, shallow_water.g, shallow_water.b)
	var deep_rgb := Vector3(deep.r, deep.g, deep.b)
	var horizon_rgb := Vector3(horizon_water.r, horizon_water.g, horizon_water.b)
	sm.set_shader_parameter("shallow_albedo", shallow_rgb)
	sm.set_shader_parameter("deep_albedo", deep_rgb)
	sm.set_shader_parameter("horizon_tint", horizon_rgb)
	sm.set_shader_parameter("fresnel_sky_mix", 0.05)
	sm.set_shader_parameter("roughness", 0.38)
	sm.set_shader_parameter("metallic", 0.06)
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
	var time_of_day := 0.42
	var weather_amount := 0.0
	var weather := _weather_lighting()
	if weather != null:
		time_of_day = float(weather.get("time_of_day"))
		weather_amount = float(weather.get("weather_amount"))

	var sun_arc := sin(time_of_day * TAU - PI * 0.5)
	var daylight := smoothstep(-0.18, 0.72, sun_arc)
	var cloud := clampf(weather_amount, 0.0, 1.0)
	var rain := smoothstep(0.58, 1.0, cloud)

	if _sun != null:
		_sun.rotation_degrees = Vector3(
			lerpf(8.0, -72.0, daylight),
			time_of_day * 360.0 - 120.0,
			0.0
		)
		_sun.light_energy = lerpf(0.03, 1.9, daylight) * lerpf(1.0, 0.28, cloud)
		var dawn := Color(1.0, 0.68, 0.42)
		var noon := Color(1.0, 0.94, 0.82)
		var storm := Color(0.58, 0.62, 0.68)
		_sun.light_color = dawn.lerp(noon, daylight).lerp(storm, cloud)

	if _environment != null:
		_environment.ambient_light_energy = lerpf(0.08, 0.58, daylight) * lerpf(1.0, 0.72, cloud)

	if _sky_material != null:
		var night_top := Color(0.025, 0.035, 0.070)
		var day_top := Color(0.26, 0.46, 0.70)
		var storm_top := Color(0.18, 0.20, 0.23)
		var night_horizon := Color(0.08, 0.075, 0.09)
		var day_horizon := Color(0.65, 0.78, 0.90)
		var storm_horizon := Color(0.31, 0.33, 0.35)
		_sky_material.sky_top_color = (
			night_top.lerp(day_top, daylight).lerp(storm_top, cloud)
		)
		_sky_material.sky_horizon_color = (
			night_horizon.lerp(day_horizon, daylight).lerp(storm_horizon, cloud)
		)
		_sky_material.ground_bottom_color = (
			Color(0.04, 0.04, 0.05)
			.lerp(Color(0.16, 0.14, 0.12), daylight)
			.lerp(Color(0.09, 0.09, 0.09), cloud)
		)
		_sky_material.ground_horizon_color = (
			Color(0.08, 0.07, 0.06)
			.lerp(Color(0.48, 0.44, 0.36), daylight)
			.lerp(Color(0.20, 0.20, 0.19), cloud)
		)

	if _ocean_shader_material != null:
		var day_ocean := C_OCEAN
		var night_ocean := Color(0.015, 0.028, 0.050)
		var storm_ocean := Color(0.06, 0.075, 0.085)
		var ocean_color := night_ocean.lerp(day_ocean, daylight).lerp(storm_ocean, cloud)
		var deep: Color = ocean_color.darkened(lerpf(0.80, 0.62, rain))
		var shallow_water: Color = ocean_color.darkened(lerpf(0.45, 0.22, rain))
		var horizon_water: Color = ocean_color.lerp(Color(0.22, 0.24, 0.25), 0.45 + cloud * 0.28)
		_ocean_shader_material.set_shader_parameter(
			"shallow_albedo",
			Vector3(shallow_water.r, shallow_water.g, shallow_water.b)
		)
		_ocean_shader_material.set_shader_parameter("deep_albedo", Vector3(deep.r, deep.g, deep.b))
		_ocean_shader_material.set_shader_parameter(
			"horizon_tint",
			Vector3(horizon_water.r, horizon_water.g, horizon_water.b)
		)
		_ocean_shader_material.set_shader_parameter("fresnel_sky_mix", lerpf(0.05, 0.14, cloud))
		_ocean_shader_material.set_shader_parameter("roughness", lerpf(0.38, 0.78, rain))
		_ocean_shader_material.set_shader_parameter("metallic", lerpf(0.06, 0.015, rain))


func _weather_lighting() -> Node:
	return get_node_or_null("/root/WeatherLighting")


func _build_island() -> void:
	# Flat walkable island — top surface at y = 0
	var ground := MeshBuilder.static_box(Vector3(80, 2, 60), C_SAND)
	ground.position = Vector3(0, -1.0, 0)
	add_child(ground)


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
