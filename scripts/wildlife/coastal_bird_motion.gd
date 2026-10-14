class_name CoastalBirdMotion
extends RefCounted
## Closed-form flock tracks: join/rejoin at any shared time without replaying
## thousands of boids ticks. The workshop's free boids remain a separate experiment.
# Integer mixing avoids index-based angles/rings and consumes no mutable RNG state.
static func unit(seed: int, index: int, channel: int) -> float:
	var n := posmod(seed + index * 374761393 + channel * 668265263, 2147483647)
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	n = n ^ (n >> 16)
	return float(n) / 2147483647.0

static func waypoint(seed: int, index: int, knot: int) -> Vector3:
	return Vector3(unit(seed,index,knot*3)*2-1,unit(seed,index,knot*3+1),unit(seed,index,knot*3+2)*2-1)

static func wander(seed: int, index: int, time: float) -> Vector3:
	# Uniform cubic B-spline: continuous velocity/acceleration, no stops at knots,
	# no repeating orbit, and contained within the habitat's checked envelope.
	var knot := int(floor(time))
	var t := time-floorf(time)
	var t2 := t*t
	var t3 := t2*t
	return (waypoint(seed,index,knot-1)*pow(1-t,3) + waypoint(seed,index,knot)*(3*t3-6*t2+4) + waypoint(seed,index,knot+1)*(-3*t3+3*t2+3*t+1) + waypoint(seed,index,knot+2)*t3)/6.0

static func flight(seed: int, index: int, seconds: float, species: String) -> Vector3:
	var pace := lerpf(5.0,10.0,unit(seed,0,91))
	if species == "white_tailed_eagle": pace *= 1.6
	if species == "arctic_tern": pace *= 0.65
	var route := wander(seed,51,seconds/pace)
	var individual := wander(seed,index+100,seconds/lerpf(4.0,8.0,unit(seed,index,92))+unit(seed,index,93)*100)
	var spread := lerpf(10.0,24.0,unit(seed,0,94))
	var point := route*32.0+individual*spread
	point.y = 8.0+route.y*12+individual.y*6
	if species == "white_tailed_eagle": point.y=32+route.y*25
	elif species == "arctic_tern": point.y=5+individual.y*9
	return point

static func schedule(seed: int,index: int,seconds: float) -> Vector4:
	var fly := lerpf(90.0,240.0,unit(seed,index,70))
	var rest := lerpf(240.0,660.0,unit(seed,index,71))
	var transition := lerpf(7.0,12.0,unit(seed,index,72))
	var phase := fposmod(seconds+unit(seed,index,73)*1300,fly+rest+transition*2)
	return Vector4(phase,fly,rest,transition)

static func visit(seed: int,index: int,seconds: float) -> int:
	var timing := schedule(seed,index,seconds)
	return int(floor((seconds+unit(seed,index,73)*1300)/(timing.y+timing.z+timing.w*2)))

static func base_position(seed: int, index: int, seconds: float, species: String) -> Vector3:
	var air := flight(seed,index,seconds,species)
	if species == "white_tailed_eagle": return air
	if species == "arctic_tern":
		var interval := lerpf(43.0,113.0,unit(seed,index,81))
		var dive := fposmod(seconds + unit(seed,index,82)*interval,interval)
		var start_time := seconds-dive
		var start := flight(seed,index,start_time,species)
		if dive < 3: return start.lerp(flight(seed,index,start_time+3,species),smoothstep(0,3,dive)*0.15)
		start=start.lerp(flight(seed,index,start_time+3,species),0.15)
		if dive < 4: return start.lerp(Vector3(start.x,0.15,start.z),smoothstep(3,4,dive))
		if dive < 8: return Vector3(start.x,0.15,start.z).lerp(air,smoothstep(4,8,dive))
		return air
	var timing := schedule(seed,index,seconds)
	var phase := timing.x
	var land := timing.y
	var sit := land+timing.w
	var leave := sit+timing.z
	var rest_at := resting_point(seed,index,visit(seed,index,seconds))
	# Slow shared drift preserves personal space rather than fixing birds in place.
	var drift := wander(seed,400,seconds/60.0)*1.2
	rest_at += Vector3(drift.x,0,drift.z)
	if phase < land: return air
	if phase < sit: return air.lerp(rest_at,smoothstep(land,sit,phase))
	if phase < leave: return rest_at
	return rest_at.lerp(air,smoothstep(leave,leave+timing.w,phase))

