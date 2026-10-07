class_name DistantForest
extends Node3D
## Persistent world canopy; camera movement never removes part of a woodland.
## Worker reads immutable geography and copied exclusions; it never touches
## scene nodes, GPU resources or the main-thread ForestField zone cache.
## Main-thread uploads combine 4x4 coverage cells per species for culling.
const STEP := 9.0
const CACHE = preload("res://scripts/world/distant_forest_cache.gd")
var cache_path := ""
var cache_key := ""
var cache_hit := false
var prepare_ms := 0
var started_ms := 0
var ready_ms := 0
var layout: Object
var jobs: Array[Vector2i] = []
var coverage: Image
var cell_m: float
var cancel_lock := Mutex.new()
var cancelled := false
var worker: Thread
var zones: Array = []
var trees := 0
var peak_ms := 0.0
var batches: Dictionary = {}
var uploads: Array = []
var meshes: Array[ArrayMesh] = []
func pending() -> int: return 1 if worker != null else uploads.size()
func _exit_tree() -> void:
	cancel_lock.lock();cancelled=true;cancel_lock.unlock()
	if worker != null: worker.wait_to_finish();worker=null
func generate() -> void:
	var started := Time.get_ticks_msec()
	batches = CACHE.read(cache_path, cache_key)
	cache_hit = not batches.is_empty()
	if cache_hit:
		jobs.clear()
		prepare_ms = Time.get_ticks_msec() - started
		return
	for cell in jobs:
		cancel_lock.lock();var stop:=cancelled;cancel_lock.unlock()
		if stop: return
		build_cell(cell)
	jobs.clear()
	CACHE.write(cache_path, cache_key, batches)
	prepare_ms = Time.get_ticks_msec() - started
func configure(source: Object) -> void:
	started_ms=Time.get_ticks_msec()
	layout=source
	coverage=ForestField.coverage_texture().get_image()
	cell_m=layout.world_size_m/coverage.get_width()
	for y in coverage.get_height():
		for x in coverage.get_width():
			# Include neighbouring texels for filtered woodland edges.
			var density:=0.0
			for dz in range(-1,2):
				for dx in range(-1,2):
					density=maxf(density,coverage.get_pixel(clampi(x+dx,0,coverage.get_width()-1),clampi(y+dz,0,coverage.get_width()-1)).r)
			if density>.08: jobs.append(Vector2i(x,y))
	var camera:=get_viewport().get_camera_3d()
	var center:=Vector2.ZERO if camera==null else Vector2(camera.global_position.x,camera.global_position.z)
	jobs.sort_custom(func(a:Vector2i,b:Vector2i): return point(a).distance_squared_to(center)<point(b).distance_squared_to(center))
	zones=ForestField._flatten_zones.duplicate(true)
	cache_path=CACHE.default_path()
	cache_key=CACHE.identity(layout.layout_checksum,layout.seed,layout.world_size_m,coverage.get_data(),zones,STEP,WorldTerrainStreamer.TERRAIN_SINK_M)
	worker=Thread.new();worker.start(generate)
func point(cell: Vector2i) -> Vector2:
	return Vector2(cell)*cell_m-Vector2.ONE*layout.half_extent_m
func density_at(p:Vector2) -> float:
	var uv:Vector2=(p+Vector2.ONE*layout.half_extent_m)/cell_m-Vector2(.5,.5)
	var c:=Vector2i(floori(uv.x),floori(uv.y));var f:=uv-Vector2(c)
	return lerpf(lerpf(coverage.get_pixel(clampi(c.x,0,coverage.get_width()-1),clampi(c.y,0,coverage.get_width()-1)).r,coverage.get_pixel(clampi(c.x+1,0,coverage.get_width()-1),clampi(c.y,0,coverage.get_width()-1)).r,f.x),lerpf(coverage.get_pixel(clampi(c.x,0,coverage.get_width()-1),clampi(c.y+1,0,coverage.get_width()-1)).r,coverage.get_pixel(clampi(c.x+1,0,coverage.get_width()-1),clampi(c.y+1,0,coverage.get_width()-1)).r,f.x),f.y)
func _process(_delta:float) -> void:
	if layout==null or pending()==0 or not ForestTreeMesh.assets_ready(): return
	if meshes.is_empty():
		for species in 4:
			var mesh := ForestTreeMesh.species_mesh(species,false).duplicate() as ArrayMesh
			var material := mesh.surface_get_material(0).duplicate() as ShaderMaterial
			material.set_shader_parameter("forest_world_canopy",1.0)
			mesh.surface_set_material(0,material);meshes.append(mesh)
	var start:=Time.get_ticks_usec()
	if worker != null:
		if worker.is_alive(): return
		worker.wait_to_finish();worker=null;uploads=batches.keys()
	while not uploads.is_empty() and Time.get_ticks_usec()-start<2000:
		upload_batch(uploads.pop_front())
	peak_ms=maxf(peak_ms,(Time.get_ticks_usec()-start)/1000.0)
	if uploads.is_empty(): ready_ms=Time.get_ticks_msec()-started_ms
func build_cell(cell:Vector2i) -> void:
	var key := Vector2i(cell.x/4,cell.y/4)
	if not batches.has(key): batches[key]=[PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	var groups: Array = batches[key]
	var origin:=point(cell)
	var local_zones: Array = []
	for offset in [Vector2.ZERO,Vector2(cell_m,0),Vector2(0,cell_m),Vector2.ONE*cell_m]:
		var p:Vector2=origin+offset
		for zone in WorldTerrainStreamer.zones_intersecting_chunk(zones,Vector2i(floori(p.x/1000),floori(p.y/1000)),1000):
			if not local_zones.has(zone): local_zones.append(zone)
	var count:=ceili(cell_m/STEP)
	var spacing:=cell_m/count
	for y in count:
		for x in count:
			var random:=WorldForestStreamer._hash01(cell.x,cell.y,x,y)
			var p:=origin+Vector2(x+.2+random*.6,y+.2+WorldForestStreamer._hash01(cell.y,cell.x,y,x)*.6)*spacing
			if random>density_at(p) or layout.sample_signed_distance(p)>-22.0: continue
			if ForestField.inside_flatten_zones(p,local_zones): continue
			var height:float=layout.sample_height(p)-WorldTerrainStreamer.TERRAIN_SINK_M
			if height<1.2: continue
			var species:=WorldForestStreamer.coastal_species(layout,p)
			var scale:=lerpf(.8,1.35,WorldForestStreamer._hash01(x,y,cell.y,cell.x))
			# Placement has no rotation: keep four floats instead of Variant transforms.
			groups[species].append_array(PackedFloat32Array([p.x,height,p.y,scale]))
func upload_batch(key:Vector2i) -> void:
	var groups: Array = batches[key]
	for species in 4:
		if groups[species].is_empty(): continue
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=meshes[species];mm.instance_count=groups[species].size()/4
		var data: PackedFloat32Array = groups[species]
		for i in mm.instance_count:
			var base:=i*4
			var scale:=data[base+3]
			mm.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3(scale*1.8,scale,scale*1.8)),Vector3(data[base],data[base+1],data[base+2])))
		var node:=MultiMeshInstance3D.new();node.multimesh=mm
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		trees+=mm.instance_count

	batches.erase(key)
