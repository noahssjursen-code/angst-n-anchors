class_name CoastalBirdWorld
extends Node3D
## Gameplay world component, deliberately absent from menus/shipyard previews.
const MAX_GROUPS := 8
var layout: WorldLayout
var exclusions: Array = []
var groups: Dictionary = {}
var habitat_cache: Dictionary = {}
var disturbances: Dictionary = {}
var vessel_observations: Array = []
var clock_provider: Callable # Isolated deterministic review/test scenes only.
var _stream_wait := 0.0
var _network_wait := 0.0
var _pending := false
var _remote_ready := false
var _session := ""
var _unsupported := false
var observed_positions: Dictionary = {}

func _ready() -> void:
	set_process(true)

func configure(value: WorldLayout, zones: Array) -> void:
	layout=value
	exclusions=zones

func _process(delta: float) -> void:
	if layout==null or get_viewport().get_camera_3d()==null: return
	var seconds := WorldGateway.server_unix_seconds()
	if clock_provider.is_valid() and not WorldGateway.is_remote(): seconds=float(clock_provider.call())
	if WorldGateway.is_remote():
		var token := WorldGateway.session_token()
		if token != _session:
			_session=token
			_remote_ready=false
			_pending=false
			_unsupported=false
			disturbances.clear()
			vessel_observations.clear()
		_network_wait-=delta
		if WorldGateway.is_ready() and not _pending and not _unsupported and _network_wait<=0:
			_pending=true
			_network_wait=0.5
			WorldGateway.fetch_wildlife(func(response: Dictionary):
				if token != _session: return
				_pending=false
				if int(response.get("status",0))==404:
					_unsupported=true
					push_warning("Coastal birds require the server wildlife update; hiding birds until supported.")
					return
				var data: Dictionary=response.get("payload",{})
				if not bool(response.get("transport_ok",false)) or int(data.get("version",0))!=1:
					_network_wait=4.0
					return
				_remote_ready=true
				vessel_observations=data.get("boats",[])
				for event in data.get("disturbances",[]):
					if event is Dictionary: disturbances[str(event.get("id",""))]=event
			)
		visible=_remote_ready
		if not _remote_ready: return
	else:
		visible=true
	# Visible replicated vessels are already authoritative observations. Do not make
	# reactions depend on an optional HTTP boats field or a separate deployment.
	var observations := scene_observations(seconds,delta)
	if observations.is_empty(): observations=vessel_observations
	for key in disturbances.keys():
		if seconds>float(disturbances[key].get("until",0))+8: disturbances.erase(key)
	_stream_wait-=delta
	var observer := WorldReference.visual_position(get_viewport())
	if _stream_wait<=0:
		_stream_wait=0.5
		_stream(observer)
	for group: CoastalBirdGroup in groups.values():
		var distance := observer.distance_to(group.global_position)
		group.set_detail(distance<(230.0 if group.detailed else CoastalBirdHabitat.DETAIL_RANGE))
		group.disturbance=disturbances.get(group.record.id,{}) if observations.is_empty() else {}
		group.update_interest(observations,seconds,delta)
		group.present(seconds,delta)

func _stream(observer: Vector3) -> void:
	var center := Vector2i(floori(observer.x/256.0),floori(observer.z/256.0))
	var candidates: Array[Dictionary]=[]
	for x in range(center.x-5,center.x+6):
		for z in range(center.y-5,center.y+6):
			var cell:=Vector2i(x,z)
			var at:=CoastalBirdHabitat.anchor(cell)
			if observer.distance_to(at)>CoastalBirdHabitat.RANGE: continue
			var id:=CoastalBirdHabitat.identity(cell)
			if not habitat_cache.has(id): habitat_cache[id]=CoastalBirdHabitat.record(cell,layout,exclusions)
			var record: Dictionary=habitat_cache[id]
			if not record.is_empty(): candidates.append(record)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return observer.distance_squared_to(a.anchor)<observer.distance_squared_to(b.anchor))
	var wanted: Dictionary={}
	for i in mini(MAX_GROUPS,candidates.size()): wanted[candidates[i].id]=candidates[i]
	# Reserve a slot for a visible non-gull species instead of allowing all eight
	# nearest gull patches to hide rarer coastal wildlife.
	for species in ["white_tailed_eagle","arctic_tern"]:
		for candidate in candidates:
			if candidate.species!=species: continue
			if not wanted.has(candidate.id):
				for key in wanted.keys().duplicate().slice(0):
					if wanted[key].species=="herring_gull": wanted.erase(key);break
				if wanted.size()<MAX_GROUPS: wanted[candidate.id]=candidate
			break
	for id in groups.keys():
		if not wanted.has(id):
			groups[id].queue_free()
			groups.erase(id)
	for id in wanted:
		if groups.has(id): continue
		var group:=CoastalBirdGroup.new()
		group.record=wanted[id]
		add_child(group)
		groups[id]=group
	# Keep discovery bounded during long free-camera trips.
	if habitat_cache.size()>2048: habitat_cache.clear()

func _disturb_local_vessels(seconds: float) -> void:
	# Same cell/range/hold rule as the authority, using actual local world boats.
	for boat in get_tree().get_nodes_in_group("wildlife_vessels"):
		if not boat is Node3D: continue
		var at: Vector3=boat.global_position
		var cell:=Vector2i(floori(at.x/256.0),floori(at.z/256.0))
		var anchor:=CoastalBirdHabitat.anchor(cell)
		if Vector2(at.x-anchor.x,at.z-anchor.z).length()>100: continue
		var id:=CoastalBirdHabitat.identity(cell)
		if not disturbances.has(id) or seconds>float(disturbances[id].until)+8:
			disturbances[id]={"id":id,"started":seconds,"until":seconds+60}
		disturbances[id].until=seconds+60

func scene_observations(seconds: float,delta: float) -> Array:
	var out: Array=[]
	var seen: Dictionary={}
	for category in ["wildlife_vessels","player"]:
		for body in get_tree().get_nodes_in_group(category):
			if not body is Node3D or not body.is_visible_in_tree(): continue
			var id:=str(body.get_instance_id())
			var at: Vector3=body.global_position
			var speed:=Vector3.ZERO
			if observed_positions.has(id) and delta>0:
				speed=(at-Vector3(observed_positions[id]))/delta
				speed.y=0
				speed=speed.limit_length(35)
			elif body is RigidBody3D: speed=body.linear_velocity
			observed_positions[id]=at;seen[id]=true
			out.append({"id":id,"x":at.x,"z":at.z,"vx":speed.x,"vz":speed.z,"time":seconds,"kind":"player" if category=="player" else "boat"})
	for id in observed_positions.keys():
		if not seen.has(id): observed_positions.erase(id)
	return out