static var rest_slots: Dictionary = {}
static func resting_point(seed: int,index: int,visit_id: int = 0) -> Vector3:
	# Cache bounded, deterministic rejection sampling; no rings or index angles.
	if not rest_slots.has(seed):
		if rest_slots.size()>=256: rest_slots.erase(rest_slots.keys()[0])
		rest_slots[seed]=[]
	var slots: Array = rest_slots[seed]
	while slots.size()<=index:
		var bird := slots.size()
		var patch := 1 if unit(seed,bird,111)<0.3 else 0
		var center := Vector3(unit(seed,patch,112)*22-11,0,unit(seed,patch,113)*22-11)
		var width := lerpf(12.0,28.0,unit(seed,0,114))
		var length := lerpf(12.0,28.0,unit(seed,0,115))
		var best := center
		var best_clearance := -1.0
		for attempt in 64:
			var candidate := center+Vector3((unit(seed,bird,116+attempt*2)-0.5)*width,0,(unit(seed,bird,117+attempt*2)-0.5)*length)
			var clearance := INF
			for other: Vector3 in slots: clearance=minf(clearance,candidate.distance_to(other))
			if clearance>best_clearance: best=candidate;best_clearance=clearance
			if clearance>=2.5: break
		slots.append(best)
	# Small changes on each visit cannot erase the personal space between birds.
	return slots[index]+Vector3(unit(seed,index,210+visit_id*2)-0.5,0,unit(seed,index,211+visit_id*2)-0.5)*0.6

static func position_at(seed: int,index: int,seconds: float,species: String,event: Dictionary) -> Vector3:
	var base := base_position(seed,index,seconds,species)
	if event.is_empty() or species != "herring_gull": return base
	var begin := float(event.get("started",0))+unit(seed,index,120)*1.4
	var end := float(event.get("until",0))
	if seconds < begin or seconds > end+8: return base
	var escape := flight(seed,index,seconds,species) + Vector3.UP * 8.0
	if seconds < begin+4:
		return base_position(seed,index,begin,species).lerp(escape,smoothstep(0,4,seconds-begin))
	return escape.lerp(base,smoothstep(end,end+8,seconds))

static func sample(seed: int,index: int,seconds: float,species: String,event: Dictionary = {}) -> GullWaterBehaviour:
	var state := GullWaterBehaviour.new()
	state.idle_seed = posmod(seed + index * 104729,2147483647)
	state.position = position_at(seed,index,seconds,species,event)
	state.velocity = (position_at(seed,index,seconds+0.02,species,event)-position_at(seed,index,seconds-0.02,species,event))/0.04
	state.heading = Vector3(state.velocity.x,0,state.velocity.z).normalized()
	if state.heading.length_squared()<0.1: state.heading=Vector3.FORWARD.rotated(Vector3.UP,unit(seed,index,121)*TAU)
	state.target = resting_point(seed,index)
	if species != "herring_gull": return state
	var timing := schedule(seed,index,seconds)
	var phase := timing.x
	var land := timing.y
	var sit := land+timing.w
	var leave := sit+timing.z
	state.target=resting_point(seed,index,visit(seed,index,seconds))
	state.duration=timing.w
	if phase>=land and phase<sit:
		state.stage=GullWaterBehaviour.Stage.LANDING
		state.elapsed=phase-land
	elif phase>=sit and phase<leave:
		state.stage=GullWaterBehaviour.Stage.RESTING
		state.elapsed=phase-sit
		state.heading=Vector3.FORWARD.rotated(Vector3.UP,unit(seed,index,121)*TAU+wander(seed,index+900,seconds/35).x*0.6)
	elif phase>=leave:
		state.stage=GullWaterBehaviour.Stage.TAKING_OFF
		state.elapsed=phase-leave
	var startled_at := float(event.get("started",0))+unit(seed,index,120)*1.4
	if not event.is_empty() and seconds>=startled_at and seconds<float(event.until)+8:
		state.stage=GullWaterBehaviour.Stage.TAKING_OFF if seconds<startled_at+4 else GullWaterBehaviour.Stage.FLYING
		state.elapsed=seconds-startled_at
		state.duration=4
		state.startled=true
		state.departure_fold=1.0 if base_position(seed,index,startled_at,species).y<0.1 else 0.0
		if seconds>float(event.until):
			state.stage=GullWaterBehaviour.Stage.LANDING
			state.elapsed=seconds-float(event.until)
			state.duration=8
	return state
