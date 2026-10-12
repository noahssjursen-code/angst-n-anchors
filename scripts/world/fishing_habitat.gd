class_name FishingHabitat
extends RefCounted

## Local, bounded queries. No global fish-node population or chart overlay.
const CELL_M := 160.0
## Bait attracts a school horizontally; paying out to its depth still matters.
const CATCH_RADIUS_M := 70.0
const CATCH_DEPTH_TOLERANCE_M := 6.0
var layout: WorldLayout
var zones: Array = []
var _terrain_cache: Dictionary = {}
var _habitats: Dictionary = {}
var _taken: Dictionary = {}
var _removed: Dictionary = {}
var _hooked: Dictionary = {}
var _specimens: Dictionary = {}

func configure(source: WorldLayout, grading: Array = []) -> void:
	layout=source;zones=grading
	_terrain_cache.clear();_habitats.clear();_taken.clear();_removed.clear();_hooked.clear();_specimens.clear()

func bottom(at: Vector2) -> float:
	if _terrain_cache.size()>8192: _terrain_cache.clear()
	return WorldForestStreamer.sample_root_height(layout,at,zones,_terrain_cache)

func sample(at: Vector2) -> Dictionary:
	var cell:=Vector2i(floori(at.x/25),floori(at.y/25))
	if _habitats.has(cell): return _habitats[cell]
	var p:=Vector2(cell)*25+Vector2(12.5,12.5)
	var h:=bottom(p)
	var depth:=maxf(0,WaveSurface.WATER_LEVEL-h)
	var dx:=(bottom(p+Vector2(25,0))-bottom(p-Vector2(25,0)))/50
	var dz:=(bottom(p+Vector2(0,25))-bottom(p-Vector2(0,25)))/50
	var slope:=Vector2(dx,dz).length()
	var relief:=absf(h-(bottom(p+Vector2(50,0))+bottom(p-Vector2(50,0))+bottom(p+Vector2(0,50))+bottom(p-Vector2(0,50)))*.25)
	var substrate:="rock" if slope>.18 or relief>2 or depth<25 else ("mud" if depth>100 else "sand")
	# Gameplay suitability curves, not measured stock densities.
	var cod:=smoothstep(3,15,depth)*(1-smoothstep(100,220,depth))
	cod*=clampf(.45+slope*.9+relief*.08,.0,1.0)
	var crab:=smoothstep(1,6,depth)*(1-smoothstep(35,85,depth))*(1.0 if substrate=="rock" else .25)
	var result:={"depth_m":depth,"bottom_y":h,"slope":slope,"relief_m":relief,"substrate":substrate,"cod":cod,"crab":crab}
	if _habitats.size()>2048: _habitats.clear()
	_habitats[cell]=result
	return result

func schools_near(at: Vector2, hours: float, radius: float = 200.0) -> Array:
	var result:Array=[]
	if layout==null: return result
	var cell:=Vector2i(floori(at.x/CELL_M),floori(at.y/CELL_M))
	var reach:=ceili(minf(radius,500)/CELL_M)+1
	for z in range(cell.y-reach,cell.y+reach+1):
		for x in range(cell.x-reach,cell.x+reach+1):
			var rng:=RandomNumberGenerator.new()
			rng.seed=hash("fish:%d:%d:%d"%[layout.seed,x,z])
			var origin:=(Vector2(x,z)+Vector2(rng.randf_range(.2,.8),rng.randf_range(.2,.8)))*CELL_M
			var habitat:=sample(origin)
			var depth:=float(habitat.depth_m)
			if depth<5: continue
			for species_id in FishCatalog.fish_ids():
				var entry:=FishCatalog.species(species_id)
				var id:="%s:%d:%d"%[species_id,x,z]
				rng.seed=hash("%d:%s"%[layout.seed,id])
				var band_lo:=float(entry.depth_m[0])
				var band_hi:=float(entry.depth_m[1])
				if depth<band_lo: continue
				var suitability:=1.0 if entry.substrate=="any" or entry.substrate==habitat.substrate else .3
				if rng.randf()>float(entry.spawn_weight)*suitability*.62: continue
				var phase:=rng.randf()*TAU
				var p:=origin+Vector2(cos(hours*.35+phase),sin(hours*.35+phase))*12
				var local_depth:=WaveSurface.WATER_LEVEL-bottom(p)
				if local_depth<5: continue
				var school_radius:=rng.randf_range(9,18)
				if p.distance_to(at)>radius+school_radius: continue
				var count:=maxi(0,(rng.randi_range(1,3) if species_id=="halibut" else rng.randi_range(8,24))-int(_taken.get(id,0)))
				if count==0: continue
				var fish_depth:=maxf(1,local_depth-rng.randf_range(1,4))
				if entry.zone=="surface": fish_depth=minf(local_depth-1,rng.randf_range(2,8))
				elif entry.zone=="midwater": fish_depth=local_depth*rng.randf_range(.25,.65)
				elif entry.zone=="reef": fish_depth=maxf(2,local_depth-rng.randf_range(3,12))
				# The band is where the fish swims. Deeper water keeps surface and
				# midwater schools inside it; bottom fish stay on ground that is in range.
				if local_depth>band_hi:
					if entry.zone=="bottom" or entry.zone=="reef": continue
					if entry.zone=="midwater": fish_depth=rng.randf_range(band_lo,minf(band_hi,local_depth-1))
				result.append({"id":id,"species":species_id,"position":p,"depth_m":fish_depth,"radius_m":school_radius,"count":count,"total":count+int(_taken.get(id,0))})
	return result

