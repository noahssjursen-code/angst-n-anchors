class_name MenuBackdrop
extends Node3D

## Title waters: one ready-built trawler as the visual hero, camera held close
## on a three-quarter bow so brand UI (left) and hull (right) share a frame.

const VesselSpawnScript := preload("res://scripts/ship/vessel_spawn.gd")
const PrebuiltCatalogScript := preload("res://scripts/ship/prebuilt_vessel_catalog.gd")

const DISPLAY_PREBUILT_ID := "fishing_trawler"
const STRIP_CHILDREN := ["BoatController", "BoatCamera", "BoatAudio"]
const WAREHOUSE_PATH := "res://resources/data/meshes/port_buildings/warehouse_building.json"
const TOWN_PATH := "res://resources/data/meshes/port_buildings/town_building.json"
const HARBOUR_PATH := "res://resources/data/meshes/port_buildings/harbour_master_building.json"
const HARBOUR_SEED := 81427
const HARBOUR_WIDTH := 92.0
const HARBOUR_DEPTH := 104.0
const HARBOUR_ORIGIN_Z := 62.0

var camera: Camera3D

## Start on the port quarter so the bow points into the right half of frame.
var orbit_angle := 4.05
var orbit_speed := 0.006
var orbit_radius := 30.0
var orbit_height := 7.2
var look_at := Vector3(2.5, 2.2, 0.0)
var _target_radius := 30.0
var _target_height := 7.2
var _target_look_at := Vector3(2.5, 2.2, 0.0)
var _orbit_amp := 0.18

var _boat: Node3D
var _display_dock: PortDock
var _boat_base_y := 0.0
var _boat_base_yaw := -PI * 0.5
var _bob_t := 0.0
var _base_orbit_angle := 4.05


func _ready() -> void:
	_configure_weather()
	var renderer_script := load("res://scripts/world/world_renderer.gd")
	if renderer_script != null:
		var renderer: Node3D = renderer_script.new()
		renderer.name = "BackgroundWorldRenderer"
		add_child(renderer)

	camera = Camera3D.new()
	camera.name = "BackgroundCamera"
	camera.current = true
	camera.far = 40000.0
	camera.fov = 42.0
	add_child(camera)

	_build_coastal_harbour()
	_spawn_display_vessel()


func _process(delta: float) -> void:
	orbit_radius = lerpf(orbit_radius, _target_radius, 3.0 * delta)
	orbit_height = lerpf(orbit_height, _target_height, 3.0 * delta)
	look_at = look_at.lerp(_target_look_at, 3.0 * delta)
	_bob_t += delta
	# Slow sway around a locked cinematic angle — not a long empty orbit.
	orbit_angle = _base_orbit_angle + sin(_bob_t * orbit_speed * 40.0) * _orbit_amp
	_bob_display_vessel(delta)
	if camera == null or not is_instance_valid(camera):
		return
	var offset := Vector3(
		cos(orbit_angle) * orbit_radius,
		orbit_height + sin(_bob_t * 0.35) * 0.35,
		sin(orbit_angle) * orbit_radius,
	)
	camera.global_position = look_at + offset
	camera.look_at(look_at, Vector3.UP)


func set_cinematic(_page_name: String) -> void:
	# Page navigation must not kick the camera. The harbour is one continuous
	# title scene; UI changes happen over it without reframing or zooming.
	pass


func _build_coastal_harbour() -> void:
	var harbour := Node3D.new()
	harbour.name = "MenuHarbour"
	harbour.position.z = HARBOUR_ORIGIN_Z
	add_child(harbour)

	# Use the same organic terrain builder as real ports.
	var polygon := IslandMeshBuilder.build_polygon(HARBOUR_WIDTH, HARBOUR_DEPTH, HARBOUR_SEED)
	var ground := MeshInstance3D.new()
	ground.name = "IslandGround"
	ground.mesh = IslandMeshBuilder.to_mesh(
		polygon,
		HARBOUR_WIDTH + PortPlot.PAD_SAFE_MARGIN * 2.0,
		HARBOUR_DEPTH + PortPlot.PAD_SAFE_MARGIN * 2.0,
		HARBOUR_SEED,
		HARBOUR_WIDTH,
		HARBOUR_DEPTH,
	)
	var terrain_material := ShaderMaterial.new()
	terrain_material.shader = load("res://resources/shaders/terrain.gdshader") as Shader
	ground.material_override = terrain_material
	harbour.add_child(ground)

	# Use the real dock builder: quay slab, lip, bollards, apron and gantry.
	# Empty port_id keeps this presentation set out of registries/contracts.
	var dock := PortDock.new()
	dock.name = "PresentationDock"
	dock.port_id = ""
	dock.dock_length = 70.0
	dock.has_fuel_point = false
	dock.max_ship_class = ShipClass.Type.COASTAL_TRADER
	dock.berth_types = [CargoBerthType.Type.GENERAL]
	dock.position = Vector3(0.0, 0.0, -HARBOUR_DEPTH * 0.5)
	harbour.add_child(dock)
	_display_dock = dock

	# Existing in-house port-building meshes, stamped as visual-only scenery.
	_add_cached_building(harbour, WAREHOUSE_PATH, Vector3(-23, 0.0, -24), -0.08)
	_add_cached_building(harbour, HARBOUR_PATH, Vector3(5, 0.0, -22), 0.04)
	_add_cached_building(harbour, TOWN_PATH, Vector3(27, 0.0, -12), -0.05)

	# Use the actual lighthouse model and sweep implementation.
	var lighthouse := LighthouseBuilding.new()
	lighthouse.name = "PresentationLighthouse"
	lighthouse.position = Vector3(40, 0.0, -4)
	harbour.add_child(lighthouse)


