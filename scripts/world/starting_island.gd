@tool
extends Node3D

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")
const BOAT_SCENE   := preload("res://scenes/boats/test_boat.tscn")
const OCEAN_SHADER := preload("res://resources/shaders/ocean_waves.gdshader")

const C_SAND  := Color(0.82, 0.74, 0.58)
const C_OCEAN := Color(0.10, 0.28, 0.48)
const C_WOOD  := Color(0.32, 0.22, 0.13)
const C_POST  := Color(0.24, 0.16, 0.09)

var _ocean_shader_material: ShaderMaterial


func _process(_delta: float) -> void:
	if _ocean_shader_material:
		_ocean_shader_material.set_shader_parameter("wave_time", WaveSurface.get_sim_time())
		_ocean_shader_material.set_shader_parameter("wave_intensity", WaveSurface.wave_intensity)
		WaveSurface.sync_ocean_coupling_to_shader(_ocean_shader_material)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventKey and event.pressed):
		return
	var key_event := event as InputEventKey
	match key_event.physical_keycode:
		KEY_UP:
			WaveSurface.bump_wave_intensity(WaveSurface.WAVE_INTENSITY_STEP)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			WaveSurface.bump_wave_intensity(-WaveSurface.WAVE_INTENSITY_STEP)
			get_viewport().set_input_as_handled()
		_:
			pass


func _ready() -> void:
	# Clear existing generated nodes to avoid duplicates in editor
	for child in get_children():
		if (
			child is MeshInstance3D
			or child is StaticBody3D
			or child is WorldEnvironment
			or child is DirectionalLight3D
		):
			child.queue_free()

	_build_sky()
	_build_ocean()
	_build_island()
	_build_dock()
	
	if not Engine.is_editor_hint():
		_spawn_player()
		_spawn_boat()


func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color     = Color(0.26, 0.46, 0.70)
	sky_mat.sky_horizon_color = Color(0.65, 0.78, 0.90)
	sky_mat.ground_bottom_color  = Color(0.16, 0.14, 0.12)
	sky_mat.ground_horizon_color = Color(0.48, 0.44, 0.36)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var environ := Environment.new()
	environ.sky = sky
	environ.background_mode      = Environment.BG_SKY
	environ.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environ.ambient_light_energy = 0.5
	environ.tonemap_mode         = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = environ
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 28, 0)
	sun.light_color    = Color(1.0, 0.94, 0.82)
	sun.light_energy   = 1.8
	sun.shadow_enabled = true
	add_child(sun)


func _build_ocean() -> void:
	# Vertex waves + hull dip match WaveSurface.get_height_at — buoyancy stays in sync.
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


func _build_island() -> void:
	# Flat walkable island — top surface at y = 0
	var ground := MeshBuilder.static_box(Vector3(80, 2, 60), C_SAND)
	ground.position = Vector3(0, -1.0, 0)
	add_child(ground)


func _build_dock() -> void:
	# Dock runs south from the island edge (z=30) to z=44 — 14 m long, 4 m wide.
	var walkway := MeshBuilder.static_box(Vector3(4.0, 2.0, 14.0), C_WOOD, 0.9)
	walkway.position = Vector3(0.0, -1.0, 37.0)
	add_child(walkway)

	# Support piles every 3.5 m
	for i: int in range(4):
		var pz: float = 31.5 + i * 3.5
		for px: float in [-1.7, 1.7]:
			var pile := MeshBuilder.cylinder(0.14, 3.5, C_POST, 0.95)
			pile.position = Vector3(px, -1.75, pz)
			add_child(pile)

	# Bollards
	for bz: float in [31.0, 43.0]:
		var bollard := MeshBuilder.cylinder(0.12, 0.7, C_POST, 0.8)
		bollard.position = Vector3(1.85, 0.35, bz)
		add_child(bollard)


func _spawn_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	# On the dock walkway (matches _build_dock: 4×14 m, top y=0, z≈30–44).
	# Slightly toward the island (lower z) so you start on planks, not over the boat side.
	player.position = Vector3(0.0, 0.5, 32.5)
	add_child(player)


func _spawn_boat() -> void:
	var boat := BOAT_SCENE.instantiate()
	# Moored alongside the dock
	boat.position = Vector3(5.0, -1.8, 37.0)
	add_child(boat)