## Stable individual identities shared by rendering, sonar and tackle queries.
func members(school:Dictionary,hours:float)->Array:
	var result:Array=[]
	var total:=int(school.get("total",school.get("count",1)))
	for i in total:
		var id:="%s/%d"%[school.id,i]
		if _removed.has(id) or _hooked.has(id):continue
		var seed_value:=hash(id)
		var motion:=RandomNumberGenerator.new();motion.seed=seed_value
		var angle:=motion.randf()*TAU+hours*1.0
		var radius:=sqrt(float(i+1)/total)*float(school.get("radius_m",12))*.8
		var center:Vector2=school.get("position",Vector2.ZERO)
		var at:=center+Vector2(cos(angle),sin(angle))*radius
		var depth:=float(school.depth_m)+sin(angle*1.7+i)*1.2
		var floor_depth:=WaveSurface.WATER_LEVEL-bottom(at)
		if floor_depth<2:continue
		depth=clampf(depth,1,floor_depth-.6)
		if not _specimens.has(id):
			var rng:=RandomNumberGenerator.new();rng.seed=seed_value
			if _specimens.size()>2048:_specimens.clear()
			_specimens[id]=FishCatalog.specimen(str(school.species),rng)
		result.append({"fish_id":id,"school_id":school.id,"species":school.species,"position":Vector3(at.x,WaveSurface.WATER_LEVEL-depth,at.y),"heading":Vector3(-sin(angle),0,cos(angle)),"specimen":_specimens[id]})
	return result

func at_hook(at:Vector2, depth:float, hours:float, min_kg:float=0.0, max_kg:float=INF)->Dictionary:
	var hook:=Vector3(at.x,WaveSurface.WATER_LEVEL-depth,at.y)
	var best:Dictionary={}
	var nearest:=INF
	if depth<=0 or depth>=WaveSurface.WATER_LEVEL-bottom(at):return best
	for school:Dictionary in schools_near(at,hours,CATCH_RADIUS_M):
		if at.distance_to(school.position)>CATCH_RADIUS_M:continue
		for fish:Dictionary in members(school,hours):
			if float(fish.specimen.mass_kg)<min_kg or float(fish.specimen.mass_kg)>max_kg:continue
			if absf(hook.y-fish.position.y)>CATCH_DEPTH_TOLERANCE_M:continue
			var distance:=hook.distance_to(fish.position)
			if distance<nearest and _open_water_path(hook,fish.position):
				nearest=distance;best=school.duplicate()
				best["fish_id"]=fish.fish_id;best["specimen"]=fish.specimen
	return best

## The debug volume uses the same members and tolerances as bite detection.
## Seabed/land can occlude part of this attraction envelope.
func catch_area(school:Dictionary,hours:float)->Dictionary:
	var fish:=members(school,hours)
	if fish.is_empty():return {}
	var shallow:=INF
	var deep:=0.0
	for individual:Dictionary in fish:
		var depth:float=WaveSurface.WATER_LEVEL-individual.position.y
		shallow=minf(shallow,depth);deep=maxf(deep,depth)
	return {"position":school.position,"radius_m":CATCH_RADIUS_M,
		"min_depth_m":maxf(.1,shallow-CATCH_DEPTH_TOLERANCE_M),
		"max_depth_m":deep+CATCH_DEPTH_TOLERANCE_M,"members":fish}

func _open_water_path(a:Vector3,b:Vector3)->bool:
	# Local, only for eligible fish. Do not attract fish through an island or reef.
	var steps:=maxi(1,ceili(a.distance_to(b)/5.0))
	for i in range(1,steps):
		var p:=a.lerp(b,float(i)/steps)
		if bottom(Vector2(p.x,p.z))>=p.y:return false
	return true

func set_hooked(fish_id:String,value:bool)->void:
	if fish_id.is_empty():return
	if value:_hooked[fish_id]=true
	else:_hooked.erase(fish_id)

func take_one(id:String,fish_id:String="")->void:
	if fish_id.is_empty():
		var i:=0
		while _removed.has("%s/%d"%[id,i]):i+=1
		fish_id="%s/%d"%[id,i]
	if _removed.has(fish_id):return
	_removed[fish_id]=true
	_taken[id]=int(_taken.get(id,0))+1

func ping(at:Vector2,hours:float)->Dictionary:
	var depth:=maxf(0,WaveSurface.WATER_LEVEL-bottom(at))
	var echoes:Array=[]
	var targets:Array=[]
	# Only individuals inside the downward cone contribute a return.
	for school:Dictionary in schools_near(at,hours,minf(500,depth*tan(deg_to_rad(20)))):
		var hits:=0
		var sum_depth:=0.0
		for fish:Dictionary in members(school,hours):
			var p:Vector3=fish.position
			var fish_depth:=WaveSurface.WATER_LEVEL-p.y
			if fish_depth<depth and at.distance_to(Vector2(p.x,p.z))<=fish_depth*tan(deg_to_rad(20)):
				hits+=1;sum_depth+=fish_depth
				var off_axis:=at.distance_to(Vector2(p.x,p.z))/maxf(.1,fish_depth*tan(deg_to_rad(20)))
				# Acoustic travel distance creates an arch as a real fish crosses the cone.
				var range_m:=sqrt(fish_depth*fish_depth+at.distance_squared_to(Vector2(p.x,p.z)))
				targets.append({"fish_id":fish.fish_id,"depth_m":fish_depth,"range_m":range_m,"strength":lerpf(.25,1.0,1-off_axis*off_axis),"thickness_m":float(fish.specimen.length_cm)*.0025})
		if hits>0:echoes.append({"school_id":school.id,"depth_m":sum_depth/hits,"strength":clampf(float(hits)/16,.1,1)})
	return {"depth_m":depth,"echoes":echoes,"targets":targets,"substrate":sample(at).substrate}
