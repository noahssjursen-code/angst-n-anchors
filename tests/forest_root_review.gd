extends "res://tests/provision_hoist_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output="C:/Users/noahs/Pictures/machinescreenshots/forest-root-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var layout:=WorldLayoutGenerator.generate(424242)
	ForestField.initialize(layout,424242,[])
	var terrain:=WorldTerrainStreamer.new()
	add_child(terrain)
	terrain.set_process(false)
	var data_by_chunk:Dictionary={}
	var ground_mat:=ShaderMaterial.new()
	ground_mat.shader=preload("res://resources/shaders/terrain.gdshader")
	TerrainSurfaceMaps.bind_to_material(ground_mat,424242)
	ground_mat.set_shader_parameter("forest_map",ForestField.coverage_texture())
	ground_mat.set_shader_parameter("forest_world_half_extent_m",ForestField.world_half_extent_m())
	for z in range(-1,1):
		for x in range(9,12):
			var coord:=Vector2i(x,z)
			var data:=WorldTerrainStreamer.build_chunk_mesh_data(layout,coord,25,[],0)
			data_by_chunk[coord]=data
			var visual:=MeshInstance3D.new()
			visual.mesh=terrain._array_mesh_from_data(data);visual.material_override=ground_mat;add_child(visual)
	ForestTreeMesh.request_assets()
	while not ForestTreeMesh.assets_ready():await get_tree().process_frame
	var groups:Array=[[],[],[],[]]
	var focus_transform:=Transform3D.IDENTITY;var focus_species:=0
	var tree_nodes:Array[Node3D]=[]
	var worst:=0.0;var target:=Vector3.ZERO;var maximum_error:=0.0;var count:=0
	var baseline:=OS.get_cmdline_user_args().has("--baseline-roots")
	for z in range(-1,2):
		for x in range(39,42):
			var transforms:=WorldForestStreamer.build_chunk_transforms(layout,Vector2i(x,z),6.5,1521)
			for transform in transforms:
				var p:=Vector2(transform.origin.x,transform.origin.z)
				var coord:=WorldTerrainStreamer.world_to_chunk(p)
				var data:Dictionary=data_by_chunk[coord]
				var local:Vector2=(p-WorldTerrainStreamer.chunk_origin(coord))/25.0
				var ix:=floori(local.x);var iz:=floori(local.y);var uv:=local-Vector2(ix,iz)
				var a:int=iz*int(data.surface_side)+ix;var b:=a+1;var c:int=a+int(data.surface_side);var d:=c+1
				var verts:PackedVector3Array=data.vertices
				var expected:float=verts[a].y*(1-uv.x-uv.y)+verts[b].y*uv.x+verts[c].y*uv.y if uv.x+uv.y<=1 else verts[b].y*(1-uv.y)+verts[c].y*(1-uv.x)+verts[d].y*(uv.x+uv.y-1)
				maximum_error=maxf(maximum_error,absf(transform.origin.y-expected))
				var old:=WorldTerrainStreamer.sample_terrain_height(layout,p)
				if old-expected>worst:
					worst=old-expected;target=Vector3(p.x,expected,p.y)
					focus_transform=transform;focus_species=WorldForestStreamer.coastal_species(layout,p)
					if baseline:focus_transform.origin.y=old
				if baseline:transform.origin.y=old
				groups[WorldForestStreamer.coastal_species(layout,p)].append(transform)
				count+=1
	assert(maximum_error<.002,"Roots do not match actual terrain triangle vertices")
	assert(count>100 and worst>.5,"Fixture did not reproduce detached roots")
	for species in 4:
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=ForestTreeMesh.species_mesh(species,true);mm.instance_count=groups[species].size()
		for i in mm.instance_count:mm.set_instance_transform(i,groups[species][i])
		var trees:=MultiMeshInstance3D.new();trees.multimesh=mm;add_child(trees);tree_nodes.append(trees)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.4,.5,.6)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.5;env.environment.ambient_light_color=Color(.72,.8,.9);add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.light_energy=1.2;sun.shadow_enabled=true;add_child(sun)
	camera=Camera3D.new();camera.far=5000;add_child(camera);camera.current=true
	await shot("roots-close",target+Vector3(22,10,25),target+Vector3(0,4,0))
	await shot("roots-context",target+Vector3(55,30,65),target+Vector3(0,4,0))
	for tree in tree_nodes:tree.visible=false
	var focus:=MeshInstance3D.new();focus.mesh=ForestTreeMesh.species_mesh(focus_species,true);focus.transform=focus_transform;add_child(focus)
	await shot("root-focus",target+Vector3(12,5,15),target+Vector3(0,2,0))
	print("FOREST ROOT PASS count=",count," old_max_hover_m=",worst," new_max_error_m=",maximum_error," target=",target," baseline=",baseline)
	ForestField.clear()
	get_tree().quit()
