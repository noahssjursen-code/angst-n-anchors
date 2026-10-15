class_name RodFishingStation
extends Node3D

var personal_player: CharacterBody3D
var equipment_id:="fishing_rod"
var _stored_rod:Node3D
var _harpe_model:Node3D
var _harpe_rig:HarpeRigVisual
var inspect_mode:=false
var working := false
var _interaction: Area3D
var _carried: Node3D
var _hand_pose: SkeletonModifier3D
var _rod_parts: Array[Dictionary] = []
var session:=RodFishingSession.new()
var _cast_at := Vector2.ZERO
var _cast_from := Vector3.ZERO
var _cast_time := 0.0
var _cast_span := 0.0
var _bend := 0.0
var _rod_root: Node3D
var _flex: Array[Node3D] = []
var _crank: Node3D
var _fish: Node3D
var _fish_species := ""
var _fish_mouth := Vector3.ZERO
var _splash: MeshInstance3D
var _splash_age := 9.0
var _last_phase := "stowed"
var _boat:BoatBody
var _timer:=0.0
var authored_station:Node3D
var _tip:Node3D
var _tackle:Node3D
var _line:MeshInstance3D
var _reserved_fish:=""
var _rope:=FishingLineShape.new()
var _pending_catches: Dictionary = {}
var remote_player: Node3D
var remote_pose := Transform3D.IDENTITY
var remote_hook := Vector3.ZERO
var visual_hook := Vector3.ZERO
var _remote_display_pose := Transform3D.IDENTITY
var _remote_display_hook := Vector3.ZERO
var _remote_initialized := false

func _init()->void:
	add_to_group("ship_owner_only")
	add_to_group("rod_fishing_stations")

func _ready()->void:
	# Player._process finalizes deck riding and camera pose at priority zero.
	# Update both rod and its world-space line afterwards, in the same render frame.
	process_priority=100
	var node:=get_parent()
	while node!=null:
		if node is BoatBody: _boat=node;break
		node=node.get_parent()
	if _boat==null and remote_player==null and personal_player==null:return
	assert(authored_station!=null,"Rod gameplay requires installed authored equipment")
	_interaction = Area3D.new()
	_interaction.collision_layer = 0 if personal_player!=null else 16
	_interaction.collision_mask = 0
	authored_station.add_child(_interaction)
	_interaction.position = Vector3(0, 1.0, 0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	_interaction.add_child(shape)
	_rod_root=authored_station.find_child("FishingRod",true,false)
	assert(_rod_root!=null,"Rod model requires portable FishingRod group")
	_tip=_rod_root.find_child("LineTip*",true,false)
	for joint in _rod_root.find_children("RodFlex*","Node3D",true,false):_flex.append(joint)
	_crank=_rod_root.find_child("ReelCrank*",true,false)
	_tackle=load("res://resources/models/fishing_items/heavy_pilk.glb").instantiate();add_child(_tackle);_tackle.visible=false
	_line=MeshInstance3D.new();_line.mesh=ImmediateMesh.new()
	var filament:=StandardMaterial3D.new();filament.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	# Opaque filament participates in scene depth and the ocean transmission buffer.
	# Alpha-sorted line was missing from that buffer and covered by near water.
	filament.albedo_color=Color(.65,.76,.72,1)
	_line.material_override=filament;_line.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(_line)
	_line.top_level=true;_line.global_transform=Transform3D.IDENTITY
	_line.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	filament.cull_mode=BaseMaterial3D.CULL_DISABLED
	_splash=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=.9;ring.outer_radius=1
	_splash.mesh=ring;var foam:=StandardMaterial3D.new();foam.albedo_color=Color(.85,.94,.93,.7);foam.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash.material_override=foam;_splash.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(_splash);_splash.hide()
	_stored_rod=_rod_root
	if remote_player==null and personal_player==null:
		PlayerSession.vessels_synced.connect(_refresh_equipment)
		call_deferred("_refresh_equipment")


func _deck_player() -> CharacterBody3D:
	if personal_player!=null:
		return personal_player if not personal_player.is_vehicle_occupied() and not LocalPlayerView.is_helming() else null
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null or player.is_vehicle_occupied() or LocalPlayerView.is_helming(): return null
	if LocalPlayerView.get_active_ship() != _boat: return null
	return player

func can_interact() -> bool:
	if remote_player!=null or personal_player!=null:return false
	if not _authority_available() or GameMenu.is_modal_open(): return false
	var player := _deck_player()
	if player == null or player.global_position.distance_to(authored_station.global_position) > 2.4: return false
	var camera := player.get_node("Camera3D") as Camera3D
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position-camera.global_basis.z*3.0, 21)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Node = hit.get("collider")
	return collider == _interaction or (collider != null and authored_station.is_ancestor_of(collider))

