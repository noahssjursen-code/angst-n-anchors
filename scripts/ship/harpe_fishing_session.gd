class_name HarpeFishingSession
extends RodFishingSession

const HOOK_COUNT:=6
const HOOK_SPACING_M:=.65
var catches:Array[Dictionary]=[]
var _hook_wait:Array[float]=[0.,0.,0.,0.,0.,0.]
var _habitat:FishingHabitat
var _sample_clock:=0.0

func hook_depth(index:int)->float:
	return depth_m-(index+1)*HOOK_SPACING_M

func release_fish()->void:
	if _habitat!=null:
		for caught in catches:_habitat.set_hooked(str(caught.fish_id),false)

func recover(text:String="Line recovered — hold left mouse to cast")->void:
	release_fish();catches.clear();_hook_wait.fill(0.0);_sample_clock=0
	super.recover(text)

func begin_haul(hours:float)->void:
	if phase!="fishing" or catches.is_empty():return
	_school={"id":catches[0].school_id,"fish_id":catches[0].fish_id,"specimen":catches[0]}
	phase="bite";super.strike(hours)
	var mass:=0.0
	for caught in catches:mass+=float(caught.mass_kg)
	catch_data["fight_mass_kg"]=mass
	band_width=maxf(.20,.30-float(catches.size()-1)*.015)

func advance(dt:float,at:Vector2,speed:float,reel:bool,pay:bool,habitat:FishingHabitat,hours:float)->Dictionary:
	_habitat=habitat
	if phase=="fishing":
		if reel and not pay and not catches.is_empty():
			begin_haul(hours)
		else:
			line_action="hold" if reel==pay else ("reel" if reel else "pay")
			_bottom=maxf(0,WaveSurface.WATER_LEVEL-habitat.bottom(at))
			if pay and not reel:depth_m=minf(line_limit(_bottom),depth_m+dt*3.5)
			elif reel and not pay:
				var vertical:=minf(depth_m,dt*6)
				depth_m-=vertical;reach_m=maxf(0,reach_m-(dt*6-vertical))
				if depth_m<=.01 and reach_m<=.2:recover();return {}
			_sample_clock+=dt
			if _sample_clock>=.5:
				var elapsed:=_sample_clock;_sample_clock=0
				for index in HOOK_COUNT:
					if catches.any(func(c):return int(c.hook_index)==index):continue
					var target:=habitat.at_hook(at,hook_depth(index),hours,0.0,5.0) if speed<=2 else {}
					if target.is_empty():_hook_wait[index]=0;continue
					_hook_wait[index]+=elapsed
					if _hook_wait[index]<2.5+index*.35:continue
					var caught:Dictionary=target.specimen.duplicate(true)
					caught.merge({"fish_id":target.fish_id,"school_id":target.id,"hook_index":index},true)
					catches.append(caught);habitat.set_hooked(target.fish_id,true)
			message="%d / 6 hooks occupied · LMB to haul · RMB to lower"%catches.size()
			if _bottom>MAX_LINE_M and depth_m>=MAX_LINE_M-.15:message="180 m is as deep as this line goes · LMB to haul"
			return {}
	var result:=super.advance(dt,at,speed,reel,pay,habitat,hours)
	if not result.is_empty():
		result["catches"]=catches.duplicate(true)
		message="%d fish landed"%catches.size()
	return result
