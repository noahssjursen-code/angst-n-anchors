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
var density_pixels:=PackedFloat32Array()
var verify_cache:=false
var cell_m: float
var cancel_lock := Mutex.new()
var cancelled := false
var worker: Thread
var zones: Array = []
## Worker-private spatial cache. Settlement roads add many small exclusions;
## scanning the whole world's list for every coverage cell is unnecessary.
var zone_chunks: Dictionary = {}
var trees := 0
var peak_ms := 0.0
var batches: Dictionary = {}
var completed_lock := Mutex.new()
var completed_batches: Array = []
var display_batches: Dictionary = {}
var focus_xz := Vector2.ZERO
var uploads: Array = []
var meshes: Array[ArrayMesh] = []
## Late bridge corridors stay on the main thread. The immutable worker and
## its reusable cache need not be cancelled or regenerated for these cuts.
var late_exclusions: Array = []
var exclusion_jobs: Array[Dictionary] = []

func add_exclusions(added: Array) -> void:
	late_exclusions.append_array(added)
	for child in get_children():
		if not child is MultiMeshInstance3D: continue
		var box: AABB = child.multimesh.get_aabb()
		var bounds: Rect2 = child.get_meta("forest_bounds",Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)))
		var local_zones: Array = []
		for zone in added:
			if bounds.intersects(WorldTerrainStreamer._zone_influence_bounds(zone), true):
				local_zones.append(zone)
		if not local_zones.is_empty():
			exclusion_jobs.append({"node":child,"zones":local_zones,"index":0,"kept":[]})

func _process_exclusions() -> void:
	if exclusion_jobs.is_empty(): return
	var job := exclusion_jobs[0]
	var node: MultiMeshInstance3D = job.node
	var mm := node.multimesh
	var end := mini(int(job.index)+256,mm.instance_count)
	for i in range(int(job.index),end):
		var xf := mm.get_instance_transform(i)
		if not ForestField.inside_flatten_zones(Vector2(xf.origin.x,xf.origin.z),job.zones):
			job.kept.append(xf)
	job.index=end
	if end < mm.instance_count: return
	trees -= mm.instance_count-job.kept.size()
	mm.instance_count=job.kept.size()
	for i in job.kept.size(): mm.set_instance_transform(i,job.kept[i])
	exclusion_jobs.pop_front()
func pending() -> int: return 1 if worker != null else uploads.size()
func _exit_tree() -> void:
	cancel_lock.lock();cancelled=true;cancel_lock.unlock()
	if worker != null: worker.wait_to_finish();worker=null
func generate() -> void:
	var started := Time.get_ticks_msec()
	batches = CACHE.read(cache_path, cache_key)
	var reference:Dictionary=batches if verify_cache else {}
	if verify_cache: batches={}
	cache_hit = not batches.is_empty()
	if cache_hit:
		jobs.clear()
		prepare_ms = Time.get_ticks_msec() - started
		return
	# Publish complete spatial batches near the spawn first. Previously even
	# the first visible tree waited for every coverage cell across the world.
	var grouped := {}
	for cell in jobs:
		var key := Vector2i(cell.x/4,cell.y/4)
		if not grouped.has(key): grouped[key]=[]
		grouped[key].append(cell)
	var ordered := grouped.keys()
	ordered.sort_custom(func(a:Vector2i,b:Vector2i):
		return point(a*4+Vector2i(2,2)).distance_squared_to(focus_xz)<point(b*4+Vector2i(2,2)).distance_squared_to(focus_xz))
	for key in ordered:
		for cell in grouped[key]:
			cancel_lock.lock();var stop:=cancelled;cancel_lock.unlock()
			if stop: return
			build_cell(cell)
		completed_lock.lock()
		completed_batches.append({"key":key,"groups":batches[key]})
		completed_lock.unlock()
	jobs.clear()
	if verify_cache:
		assert(not reference.is_empty() and batches==reference,"Forest optimization changed cached placements")
		print("FOREST CACHE PARITY PASS: all world placements/species/scales unchanged")
	CACHE.write(cache_path, cache_key, batches)
	prepare_ms = Time.get_ticks_msec() - started
