class_name CoastalBridgePlan
extends RefCounted

## Advisory geometry only: no terrain, collision, shipping or save mutations.
const MAX_SPAN := 2200.0
const MIN_SPAN := 60.0
const SHORE_STEP := 100.0
const LANDING_INSET := 45.0
const MAX_BRIDGES := 56
const SEPARATION := 450.0
const MAX_MAINLAND_SHORTCUTS := 2
const MAX_MAINLAND_GAP := 350.0

var _layout: WorldLayout
var _n := 0
var _step := 0.0
var _components := PackedInt32Array()
var _mainland := -1
var _areas := {}
var _edges := PackedByteArray()
var _landing_cache := {}
var _demand_cache := {}
var _port_components := {}
var _ports: Array = []
var _settlements: Array = []
var _demands: Array[Dictionary] = []

static func build(layout: WorldLayout, ports: Array, settlements: Array = []) -> Dictionary:
	var planner := CoastalBridgePlan.new()
	planner._layout = layout
	planner._ports = ports
	planner._settlements = settlements
	return planner._build()

func _build() -> Dictionary:
	var started := Time.get_ticks_usec()
	_label_land()
	var grouping_ms := (Time.get_ticks_usec()-started)/1000.0
	for port: PortDefinition in _ports:
		var id := _component_at(Vector2(port.world_position.x, port.world_position.z))
		if id >= 0:
			if not _port_components.has(id): _port_components[id]=[]
			_port_components[id].append(port.display_name)
	var settlement_counts := {}
	for building: Dictionary in _settlements:
		var at := Vector2(building.position.x,building.position.z)
		var id := _component_at(at)
		if id>=0: settlement_counts[id]=settlement_counts.get(id,0)+1
	for id in settlement_counts:
		if settlement_counts[id]>=3 and _areas.get(id,0.0)>=150000 and not _port_components.has(id):
			_port_components[id]=["Coastal settlement"]
	for port: PortDefinition in _ports:
		var at := Vector2(port.world_position.x,port.world_position.z)
		_demands.append({"at":at,"component":_component_at(at),"name":port.display_name})
	var shores: Array[Dictionary] = []
	var bins := {}
	for contour in _layout.coastline_contours:
		var carry := 0.0
		for i in range(contour.size()-1):
			var length := contour[i].distance_to(contour[i+1])
			var offset := carry
			while offset < length:
				var at := contour[i].lerp(contour[i+1], offset/maxf(length,.001))
				offset += SHORE_STEP
				var normal := CoastalSettlementPlan.gradient(_layout, at)
				# Trace the physical waterline, including the dry datum/beach apron.
				var dry := at-normal*80
				var wet := at+normal*120
				if not _dry(dry) or _dry(wet): continue
				for iteration in 10:
					var mid := (dry+wet)*.5
					if _dry(mid): dry=mid
					else: wet=mid
				at=(dry+wet)*.5
				var landing := at-normal*LANDING_INSET
				var component := _component_at(landing)
				if component < 0 or not _dry(landing): continue
				if component != _mainland and not _port_components.has(component) and _areas.get(component,0.0)<80000: continue
				var item := {"shore":at,"point":landing,"normal":normal,"component":component}
				var bin := Vector2i(floori(at.x/MAX_SPAN),floori(at.y/MAX_SPAN))
				if not bins.has(bin): bins[bin] = []
				bins[bin].append(shores.size())
				shores.append(item)
			carry = offset-length
	var candidates: Array[Dictionary] = []
	for i in shores.size():
		var a := shores[i]
		var bin := Vector2i(floori(a.shore.x/MAX_SPAN),floori(a.shore.y/MAX_SPAN))
		for dz in range(-1,2):
			for dx in range(-1,2):
				for j: int in bins.get(bin+Vector2i(dx,dz),[]):
					if j <= i: continue
					var b := shores[j]
					# Distinct substantial land components may connect through islands.
					if a.component==b.component and a.component!=_mainland: continue
					var distance: float = a.shore.distance_to(b.shore)
					if distance < MIN_SPAN or distance > MAX_SPAN: continue
					# Existing mainland access is the default. Only short narrows merit a shortcut.
					if a.component==b.component and distance>MAX_MAINLAND_GAP: continue
					var direction: Vector2 = (b.shore-a.shore).normalized()
					if a.normal.dot(direction)<.65 or b.normal.dot(-direction)<.65: continue
					var proposal := _evaluate(a,b)
					if not proposal.is_empty(): candidates.append(proposal)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.score<b.score)
	# Minimum-cost forest of land masses, then remove unneeded stepping-stone
	# leaves. A small island is useful only when it lies on a route to a target.
	var selected: Array[Dictionary] = []
	var parent := {}
	for component in _areas: parent[component]=component
	for candidate in candidates:
		if candidate.component_a==candidate.component_b: continue
		var ra := _root(parent,candidate.component_a)
		var rb := _root(parent,candidate.component_b)
		if ra==rb: continue
		parent[ra]=rb
		selected.append(candidate)
	var changed := true
	while changed:
		changed=false
		var degree := {}
		for bridge in selected:
			for component in [bridge.component_a,bridge.component_b]: degree[component]=degree.get(component,0)+1
		for i in range(selected.size()-1,-1,-1):
			var bridge := selected[i]
			for component in [bridge.component_a,bridge.component_b]:
				if degree[component]==1 and not _terminal(component):
					selected.remove_at(i);changed=true;break
	# Never discard an entire mainland-connected region because it exceeds
	# the preview budget. Trim its least valuable leaf branches instead;
	# retained links remain connected and port access is strongly preferred.
	while true:
		var degree := {}
		for bridge in selected:
			for component in [bridge.component_a,bridge.component_b]: degree[component]=degree.get(component,0)+1
		var remove_index := -1
		var worst := -INF
		for i in selected.size():
			var bridge := selected[i]
			for component in [bridge.component_a,bridge.component_b]:
				if degree[component]!=1 or component==_mainland: continue
				if selected.size()<=MAX_BRIDGES-MAX_MAINLAND_SHORTCUTS and _terminal(component): continue
				var importance := 1.0+minf(_areas[component]/400000.0,10.0)
				if _port_components.has(component): importance+=20
				var cost: float = bridge.span_m/importance
				if not _terminal(component): cost+=100000
				if cost>worst: worst=cost;remove_index=i
		if remove_index<0: break
		selected.remove_at(remove_index)
	var mainland_count := 0
	for candidate in candidates:
		if selected.size()>=MAX_BRIDGES or mainland_count>=MAX_MAINLAND_SHORTCUTS: break
		if candidate.component_a!=candidate.component_b: continue
		var crowded := false
		for existing in selected:
			if candidate.center.distance_to(existing.center)<SEPARATION: crowded=true;break
		if crowded: continue
		if _short_land_path(candidate.a_xz,candidate.b_xz,maxf(5000,candidate.span_m*10)*sqrt(2.0)+4*_step): continue
		selected.append(candidate);mainland_count+=1
	var alternatives := {}
	for i in selected.size():
		selected[i].id=i+1
		var options: Array = []
		for candidate: Dictionary in candidates:
			if candidate==selected[i]: continue
			var same_pair: bool = (candidate.component_a==selected[i].component_a and candidate.component_b==selected[i].component_b) or (candidate.component_b==selected[i].component_a and candidate.component_a==selected[i].component_b)
			if not same_pair or candidate.center.distance_to(selected[i].center)>1200: continue
			var option:=candidate.duplicate();option.id=i+1;options.append(option)
			if options.size()>=4: break
		alternatives[i+1]=options
	return {"alternatives":alternatives,"bridges":selected,"candidate_count":candidates.size(),"shore_samples":shores.size(),
		"grouping_ms":grouping_ms,"build_ms":(Time.get_ticks_usec()-started)/1000.0,"grid_m":_step}

