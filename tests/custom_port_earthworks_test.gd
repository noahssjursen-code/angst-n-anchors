extends Node

const Cuts = preload("res://scripts/world/world_terrain_earthworks.gd")
const EarthworkProjection = preload("res://scripts/port/state/custom_port_earthworks.gd")
var checks := 0
var failures: Array[String] = []
var measurements := {}
var catalog := {"tile":{"kind":"platform","footprint_m":[4,4]},
	"triangle":{"kind":"platform","footprint_m":[4,4],"footprint_polygon_m":[[-2,-2],[2,2],[-2,2]]},
	"chamfer":{"kind":"platform","footprint_m":[4,4],"footprint_polygon_m":[[-2,-2],[1,-2],[2,-1],[2,2],[-2,2]]}}

class Hillside extends RefCounted:
	func sample_signed_distance(_point: Vector2) -> float:return -100.0
	func sample_height(point: Vector2) -> float:return 10.0+point.x*.02+point.y*.03+WorldTerrainStreamer.TERRAIN_SINK_M

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_small_shapes()
	_test_boundaries_and_restore()
	await _test_refresh_readiness()
	await _test_real_world()
	for failure in failures:push_error(failure)
	print("CUSTOM PORT EARTHWORKS %s (%d checks) %s"%["PASS" if failures.is_empty() else "FAIL",checks,JSON.stringify(measurements)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_small_shapes() -> void:
	var base:=_quad(0,0,25,25)
	var record:=_record(Vector3(12,.5,12),[_tile("a",0,0)])
	var projection:=EarthworkProjection.project(record,catalog)
	var data:=_cut(base,[projection])
	_check(is_equal_approx(_height(data,Vector2(12,12)),.38),"4m tile cuts a terrain triangle even when no base grid vertex is inside")
	for p in [Vector2(9.99,12),Vector2(14.01,12),Vector2(12,9.99),Vector2(12,14.01),Vector2(2,2)]:
		_check(absf(_height(data,p)-_height(base,p))<.0001,"unbuilt terrain preserves original interpolation at "+str(p))
	_check(_wall_count(data)>0,"excavation has vertical retaining collision faces")
	_check(_area_sum(data)==_area_sum(base),"triangle clipping leaves no holes or duplicate horizontal surfaces")
	_check(_cut(base,[])==base,"no projection leaves arrays byte-for-byte unchanged")
	var changed:=record.duplicate(true)
	changed.revision=7
	changed.receipts={"cargo":{}}
	var same:=EarthworkProjection.project(changed,catalog)
	_check(same.geometry_signature==projection.geometry_signature and same.revision==7,"cargo revision reuses same earthwork geometry")
	changed.placements[0].attributes={"support_depth_m":50}
	_check(EarthworkProjection.project(changed,catalog).geometry_signature==projection.geometry_signature,"support depth does not change surface cutting")
	var adjacent:=record.duplicate(true)
	adjacent.placements.append(_tile("b",4,0))
	data=_cut(base,[EarthworkProjection.project(adjacent,catalog)])
	_check(is_equal_approx(_height(data,Vector2(16,12)),.38),"adjoining tile extends the same deck cut")
	_check(not _wall_on_x(data,14,10.01,13.99),"adjoining tile leaves no buried internal retaining wall")
	var separate:=_record(Vector3(16,.5,12),[_tile("b",0,0)])
	separate.id="second-port"
	data=_cut(base,[projection,EarthworkProjection.project(separate,catalog)])
	_check(not _wall_on_x(data,14,10.01,13.99),"adjoining separate port projections do not leave internal walls")
	var ring:=record.duplicate(true)
	ring.placements=[]
	for x in [-4,0,4]:
		for z in [-4,0,4]:
			if x!=0 or z!=0:ring.placements.append(_tile("%d:%d"%[x,z],x,z))
	data=_cut(base,[EarthworkProjection.project(ring,catalog)])
	_check(absf(_height(data,Vector2(12,12))-_height(base,Vector2(12,12)))<.0001,"unbuilt hole keeps original ground")
	_check(is_equal_approx(_height(data,Vector2(16,12)),.38),"built ring surrounding hole is cut")
	_check(_wall_on_x(data,14,10.01,13.99),"hole boundary has a retaining wall")
	for kind in ["triangle","chamfer"]:
		var angled:=record.duplicate(true)
		angled.placements[0].asset_id=kind
		data=_cut(base,[EarthworkProjection.project(angled,catalog)])
		_check(is_equal_approx(_height(data,Vector2(10.5,13.5)),.38),kind+" actual footprint is cut")
		_check(absf(_height(data,Vector2(13.8,10.2))-_height(base,Vector2(13.8,10.2)))<.0001,kind+" cutaway retains natural terrain")
	var submerged:=_quad(0,0,25,25)
	for i in submerged.vertices.size():submerged.vertices[i].y-=40
	_check(_cut(submerged,[projection])==submerged,"cut-only operation never fills deeper water")
	var crossing:=_quad(0,0,25,25)
	for i in crossing.vertices.size():crossing.vertices[i].y=crossing.vertices[i].x-12
	data=_cut(crossing,[projection])
	_check(absf(_height(data,Vector2(10.5,12))+1.5)<.0001,"height transition preserves terrain below cap")
	_check(is_equal_approx(_height(data,Vector2(13.5,12)),.38),"height transition caps terrain above deck without tilted bridge")

func _test_boundaries_and_restore() -> void:
	var hillside:=Hillside.new()
	var record:=_record(Vector3(1000,.5,512),[_tile("a",0,0)])
	var projection:=EarthworkProjection.project(record,catalog)
	var original:=WorldTerrainStreamer.build_chunk_mesh_data(hillside,Vector2i.ZERO,25,[],0)
	var west:=WorldTerrainStreamer.build_chunk_mesh_data(hillside,Vector2i.ZERO,25,[],0,[projection])
	var east:=WorldTerrainStreamer.build_chunk_mesh_data(hillside,Vector2i(1,0),25,[],0,[projection])
	_check(west.normals.slice(0,original.normals.size())==original.normals,"source smooth normals remain byte-for-byte unchanged outside the clipped footprint")
	_check(west.normals.size()==west.vertices.size(),"split terrain, cap and retaining vertices all carry explicit normals")
	var normal_ok:=true
	var slope_normal:=Vector3(-.02,1,-.03).normalized()
	for i in range(original.vertices.size(),west.vertices.size()):
		var p:Vector3=west.vertices[i]
		var n:Vector3=west.normals[i]
		if p.x>997.99 and p.x<998.01 and n.y>0 and absf(p.y-.38)>.01:
			normal_ok=normal_ok and n.normalized().distance_to(slope_normal)<.001
	_check(normal_ok,"split outside terrain keeps interpolated slope normals instead of faceting")
	for z in [510.1,511,512,513.9]:
		_check(absf(_height(west,Vector2(1000,z))-.38)<.0001 and absf(_height(east,Vector2(1000,z))-.38)<.0001,"cut is continuous across chunk boundary "+str(z))
	_check(not _wall_on_x(west,1000,510.01,513.99) and not _wall_on_x(east,1000,510.01,513.99),"chunk seam is not an exposed port edge")
	_check(WorldTerrainStreamer.build_chunk_mesh_data(hillside,Vector2i.ZERO,25,[],0,[])==original,"undo/removal restores exact original chunk data")
	var collider:=WorldTerrainStreamer.collision_faces(west)
	_check(collider.size()>0,"cut geometry reaches terrain collision source")
	var collision_data:={"vertices":collider,"indices":PackedInt32Array()}
	for i in collider.size():collision_data.indices.append(i)
	_check(absf(_height(collision_data,Vector2(999,512))-.38)<.0001,"collision surface uses same cut as rendered terrain")
	var skirted:=WorldTerrainStreamer.build_chunk_mesh_data(hillside,Vector2i.ZERO,25,[],12,[projection])
	_check(_vertical_top(skirted,1000,512)<=.381,"chunk-border skirt cannot cross the cleared foundation above its cap")

func _test_refresh_readiness() -> void:
	var streamer:=WorldTerrainStreamer.new()
	add_child(streamer)
	streamer.set_process(false)
	streamer._layout=Hillside.new()
	var initial:=EarthworkProjection.project(_record(Vector3(12,.5,12),[_tile("a",0,0)]),catalog)
	var job:={"coord":Vector2i.ZERO,"lod":0,"distance":0.0}
	streamer._queued[Vector2i.ZERO]=0
	streamer._build_task_job=job.duplicate()
	streamer._build_task_job.modifier_revision=0
	streamer._build_task_state={"data":{"indices":PackedInt32Array()},"duration_ms":0.0}
	streamer._build_task_id=WorkerThreadPool.add_task(func():pass)
	streamer.set_custom_port_earthworks([initial])
	_check(streamer._jobs.size()==1 and streamer._jobs[0].coord==Vector2i.ZERO,"first in-flight chunk is requeued after a foundation edit")
	_check(not streamer.is_custom_port_earthworks_ready(),"pending first chunk blocks walking readiness")
	var next:=_record(Vector3(12,.5,12),[_tile("a",0,0),_tile("b",4,0)])
	streamer.set_custom_port_earthworks([EarthworkProjection.project(next,catalog)])
	_check(streamer._jobs.size()==1,"successive construction edits coalesce the same queued chunk")
	while not WorkerThreadPool.is_task_completed(streamer._build_task_id):await get_tree().process_frame
	streamer._process_jobs(Vector3.ZERO)
	_check(streamer._jobs.size()==1 and streamer._chunks.is_empty(),"stale completion preserves replacement request without installing old collision")
	streamer.background_mesh_builds=false
	streamer._process_jobs(Vector3(12,.5,12))
	_check(streamer.is_custom_port_earthworks_ready() and streamer._chunks[Vector2i.ZERO].collision is StaticBody3D,"first current build clears readiness only after real collision installs")
	streamer.set_custom_port_earthworks([initial])
	_check(not streamer.is_custom_port_earthworks_ready() and not streamer._chunk_collision_ready(streamer._chunks[Vector2i.ZERO]),"loaded old terrain collision stays unready during undo rebuild")
	streamer._process_jobs(Vector3(12,.5,12))
	_check(streamer.is_custom_port_earthworks_ready(),"undo rebuild restores walking readiness")
	# Even an unrelated edit advances the global modifier version. A first-time
	# task outside its area still needs a replacement rather than a queued orphan.
	streamer._queued[Vector2i(5,5)]=0
	streamer._build_task_job={"coord":Vector2i(5,5),"lod":0,"modifier_revision":streamer._terrain_modifier_revision}
	streamer._build_task_state={"data":{"indices":PackedInt32Array()},"duration_ms":0.0}
	streamer._build_task_id=WorkerThreadPool.add_task(func():pass)
	streamer.set_custom_port_earthworks([])
	_check(streamer._jobs.any(func(row:Dictionary)->bool:return row.coord==Vector2i(5,5)),"unaffected first-time worker invalidated by global revision is also requeued")
	while not WorkerThreadPool.is_task_completed(streamer._build_task_id):await get_tree().process_frame
	streamer._process_jobs(Vector3.ZERO)
	_check(streamer._jobs.any(func(row:Dictionary)->bool:return row.coord==Vector2i(5,5)),"unaffected stale completion cannot lose queued replacement")
	streamer._clear_chunks()
	streamer.free()

func _test_real_world() -> void:
	var layout:=WorldLayoutGenerator.generate(73119,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,15000)
	var identity:={"seed":layout.seed,"generation_version":WorldLayoutGenerator.GENERATION_VERSION,"checksum":layout.layout_checksum}
	for point in [Vector2(2712,-264),Vector2(76,1668)]:
		var record:=_record(Vector3(point.x,.5,point.y),[_tile("a",0,0)])
		record.world=identity
		var projection:=EarthworkProjection.project(record,catalog)
		var coord:=Vector2i(floori(point.x/1000),floori(point.y/1000))
		var original:=WorldTerrainStreamer.build_chunk_mesh_data(layout,coord,25,[],0)
		var before:=_height(original,point)
		var started:=Time.get_ticks_usec()
		var modified:=WorldTerrainStreamer.build_chunk_mesh_data(layout,coord,25,[],0,[projection])
		measurements[str(point)]={"before_y":before,"after_y":_height(modified,point),"chunk_build_ms":(Time.get_ticks_usec()-started)/1000.0}
		_check(before>10 and absf(_height(modified,point)-.38)<.001,"real steep coast clears buried foundation at "+str(point))
		_check(absf(_height(original,point+Vector2(2.01,0))-_height(modified,point+Vector2(2.01,0)))<.001,"real coast immediately outside foundation is unchanged")
	var actual_catalog:=CustomPortCatalog.definitions()
	var full:=CustomPortExample.build(Vector3(2724,.5,-692),[],identity)
	var started:=Time.get_ticks_usec()
	var full_projection:=EarthworkProjection.project(full,actual_catalog)
	measurements.large_projection_ms=(Time.get_ticks_usec()-started)/1000.0
	var full_base:=WorldTerrainStreamer.build_chunk_mesh_data(layout,Vector2i(2,-1),25,[],0)
	started=Time.get_ticks_usec()
	var stats:=Cuts.apply(full_base.vertices,full_base.colors,full_base.indices,Rect2(2000,-1000,1000,1000),[full_projection])
	measurements.large_cut_ms=(Time.get_ticks_usec()-started)/1000.0
	measurements.large_cut_stats=stats
	measurements.large_footprints=full_projection.footprints.size()
	var steep_full:=full.duplicate(true)
	steep_full.origin_m=[200,.5,200]
	var steep_projection:=EarthworkProjection.project(steep_full,actual_catalog)
	var steep_base:=WorldTerrainStreamer.build_chunk_mesh_data(Hillside.new(),Vector2i.ZERO,25,[],0)
	started=Time.get_ticks_usec()
	var steep_stats:=Cuts.apply(steep_base.vertices,steep_base.colors,steep_base.indices,Rect2(0,0,1000,1000),[steep_projection])
	measurements.large_steep_cut_ms=(Time.get_ticks_usec()-started)/1000.0
	measurements.large_steep_stats=steep_stats
	_check(steep_stats.changed_triangles>20 and steep_stats.retaining_triangles>20,"complete port footprint clips real-sized sloping terrain without skipping dense adjacent tiles")
	var streamer:=WorldTerrainStreamer.new()
	streamer._layout=layout
	streamer.set_custom_port_earthworks([full_projection])
	var version:=streamer._terrain_modifier_revision
	var cargo_revision:=full_projection.duplicate(true)
	cargo_revision.revision+=1
	streamer.set_custom_port_earthworks([cargo_revision])
	_check(streamer._terrain_modifier_revision==version,"stock-only revision does not queue terrain rebuild")
	streamer._queued[Vector2i(2,-1)]=0
	streamer._build_task_job={"coord":Vector2i(2,-1),"lod":0,"modifier_revision":version-1}
	streamer._build_task_state={"data":full_base,"duration_ms":0}
	streamer._build_task_id=WorkerThreadPool.add_task(func():pass)
	while not WorkerThreadPool.is_task_completed(streamer._build_task_id):await get_tree().process_frame
	streamer._process_jobs(Vector3.ZERO)
	_check(streamer._chunks.is_empty() and streamer._queued.has(Vector2i(2,-1)),"stale worker result cannot install old terrain or erase new queued revision")
	streamer.set_custom_port_earthworks([])
	_check(streamer._custom_earthworks.is_empty(),"empty projection removes earthwork layer")
	streamer.visual_radius_m=1000
	streamer._pending_custom_earthwork_chunks[Vector2i(5,5)]=true
	streamer._refresh_requests(Vector3(2500,.5,-500))
	_check(not streamer._pending_custom_earthwork_chunks.has(Vector2i(5,5)),"leaving an unfinished distant chunk releases its readiness blocker")
	streamer.free()

func _record(origin:Vector3,placements:Array)->Dictionary:
	return {"id":"earthwork-test","revision":0,"world":{},"origin_m":[origin.x,origin.y,origin.z],"deck_height_above_sea_m":2,"placements":placements}

func _tile(id:String,x:float,z:float)->Dictionary:
	return {"id":id,"asset_id":"tile","position_m":[x,0,z],"yaw_degrees":0,"attributes":{}}

func _quad(x:float,z:float,width:float,depth:float)->Dictionary:
	var vertices:=PackedVector3Array()
	for p in [Vector2(x,z),Vector2(x+width,z),Vector2(x,z+depth),Vector2(x+width,z+depth)]:vertices.append(Vector3(p.x,10+p.x*.2+p.y*.3,p.y))
	return {"vertices":vertices,"colors":PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE]),"indices":PackedInt32Array([0,1,2,1,3,2])}