func configure(source: Object, focus: Vector3 = Vector3.ZERO) -> void:
	started_ms=Time.get_ticks_msec()
	verify_cache=ShipyardPlaytestMode.active() and OS.get_cmdline_user_args().has("--verify-forest-cache")
	layout=source
	focus_xz=Vector2(focus.x,focus.z)
	coverage=ForestField.coverage_texture().get_image()
	prepare_density_pixels()
	cell_m=layout.world_size_m/coverage.get_width()
	for y in coverage.get_height():
		for x in coverage.get_width():
			# Include neighbouring texels for filtered woodland edges.
			var density:=0.0
			for dz in range(-1,2):
				for dx in range(-1,2):
					density=maxf(density,coverage.get_pixel(clampi(x+dx,0,coverage.get_width()-1),clampi(y+dz,0,coverage.get_width()-1)).r)
			if density>.08: jobs.append(Vector2i(x,y))
	zones=ForestField._flatten_zones.duplicate(true)
	cache_path=CACHE.default_path()
	cache_key=CACHE.identity(layout.layout_checksum,layout.seed,layout.world_size_m,coverage.get_data(),zones,STEP,WorldTerrainStreamer.TERRAIN_SINK_M)
	worker=Thread.new();worker.start(generate)
func point(cell: Vector2i) -> Vector2:
	return Vector2(cell)*cell_m-Vector2.ONE*layout.half_extent_m
func prepare_density_pixels() -> void:
	density_pixels.resize(coverage.get_width()*coverage.get_height())
	for y in coverage.get_height():
		for x in coverage.get_width():
			density_pixels[y*coverage.get_width()+x]=coverage.get_pixel(x,y).r
func density_pixel(x:int,y:int) -> float:
	x=clampi(x,0,coverage.get_width()-1);y=clampi(y,0,coverage.get_height()-1)
	if density_pixels.is_empty(): return coverage.get_pixel(x,y).r
	return density_pixels[y*coverage.get_width()+x]
func density_at(p:Vector2) -> float:
	var uv:Vector2=(p+Vector2.ONE*layout.half_extent_m)/cell_m-Vector2(.5,.5)
	var c:=Vector2i(floori(uv.x),floori(uv.y));var f:=uv-Vector2(c)
	return lerpf(lerpf(density_pixel(c.x,c.y),density_pixel(c.x+1,c.y),f.x),lerpf(density_pixel(c.x,c.y+1),density_pixel(c.x+1,c.y+1),f.x),f.y)
func _process(_delta:float) -> void:
	_process_exclusions()
	if layout==null or pending()==0 or not ForestTreeMesh.assets_ready(): return
	if meshes.is_empty():
		for species in 4:
			var mesh := ForestTreeMesh.species_mesh(species,false).duplicate() as ArrayMesh
			var material := mesh.surface_get_material(0).duplicate() as ShaderMaterial
			material.set_shader_parameter("forest_world_canopy",1.0)
			mesh.surface_set_material(0,material);meshes.append(mesh)
	var start:=Time.get_ticks_usec()
	if worker != null:
		completed_lock.lock()
		var completed := completed_batches
		completed_batches=[]
		completed_lock.unlock()
		for batch in completed:
			display_batches[batch.key]=batch.groups
			uploads.append(batch.key)
		if not worker.is_alive():
			worker.wait_to_finish();worker=null
			# Drain anything published between the queue swap and joining.
			for batch in completed_batches:
				display_batches[batch.key]=batch.groups
				uploads.append(batch.key)
			completed_batches=[]
			if cache_hit:
				display_batches=batches.duplicate()
				uploads=batches.keys()
				uploads.sort_custom(func(a:Vector2i,b:Vector2i):
					return point(a*4+Vector2i(2,2)).distance_squared_to(focus_xz)<point(b*4+Vector2i(2,2)).distance_squared_to(focus_xz))
			batches={}
	while not uploads.is_empty() and Time.get_ticks_usec()-start<2000:
		upload_batch(uploads.pop_front())
	peak_ms=maxf(peak_ms,(Time.get_ticks_usec()-start)/1000.0)
	if uploads.is_empty() and worker==null: ready_ms=Time.get_ticks_msec()-started_ms
