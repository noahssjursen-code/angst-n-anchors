extends Node3D
## Identical authored floor/roof at origin and real-world distance, without ships.
var camera:Camera3D
var assembly:Node3D
var output:String
var checks:Array[Dictionary]=[]
var failures:Array[String]=[]

func check(ok:bool,description:String) -> void:
	checks.append({"ok":ok,"check":description})
	print("SURFACE PRECISION ","PASS " if ok else "FAIL ",description)
	if not ok:failures.append(description)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("review")

func review() -> void:
	output="C:/Users/noahs/Pictures/machinescreenshots/surface-precision-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	verify_geometry()
	check(checks.size()==19,"all geometry checks ran without an interrupted fixture")
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.4,.52,.65)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy=.6
	add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-25,0);light.light_energy=1.4;add_child(light)
	camera=Camera3D.new();camera.fov=65;add_child(camera);camera.make_current()
	for style:String in ["floor","roof"]:
		var record:Dictionary={"asset_id":style+"_tile","outline":[[-4,-4],[4,-4],[4,4],[-4,4]],"crown":style=="roof","visor_direction":0}
		var start:=Time.get_ticks_usec()
		assembly=ShipSurfaceKit.create(record,true,not OS.get_cmdline_user_args().has("--unbatched"))
		print("SURFACE BUILD ",style," ",(Time.get_ticks_usec()-start)/1000.0,"ms meshes=",SurfaceMaterialLibrary.meshes(assembly).size())
		add_child(assembly)
		ModelPaint.apply(assembly,{"surface":Color(.1,.13,.14),"fascia":Color(.84,.84,.8),"underside":Color(.84,.84,.8)})
		for offset:Vector3 in [Vector3.ZERO,Vector3(12500,10,-13800)]:
			assembly.position=offset;assembly.rotation=Vector3(.05,.74,.03)
			camera.position=assembly.to_global(Vector3(2,1.65,3))
			camera.look_at(assembly.to_global(Vector3(0,0,-1)),assembly.global_basis.y)
			for frame in 25:await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var tag:=style+("-origin" if offset==Vector3.ZERO else "-far")
			get_viewport().get_texture().get_image().save_png(output.path_join(tag+".png"))
		assembly.free()
	print("SURFACE PRECISION REVIEW ",output)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cache_bytes":ShipSurfaceKit._infill_cache_bytes},"\t"))
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_geometry() -> void:
	var polygons:Array=[
		[[-2,-2],[2,-2],[2,2],[-2,2]],
		[[-1,-1],[1,-1],[1,0],[0,0],[0,1],[-1,1]],
		[[-1.5,2],[1.5,2],[1.5,-.5],[1,-1.5],[.5,-2],[-.5,-2],[-1,-1.5],[-1.5,-.5]]]
	for style:String in ["floor","roof"]:
		for index in polygons.size():
			var record:Dictionary={"asset_id":style+"_tile","outline":polygons[index],"crown":index!=1,"visor_direction":index+1}
			var original:=ShipSurfaceKit.create(record,false,false)
			var merged:=ShipSurfaceKit.create(record)
			check(corners(original)==corners(merged),style+" footprint/crown/paint-region triangle corners retained "+str(index))
			var second:=ShipSurfaceKit.create(record)
			check(merged.get_node("AuthoredInfill").mesh==second.get_node("AuthoredInfill").mesh,style+" repeated assembly shares baked geometry "+str(index))
			ModelPaint.apply(merged,{"surface":Color.RED});ModelPaint.apply(second,{"surface":Color.BLUE})
			var independent:=false
			for a:MeshInstance3D in SurfaceMaterialLibrary.meshes(merged):
				if a.get_parent()!=merged:continue
				var b:=second.get_node(merged.get_path_to(a)) as MeshInstance3D
				for surface in a.mesh.get_surface_count():
					if a.mesh.surface_get_material(surface).resource_name.begins_with("Paint_Surface"):
						independent=SurfaceMaterialLibrary.colour_of(a.get_active_material(surface))==Color.RED and SurfaceMaterialLibrary.colour_of(b.get_active_material(surface))==Color.BLUE
			check(independent,style+" cached geometry retains independent paint "+str(index))
			original.free();merged.free();second.free()
	check(ShipSurfaceKit._infill_cache_bytes<=ShipSurfaceKit.INFILL_CACHE_BYTES,"geometry cache bounded")

func corners(root:Node3D) -> Dictionary:
	var result:Dictionary={}
	var inspector:=ImportedShipPartsEditor.new()
	for node in SurfaceMaterialLibrary.meshes(root):
		var mesh:=node as MeshInstance3D
		var pose:=mesh.transform;var parent:=mesh.get_parent()
		while parent!=root:
			if parent is Node3D:pose=parent.transform*pose
			parent=parent.get_parent()
		for surface in mesh.mesh.get_surface_count():
			var material_name:=mesh.mesh.surface_get_material(surface).resource_name.get_slice(".",0)
			var counts:Dictionary=result.get_or_add(material_name,{})
			var vertices:=inspector.deformed_vertices(mesh,surface)
			var indices:PackedInt32Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for i in vertices.size():indices.append(i)
			for i in indices:
				var key:=Vector3i((pose*vertices[i]*10000).round())
				counts[key]=int(counts.get(key,0))+1
	inspector.free()
	return result