func _evaluate(a: Dictionary,b: Dictionary) -> Dictionary:
	var from: Vector2 = a.point
	var to: Vector2 = b.point
	var span := from.distance_to(to)
	for port: PortDefinition in _ports:
		var at := Vector2(port.world_position.x,port.world_position.z)
		# Protect the quay-facing approach, not a blanket circle around town.
		var seaward := Vector2(sin(port.rotation_y),cos(port.rotation_y))*-1
		var approach := at+seaward*350
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at,from,to))<120: return {}
		if Geometry2D.segment_intersects_segment(from,to,at,approach)!=null: return {}
	var profile_a := _landing(a)
	var profile_b := _landing(b)
	if profile_a.is_empty() or profile_b.is_empty(): return {}
	var height_a: float = profile_a.height
	var height_b: float = profile_b.height
	var max_grade: float = maxf(profile_a.grade,profile_b.grade)
	if absf(height_a-height_b)/span>.08: return {}
	# Both edges of the 12m corridor must be water between the shores.
	var side := (to-from).normalized().orthogonal()*8
	var count := ceili(a.shore.distance_to(b.shore)/12.0)
	for i in range(1,count):
		var at: Vector2 = a.shore.lerp(b.shore,float(i)/count)
		for shift: Vector2 in [Vector2.ZERO,side,-side]:
			if _dry(at+shift): return {}
	var island := -1
	if a.component!=b.component:
		island=b.component if a.component==_mainland else a.component
	var access := INF
	var served: Array = _port_components.get(island,[]).duplicate()
	if island<0:
		# A shortcut needs distinct nearby destinations on the two banks.
		# Short geometric gaps between empty headlands are not useful trips.
		var left := _nearby_demand(from)
		var right := _nearby_demand(to)
		if left.is_empty() or right.is_empty() or left.name==right.name: return {}
		served=[left.name,right.name]
		access=from.distance_to(left.at)+to.distance_to(right.at)
		if from.distance_to(left.at)>1200 or to.distance_to(right.at)>1200: return {}
	else:
		for demand in _demands:
			if demand.component==island:
				access=minf(access,minf(from.distance_to(demand.at),to.distance_to(demand.at)))
		if is_inf(access): access=500
	var deck := maxf(WaveSurface.WATER_LEVEL+35,maxf(height_a,height_b)+4)
	return {"a_xz":from,"b_xz":to,"a_ground":height_a,"b_ground":height_b,
		"served_ports":served,"component_a":a.component,"component_b":b.component,
		"center":(from+to)*.5,"span_m":span,"deck_y":deck,"max_grade":max_grade,
		"island_component":island,"kind":("Island-to-island link" if a.component!=_mainland and b.component!=_mainland else "Island connection") if island>=0 else "Mainland shortcut",
		"score":span+access*.6+max_grade*600+absf(height_a-height_b)*5-(2500 if island>=0 else 0)}