func _unhandled_input(event: InputEvent) -> void:
	if remote_player!=null or personal_player!=null:return
	if not event.is_action_pressed("interact") or GameMenu.is_modal_open(): return
	if working:
		for hold in CatchHoldComponent.get_all_for_ship(_boat):
			if hold.can_inspect(): return
		if not can_interact():
			session.message = "Return to the equipment mount to put it down"
		elif session.phase not in ["stowed","landed","charging"]:
			session.message = "Recover the line before putting the equipment down"
		else:
			session.recover()
			working = false
			_carry(false)
		get_viewport().set_input_as_handled()
	elif can_interact():
		working = true
		_carry(true)
		get_viewport().set_input_as_handled()

func _carry(value: bool) -> void:
	if value and is_instance_valid(_carried):return
	if value:
		var player:Node3D = remote_player if remote_player!=null else _deck_player()
		if player == null: return
		_carried = Node3D.new();player.add_child(_carried)
		_carried.top_level=true
		_carried.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		_carried.position=Vector3(.16,-.18,-.30)
		_rod_parts.append({"node":_rod_root,"parent":_rod_root.get_parent(),"transform":_rod_root.transform})
		_rod_root.reparent(_carried,false);_rod_root.transform=Transform3D.IDENTITY
		var body:=player.get_node_or_null("BodyMesh") as NpcBase
		if body!=null and body.visual!=null and body.visual.skeleton!=null:
			_hand_pose=preload("res://scripts/character/rod_hand_pose.gd").new()
			_hand_pose.rod=_rod_root
			_hand_pose.handline=equipment_id=="harpe"
			_hand_pose.hand_mesh=body.visual.get_part("Hands")
			_hand_pose.right_grip=_rod_root.find_child("RightGrip",true,false)
			_hand_pose.left_grip=_rod_root.find_child("LeftGrip",true,false)
			body.visual.skeleton.add_child(_hand_pose)
	else:
		if is_instance_valid(_hand_pose):_hand_pose.release()
		_hand_pose=null
		for part in _rod_parts:
			if is_instance_valid(part.node) and is_instance_valid(part.parent):
				part.node.reparent(part.parent,false);part.node.transform=part.transform
		_rod_parts.clear()
		if is_instance_valid(_carried):_carried.queue_free()
		_carried=null
		for joint in _flex:joint.rotation=Vector3.ZERO

func _exit_tree() -> void:
	if remote_player==null:
		if session is HarpeFishingSession:session.release_fish()
		if FishingField.habitat!=null:FishingField.habitat.set_hooked(_reserved_fish,false)
	if is_instance_valid(_hand_pose):_hand_pose.release()
	if is_instance_valid(_carried):
		# Reparenting during teardown is unsafe. These visuals belong to this ship.
		_carried.queue_free()

func snapshot()->Dictionary:
	return {"total_catch_kg":_batch_mass(),"total_catch_value":_batch_value(),"equipment":equipment_id,"hook_count":session.catches.size() if session is HarpeFishingSession else 0,"working":working,"phase":session.phase,"line_m":session.depth_m,"bottom_m":session._bottom,"line_action":session.line_action,"tension":session.tension,"message":session.message,"charge":session.charge,"control":session.control,"fish_position":session.fish_position,"band_width":session.band_width,"progress":session.progress,"catch":session.catch_data}

func _free_space() -> float:
	var free:=0.0
	for hold in CatchHoldComponent.get_all_for_ship(_boat):free=maxf(free,hold.state.available_kg())
	return free

