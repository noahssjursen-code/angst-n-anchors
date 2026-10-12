extends Node3D
class Hillside extends RefCounted:
	func sample_signed_distance(p: Vector2) -> float: return -p.y-30.0
	func sample_height(p: Vector2) -> float: return clampf(p.y*.6+15,-20,110)+WorldTerrainStreamer.TERRAIN_SINK_M

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var hill:=Hillside.new()
	var graph:=PortLayoutGraph.new()
	var foundation:={"spine":[[-160,0],[0,0],[160,0]],"town_inland_m":88.0,"dock_reach_m":26.0,"bay_lip_m":6.0,"surface_y_m":2.0}
	var plan:=PortFacilityPlan.build(foundation,{"quay_stations":[]},PortTradeProfile.new(),2)
	graph.initial_attributes={"foundation":foundation,"land_plan":{"facility_plan":plan},"berth_plan":{"quay_stations":[]}}
	var zones:=graph.flatten_zone_records(Vector3.ZERO,0)
	var visual:=PortLayoutGraphVisualizer.new()
	add_child(visual);visual.configure(graph,null)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.32,.4,.19);material.roughness=1
	for coord in [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i.ZERO]:
		var data:=WorldTerrainStreamer.build_chunk_mesh_data(hill,coord,100,zones)
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals;arrays[Mesh.ARRAY_INDEX]=data.indices
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;add_child(node)
	# Root markers expose discrepancies between decoration placement and terrain.
	for x in range(-240,241,40):
		for z in range(120,401,40):
			var p:=Vector2(x,z)
			var node:=MeshInstance3D.new();var cylinder:=CylinderMesh.new()
			cylinder.top_radius=1.5;cylinder.bottom_radius=1.5;cylinder.height=10
			node.mesh=cylinder;node.position=Vector3(x,WorldForestStreamer.sample_root_height(hill,p,zones,{})+5,z);add_child(node)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.45,.62,.75);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;add_child(env)
	var camera:=Camera3D.new();camera.far=4000;add_child(camera);camera.make_current()
	var archive:="C:/Users/noahs/Pictures/machinescreenshots";DirAccess.make_dir_recursive_absolute(archive)
	for pos in [Vector3(400,240,-370),Vector3(240,25,-50)]:
		camera.position=pos;camera.look_at(Vector3(0,25,130))
		await get_tree().create_timer(1).timeout
		await RenderingServer.frame_post_draw
		var path:=archive.path_join("port-steep-grading-%d-%d.png"%[Time.get_unix_time_from_system(),pos.y])
		get_viewport().get_texture().get_image().save_png(path);print("GRADING CAPTURE ",path)
	get_tree().quit()
