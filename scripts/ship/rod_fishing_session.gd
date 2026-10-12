class_name RodFishingSession
extends RefCounted

## Input-independent cast / bite / fight state. The station owns world placement.
var phase := "stowed"
var depth_m := 0.0
var reach_m := 0.0
var tension := .25
var charge := 0.0
var control := .5
var fish_position := .5
var band_width := .28
var progress := .18
var message := "Hold right mouse to lower the tackle"
var catch_data: Dictionary = {}
var _wait := 0.0
var _waiting_school := ""
var _bite := 0.0
var _fight := 0.0
var _stress := 0.0
var _flight := 0.0
var _reveal := 0.0
var _school: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _serial := 0
var _flight_depth := 0.0
var _probe_timer := 0.0
var _nearby: Array = []
var _investigating: Dictionary = {}
var _bottom := 0.0
var line_action := "hold"
const MIN_WATER_M := 3.0
const MAX_LINE_M := 180.0

func begin_charge() -> void:
	if phase == "stowed":
		charge=0;phase="charging";message="Release left mouse to cast"

func line_limit(bottom: float) -> float:
	return minf(maxf(0.0, bottom - 1.0), MAX_LINE_M)

func cast(bottom_depth: float, free_kg: float, horizontal_span: float = 0.0) -> bool:
	if phase != "charging": return false
	if bottom_depth < MIN_WATER_M:
		recover("Too shallow to fish");return false
	if free_kg < .2:
		recover("The catch crate is full");return false
	phase="casting";_flight=0;depth_m=0;_wait=0;_school={};catch_data={}
	_probe_timer=0;_nearby=[];_investigating={};_bottom=bottom_depth;reach_m=maxf(0,horizontal_span)
	message="Casting…"
	return true

func drop(bottom_depth:float,free_kg:float)->bool:
	begin_charge()
	if not cast(bottom_depth,free_kg,0.0):return false
	phase="fishing";message="Hold RMB to lower · Hold LMB to retrieve"
	return true

func strike(hours: float) -> void:
	if phase != "bite": return
	_serial+=1;_rng.seed=hash("%s:%d:%d"%[_school.id,_serial,int(hours*3600)])
	catch_data=_school.specimen.duplicate(true) if _school.has("specimen") else FishCatalog.specimen(str(_school.species),_rng)
	catch_data["fish_id"]=_school.get("fish_id", "")
	catch_data["school_id"]=_school.id
	phase="fighting";control=.5;fish_position=.5;progress=0;_fight=0;_stress=0;tension=.25
	band_width=.30 if catch_data.species_id in ["mackerel","cod","saithe"] else .25
	if catch_data.species_id=="halibut": band_width=.22
	_flight_depth=depth_m
	message="Hold left mouse: reel in · hold right mouse: give line. Keep the fish in the white bar. Hauling continuously."

func recover(text: String = "Line recovered — hold left mouse to cast") -> void:
	phase="stowed";depth_m=0;reach_m=0;charge=0;_school={};message=text;tension=.25;_wait=0;_waiting_school=""

func advance(dt: float, at: Vector2, speed: float, reel: bool, pay: bool, habitat: FishingHabitat, hours: float) -> Dictionary:
	line_action="hold" if reel==pay else ("reel" if reel else "pay")
	if phase=="stowed":return {}
	if phase=="charging":charge=minf(1,charge+dt*.8);return {}
	if phase=="landed":
		_reveal-=dt
		if _reveal<=0:recover()
		return {}
	# Opposing buttons neutralize control. Hooked fish still haul continuously.
	if reel and pay:reel=false;pay=false
	if phase=="casting":
		_flight+=dt
		if _flight>=.85:phase="fishing";message="Hold right mouse to let line out and sink the tackle"
		return {}
	_probe_timer-=dt
	if _probe_timer<=0:
		_probe_timer=.25
		_bottom=maxf(0,WaveSurface.WATER_LEVEL-habitat.bottom(at))
		if phase=="fishing":_investigating=habitat.at_hook(at,depth_m,hours,1.5)
	var bottom:=_bottom
	if bottom<2:message="Too shallow. Hold left mouse to reel in."
	if phase=="fighting":
		_fight+=dt
		control=clampf(control+dt*(.56 if reel else (-.46 if pay else 0.0)),band_width*.5,1-band_width*.5)
		# Runs and reversals require both controls, independently of haul progress.
		var vigor:=1.15 if catch_data.species_id=="halibut" else .95
		fish_position=clampf(.5+sin(_fight*vigor)*.30+sin(_fight*2.1)*.13,.06,.94)
		var controlled:=absf(control-fish_position)<=band_width*.5
		# Giving line is not immunity: either button must keep the fish in the bar.
		_stress=clampf(_stress+dt*(-.48 if controlled else .48),0,1)
		tension=.22+_stress*.78
		var duration:=clampf(6.0+sqrt(float(catch_data.get("fight_mass_kg",catch_data.mass_kg)))*.55,6.0,11.0)
		progress=minf(1,progress+dt/duration)
		depth_m=lerpf(_flight_depth,0,progress)
		if _stress>=1:
			recover("Line snapped. Keep the fish inside the white bar.");return {}
		if progress>=1:
			phase="landed";depth_m=0;_reveal=7
			message="%s · %.2f kg · %.1f cm"%[FishCatalog.species(catch_data.species_id).name,catch_data.mass_kg,catch_data.length_cm]
			return catch_data.duplicate(true)
		return {}
	if phase=="bite":
		_bite-=dt
		if pay or _bite<=0:phase="fishing";_wait=0;message="Missed it. Wait for the next bite."
		else:return {}
	# Letting out line and retrieving are continuous, player-controlled actions.
	if pay:
		depth_m=minf(line_limit(bottom),depth_m+dt*6.0)
	elif reel:
		var budget:=dt*6
		var vertical:=minf(depth_m,budget)
		depth_m-=vertical;reach_m=maxf(0,reach_m-(budget-vertical))
		if depth_m<=.01 and reach_m<=.2:recover();return {}
	message="%s · %.1f m deep · Hold LMB: reel in / RMB: let line out"%["Letting line out" if pay else ("Reeling in" if reel else "Holding line"),depth_m]
	if speed>2:_wait=0;message="Boat moving too fast for a bite. Hold left mouse to reel in.";return {}
	var school:Dictionary=_investigating
	if school.is_empty():
		_wait=0;_waiting_school=""
		if depth_m>=bottom-1.1:message="Just above the seabed · Hold left mouse to reel in"
		elif bottom>MAX_LINE_M and depth_m>=MAX_LINE_M-.15:message="180 m is as deep as this line goes · Hold left mouse to reel in"
		return {}
	if _waiting_school!=str(school.id):
		_wait=0;_waiting_school=str(school.id)
	_wait+=dt
	if _wait>=3.5+float(abs(hash(school.id))%40)*.1:
		_school=school;phase="bite";_bite=3.2;_wait=0;message="BITE!  Left click to strike"
	return {}
