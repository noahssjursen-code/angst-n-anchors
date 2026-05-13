@tool
extends Node3D

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")
const BOAT_SCENE   := preload("res://scenes/boats/cargo_runner.tscn")

const C_SAND  := Color(0.82, 0.74, 0.58)
const C_OCEAN := Color(0.10, 0.28, 0.48)
const C_WOOD  := Color(0.32, 0.22, 0.13)
const C_POST  := Color(0.24, 0.16, 0.09)


func _ready() -> void:
	# Clear existing generated nodes to avoid duplicates in editor
	for child in get_children():
		if child is MeshInstance3D or child is StaticBody3D or child is WorldEnvironment or child is DirectionalLight3D:
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
	# Must sit at WaveSurface.WATER_LEVEL
	var ocean := MeshBuilder.plane(Vector2(600, 600), C_OCEAN)
	var mat   := ocean.material_override as StandardMaterial3D
	mat.roughness = 0.12
	mat.metallic  = 0.25
	ocean.position = Vector3(0, WaveSurface.WATER_LEVEL, 0)
	add_child(ocean)


func _build_island() -> void:
	# Flat walkable island — top surface at y = 0
	var ground := MeshBuilder.static_box(Vector3(80, 2, 60), C_SAND)
	ground.position = Vector3(0, -1.0, 0)
	add_child(ground)


func _build_dock() -> void:
	# Dock runs south from the island edge (z=30) to z=44 — 14 m long, 4 m wide.
	# The boat is moored alongside on the right (positive-X) side.
	# Top surface at y=0, flush with the island.
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

	# Bollards at the boat-side corners so there's something to read visually
	for bz: float in [31.0, 43.0]:
		var bollard := MeshBuilder.cylinder(0.12, 0.7, C_POST, 0.8)
		bollard.position = Vector3(1.85, 0.35, bz)
		add_child(bollard)


func _spawn_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.5, 0)
	add_child(player)


func _spawn_boat() -> void:
	var boat := BOAT_SCENE.instantiate()
	# Moored alongside the dock on the right (starboard faces dock).
	# x=5 puts the port side ~0.5 m from the dock's right edge (x=2).
	# y=-1.8 is the equilibrium waterline so the boat settles instead of plunging.
	boat.position = Vector3(5.0, -1.8, 37.0)
	add_child(boat)
