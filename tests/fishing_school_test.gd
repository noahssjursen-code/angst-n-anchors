extends Node
class Ground extends FishingHabitat:
	var species:="cod"
	var fish_depth:=20.0
	var reef:=false
	func bottom(at:Vector2)->float:return WaveSurface.WATER_LEVEL if reef and at.x>25 and at.x<40 else WaveSurface.WATER_LEVEL-100
	func schools_near(_at:Vector2,_hours:float,_radius:float=200)->Array:
		return [{"id":species+":fixture","species":species,"position":Vector2.ZERO,"depth_m":fish_depth,"radius_m":12.0,"count":12,"total":12}]
	func sample(_at:Vector2)->Dictionary:return {"substrate":"rock"}
func _ready()->void:
	# Sonar-led deep fishing: bait can be a deck/cast offset away from the return.
	for species in FishCatalog.fish_ids():
		var fixture:=Ground.new();fixture.species=species;fixture.fish_depth=72
		var ping:=fixture.ping(Vector2.ZERO,0)
		assert(not ping.echoes.is_empty())
		var depth:float=ping.echoes[0].depth_m
		var volume:=fixture.catch_area(fixture.schools_near(Vector2.ZERO,0)[0],0)
		assert(volume.radius_m==70 and volume.min_depth_m<depth and volume.max_depth_m>depth)
		for angle in range(0,360,30):
			var at:=Vector2.from_angle(deg_to_rad(angle))*69.9
			assert(not fixture.at_hook(at,depth,0).is_empty(),"Every bearing inside the 70 m school radius is fishable")
			assert(fixture.at_hook(at*1.01,depth,0).is_empty(),"Outside 70 m must not attract this school")
			assert(fixture.at_hook(at,depth-12,0).is_empty(),"Depth is still required")
		var session:=RodFishingSession.new();session.begin_charge();assert(session.cast(100,100,25))
		session.advance(1,Vector2(65,0),0,false,false,fixture,0)
		while session.depth_m<depth:session.advance(.05,Vector2(65,0),0,false,true,fixture,0)
		for tick in 240:
			session.advance(.05,Vector2(65,0),0,false,false,fixture,0)
			if session.phase=="bite":break
		assert(session.phase=="bite","Following sonar and paying out must reach deep "+species)
		fixture.reef=true
		assert(fixture.at_hook(Vector2(65,0),depth,0).is_empty(),"Bait cannot attract fish through a reef / island")
	var habitat:=Ground.new()
	var group:Dictionary=habitat.schools_near(Vector2.ZERO,0)[0]
	var members:=habitat.members(group,0)
	assert(members.size()==12)
	assert(habitat.ping(Vector2(200,0),0).echoes.is_empty(),"No sonar returns outside the fish cone")
	var session:=RodFishingSession.new()
	var ids:Dictionary={}
	for cycle in 3:
		var fish:Dictionary=habitat.members(group,0)[0]
		var at:=Vector2(fish.position.x,fish.position.z)
		var depth:float=WaveSurface.WATER_LEVEL-fish.position.y
		assert(not habitat.ping(at,0).echoes.is_empty(),"Visible fish under transducer must return an echo")
		assert(habitat.at_hook(at,depth,0).fish_id==fish.fish_id)
		assert(habitat.at_hook(at,1,0).is_empty(),"Hook over school but at wrong depth cannot catch")
		session.recover();session.begin_charge();assert(session.cast(40,100,20))
		session.advance(1,at,0,false,false,habitat,0)
		session.depth_m=depth
		for i in 150:
			session.advance(.1,at,0,false,false,habitat,0)
			if session.phase=="bite":break
		assert(session.phase=="bite")
		session.strike(0)
		assert(session.catch_data.length_cm==fish.specimen.length_cm,"Caught size must match the visible individual")
		var caught:Dictionary={}
		for i in 3000:
			caught=session.advance(.025,at,0,session.control<session.fish_position,session.control>=session.fish_position,habitat,0)
			if not caught.is_empty():break
		assert(not caught.is_empty() and not ids.has(caught.fish_id))
		ids[caught.fish_id]=true
		habitat.take_one(caught.school_id,caught.fish_id)
		habitat.take_one(caught.school_id,caught.fish_id)
		assert(habitat.members(group,0).size()==11-cycle,"Depletion removes exact fish once")
	var rope:=FishingLineShape.new()
	for frame in 240:
		var tip:=Vector3(sin(frame*.02),3,0)
		var hook:=Vector3(20,-12,0)
		var points:=rope.advance(1.0/60,tip,hook,.7)
		assert(points[0].distance_to(tip)<.0001 and points[-1].distance_to(hook)<.0001)
		for point in points:assert(point.is_finite())
	assert(rope.points[12].y<rope.points[0].lerp(rope.points[-1],.5).y,"Slack bows below a straight ray")
	print("SCHOOL + ROPE PASS: all six species from sonar at 72 m; 70 m radius all bearings; depth and reef exclusions; exact specimen; 3 consecutive catches; depletion; moving rope")
	get_tree().quit()