func _add_cached_building(parent: Node3D, path: String, pos: Vector3, yaw: float) -> void:
	var visual := ModelCache.instance(path)
	visual.position = pos
	visual.rotation.y = yaw
	parent.add_child(visual)


func _spawn_display_vessel() -> void:
	var entry := _pick_display_entry()
	if entry.is_empty():
		return
	var hull_id := str(entry.get("id", VesselSpawnScript.TRAWLER_SMALL_ID))
	var layout: Dictionary = entry.get("prebuilt_layout", {})
	if typeof(layout) != TYPE_DICTIONARY:
		layout = {}
	var boat := VesselSpawnScript.instantiate(hull_id, layout as Dictionary) as Node3D
	if boat == null:
		return
	boat.name = "MenuDisplayVessel"
	_prepare_display_boat(boat)
	add_child(boat)
	if _display_dock != null:
		var half_beam := 2.5
		if boat is BoatBody:
			half_beam = maxf((boat as BoatBody).hull_size.x * 0.5, 1.0)
		boat.global_transform = _display_dock.get_berth_spawn_transform(0, half_beam)
	else:
		boat.global_position = Vector3(0.0, WaveSurface.WATER_LEVEL, 7.0)
		boat.rotation.y = _boat_base_yaw
	if boat.has_method("place_at_waterline"):
		boat.call("place_at_waterline", WaveSurface.WATER_LEVEL)
	if boat is BoatBody:
		var body := boat as BoatBody
		body.automatic_physics_lod = false
		body.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
		body.freeze = true
	_boat = boat
	_boat_base_y = boat.global_position.y
	_boat_base_yaw = boat.rotation.y
	var height := 4.5
	if boat is BoatBody:
		height = maxf((boat as BoatBody).hull_size.y, 3.0)
	_target_look_at = Vector3(-2.0, height * 0.42, boat.global_position.z - 1.0)
	look_at = _target_look_at


func _pick_display_entry() -> Dictionary:
	var entries: Array = PrebuiltCatalogScript.catalog_entries()
	for raw in entries:
		var entry := raw as Dictionary
		if str(entry.get("prebuilt_id", "")) == DISPLAY_PREBUILT_ID:
			return entry
	if not entries.is_empty():
		return entries[0] as Dictionary
	return {}


func _prepare_display_boat(boat: Node3D) -> void:
	for child_name in STRIP_CHILDREN:
		var n := boat.get_node_or_null(child_name)
		if n != null:
			n.queue_free()
	if boat is BoatBody:
		var body := boat as BoatBody
		body.automatic_physics_lod = false
		body.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.collision_layer = 0
		body.collision_mask = 0
	elif boat is RigidBody3D:
		var rb := boat as RigidBody3D
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.collision_layer = 0
		rb.collision_mask = 0
	if boat.is_in_group("player_boat"):
		boat.remove_from_group("player_boat")


func _bob_display_vessel(delta: float) -> void:
	if _boat == null or not is_instance_valid(_boat):
		return
	_boat.position.y = _boat_base_y + sin(_bob_t * 0.55) * 0.12
	_boat.rotation.y = _boat_base_yaw + sin(_bob_t * 0.09) * 0.03
	_boat.rotation.x = sin(_bob_t * 0.31) * 0.01
	_boat.rotation.z = sin(_bob_t * 0.37) * 0.014


func _configure_weather() -> void:
	var weather_lighting := get_node_or_null("/root/WeatherLighting")
	if weather_lighting == null:
		return
	randomize()
	# Prefer late day / early dusk — flat midnight washes the hull out.
	weather_lighting.set("time_of_day", randf_range(0.58, 0.78))
	weather_lighting.set("cloud_cover", randf_range(0.22, 0.48))
	weather_lighting.set("precipitation", 0.0)
	var breeze := randf_range(0.10, 0.26)
	weather_lighting.set("wind_force", breeze)
	weather_lighting.set("sea_state", breeze * 0.55)
	weather_lighting.set("visibility", 1.0)
