class_name MenuBackdrop
extends Node3D

## A deliberately staged title shot. It is not a miniature game world: no port
## generation, harbour state, NPCs, cargo, or terrain streaming belong here.

const VesselSpawnScript := preload("res://scripts/ship/vessel_spawn.gd")
const PrebuiltCatalogScript := preload("res://scripts/ship/prebuilt_vessel_catalog.gd")

const DISPLAY_PREBUILT_ID := "fishing_trawler"
const STRIP_CHILDREN := ["BoatController", "BoatCamera", "BoatAudio"]
const VESSEL_START_POSITION := Vector3(15.0, 0.0, 7.0)
const CAMERA_POSITION := Vector3(-22.0, 6.8, 29.0)
const CAMERA_TARGET := Vector3(10.0, 2.0, -8.0)
const TITLE_TIME_OF_DAY := 0.02
const TITLE_WORLD_SEED := 81427
const TITLE_WORLD_SIZE_M := 10000.0
const TITLE_COAST_DISTANCE_M := 280.0
const TITLE_TERRAIN_CHUNK_RADIUS := 2
const TITLE_TERRAIN_STEP_M := 100.0

var camera: Camera3D
var _boat: Node3D
var _boat_base_y := 0.0
var _elapsed := 0.0
var _world_clock_was_processing := true


func _ready() -> void:
	_pause_world_clock_for_title()
	_configure_weather()
	_build_ocean()
	_build_distant_coast()
	_spawn_display_vessel()
	_build_camera()


func _process(delta: float) -> void:
	_elapsed += delta
	_animate_display_vessel()
	_lock_title_time()
	if camera == null or not is_instance_valid(camera):
		return
	# A restrained handheld-on-deck drift keeps the image alive without making
	# menu navigation reframe the scene or inducing motion sickness.
	camera.position = CAMERA_POSITION + Vector3(
		sin(_elapsed * 0.075) * 0.28,
		sin(_elapsed * 0.11) * 0.12,
		0.0,
	)
	camera.look_at(CAMERA_TARGET + Vector3(0.0, sin(_elapsed * 0.09) * 0.08, 0.0))


func _exit_tree() -> void:
	var world_clock := get_node_or_null("/root/WorldClock")
	if world_clock != null:
		world_clock.set_process(_world_clock_was_processing)


func set_cinematic(_page_name: String) -> void:
	# Every page shares one locked title composition.
	pass


func _build_ocean() -> void:
	var renderer_script := load("res://scripts/world/world_renderer.gd")
	if renderer_script == null:
		return
	var renderer: Node3D = renderer_script.new()
	renderer.name = "TitleOcean"
	add_child(renderer)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "TitleCamera"
	camera.current = true
	camera.far = 40000.0
	camera.fov = 39.0
	add_child(camera)
	camera.position = CAMERA_POSITION
	camera.look_at(CAMERA_TARGET)


func _build_distant_coast() -> void:
	# The menu only needs one authentic coastline slice. The smallest supported
	# world keeps startup quick while exercising the exact production generator.
	var layout := WorldLayoutGenerator.generate(
		TITLE_WORLD_SEED,
		WorldLayoutGenerator.DEFAULT_CONFIG_PATH,
		TITLE_WORLD_SIZE_M,
	)
	var site := _choose_title_coast_site(layout)
	if site.is_empty():
		return
	var coast_point: Vector2 = site["point"]
	var tangent: Vector2 = site["tangent"]
	var water_direction: Vector2 = site["water_direction"]
	var coast := Node3D.new()
	coast.name = "DistantCoastTerrain"
	add_child(coast)

	var terrain_material := StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.96
	terrain_material.metallic_specular = 0.0
	var center_coord := WorldTerrainStreamer.world_to_chunk(coast_point)
	for chunk_z in range(center_coord.y - TITLE_TERRAIN_CHUNK_RADIUS, center_coord.y + TITLE_TERRAIN_CHUNK_RADIUS + 1):
		for chunk_x in range(center_coord.x - TITLE_TERRAIN_CHUNK_RADIUS, center_coord.x + TITLE_TERRAIN_CHUNK_RADIUS + 1):
			var data := WorldTerrainStreamer.build_chunk_mesh_data(
				layout,
				Vector2i(chunk_x, chunk_z),
				TITLE_TERRAIN_STEP_M,
				[],
				0.0,
			)
			var indices := data["indices"] as PackedInt32Array
			if indices.is_empty():
				continue
			var terrain_piece := MeshInstance3D.new()
			terrain_piece.name = "Terrain_%d_%d" % [chunk_x, chunk_z]
			terrain_piece.mesh = _title_terrain_mesh(data, coast_point, tangent, water_direction)
			terrain_piece.material_override = terrain_material
			terrain_piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			coast.add_child(terrain_piece)

	var lighthouse_source := _find_lighthouse_site(layout, coast_point, tangent, water_direction)
	var lighthouse_delta := lighthouse_source - coast_point
	var lighthouse_position := Vector3(
		lighthouse_delta.dot(tangent),
		layout.sample_height(lighthouse_source) - WorldTerrainStreamer.TERRAIN_SINK_M,
		lighthouse_delta.dot(water_direction) - TITLE_COAST_DISTANCE_M,
	)
	_build_lighthouse(coast, lighthouse_position)