func _cut(base:Dictionary,projections:Array)->Dictionary:
	var result:=base.duplicate(true)
	Cuts.apply(result.vertices,result.colors,result.indices,Rect2(-1000,-1000,3000,3000),projections)
	return result

func _height(data:Dictionary,point:Vector2)->float:
	var found:=-INF
	for i in range(0,data.indices.size(),3):
		var tri:=PackedVector3Array([data.vertices[data.indices[i]],data.vertices[data.indices[i+1]],data.vertices[data.indices[i+2]]])
		var planar:=Cuts._xz(tri)
		if absf(Cuts._area(planar))<.00001:continue
		var w:=Cuts._weights(point,tri)
		if minf(w.x,minf(w.y,w.z))>=-.00001:found=maxf(found,Cuts._height_at(point,tri))
	return found

func _wall_count(data:Dictionary)->int:
	var result:=0
	for i in range(0,data.indices.size(),3):
		var tri:=PackedVector3Array([data.vertices[data.indices[i]],data.vertices[data.indices[i+1]],data.vertices[data.indices[i+2]]])
		if absf(Cuts._area(Cuts._xz(tri)))<.00001:result+=1
	return result

func _wall_on_x(data:Dictionary,x:float,z0:float,z1:float)->bool:
	for i in range(0,data.indices.size(),3):
		var a:Vector3=data.vertices[data.indices[i]]
		var b:Vector3=data.vertices[data.indices[i+1]]
		var c:Vector3=data.vertices[data.indices[i+2]]
		if absf(a.x-x)<.0001 and absf(b.x-x)<.0001 and absf(c.x-x)<.0001 and (a.z+b.z+c.z)/3>z0 and (a.z+b.z+c.z)/3<z1:return true
	return false

func _vertical_top(data:Dictionary,x:float,z:float)->float:
	var top:=-INF
	for i in range(0,data.indices.size(),3):
		var a:Vector3=data.vertices[data.indices[i]]
		var b:Vector3=data.vertices[data.indices[i+1]]
		var c:Vector3=data.vertices[data.indices[i+2]]
		if absf(a.x-x)<.0001 and absf(b.x-x)<.0001 and absf(c.x-x)<.0001 and z>minf(a.z,minf(b.z,c.z))+.0001 and z<maxf(a.z,maxf(b.z,c.z))-.0001:
			top=maxf(top,maxf(a.y,maxf(b.y,c.y)))
	return top

func _area_sum(data:Dictionary)->float:
	var area:=0.0
	for i in range(0,data.indices.size(),3):area+=absf(Cuts._area(PackedVector2Array([Vector2(data.vertices[data.indices[i]].x,data.vertices[data.indices[i]].z),Vector2(data.vertices[data.indices[i+1]].x,data.vertices[data.indices[i+1]].z),Vector2(data.vertices[data.indices[i+2]].x,data.vertices[data.indices[i+2]].z)])))
	return area

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
