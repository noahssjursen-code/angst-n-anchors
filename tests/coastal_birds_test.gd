extends Node3D
var errors: Array[String]=[]
func check(ok: bool,message: String) -> void:
	if not ok: errors.append(message);push_error(message)
func _ready() -> void: call_deferred("run")
func run() -> void:
	check(CoastalBirdHabitat.identity(Vector2i(-1,-1))=="-1:-1","Server/client negative cell identity")
	check(CoastalBirdHabitat.anchor(Vector2i(-1,-1)).x==-128,"Shared cell anchor")
	var camera:=Camera3D.new();add_child(camera);camera.current=true
	for species in ["herring_gull","white_tailed_eagle","arctic_tern"]:
		var group:=CoastalBirdGroup.new()
		group.record={"anchor":Vector3.ZERO,"id":"0:0","species":species,"seed":761,"count":3}
		add_child(group)
		check(group.far.multimesh.mesh!=null,"Distant mesh "+species)
		group.set_detail(true)
		group.present(1000,.016);group.present(1000,.016)
		check(group.birds.size()==3,"Detailed model construction "+species)
		group.set_detail(false)
		group.present(1000,.1)
		check(group.birds.is_empty() and group.far.visible,"Detailed model unload "+species)
		group.queue_free()
		var maximum_step:=0.0
		var previous:=CoastalBirdMotion.position_at(761,0,0,species,{})
		for tick in range(1,130001):
			var t:=float(tick)*.01
			var at:=CoastalBirdMotion.position_at(761,0,t,species,{})
			maximum_step=maxf(maximum_step,at.distance_to(previous))
			check(at.is_finite() and at.y>=-0.001,"Finite above-water path "+species)
			previous=at
		check(maximum_step<.7,"Continuous complete lifecycle "+species+" step="+str(maximum_step))
		var event:Dictionary={"id":"0:0","started":1000.0,"until":1060.0}
		var restored:Dictionary=JSON.parse_string(JSON.stringify(event))
		for t in [1000.0,1001.0,1064.0,1068.0,1792000400.0]:
			var a:=CoastalBirdMotion.sample(761,2,t,species,event)
			var b:=CoastalBirdMotion.sample(761,2,t,species,restored)
			check(a.position.is_equal_approx(b.position) and a.stage==b.stage,"Late joining independent client reconstruction")
	for flock_seed in [761,9481,518351]:
		var flight_counts: Array[int]=[]
		for t in [0.0,100.0,300.0,600.0]:
			var flying := 0
			for i in 16:
				var state := CoastalBirdMotion.sample(flock_seed,i,t,"herring_gull")
				if state.stage==GullWaterBehaviour.Stage.FLYING: flying+=1
				check(Vector2(state.position.x,state.position.z).length()<85,"Movement stays in checked habitat")
			flight_counts.append(flying)
		check(flight_counts.any(func(n): return n>0 and n<16),"Flock has independent flying/resting birds")
		for i in 16:
			for j in i:
				check(CoastalBirdMotion.resting_point(flock_seed,i).distance_to(CoastalBirdMotion.resting_point(flock_seed,j))>1.5,"Resting birds retain personal space")
		check(CoastalBirdMotion.flight(flock_seed,0,0,"herring_gull").distance_to(CoastalBirdMotion.flight(flock_seed,0,440,"herring_gull"))>1,"Flight does not repeat former orbit")
	var curious:=CoastalBirdGroup.new()
	curious.record={"anchor":Vector3.ZERO,"id":"0:0","species":"herring_gull","seed":761,"count":8}
	add_child(curious)
	var boat:Dictionary={"id":"test","x":80.0,"z":20.0,"vx":0.0,"vz":0.0,"time":100.0}
	curious.update_interest([boat],100,12)
	check(curious.interest_weight==1,"Nearby vessel attracts gulls")
	var close:=curious.interested_position(0,100)
	check(close.distance_to(Vector3(80,0,20))<45 and close.y>=7,"Stopped boat receives close passes above deck")
	boat.vx=5.0
	curious.update_interest([boat],100,12)
	check(curious.interested_position(0,100).x<80,"Moving vessel gulls trail astern")
	curious.update_interest([boat],120,12)
	check(curious.interest_weight==0,"Expired vessel observations release gulls")
	curious.update_interest([{"id":"steer","x":80.0,"z":20.0,"vx":0.0,"vz":0.0,"time":200.0}],200,5)
	var flight_state:=GullWaterBehaviour.new()
	flight_state.position=Vector3(0,8,0);flight_state.velocity=Vector3(0,0,-5)
	var initial_distance:=flight_state.position.distance_to(Vector3(80,8,20))
	for frame in 1800:
		var before:=flight_state.position
		var before_velocity:=flight_state.velocity
		curious.steer_interest(0,200+float(frame)/60.0,1.0/60.0,flight_state)
		check(flight_state.position.distance_to(before)<0.16,"Approach has no positional jump")
		check(flight_state.velocity.distance_to(before_velocity)<0.051,"Approach respects acceleration limit")
	check(flight_state.position.distance_to(Vector3(80,8,20))<initial_distance*0.6,"Steering actually approaches vessel")
	curious.approach_states.clear()
	var real_boat:=VesselSpawn.instantiate("trawler_hull_14m",JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/fishing_hook_line.json")).brick_layout)
	real_boat.freeze=true
	add_child(real_boat)
	real_boat.global_position=Vector3(5,0,0)
	check(real_boat.is_in_group("wildlife_vessels"),"Real vessel subclass registers without base ready")
	var sensing:=CoastalBirdWorld.new();add_child(sensing)
	var observed:=sensing.scene_observations(200,0.1)
	check(observed.any(func(v):return v.id==str(real_boat.get_instance_id())),"Production sensor sees actual spawned boat")
	curious.last_positions[0]=Vector3.ZERO
	curious.update_interest(observed,200,0.1)
	var resting:=GullWaterBehaviour.new();resting.rest_at(Vector3.ZERO,Vector3.FORWARD)
	curious.apply_threat_response(0,200,resting)
	check(resting.startled and resting.stage==GullWaterBehaviour.Stage.TAKING_OFF,"Real hull near bird interrupts water rest")
	curious.apply_threat_response(0,201,resting)
	check(resting.position.y>2,"Scared bird visibly gains altitude")
	real_boat.queue_free();sensing.queue_free()
	curious.queue_free()
	var layout:=WorldLayoutGenerator.generate(42)
	var found:Dictionary={}
	for x in range(-25,26):
		for z in range(-25,26):
			var item:=CoastalBirdHabitat.record(Vector2i(x,z),layout,[])
			if not item.is_empty(): found=item;break
		if not found.is_empty(): break
	check(not found.is_empty(),"Real seeded coast has valid bird habitat")
	if not found.is_empty():
		camera.position=found.anchor+Vector3(0,30,60)
		var world:=CoastalBirdWorld.new();world.configure(layout,[]);add_child(world)
		await get_tree().process_frame
		await get_tree().process_frame
		check(world.is_processing(),"Gameplay component updates automatically")
		check(world.groups.size()>0 and world.groups.size()<=world.MAX_GROUPS,"Real geography streaming")
		world._stream(Vector3(100000,20,100000))
		check(world.groups.is_empty(),"Distant flocks unload")
		world.queue_free()
	await get_tree().process_frame
	print("COASTAL BIRDS failures=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