func _choose_title_coast_site(layout: WorldLayout) -> Dictionary:
	var contours := layout.coastline_contours
	if contours.is_empty():
		return {}
	var contour: PackedVector2Array = contours[0]
	for candidate in contours:
		var candidate_contour := candidate as PackedVector2Array
		if candidate_contour.size() > contour.size():
			contour = candidate_contour
	if contour.size() < 5:
		return {}

	var best := {}
	var best_score := -INF
	var stride := maxi(1, contour.size() / 96)
	for index in range(2, contour.size() - 2, stride):
		var point := contour[index]
		if absf(point.x) > layout.half_extent_m * 0.82 or absf(point.y) > layout.half_extent_m * 0.82:
			continue
		var tangent := (contour[index + 2] - contour[index - 2]).normalized()
		if tangent.length_squared() < 0.5:
			continue
		var normal := Vector2(-tangent.y, tangent.x)
		var plus_distance := layout.sample_signed_distance(point + normal * 300.0)
		var minus_distance := layout.sample_signed_distance(point - normal * 300.0)
		var water_direction := normal if plus_distance > minus_distance else -normal
		var inland_height := layout.sample_height(point - water_direction * 700.0)
		var before := (contour[index] - contour[index - 2]).normalized()
		var after := (contour[index + 2] - contour[index]).normalized()
		var smoothness := before.dot(after)
		var score := smoothness * 80.0 - absf(inland_height - 150.0) * 0.28
		if score > best_score:
			best_score = score
			best = {
				"point": point,
				"tangent": tangent,
				"water_direction": water_direction,
			}
	return best


func _title_terrain_mesh(data: Dictionary, coast_point: Vector2, tangent: Vector2, water_direction: Vector2) -> ArrayMesh:
	var source_vertices := data["vertices"] as PackedVector3Array
	var source_normals := data["normals"] as PackedVector3Array
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(source_vertices.size())
	normals.resize(source_normals.size())
	for index in source_vertices.size():
		var source := source_vertices[index]
		var delta := Vector2(source.x, source.z) - coast_point
		vertices[index] = Vector3(
			delta.dot(tangent),
			source.y,
			delta.dot(water_direction) - TITLE_COAST_DISTANCE_M,
		)
		var source_normal := source_normals[index]
		var normal_xz := Vector2(source_normal.x, source_normal.z)
		normals[index] = Vector3(
			normal_xz.dot(tangent),
			source_normal.y,
			normal_xz.dot(water_direction),
		).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _find_lighthouse_site(layout: WorldLayout, coast_point: Vector2, tangent: Vector2, water_direction: Vector2) -> Vector2:
	var along_coast := coast_point + tangent * 150.0
	for raw_inland_distance in [20.0, 35.0, 55.0, 80.0, 120.0]:
		var inland_distance := float(raw_inland_distance)
		var candidate: Vector2 = along_coast - water_direction * inland_distance
		if layout.sample_signed_distance(candidate) < -8.0:
			return candidate
	return coast_point - water_direction * 45.0