func _drop() -> void:
	var target:=_tip.global_position
	target.y=WaveSurface.WATER_LEVEL
	var player:=_deck_player()
	var query:=PhysicsRayQueryParameters3D.create(_tip.global_position,target,5)
	if player!=null:query.exclude=[player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		session.recover("Move to the rail with the tackle over open water");return
	_cast_at=Vector2(target.x,target.z);_cast_span=0
	session.drop(WaveSurface.WATER_LEVEL-FishingField.habitat.bottom(_cast_at),_free_space())

func _physics_process(delta:float)->void:
	if not is_instance_valid(_boat) or FishingField.habitat==null or not _authority_available():
		if personal_player!=null and session.phase not in ["stowed","landed"]:session.recover("Stand on a vessel deck to fish.")
		return
	if personal_player==null and LocalPlayerView.get_active_ship()!=_boat and not (inspect_mode and ShipyardPlaytestMode.active()):return
	var controls:=((working and _deck_player()!=null) or (inspect_mode and ShipyardPlaytestMode.active())) and not LocalPlayerView.is_helming() and not GameMenu.is_modal_open()
	if working and _deck_player()==null:
		working=false;session.recover();_carry(false)
	if controls:
		if Input.is_action_just_pressed("fishing_lower") and session.phase in ["stowed","landed"]:
			session.recover();_drop()
		if Input.is_action_just_pressed("fishing_rod") and session.phase=="bite":session.strike(WorldClock.get_game_hours_elapsed())
	var dt:=delta
	var catch_result:=session.advance(dt,_hook_at(),Vector2(_boat.linear_velocity.x,_boat.linear_velocity.z).length(),controls and Input.is_action_pressed("fishing_reel"),controls and Input.is_action_pressed("fishing_lower"),FishingField.habitat,WorldClock.get_game_hours_elapsed())
	if not catch_result.is_empty():
		if catch_result.has("catches"):
			for caught:Dictionary in catch_result.catches:_store_catch(caught)
		else:_store_catch(catch_result)
	var hooked:=str(session.catch_data.get("fish_id","")) if session.phase=="fighting" and not session is HarpeFishingSession else ""
	if hooked!=_reserved_fish:
		FishingField.habitat.set_hooked(_reserved_fish,false)
		_reserved_fish=hooked
		FishingField.habitat.set_hooked(_reserved_fish,true)
	if session.phase=="fishing" and _last_phase=="casting":
		_splash.global_position=Vector3(_cast_at.x,WaveSurface.WATER_LEVEL+.025,_cast_at.y);_splash_age=0
	_last_phase=session.phase

func _process(delta: float) -> void:
	if (_boat==null and remote_player==null and personal_player==null) or not is_instance_valid(_tip):return
	if not working and session.phase=="stowed" and not _line.visible:return
	_update_visual(delta,working and not GameMenu.is_modal_open())

func _hook_at() -> Vector2:
	var origin:=Vector2(_tip.global_position.x,_tip.global_position.z)
	return origin.lerp(_cast_at,clampf(session.reach_m/maxf(.01,_cast_span),0,1))

func _store_catch(data: Dictionary) -> void:
	var record:=data.duplicate(true)
	record.merge({"lot_id":PlayerData.new_uuid(),"caught_game_hours":WorldClock.get_game_hours_elapsed(),"caught_position":_cast_at,"vessel_id":str(_boat.get_meta("vessel_uid","")),"owner_id":str(LocalPlayerView.get_network_player_id())},true)
	var lot:=CatchLot.create(record)
	if WorldGateway.is_remote():
		var service := WorldGateway.fishing_catches
		if service == null or not _authority_available():
			session.message = "Server unavailable; catch was not stored"
			return
		var vessel_id := str(_boat.get_meta("server_vessel_id", ""))
		for hold in CatchHoldComponent.get_all_for_ship(_boat):
			if hold.state.available_kg() - service.pending_mass(vessel_id, hold.hold_id) < lot.mass_kg: continue
			if not service.catch_finished.is_connected(_on_catch_finished): service.catch_finished.connect(_on_catch_finished)
			_pending_catches[lot.lot_id] = true
			service.submit(vessel_id, hold.hold_id, lot.to_dict(), data)
			session.message = "Storing catch on server…"
			return
		session.message = "Crate full; fish released"
		return
	for hold in CatchHoldComponent.get_all_for_ship(_boat):
		if hold.state.available_kg()>=lot.mass_kg:
			if hold.accept_lot(lot).is_empty():
				FishingField.habitat.take_one(data.school_id,str(data.get("fish_id","")))
				session.message+=" · Stored in the deck crate"
				return
	session.message+=" · Crate full; fish released"

func _authority_available() -> bool:
	if remote_player!=null:return false
	if not WorldGateway.is_remote(): return true
	return WorldGateway.is_ready() and WorldGateway.fishing_catches != null and (personal_player!=null or FishingCatchReplication.owns_ship(_boat))

func _on_catch_finished(lot_id: String, _ok: bool, message: String) -> void:
	if not _pending_catches.has(lot_id): return
	_pending_catches.erase(lot_id)
	session.message = message

func _update_visual(delta: float, controls: bool) -> void:
	if remote_player!=null:
		var blend:=1.0-exp(-delta*18.0) if _remote_initialized else 1.0
		_remote_display_pose=_remote_display_pose.interpolate_with(remote_pose,blend)
		_remote_display_hook=_remote_display_hook.lerp(remote_hook,blend)
		_remote_initialized=true
	var fishing:=session.phase in ["casting","fishing","bite","fighting"]
	if equipment_id=="harpe":
		var stored:=_rod_root.find_child("StoredTackle",true,false) as Node3D
		if stored!=null:stored.visible=session.phase in ["stowed","charging"]
	var time:=float(Time.get_ticks_msec())*.001
	var target_bend:=.09+.16*session.tension if session.phase=="fighting" else (.045+.015*sin(time*25) if session.phase=="bite" else (.028 if fishing else 0.0))
	_bend=lerpf(_bend,target_bend,1-exp(-delta*12))
	var pull_target:=remote_player.to_global(_remote_display_hook) if remote_player!=null else Vector3(_cast_at.x,WaveSurface.WATER_LEVEL-session.depth_m,_cast_at.y)
	var pull:=_rod_root.global_basis.inverse()*(pull_target-_tip.global_position).normalized()
	var bend_axis:=Vector3.FORWARD.cross(pull).normalized()
	if bend_axis.length_squared()<.5:bend_axis=Vector3.LEFT
	for i in _flex.size():_flex[i].quaternion=Quaternion(bend_axis,_bend*float(i+1)/_flex.size())
	if is_instance_valid(_carried) and remote_player!=null:
		_carried.global_transform=remote_player.global_transform*_remote_display_pose
	elif is_instance_valid(_carried):
		var player:=_deck_player()
		if player==null:return
		var camera:=player.get_node("Camera3D") as Camera3D
		var controller:=player.get_node("PlayerCamera") as PlayerCamera
		# Aim from the torso; camera offsets must not add to arm reach.
		var anchor:=Transform3D(camera.global_basis,player.global_position+Vector3.UP*1.42)
		if controller.is_third_person():
			# Orbiting the camera must never drag equipment away from the person.
			var body:=player.get_node("BodyMesh") as Node3D
			anchor.basis=Basis(Vector3.UP,body.global_rotation.y)
		else:
			var body:=player.get_node("BodyMesh") as NpcBase
			if body!=null and body.visual!=null:
				anchor.origin+=body.visual.presentation_offset_world()
		_carried.global_transform=anchor*Transform3D(Basis.IDENTITY,(Vector3(.07,.08,-.45) if equipment_id=="harpe" else Vector3(.14,.08,-.40)))
		var angle:=.20
		if session.phase=="charging":angle=.20+session.charge*.85
		elif session.phase=="casting":angle=-.16
		_carried.rotate_object_local(Vector3.RIGHT,angle)
		if session.phase=="fighting":_carried.rotate_object_local(Vector3.BACK,sin(time*4)*.014)
	if is_instance_valid(_crank) and controls and (session.phase=="fighting" or (session.phase=="fishing" and session.line_action=="reel")):_crank.rotation.x+=delta*12
	_splash_age+=delta;_splash.visible=_splash_age<1.3
	if _splash.visible:
		_splash.scale=Vector3.ONE*(.1+_splash_age*.9)
		(_splash.material_override as StandardMaterial3D).albedo_color.a=.65*(1-_splash_age/1.3)
	var show_fish:=session.phase in ["landed","fighting"] and not session.catch_data.is_empty()
	_tackle.visible=fishing and not show_fish
	_line.visible=fishing
	var tip:=_tip.global_position
	var hook_at:=_hook_at()
	var hook:=Vector3(hook_at.x,WaveSurface.WATER_LEVEL-session.depth_m,hook_at.y)
	if session.phase=="casting":
		_cast_time+=delta
		var t:=clampf(_cast_time/.85,0,1)
		hook=_cast_from.lerp(hook,t)+Vector3.UP*sin(t*PI)*3
	elif session.phase=="fighting":
		var remaining:=1.0-session.progress
		var sideways:=Vector3(tip.z-hook.z,0,hook.x-tip.x).normalized()
		hook+=sideways*(session.fish_position-.5)*3.0*remaining
		hook=hook.lerp(tip-Vector3.UP*1.2,session.progress*session.progress)
	if remote_player!=null:hook=remote_player.to_global(_remote_display_hook)
	visual_hook=hook
	if fishing:
		_tackle.global_position=hook;_tackle.global_basis=Basis.IDENTITY
		var slack:=.04 if session.phase=="fighting" else (.65 if session.line_action=="pay" else .20)
		var endpoint:=HarpeRigVisual.leader_top(session,hook,tip) if session is HarpeFishingSession else hook
		var points:=_rope.advance(delta,tip,endpoint,slack)
		var view:=get_viewport().get_camera_3d()
		var line:=_line.mesh as ImmediateMesh;line.clear_surfaces();line.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in points.size():
			var tangent:=points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]
			var side:=tangent.cross(view.global_position-points[i]).normalized()
			var radius:=clampf(view.global_position.distance_to(points[i])*.0002,.0015,.006)
			line.surface_add_vertex(points[i]-side*radius)
			line.surface_add_vertex(points[i]+side*radius)
		line.surface_end()
	else:_rope.clear()
	if show_fish and not session.catch_data.is_empty():
		var id:=str(session.catch_data.species_id)
		if _fish_species!=id or not is_instance_valid(_fish):
			if is_instance_valid(_fish):_fish.queue_free()
			_fish=FishCatalog.model(id);add_child(_fish);_fish_species=id
			_fish.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
			var mouth:=_fish.find_child("MouthHook",true,false) as Node3D
			assert(mouth!=null,"Fish requires a Blender-authored mouth attachment")
			_fish_mouth=_fish.to_local(mouth.global_position)
			for animator in _fish.find_children("*","AnimationPlayer",true,false):
				for clip in animator.get_animation_list():
					if "Swim" in clip:animator.get_animation(clip).loop_mode=Animation.LOOP_LINEAR;animator.play(clip)
		_fish.visible=true
		_fish.scale=Vector3.ONE*float(session.catch_data.length_cm)/100
		if session.phase=="landed":
			var camera:=get_viewport().get_camera_3d()
			var anchor:=remote_player.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.2,-.8)) if remote_player!=null else Transform3D(camera.global_basis, camera.global_position+camera.global_basis*Vector3(-.10,-.16,-1.35))
			_fish.global_transform=anchor
			_fish.scale=Vector3.ONE*minf(1.1,float(session.catch_data.length_cm)/100)
			_fish.rotate_object_local(Vector3.UP,sin(time*2)*.10)
			if id=="halibut":_fish.rotate_object_local(Vector3.RIGHT,.85)
		else:
			_fish.global_transform=FishCatalog.hooked_transform(hook,tip,_fish_mouth,float(session.catch_data.length_cm)/100,sin(time*7)*.12)
	elif is_instance_valid(_fish):_fish.hide()
	if session is HarpeFishingSession and _harpe_rig!=null:
		if is_instance_valid(_fish):_fish.hide()
		_tackle.hide()
		_harpe_rig.update_rig(session,hook,tip,time)



