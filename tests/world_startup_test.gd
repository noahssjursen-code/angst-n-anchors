extends Node

func _ready() -> void: call_deferred("run")

func run() -> void:
	var cache_key := "startup-cache-test"
	WorldGenerationCache.write(cache_key,{"value":1})
	WorldGenerationCache.write(cache_key,{"value":2})
	assert(WorldGenerationCache.read(cache_key).get("value")==2,"Cache replacement must work on Windows")
	var path := WorldGenerationCache.DIRECTORY+cache_key.sha256_text()+".bin"
	var damaged := FileAccess.open(path,FileAccess.WRITE)
	damaged.store_var({"key":cache_key,"data":{"value":3},"digest":"invalid"});damaged.close()
	assert(WorldGenerationCache.read(cache_key).is_empty(),"Damaged cache must be ignored")
	DirAccess.remove_absolute(path)
	if OS.get_cmdline_user_args().has("--cache-only"):
		print("STARTUP CACHE REPLACEMENT AND INTEGRITY PASS");get_tree().quit();return
	var config := WorldConfig.resolve(40000,WorldConfig.ARCHETYPE_PATH)
	var seed_value := 424242
	var rng := RandomNumberGenerator.new();rng.seed=seed_value
	var phases := PackedFloat32Array()
	for i in int(config.mainland.coast_harmonics): phases.append(rng.randf()*TAU)
	var shape := {"phases":phases,"offset_m":rng.randf_range(-1100,1100)*WorldConfig.scale_factor(40000),"tilt":rng.randf_range(-.055,.055)}
	var waterways := WorldLayoutGenerator._build_waterways(rng,config,shape,20000)
	var lobes := WorldLayoutGenerator._build_island_lobes(rng,config,20000,shape)
	var parallel := WorldLayoutGenerator._bake_field(seed_value,config,shape,waterways,lobes)
	var serial := WorldLayoutGenerator._bake_field_rows(seed_value,config,shape,waterways,lobes,0,int(config.raster_resolution))
	serial.distances=WorldLayoutGenerator._redistance(serial.distances,int(config.raster_resolution),40000.0/(config.raster_resolution-1))
	assert(parallel.distances==serial.distances and parallel.regions==serial.regions,"Parallel terrain must be bit-identical")
	var layout := WorldLayoutGenerator.generate(seed_value)
	var contours := WorldLayoutGenerator._extract_contours(serial.distances,int(config.raster_resolution),40000)
	assert(layout.layout_checksum==WorldLayoutGenerator._checksum(seed_value,int(config.raster_resolution),40000,serial.distances,serial.regions,contours,waterways),"Cached geography must match original serial generator")
	var defs := CoastalPortPlacer._place_ports_uncached(layout)
	var cached := CoastalPortPlacer.place_ports(layout)
	assert(defs.size()==cached.size())
	for i in defs.size(): assert(defs[i].to_dict()==cached[i].to_dict(),"Cached ports must preserve fresh generation")
	cached[0].development_facilities=true
	assert(not CoastalPortPlacer.place_ports(layout)[0].development_facilities,"Cached port records cannot retain a captain's mutations")
	var scenery := CoastalSettlements.new();add_child(scenery);scenery.set_process(false)
	var records := {"buildings":[],"roads":[],"exclusions":[]}
	for x in [100,15000,30000]: records.buildings.append({"position":Vector3(x,10,100),"kind":"house","paint":0,"yaw":0})
	scenery.configure(layout,records,[])
	scenery._refresh_local_chunks(Vector3.ZERO)
	assert(scenery._jobs.size()==1,"Only nearby settlement detail is queued")
	scenery._build_chunk(scenery._jobs.pop_front())
	assert(scenery._nodes.size()==1)
	scenery._refresh_local_chunks(Vector3(15000,0,0))
	assert(scenery._jobs.size()==1 and scenery._jobs[0].x>50,"Moving streams the new region only")
	assert(scenery._nodes.is_empty(),"Leaving a region unloads its decorative geometry")
	scenery._build_chunk(scenery._jobs.pop_front())
	assert(scenery._nodes.size()==1,"New region builds without retaining old chunks")
	scenery.queue_free()
	var marks := CoastalSeamarks.new();add_child(marks)
	marks.configure_async(layout,defs)
	while marks._worker!=null: await get_tree().create_timer(.05).timeout
	assert(marks.records==CoastalSeamarks.plan(layout,defs),"Worker seamarks match synchronous placement")
	marks.queue_free()
	print("WORLD STARTUP PARITY, CACHE ISOLATION, LOCAL STREAMING AND SEAMARKS PASS")
	get_tree().quit()
