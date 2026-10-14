class_name CoastalBirdGroup
extends Node3D
## One flock, one batched distant draw. Detailed nodes exist only close by.
var record: Dictionary
var disturbance: Dictionary = {}
var interest_weight := 0.0
var interest_position := Vector3.ZERO
var interest_velocity := Vector3.ZERO
var interest_id := ""
var threats: Array=[]
var escapes: Dictionary={}
var last_positions: Dictionary={}
var approach_states: Dictionary={}


func update_interest(vessels: Array, seconds: float, delta: float) -> void:
	if record.species!="herring_gull": return
	threats=vessels
	var chosen: Dictionary={}
	var nearest := 260.0
	for vessel: Dictionary in vessels:
		if vessel.get("kind","boat")=="player": continue
		if seconds-float(vessel.get("time",0))>12: continue
		var at:=Vector3(float(vessel.x),global_position.y,float(vessel.z))
		var distance:=global_position.distance_to(at)
		if distance<nearest:
			nearest=distance;chosen=vessel
	if not chosen.is_empty():
		var target:=Vector3(float(chosen.x),global_position.y,float(chosen.z))
		if interest_weight<0.001: interest_position=target
		interest_position=interest_position.lerp(target,1-exp(-delta*2))
		interest_velocity=interest_velocity.lerp(Vector3(float(chosen.get("vx",0)),0,float(chosen.get("vz",0))),1-exp(-delta))
		interest_id=str(chosen.id)
	interest_weight=move_toward(interest_weight,0.0 if chosen.is_empty() else 1.0,delta/5.0)

func interested_position(index: int,seconds: float) -> Vector3:
	var u:=CoastalBirdMotion.unit(int(record.seed),index,601)
	var angle:=seconds*lerpf(0.13,0.24,u)+u*TAU
	var radius:=lerpf(12,23,CoastalBirdMotion.unit(int(record.seed),index,602))
	var wander:=CoastalBirdMotion.wander(int(record.seed),index+650,seconds/7)
	var circle:=Vector3(cos(angle)*radius,4+wander.y*5,sin(angle)*radius)+Vector3(wander.x,0,wander.z)*5
	var forward:=interest_velocity.normalized() if interest_velocity.length()>0.1 else Vector3.FORWARD
	var side:=forward.cross(Vector3.UP)
	var wake:=-forward*lerpf(20,55,u)+side*wander.x*24+Vector3.UP*(7+wander.y*8)
	return interest_position-global_position+circle.lerp(wake,smoothstep(0.5,2.5,interest_velocity.length()))

var detailed := false
var birds: Array[CoastalGull] = []
var profiles: Array[GullProfile] = []
var far_rest: MultiMeshInstance3D
var far: MultiMeshInstance3D
static var meshes: Dictionary = {}
var _pose_wait := 0.0

func _ready() -> void:
	position = record.anchor
	for i in int(record.count):
		var profile := GullProfile.seeded(record.seed,i,4.0,1.0,0.6)
		profile.species = record.species
		if profile.species == "white_tailed_eagle": profile.flap_hz=0.65
		elif profile.species == "arctic_tern": profile.flap_hz=3.0
		profiles.append(profile)
	far = MultiMeshInstance3D.new()
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.multimesh = MultiMesh.new()
	far.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	far.multimesh.mesh = distance_mesh(record.species)
	far.multimesh.instance_count = int(record.count)
	add_child(far)
	if record.species == "herring_gull":
		far_rest = MultiMeshInstance3D.new()
		far_rest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far_rest.multimesh = MultiMesh.new()
		far_rest.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		far_rest.multimesh.mesh = distance_mesh("herring_gull_rest")
		far_rest.multimesh.instance_count = int(record.count)
		add_child(far_rest)

static func distance_mesh(species: String) -> Mesh:
	if meshes.has(species): return meshes[species]
	var scene := load("res://resources/models/wildlife/"+species+"_far.glb") as PackedScene
	var model := scene.instantiate()
	var parts := model.find_children("*","MeshInstance3D",true,false)
	var mesh: Mesh = (parts[0] as MeshInstance3D).mesh
	meshes[species]=mesh
	model.free()
	return mesh

func set_detail(value: bool) -> void:
	if value==detailed: return
	detailed=value
	if not detailed:
		for bird in birds: bird.queue_free()
		birds.clear()
	far.visible=not detailed

func present(seconds: float, delta: float) -> void:
	# Bound construction to two detailed birds per rendered frame.
	if detailed:
		for i in mini(2,profiles.size()-birds.size()):
			var bird := CoastalGull.new()
			bird.profile=profiles[birds.size()]
			add_child(bird)
			birds.append(bird)
		far.visible = birds.size()<profiles.size()
	if far_rest: far_rest.visible = far.visible
	_pose_wait-=delta
	if not detailed and _pose_wait>0: return
	_pose_wait=0.08
	for i in profiles.size():
		var motion := CoastalBirdMotion.sample(record.seed,i,seconds,record.species,disturbance)
		steer_interest(i,seconds,delta,motion)
		apply_threat_response(i,seconds,motion)
		last_positions[i]=motion.position
		if approach_states.has(i):
			approach_states[i].position=motion.position
			approach_states[i].velocity=motion.velocity
		var at := motion.position
		var forward := motion.velocity.normalized() if motion.velocity.length_squared()>0.05 else motion.heading
		var facing := Basis.looking_at(forward,Vector3.FORWARD if absf(forward.dot(Vector3.UP))>0.98 else Vector3.UP)
		var water_weight := motion.water_weight()
		if water_weight>0:
			var water := WaveSurface.sample_at(global_position.x+at.x,global_position.z+at.z)
			at.y+=(water.height-WaveSurface.WATER_LEVEL)*water_weight+0.012
			facing=Basis(facing.get_rotation_quaternion().slerp(CoastalGull.water_basis(motion.heading,water.normal).get_rotation_quaternion(),water_weight))
		if detailed and i<birds.size():
			var bird := birds[i]
			bird.position=at
			bird.basis=facing
			if motion.stage==GullWaterBehaviour.Stage.FLYING:
				var glide := 0.96 if record.species=="white_tailed_eagle" else (0.15 if record.species=="arctic_tern" else smoothstep(0.2,0.8,sin(seconds*0.55+profiles[i].phase_offset)))
				bird.pose(seconds,glide)
			else: bird.pose_water(seconds,motion)
			bird.update_audio(seconds,motion)
			far.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),at))
			if far_rest: far_rest.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),at))
		else:
			var resting := far_rest != null and water_weight > 0.5
			var pose := Transform3D(facing.scaled(Vector3.ONE*profiles[i].size_scale),at)
			var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),at)
			far.multimesh.set_instance_transform(i,hidden if resting else pose)
			if far_rest: far_rest.multimesh.set_instance_transform(i,pose if resting else hidden)