func _refresh_equipment()->void:
	if working:return
	var record:=PlayerSession.data.find_owned_vessel(str(_boat.get_meta("vessel_uid","")))
	var id:=str(record.get("equipped_fishing_item",_boat.get_meta("equipped_fishing_item","fishing_rod")))
	set_equipment(id)

func set_equipment(id:String)->void:
	if working or id==equipment_id or id not in ["fishing_rod","harpe"]:return
	session.recover()
	equipment_id=id
	_flex.clear()
	_stored_rod.visible=id=="fishing_rod"
	if id=="harpe":
		if _harpe_model==null:
			_harpe_model=load("res://resources/models/fishing_items/harpe.glb").instantiate()
			SurfaceMaterialLibrary.apply(_harpe_model,"harpe")
			authored_station.add_child(_harpe_model)
			_harpe_model.transform=_stored_rod.transform
		_harpe_model.show();_rod_root=_harpe_model
		session=HarpeFishingSession.new()
		if _harpe_rig==null:
			_harpe_rig=HarpeRigVisual.new();add_child(_harpe_rig)
	else:
		if _harpe_model!=null:_harpe_model.hide()
		if _harpe_rig!=null:_harpe_rig.hide()
		_rod_root=_stored_rod;session=RodFishingSession.new()
	_tip=_rod_root.find_child("LineTip*",true,false)
	_crank=_rod_root.find_child("ReelCrank*",true,false)
	for joint in _rod_root.find_children("RodFlex*","Node3D",true,false):_flex.append(joint)

func equipment_prompt()->String:
	var label:="harpe" if equipment_id=="harpe" else "rod"
	if personal_player!=null:return "1–6  Select equipment · Hold RMB to lower · Hold LMB to retrieve"
	return "F  Return %s to mount"%label if working else "F  Pick up %s"%label


func _batch_mass()->float:
	if not session is HarpeFishingSession:return float(session.catch_data.get("mass_kg",0))
	var value:=0.0
	for caught in session.catches:value+=float(caught.mass_kg)
	return value

func _batch_value()->int:
	if not session is HarpeFishingSession:
		return roundi(float(session.catch_data.get("mass_kg",0))*float(FishCatalog.species(str(session.catch_data.get("species_id",""))).get("marks_per_kg",0)))
	var value:=0
	for caught in session.catches:value+=roundi(float(caught.mass_kg)*float(FishCatalog.species(str(caught.species_id)).marks_per_kg))
	return value
