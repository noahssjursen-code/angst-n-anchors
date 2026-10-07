extends SceneTree
const FAR = preload("res://scripts/world/distant_forest.gd")
class Coast extends RefCounted:
	var half_extent_m := 200.0
	var world_size_m := 400.0
	func sample_signed_distance(p: Vector2) -> float: return -p.x
	func sample_height(_p: Vector2) -> float: return 30.0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := FAR.new();var b := FAR.new()
	var zone := {"center":Vector2(110,0),"half_size":Vector2(35,35),"falloff":0.0}
	for node in [a,b]:
		node.layout=Coast.new();node.cell_m=100.0
		node.coverage=Image.create(4,4,false,Image.FORMAT_R8);node.coverage.fill(Color.WHITE)
		for y in 4:
			for x in 4: node.coverage.set_pixel(x,y,Color(float(x+y)/6.0,0,0))
		# Packed sampling must match Image sampling, including filtered edges.
		if node==a: node.prepare_density_pixels()
		node.zones=[zone]
		for y in 4:
			for x in 4: node.build_cell(Vector2i(x,y))
	var count := 0
	for key in a.batches:
		for species in 4:
			assert(a.batches[key][species] == b.batches[key][species],"World canopy is not deterministic")
			for index in range(0,a.batches[key][species].size(),4):
				var data:PackedFloat32Array=a.batches[key][species]
				var position:=Vector3(data[index],data[index+1],data[index+2])
				count+=1
				assert(position.x>ForestField.MIN_INLAND_M,"Canopy crosses bare shoreline")
				assert(not ForestField.inside_flatten_zones(Vector2(position.x,position.z),[zone]),"Canopy enters cleared port")
	assert(count>200,"Distant forest unexpectedly sparse")
	a.free();b.free()
	# Closing a world during preparation must join its worker and must not
	# publish a partial woodland cache for the next visit.
	var cancelled:=FAR.new()
	cancelled.layout=Coast.new();cancelled.cell_m=100.0
	cancelled.coverage=Image.create(4,4,false,Image.FORMAT_R8);cancelled.coverage.fill(Color.WHITE)
	cancelled.cache_path=OS.get_cache_dir().path_join("forest-cancel-%d.bin" % OS.get_process_id())
	cancelled.cache_key="cancel-test"
	for index in 10000: cancelled.jobs.append(Vector2i(index%4,index/4))
	root.add_child(cancelled)
	cancelled.worker=Thread.new();cancelled.worker.start(cancelled.generate)
	var path:String=cancelled.cache_path
	cancelled.free()
	assert(not FileAccess.file_exists(path),"Cancelled world published incomplete forest")
	print("Persistent canopy placement PASS: deterministic, shoreline and port exclusions; instances=",count)
	quit()