func apply_threat_response(index: int,seconds: float,motion: GullWaterBehaviour) -> void:
	if record.species!="herring_gull": return
	var actual: Vector3=last_positions.get(index,motion.position)
	var escape: Dictionary=escapes.get(index,{})
	# Evaluate real/presented bird position and a short vessel approach prediction.
	if escape.is_empty() or seconds-float(escape.started)>4.0:
		for vessel: Dictionary in threats:
			if seconds-float(vessel.get("time",0))>12: continue
			var at:=Vector3(float(vessel.x),global_position.y,float(vessel.z))-global_position
			var velocity:=Vector3(float(vessel.get("vx",0)),0,float(vessel.get("vz",0)))
			var radius:=3.5 if vessel.get("kind","boat")=="player" else (18.0 if velocity.length()>0.8 else 7.0)
			var offset:=Vector3(actual.x-at.x,0,actual.z-at.z)
			var ahead:=clampf(offset.dot(velocity)/maxf(velocity.length_squared(),0.01),0,1.5)
			if actual.y>12 or (offset-velocity*ahead).length()>radius: continue
			var away:=offset.normalized()
			if away.length_squared()<0.1: away=Vector3.FORWARD.rotated(Vector3.UP,CoastalBirdMotion.unit(record.seed,index,903)*TAU)
			# A cross-track component prevents fleeing straight along an oncoming bow.
			if velocity.length()>0.8: away=(away+velocity.normalized().cross(Vector3.UP)*(1 if index%2==0 else -1)).normalized()
			escape={"started":seconds,"from":actual,"to":actual+away*23+Vector3.UP*maxf(9,14-actual.y)}
			escapes[index]=escape
			break
	if escape.is_empty(): return
	var elapsed:=seconds-float(escape.started)
	if elapsed>8:
		escapes.erase(index);return
	var launch:=smoothstep(0,2.5,elapsed)
	var destination: Vector3=escape.to
	var position: Vector3=Vector3(escape.from).lerp(destination,launch)
	if elapsed>2.5: position+=CoastalBirdMotion.wander(record.seed,index+920,seconds/3)*2*smoothstep(2.5,3.5,elapsed)
	var recovery:=smoothstep(4,8,elapsed)
	motion.position=position.lerp(motion.position,recovery)
	var travel:=destination-Vector3(escape.from)
	motion.velocity=travel.normalized()*8
	motion.heading=Vector3(travel.x,0,travel.z).normalized()
	motion.startled=true
	motion.stage=GullWaterBehaviour.Stage.TAKING_OFF if elapsed<2.5 else GullWaterBehaviour.Stage.FLYING
	motion.elapsed=elapsed
	motion.duration=2.5
	motion.departure_fold=1.0 if Vector3(escape.from).y<0.5 else 0.0

func steer_interest(index: int,seconds: float,delta: float,motion: GullWaterBehaviour) -> void:
	if record.species!="herring_gull" or index>=6: return
	var interested:=interest_weight>0.01
	if not interested and not approach_states.has(index): return
	if not approach_states.has(index):
		approach_states[index]={"position":motion.position,"velocity":motion.velocity,"started":seconds,"from_water":motion.position.y<0.5}
	var state: Dictionary=approach_states[index]
	var position: Vector3=state.position
	var velocity: Vector3=state.velocity
	var target:=interested_position(index,seconds+2.5) if interested else motion.position
	var offset:=target-position
	var cruise:=lerpf(5.5,8.0,CoastalBirdMotion.unit(record.seed,index,980))
	# Pursue a point ahead of the loose circuit, not a prescribed position.
	# Integrate bounded acceleration so entering/leaving interest never teleports
	# or changes the bird's flight direction instantly.
	var desired:=offset.normalized()*minf(cruise,offset.length()*0.8)
	desired.y=clampf(offset.y*0.7,-2.0,3.0)
	var step:=minf(delta,0.1)
	velocity=velocity.move_toward(desired,3.0*step)
	position+=velocity*step
	if not interested and position.distance_to(motion.position)<2.0 and velocity.distance_to(motion.velocity)<2.0:
		approach_states.erase(index)
		return
	state.position=position;state.velocity=velocity
	motion.position=position;motion.velocity=velocity
	if velocity.length_squared()>0.01: motion.heading=Vector3(velocity.x,0,velocity.z).normalized()
	var elapsed:=seconds-float(state.started)
	motion.stage=GullWaterBehaviour.Stage.TAKING_OFF if bool(state.from_water) and elapsed<3.0 else GullWaterBehaviour.Stage.FLYING
	motion.elapsed=elapsed;motion.duration=3.0
	motion.departure_fold=1.0 if bool(state.from_water) else 0.0