func _build_lighthouse(parent: Node3D, position: Vector3) -> void:
	var lighthouse := Node3D.new()
	lighthouse.name = "LighthouseSilhouette"
	lighthouse.position = position
	parent.add_child(lighthouse)

	var tower_material := _material(Color(0.16, 0.17, 0.17), 0.92)
	var dark_material := _material(Color(0.025, 0.03, 0.035), 0.96)
	_add_cylinder(lighthouse, "Tower", 2.2, 1.5, 18.0, Vector3(0.0, 9.0, 0.0), tower_material)
	_add_cylinder(lighthouse, "LanternRoom", 2.25, 2.25, 2.3, Vector3(0.0, 18.6, 0.0), dark_material)
	_add_cylinder(lighthouse, "Roof", 0.25, 2.8, 1.8, Vector3(0.0, 20.55, 0.0), dark_material)

	var beacon := OmniLight3D.new()
	beacon.name = "Beacon"
	beacon.position = Vector3(0.0, 18.7, 0.0)
	beacon.light_color = Color(1.0, 0.73, 0.38)
	beacon.light_energy = 5.0
	beacon.omni_range = 22.0
	beacon.shadow_enabled = false
	lighthouse.add_child(beacon)

	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.48
	lamp_mesh.height = 0.96
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(0.0, 18.7, 0.0)
	var lamp_material := _material(Color(1.0, 0.67, 0.26), 0.25)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.48, 0.12)
	lamp_material.emission_energy_multiplier = 5.0
	lamp.material_override = lamp_material
	lighthouse.add_child(lamp)


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
	boat.name = "DepartingVessel"
	_prepare_display_boat(boat)
	add_child(boat)
	boat.global_position = VESSEL_START_POSITION + Vector3.UP * WaveSurface.WATER_LEVEL
	# Bow is -Z: the vessel is leaving the camera for the open horizon.
	boat.rotation.y = 0.0
	if boat.has_method("place_at_waterline"):
		boat.call("place_at_waterline", WaveSurface.WATER_LEVEL)
	if boat is BoatBody:
		var body := boat as BoatBody
		body.automatic_physics_lod = false
		body.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
		body.freeze = true
	_boat = boat
	_boat_base_y = boat.global_position.y


func _pick_display_entry() -> Dictionary:
	var entries: Array = PrebuiltCatalogScript.for_sale_entries()
	if entries.is_empty():
		entries = PrebuiltCatalogScript.catalog_entries()
	for raw in entries:
		var entry := raw as Dictionary
		if str(entry.get("prebuilt_id", "")) == DISPLAY_PREBUILT_ID:
			return entry
	if not entries.is_empty():
		return entries[0] as Dictionary
	return {}


func _prepare_display_boat(boat: Node3D) -> void:
	for child_name in STRIP_CHILDREN:
		var node := boat.get_node_or_null(child_name)
		if node != null:
			node.queue_free()
	if boat is BoatBody:
		var body := boat as BoatBody
		body.automatic_physics_lod = false
		body.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.collision_layer = 0
		body.collision_mask = 0
	elif boat is RigidBody3D:
		var rigid_body := boat as RigidBody3D
		rigid_body.freeze = true
		rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rigid_body.collision_layer = 0
		rigid_body.collision_mask = 0
	if boat.is_in_group("player_boat"):
		boat.remove_from_group("player_boat")


func _animate_display_vessel() -> void:
	if _boat == null or not is_instance_valid(_boat):
		return
	_boat.position.y = _boat_base_y + sin(_elapsed * 0.55) * 0.10
	_boat.rotation.x = sin(_elapsed * 0.31) * 0.008
	_boat.rotation.z = sin(_elapsed * 0.37) * 0.012


func _pause_world_clock_for_title() -> void:
	var world_clock := get_node_or_null("/root/WorldClock")
	if world_clock == null:
		return
	_world_clock_was_processing = world_clock.is_processing()
	world_clock.set_process(false)


func _lock_title_time() -> void:
	var weather_lighting := get_node_or_null("/root/WeatherLighting")
	if weather_lighting == null:
		return
	if absf(float(weather_lighting.get("time_of_day")) - TITLE_TIME_OF_DAY) > 0.0001:
		weather_lighting.set("time_of_day", TITLE_TIME_OF_DAY)


func _add_cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 20
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _material(color: Color, roughness: float, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = false
	return material


func _configure_weather() -> void:
	var weather_lighting := get_node_or_null("/root/WeatherLighting")
	if weather_lighting == null:
		return
	weather_lighting.set("time_of_day", TITLE_TIME_OF_DAY)
	weather_lighting.set("cloud_cover", 0.60)
	weather_lighting.set("precipitation", 0.035)
	weather_lighting.set("wind_force", 0.22)
	weather_lighting.set("sea_state", 0.16)
	weather_lighting.set("visibility", 0.78)
