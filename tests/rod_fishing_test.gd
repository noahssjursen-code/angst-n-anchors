extends Node
class Ground extends WorldLayout:
	func sample_height(p:Vector2)->float:return -35+sin(p.x/120)*7+WorldTerrainStreamer.TERRAIN_SINK_M
	func sample_signed_distance(_p:Vector2)->float:return 500
class LayeredGround extends FishingHabitat:
	var probes:=0
	func bottom(_at:Vector2)->float:return WaveSurface.WATER_LEVEL-35
	func schools_near(_at:Vector2,_hours:float,_radius:float=200)->Array:
		probes+=1
		return [{"id":"surface","species":"mackerel","depth_m":5.0},{"id":"bottom","species":"cod","depth_m":30.0}]
	func at_hook(at:Vector2,depth:float,hours:float,_min_kg:float=0.0,_max_kg:float=INF)->Dictionary:
		for school:Dictionary in schools_near(at,hours,0):
			if absf(depth-float(school.depth_m))<5:return school
		return {}
func _ready()->void:
	var layered:=LayeredGround.new()
	var deep:=RodFishingSession.new();deep.begin_charge();assert(deep.cast(35,100,20))
	deep.advance(1,Vector2.ZERO,0,false,false,layered,0)
	for i in 30:deep.advance(.025,Vector2.ZERO,0,false,false,layered,0)
	assert(deep.depth_m==0 and deep.phase=="fishing","Neither button must hold the line")
	for i in 80:deep.advance(.025,Vector2.ZERO,0,false,true,layered,0)
	assert(is_equal_approx(deep.depth_m,12) and deep.reach_m==20,"RMB pays out instead of recovering")
	for i in 20:deep.advance(.025,Vector2.ZERO,0,false,false,layered,0)
	assert(is_equal_approx(deep.depth_m,12),"Releasing RMB stops payout")
	for i in 20:deep.advance(.025,Vector2.ZERO,0,true,false,layered,0)
	assert(is_equal_approx(deep.depth_m,9),"LMB reels only while held")
	for i in 20:deep.advance(.025,Vector2.ZERO,0,true,true,layered,0)
	assert(is_equal_approx(deep.depth_m,9),"Opposing inputs hold instead of fighting")
	for i in 300:
		deep.advance(.025,Vector2.ZERO,0,false,true,layered,0)
		if deep.depth_m>=30:break
	for i in 400:
		deep.advance(.025,Vector2.ZERO,0,false,false,layered,0)
		if deep.phase=="bite":break
	assert(deep.phase=="bite" and deep._school.id=="bottom","Paying out past surface fish must reach cod")
	assert(layered.probes<80,"Habitat sampling is bounded, not every physics tick")
	var retrieve:=RodFishingSession.new();retrieve.begin_charge();retrieve.cast(35,100,12)
	retrieve.advance(1,Vector2.ZERO,0,false,false,layered,0)
	for i in 40:retrieve.advance(.025,Vector2.ZERO,0,true,false,layered,0)
	assert(retrieve.phase=="fishing" and is_equal_approx(retrieve.reach_m,6),"Short hold must retrieve part of line")
	for i in 80:retrieve.advance(.025,Vector2.ZERO,0,true,false,layered,0)
	assert(retrieve.phase=="stowed","Full manual retrieval recovers the tackle")
	# All fight inputs have identical haul speed; RMB cannot unwind the catch.
	for buttons in [[false,false],[true,false],[false,true],[true,true]]:
		var fight:=RodFishingSession.new()
		fight.phase="fighting";fight.progress=0;fight._flight_depth=100;fight.depth_m=100
		fight.catch_data={"species_id":"cod","mass_kg":4.0}
		fight.advance(.1,Vector2.ZERO,0,buttons[0],buttons[1],layered,0)
		assert(is_equal_approx(fight.progress,.1/7.1),"Every fight input must advance the same constant haul")
		assert(fight.depth_m<100,"Giving line must still bring hooked fish up")
	for buttons in [[false,false],[true,false],[false,true]]:
		var missed:=RodFishingSession.new()
		missed.phase="fighting";missed.progress=0;missed.control=.15
		missed.catch_data={"species_id":"halibut","mass_kg":40.0}
		for tick in 600:
			missed.advance(1.0/60,Vector2.ZERO,0,buttons[0],buttons[1],layered,0)
			if missed.phase!="fighting":break
		assert(missed.phase=="stowed" and "snapped" in missed.message,"Ignoring the white bar must snap the line, including RMB")
	var layout:=Ground.new();layout.seed=717
	var habitat:=FishingHabitat.new();habitat.configure(layout)
	var found:Dictionary={}
	for z in range(-1200,1200,160):
		for x in range(-1200,1200,160):
			for school:Dictionary in habitat.schools_near(Vector2(x,z),0,100):found[school.species]=school
	assert(found.size()==6,"All six species must have reachable grounds")
	var rng:=RandomNumberGenerator.new();rng.seed=81
	for id in FishCatalog.fish_ids():
		var s:Dictionary=found[id]
		var member:Dictionary=habitat.members(s,0)[0]
		var at:=Vector2(member.position.x,member.position.z)
		var session:=RodFishingSession.new()
		session.begin_charge();assert(not session.cast(1,100))
		session.begin_charge();assert(not session.cast(40,0))
		session.begin_charge();assert(session.cast(40,100))
		# Simulate the lure reaching this school; no catch exists until strike and fight.
		session.phase="fishing";session.depth_m=WaveSurface.WATER_LEVEL-member.position.y
		for tick in 150:
			session.advance(.1,at,0,false,false,habitat,0)
			if session.phase=="bite":break
		assert(session.phase=="bite")
		for tick in 34:session.advance(.1,at,0,false,false,habitat,0)
		assert(session.phase=="fishing","Missed bite cannot award catch")
		for tick in 150:
			session.advance(.1,at,0,false,false,habitat,0)
			if session.phase=="bite":break
		session.strike(0)
		var caught:Dictionary={}
		for tick in 480:
			caught=session.advance(.025,at,0,session.control<session.fish_position,session.control>=session.fish_position,habitat,0)
			if not caught.is_empty():break
		assert(not caught.is_empty(),"Controlled fight must land a fish in at most 12 seconds")
		assert(caught.specimen and caught.length_cm>0 and caught.mass_kg>0)
		var fish:=FishCatalog.model(id);assert(fish!=null and not fish.find_children("*","MeshInstance3D",true,false).is_empty())
		add_child(fish)
		var mouth:=fish.find_child("MouthHook",true,false) as Node3D
		assert(mouth!=null,"Every species must have its own authored mouth socket")
		var socket:=fish.to_local(mouth.global_position)
		for size_m in [.25,1.0,1.5]:
			for direction:Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3(1,2,-3).normalized()]:
				var endpoint:=Vector3(105,3,-213)
				fish.global_transform=FishCatalog.hooked_transform(endpoint,endpoint+direction*10,socket,size_m,.17)
				assert(mouth.global_position.distance_to(endpoint)<.001,"Line attaches to lip at every specimen scale")
				assert(fish.global_basis.x.normalized().dot(direction)>.999,"Fish must face the rod, not be reeled tail first")
		fish.free()
		var data:=FishCatalog.specimen(id,rng);data.lot_id="test:"+id
		var lot:=CatchLot.create(data)
		var hold:=CatchHoldState.new();hold.capacity_kg=100
		assert(hold.accept_lot(lot).is_empty())
		var second:=lot.duplicate_lot();second.lot_id+="2"
		assert(hold.accept_lot(second).is_empty());assert(hold.lots.size()==2,"Individual catches cannot merge")
		assert(not hold.accept_lot(lot).is_empty() and hold.lots.size()==2,"Duplicate identity rejected")
		var restored:=CatchHoldState.from_dict(hold.to_dict())
		assert(restored.lots[0].length_cm==lot.length_cm and restored.lots[0].specimen)
		assert(restored.withdraw_oldest(lot.mass_kg*.5).is_empty(),"Cannot withdraw half a fish")
		assert(restored.withdraw_oldest(lot.mass_kg).size()==1 and restored.lots.size()==1)
		var small:=CatchHoldState.new();small.capacity_kg=lot.mass_kg*.5
		assert(not small.accept_lot(lot).is_empty() and small.is_empty(),"Crate cannot keep half a fish")
		var quote:=FishingLandingService.quote([restored])
		assert(quote.value_marks==roundi(lot.mass_kg*float(FishCatalog.species(id).marks_per_kg)))
		for i in int(s.count):habitat.take_one(s.id)
		for remaining:Dictionary in habitat.schools_near(at,0,0):assert(remaining.id!=s.id)
	# Average profitable common fish, occasional high-value halibut; no flat random jackpot.
	assert(float(FishCatalog.species("halibut").marks_per_kg)>float(FishCatalog.species("cod").marks_per_kg))
	print("ROD FISHING PASS: six habitats/models, charge validation, bite/miss, controlled fight, individual fish save/load, no merging/duplication/splitting, prices, depletion")
	get_tree().quit()