func _label_land() -> void:
	# Physical terrain occupancy includes the dry coastal apron.
	_n = 801
	_step = _layout.world_size_m/float(_n-1)
	_components.resize(_n*_n)
	_components.fill(-1)
	_edges.resize(_n*_n)
	_edges.fill(0)
	for z in _n:
		for x in _n:
			if _dry(_point(z*_n+x)): _components[z*_n+x]=-2
	var id := 0
	var largest := 0
	for start in _components.size():
		if _components[start] != -2: continue
		var queue := PackedInt32Array([start])
		_components[start]=id
		var head := 0
		var touches_boundary := false
		while head<queue.size():
			var at := queue[head]; head+=1
			var x := at%_n; var z := at/_n
			if x==0 or x==_n-1 or z==0 or z==_n-1: touches_boundary=true
			for next in _neighbors(at):
				if _components[next] != -2: continue
				if not _land_edge(at,next): continue
				_components[next]=id
				queue.append(next)
		if touches_boundary and queue.size()>largest:
			largest=queue.size(); _mainland=id
		_areas[id]=queue.size()*_step*_step
		id+=1

func _point(index: int) -> Vector2:
	return Vector2(index%_n,index/_n)*_step-Vector2.ONE*_layout.half_extent_m

func _index(at: Vector2) -> int:
	var cell := (at+Vector2.ONE*_layout.half_extent_m)/_step
	return clampi(roundi(cell.y),0,_n-1)*_n+clampi(roundi(cell.x),0,_n-1)

