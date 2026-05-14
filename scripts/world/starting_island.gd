@tool
extends Node3D

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")
const BOAT_SCENE   := preload("res://scenes/boats/test_boat.tscn")
const OCEAN_SHADER := preload("res://resources/shaders/ocean_waves.gdshader")
const RAIN_FIELD_SCRIPT := preload("res://scripts/systems/weather/rain_field.gd")
const MOORING_POST_SCRIPT := preload("res://scripts/systems/dock/mooring_post.gd")
const SHIP_SPAWNER_SCRIPT := preload("res://scripts/systems/dock/ship_spawner.gd")
const DOCK_TERMINAL_SCRIPT := preload("res://scripts/systems/dock/dock_terminal.gd")

const C_SAND  := Color(0.82, 0.74, 0.58)
const C_OCEAN := Color(0.10, 0.28, 0.48)
const C_WOOD  := Color(0.32, 0.22, 0.13)
const C_POST  := Color(0.24, 0.16, 0.09)

const BERTH_SHIP_POSITION := Vector3(11.0, WaveSurface.WATER_LEVEL, 47.0)
const DOCK_SURFACE_Y := 0.08
const DOCK_BODY_CENTER_Y := DOCK_SURFACE_Y - 1.0
const DOCK_PILE_CENTER_Y := DOCK_SURFACE_Y - 1.75
const MOORING_FRONT_POST_POSITION := Vector3(7.2, DOCK_SURFACE_Y, 36.5)
const MOORING_REAR_POST_POSITION := Vector3(7.2, DOCK_SURFACE_Y, 57.5)
const TERMINAL_POSITION := Vector3(-2.8, DOCK_SURFACE_Y, 31.5)

var _ocean_shader_material: ShaderMaterial
var _sky_material: ProceduralSkyMaterial
var _environment: Environment
var _sun: DirectionalLight3D
var _ship_spawner: Node3D


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
	_add_dock_section(
		"LoadingApron",
		Vector3(16.0, 2.0, 8.0),
		Vector3(-3.5, DOCK_BODY_CENTER_Y, 31.0)
	)
	_add_dock_section("SideBerth", Vector3(3.2, 2.0, 31.0), Vector3(5.6, DOCK_BODY_CENTER_Y, 45.5))
	_add_dock_section(
		"BerthConnector",
		Vector3(8.0, 2.0, 4.0),
		Vector3(2.8, DOCK_BODY_CENTER_Y, 35.0)
	)

	for z in [31.0, 36.0, 41.0, 46.0, 51.0, 56.0]:
		for x in [4.2, 7.0]:
			_add_support_pile(Vector3(x, DOCK_PILE_CENTER_Y, z))

	var front_post := _add_mooring_post("MooringPostForward", MOORING_FRONT_POST_POSITION)
	var rear_post := _add_mooring_post("MooringPostRear", MOORING_REAR_POST_POSITION)
	_build_ship_spawner(front_post, rear_post)
	_build_dock_terminal()


func _spawn_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	# On the dock walkway (matches _build_dock: 4×14 m, top y=0, z≈30–44).
	# Slightly toward the island (lower z) so you start on planks, not over the boat side.
	player.position = Vector3(0.0, 0.5, 32.5)
	add_child(player)


func _spawn_rain_field() -> void:
	var rain_field := RAIN_FIELD_SCRIPT.new() as Node3D
	rain_field.name = "RainField"
	add_child(rain_field)


func _add_dock_section(
	section_name: String,
	size: Vector3,
	section_position: Vector3,
) -> StaticBody3D:
	var section := MeshBuilder.static_box(size, C_WOOD, 0.92)
	section.name = section_name
	section.position = section_position
	add_child(section)
	return section


func _add_support_pile(pile_position: Vector3) -> void:
	var pile := MeshBuilder.cylinder(0.13, 3.5, C_POST, 0.95)
	pile.name = "DockSupportPile"
	pile.position = pile_position
	add_child(pile)


func _add_mooring_post(post_name: String, post_position: Vector3) -> Node3D:
	var post := MOORING_POST_SCRIPT.new() as Node3D
	post.name = post_name
	post.position = post_position
	add_child(post)
	return post


func _build_ship_spawner(front_post: Node3D, rear_post: Node3D) -> void:
	_ship_spawner = SHIP_SPAWNER_SCRIPT.new() as Node3D
	_ship_spawner.name = "ShipSpawner"
	add_child(_ship_spawner)
	_ship_spawner.set("ship_scene", BOAT_SCENE)
	_ship_spawner.set("spawn_position", BERTH_SHIP_POSITION)
	_ship_spawner.set("front_post_path", _ship_spawner.get_path_to(front_post))
	_ship_spawner.set("rear_post_path", _ship_spawner.get_path_to(rear_post))


func _build_dock_terminal() -> void:
	var terminal := DOCK_TERMINAL_SCRIPT.new() as Node3D
	terminal.name = "DockTerminal"
	terminal.position = TERMINAL_POSITION
	terminal.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	add_child(terminal)
	if _ship_spawner != null:
		terminal.set("spawner_path", terminal.get_path_to(_ship_spawner))