func build_cell(cell:Vector2i) -> void:
	var key := Vector2i(cell.x/4,cell.y/4)
	if not batches.has(key): batches[key]=[PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	var groups: Array = batches[key]
	var origin:=point(cell)
	var bounds := Rect2(origin,Vector2.ONE*cell_m)
	var local_zones: Array = []
	var visited := {}
	for offset in [Vector2.ZERO,Vector2(cell_m,0),Vector2(0,cell_m),Vector2.ONE*cell_m]:
		var p:Vector2=origin+offset
		var coord := Vector2i(floori(p.x/1000),floori(p.y/1000))
		if visited.has(coord): continue
		visited[coord] = true
		if not zone_chunks.has(coord):
			zone_chunks[coord] = WorldTerrainStreamer.zones_intersecting_chunk(zones,coord,1000)
		for zone in zone_chunks[coord]:
			var influence := WorldTerrainStreamer._zone_influence_bounds(zone)
			if influence.size != Vector2.ZERO and not influence.intersects(bounds,true): continue
			if not local_zones.has(zone): local_zones.append(zone)
	var terrain_samples := {}
	var count:=ceili(cell_m/STEP)
	var spacing:=cell_m/count
	for y in count:
		for x in count:
			var random:=WorldForestStreamer._hash01(cell.x,cell.y,x,y)
			var p:=origin+Vector2(x+.2+random*.6,y+.2+WorldForestStreamer._hash01(cell.y,cell.x,y,x)*.6)*spacing
			if random>density_at(p): continue
			var inland:float=-layout.sample_signed_distance(p)
			if inland<ForestField.MIN_INLAND_M: continue
			if ForestField.inside_flatten_zones(p,local_zones): continue
			var natural_height:float=layout.sample_height(p)
			var height:=natural_height-WorldTerrainStreamer.TERRAIN_SINK_M
			if not local_zones.is_empty():
				height=WorldForestStreamer.sample_root_height(layout,p,local_zones,terrain_samples)
			if height<1.2: continue
			var species:=WorldForestStreamer.coastal_species_from_samples(p,inland,natural_height)
			var scale:=lerpf(.8,1.35,WorldForestStreamer._hash01(x,y,cell.y,cell.x))
			# Placement has no rotation: keep four floats instead of Variant transforms.
			groups[species].append_array(PackedFloat32Array([p.x,height,p.y,scale]))
func upload_batch(key:Vector2i) -> void:
	var groups: Array = display_batches[key].duplicate()
	var bounds := Rect2(Vector2(key)*cell_m*4-Vector2.ONE*layout.half_extent_m,Vector2.ONE*cell_m*4)
	var local_zones: Array = []
	for zone in late_exclusions:
		if bounds.intersects(WorldTerrainStreamer._zone_influence_bounds(zone),true): local_zones.append(zone)
	for species in 4:
		if not local_zones.is_empty():
			groups[species] = filter_placements(groups[species],local_zones)
		if groups[species].is_empty(): continue
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=meshes[species];mm.instance_count=groups[species].size()/4
		var data: PackedFloat32Array = groups[species]
		for i in mm.instance_count:
			var base:=i*4
			var scale:=data[base+3]
			mm.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3(scale*1.8,scale,scale*1.8)),Vector3(data[base],data[base+1],data[base+2])))
		var node:=MultiMeshInstance3D.new();node.multimesh=mm
		node.set_meta("forest_bounds",bounds)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		trees+=mm.instance_count

	display_batches.erase(key)

static func filter_placements(data: PackedFloat32Array, exclusions: Array) -> PackedFloat32Array:
	var kept := PackedFloat32Array()
	for i in range(0,data.size(),4):
		if not ForestField.inside_flatten_zones(Vector2(data[i],data[i+2]),exclusions):
			kept.append_array(data.slice(i,i+4))
	return kept
