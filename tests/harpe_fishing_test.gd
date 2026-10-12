extends Node
class DeepSea extends FishingHabitat:
	func bottom(_at: Vector2) -> float:
		return WaveSurface.WATER_LEVEL - 254.0
class Ground extends WorldLayout:
	func sample_height(_p:Vector2)->float:return -40+WorldTerrainStreamer.TERRAIN_SINK_M
	func sample_signed_distance(_p:Vector2)->float:return 500
func _ready()->void:
	var layout:=Ground.new();layout.seed=717
	var habitat:=FishingHabitat.new();habitat.configure(layout)
	var school:Dictionary={}
	for z in range(-1200,1200,160):
		for x in range(-1200,1200,160):
			for candidate in habitat.schools_near(Vector2(x,z),0,100):
				if candidate.species=="cod":school=candidate;break
			if not school.is_empty():break
		if not school.is_empty():break
	assert(not school.is_empty())
	var rig:=HarpeFishingSession.new();rig.phase="fishing";rig.depth_m=float(school.depth_m)+2;rig.reach_m=10
	for i in 160:rig.advance(.05,school.position,0,false,false,habitat,0)
	assert(rig.catches.size()==6,"Six independently occupied hooks")
	var ids:Dictionary={}
	for caught in rig.catches:
		assert(not ids.has(caught.fish_id));ids[caught.fish_id]=true
		assert(float(caught.mass_kg)<=5.0,"Harpe targets lighter fish")
	assert(habitat._hooked.size()==6,"Fish reserved so another hook cannot duplicate them")
	rig.advance(.05,school.position,0,true,false,habitat,0)
	assert(rig.phase=="fighting")
	var caught:Dictionary={}
	for i in 300:
		caught=rig.advance(.05,school.position,0,rig.control<rig.fish_position,rig.control>=rig.fish_position,habitat,0)
		if not caught.is_empty():break
	assert(caught.get("catches",[]).size()==6,"One haul returns six individual specimens")
	rig.recover();assert(habitat._hooked.is_empty(),"Aborted/recovered rigs release reservations")
	# Wrong depth and bottom cannot yield fish, even with six hooks.
	rig.phase="fishing";rig.depth_m=0
	for i in 150:rig.advance(.05,school.position,0,false,false,habitat,0)
	assert(rig.catches.is_empty())
	var heavy:=RodFishingSession.new()
	assert(heavy.drop(40,100));assert(heavy.phase=="fishing" and heavy.charge==0 and heavy.reach_m==0,"Drop skips charging and flight")
	heavy.advance(.5,school.position,0,false,true,habitat,0)
	assert(is_equal_approx(heavy.depth_m,3.0),"Heavy pilk sinks at 6 m/s while RMB held")
	var previous:=heavy.depth_m;heavy.advance(.1,school.position,0,true,false,habitat,0)
	assert(heavy.depth_m<previous,"LMB retrieves")
	var small:=habitat.at_hook(school.position,float(school.depth_m),0,0,5)
	assert(not small.is_empty() and float(small.specimen.mass_kg)<=5)
	var large:=habitat.at_hook(school.position,float(school.depth_m),0,1.5)
	assert(not large.is_empty() and float(large.specimen.mass_kg)>=1.5)
	assert(habitat.at_hook(school.position,float(school.depth_m),0,10000,20000).is_empty(),"Ineligible size does not bite")
	var deep_layout:=Ground.new();deep_layout.seed=717
	var deep:=DeepSea.new();deep.configure(deep_layout)
	var ocean:=HarpeFishingSession.new()
	assert(ocean.drop(254,100),"254 m of water must still take a harpe")
	var seconds:=0.0
	while ocean.depth_m<50 and seconds<30:
		ocean.advance(.5,Vector2.ZERO,3,false,true,deep,0);seconds+=.5
	assert(ocean.phase=="fishing" and ocean.depth_m>=50 and ocean.depth_m<55,"The line can be held around 50 m over a deep seabed")
	while seconds<80:
		ocean.advance(.5,Vector2.ZERO,3,false,true,deep,0);seconds+=.5
	assert(is_equal_approx(ocean.depth_m,180),"The line stops at 180 m instead of following the seabed")
	var shallow:=HarpeFishingSession.new();assert(not shallow.drop(2,100))
	var mid:=false
	for z in range(-320,321,160):
		for x in range(-320,321,160):
			for group in deep.schools_near(Vector2(x,z),0,200):
				assert(float(group.depth_m)<=180,"Deep-water schools stay inside the line")
				if float(group.depth_m)>=20 and float(group.depth_m)<=80: mid=true
	assert(mid,"Fish still occupy the 50 m band when the seabed is far below")
	var record:=CompanyService.build_starter_vessel_record("fishing")
	assert(VesselEquipment.has_mount(record))
	print("HARPE PASS: six unique fish, real school/depth, reservations, continuous haul, recovery, empty surface hooks, mount compatibility")
	get_tree().quit()