func _nearest_land(at: Vector2) -> int:
	var center := _index(at)
	var best := -1
	var distance := INF
	for dz in range(-2,3):
		for dx in range(-2,3):
			var x := center%_n+dx; var z := center/_n+dz
			if x<0 or x>=_n or z<0 or z>=_n: continue
			var index := z*_n+x
			if _components[index]<0: continue
			var d := at.distance_squared_to(_point(index))
			if d>=distance: continue
			var clear := true
			for fraction in [.25,.5,.75]:
				if not _dry(at.lerp(_point(index),fraction)): clear=false;break
			if clear: best=index;distance=d
	return best

func _component_at(at: Vector2) -> int:
	var index := _nearest_land(at)
	return _components[index] if index>=0 else -1

func _neighbors(index: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if index%_n>0: result.append(index-1)
	if index%_n<_n-1: result.append(index+1)
	if index>=_n: result.append(index-_n)
	if index<_n*(_n-1): result.append(index+_n)
	return result

func _land_edge(a: int,b: int) -> bool:
	var index := mini(a,b)
	var shift := 0 if absi(a-b)==1 else 2
	var known := 1<<shift
	var pass_bit := 2<<shift
	if (_edges[index]&known)!=0: return (_edges[index]&pass_bit)!=0
	var clear := true
	for fraction in [.25,.5,.75]:
		if not _dry(_point(a).lerp(_point(b),fraction)): clear=false;break
	_edges[index] |= known
	if clear: _edges[index] |= pass_bit
	return clear

func _short_land_path(a: Vector2,b: Vector2,limit: float) -> bool:
	var start := _nearest_land(a); var goal := _nearest_land(b)
	if start<0 or goal<0: return true # unresolved topology is not evidence of a shortcut
	if _components[start]!=_components[goal]: return false
	var queue := PackedInt32Array([start])
	var distances := {start:0.0}
	var head := 0
	while head<queue.size():
		var at := queue[head]; head+=1
		if at==goal: return true
		if distances[at]+_step>limit: continue
		for next in _neighbors(at):
			if distances.has(next) or _components[next]!=_components[start]: continue
			if not _land_edge(at,next): continue
			distances[next]=distances[at]+_step
			queue.append(next)
	return false

func _dry(at: Vector2) -> bool:
	# Macro land heights are clamped above zero before the +2.5m datum;
	# skerries only raise that surface. Skip all noise evaluation inland.
	if _layout.sample_macro_signed_distance(at)<0: return true
	return _layout.sample_height(at)>WaveSurface.WATER_LEVEL+.25

func _nearby_demand(at: Vector2) -> Dictionary:
	if _demand_cache.has(at): return _demand_cache[at]
	var best := {}
	var component := _component_at(at)
	var distance := 1800.0
	for demand in _demands:
		var d: float = at.distance_to(demand.at)
		if d<distance and demand.component==component:
			best=demand;distance=d
	_demand_cache[at]=best
	return best

func _terminal(component: int) -> bool:
	# Size alone does not justify connecting an uninhabited island.
	return component==_mainland or _port_components.has(component)

static func _root(parent: Dictionary, component: int) -> int:
	while parent[component]!=component: component=parent[component]
	return component

func _landing(end: Dictionary) -> Dictionary:
	var point: Vector2 = end.point
	if _landing_cache.has(point): return _landing_cache[point]
	_landing_cache[point]={}
	var height := _layout.sample_height(point)
	if height<WaveSurface.WATER_LEVEL+1: return {}
	var previous := height
	var grade := 0.0
	for i in range(1,6):
		var at: Vector2 = point-end.normal*float(i)*20
		var h := _layout.sample_height(at)
		if h<WaveSurface.WATER_LEVEL+1: return {}
		grade=maxf(grade,absf(h-previous)/20)
		previous=h
	if grade>.40: return {}
	var result := {"height":height,"grade":grade}
	_landing_cache[point]=result
	return result
