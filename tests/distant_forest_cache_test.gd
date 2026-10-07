extends SceneTree
const CACHE=preload("res://scripts/world/distant_forest_cache.gd")
func _initialize() -> void:
	var path:=OS.get_cache_dir().path_join("forest-cache-test-%d.bin" % OS.get_process_id())
	var data:Dictionary={Vector2i(0,1):[PackedFloat32Array([100,30,200,1.2]),PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]}
	var map:=PackedByteArray([10,20,30])
	var key:=CACHE.identity("terrain-a",42,40000,map,[],9,2.5)
	assert(CACHE.write(path,key,data))
	assert(CACHE.read(path,key)==data,"Cache changed tree placements")
	assert(CACHE.write(path,key,data),"Cannot replace existing cache")
	for changed in [CACHE.identity("terrain-b",42,40000,map,[],9,2.5),CACHE.identity("terrain-a",43,40000,map,[],9,2.5),CACHE.identity("terrain-a",42,20000,map,[],9,2.5),CACHE.identity("terrain-a",42,40000,PackedByteArray([11,20,30]),[],9,2.5),CACHE.identity("terrain-a",42,40000,map,[{"center":Vector2.ONE}],9,2.5),CACHE.identity("terrain-a",42,40000,map,[],8,2.5),CACHE.identity("terrain-a",42,40000,map,[],9,3)]:
		assert(CACHE.read(path,changed).is_empty(),"Stale world cache accepted")
	assert(not CACHE.valid({Vector2i.ZERO:[PackedFloat32Array([1]),[],[],[]]}))
	var file:=FileAccess.open(path,FileAccess.READ_WRITE)
	file.seek(file.get_length()-1);file.store_8(255);file.close()
	assert(CACHE.read(path,key).is_empty(),"Corrupt cache accepted")
	file=FileAccess.open(path,FileAccess.WRITE);file.store_string("truncated");file.close()
	assert(CACHE.read(path,key).is_empty(),"Truncated cache accepted")
	assert(CACHE.write(path,key,data),"Cannot recover from broken cache")
	assert(CACHE.read(path,key)==data)
	DirAccess.remove_absolute(path)
	print("Forest cache PASS: exact roundtrip, replace, world/coverage/exclusion/rule invalidation, corruption and truncation recovery")
	quit()
