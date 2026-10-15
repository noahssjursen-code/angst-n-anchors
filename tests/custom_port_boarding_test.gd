extends "res://scripts/port/building/custom_port_showcase.gd"

## Native regression on the actual generated island and production Player.
## Run this scene with --shipyard-playtest and an isolated APPDATA directory.
## The test walks both ways without jumping, then rebuilds, departs and restores.
## Captures are archived by the inherited workshop capture helper.
var audit_failures: Array[String] = []
var audit_checks := 0

func _check(ok: bool, text: String) -> void:
	audit_checks += 1
	if not ok:
		audit_failures.append(text)
		push_error(text)

func _ready() -> void:
	await super()
	if not ready_for_review: return
	save_path="user://custom_ports/boarding-test-%d.json"%Time.get_ticks_usec()
	# The workshop already schedules _review when its capture flag is present.
	if not _capture_mode: call_deferred("_review")

func _review() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	ui.hide()
	overlays.hide()
	_set_cursor(true)
	await _review_boarding()

func _walk_route(start: Vector3, destination: Vector3, label: String, expect_arrival := true) -> void:
	player.position=SITE+start
	player.velocity=Vector3.ZERO
	player._air_deck=null
	player.reset_physics_interpolation()
	var direction := (destination-start)*Vector3(1,0,1)
	var yaw := atan2(-direction.x,-direction.z)
	player.rotation.y=yaw
	var player_camera: Node=player.get_node("PlayerCamera")
	player_camera.shift_look_yaw(yaw-player_camera.get_look_yaw())
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	Input.action_release("move_forward")
	for frame in 24:
		await get_tree().physics_frame
		player._physics_process(1.0/60.0)
	Input.action_press("move_forward")
	for frame in 240:
		await get_tree().physics_frame
		player._physics_process(1.0/60.0)
		var remaining := (SITE+destination-player.position)*Vector3(1,0,1)
		if remaining.length()<.3: break
	Input.action_release("move_forward")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var error := ((SITE+destination-player.position)*Vector3(1,0,1)).length()
	print("PORT_WALK ",label," error_m=",error," local_end=",player.position-SITE)
	if expect_arrival:_check(error<.4,"Actual player can traverse "+label+" without jumping")

func _review_boarding() -> void:
	var results: Array=[]
	for vessel_id in ["trader","bulk-trader"]:
		var vessel: Dictionary={}
		for row in state.to_dict().vessels:
			if str(row.id)==vessel_id:vessel=row;break
		var occupied: Array=[]
		for row in state.to_dict().vessels:
			if not str(row.get("berth_id","")).is_empty():occupied.append({"berth_id":row.berth_id,"vessel_id":row.id})
		var berth_id:=""
		for berth in state.derived_berths():
			var store_id:="container-yard" if vessel_id=="trader" else "bulk-yard"
			if CustomPortBerths.fit(berth,vessel,occupied).ok and store_id in CustomPortBerths.services_for_vessel(berth,vessel).store_ids:
				berth_id=str(berth.id);break
		command_sequence+=1
		var result:=state.apply({"command_id":"boarding-audit-%d"%command_sequence,"expected_revision":state.revision(),"actor_company_id":str(vessel.owner_company_id),"kind":"dock","payload":{"vessel_id":vessel_id,"berth_id":berth_id}})
		_check(bool(result.get("ok",false)),"Boarding audit can dock "+vessel_id+": "+str(result.get("code","")))
		if not result.get("ok",false):continue
		_on_state_changed(result.snapshot,result)
		for frame in 24:await get_tree().physics_frame
		var boat:=presenter.vessel_nodes.get(vessel_id) as ImportedDraftVessel
		var slot:=presenter.berth_nodes.get(berth_id) as QuayBerthSlot
		if boat==null or slot==null:continue
		var bridge:=boat.gangway
		var mooring:=boat.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
		var side:=-1 if boat.to_local(slot.global_position).x<0 else 1
		var gates: Array=bridge._candidates.get(side,[])
		var report: Dictionary={"vessel_id":vessel_id,"gangway_deployed":bridge.deployed,"gangway_status":bridge.status,"candidate_gates":gates.size(),"berth_resolved":boat.get_moored_berth()!=null,"bow_line":mooring.bow_line_tied if mooring!=null else false,"stern_line":mooring.stern_line_tied if mooring!=null else false}
		_check(bridge.deployed,"Docked "+vessel_id+" projects a boarding gangway: "+bridge.status)
		if gates.is_empty():results.append(report);continue
		var closed: Transform3D=gates[0].closed
		var toe:=closed*Vector3(0,-.015,-.5)
		toe.x-=side*.45
		var deck_toe:=boat.to_global(toe)
		var quay_point:=slot.to_local(deck_toe)
		var water:=slot.water_dir_local.normalized()
		quay_point+=water*(slot.face_offset_m-.9-quay_point.dot(water))
		quay_point=slot.to_global(quay_point)
		var query:=PhysicsRayQueryParameters3D.create(quay_point+Vector3.UP*6,quay_point-Vector3.UP*10,BoatBody.LAYER_WORLD,[player.get_rid()])
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():report.landing="No quay collision";results.append(report);continue
		quay_point=hit.position
		var direction:=((deck_toe-quay_point)*Vector3(1,0,1)).normalized()
		var start:=quay_point-direction*.7+Vector3.UP*.05
		var destination:=deck_toe+direction*1.0
		camera.global_position=(quay_point+deck_toe)*.5+Vector3(5,3.2,6)
		camera.look_at((quay_point+deck_toe)*.5+Vector3.UP*.65)
		await _walk_route(start-SITE,destination-SITE,"quay to "+vessel_id,false)
		var local_end:=boat.to_local(player.global_position)
		var arrived:=player.is_on_floor() and absf(local_end.x)<boat.beam_m*.5-.4 and absf(local_end.y-boat.depth_m)<.4
		report.player_on_deck=arrived
		report.player_end_ship_local=[local_end.x,local_end.y,local_end.z]
		report.landing_height=quay_point.y
		report.deck_height=deck_toe.y
		_check(arrived,"Actual player can board "+vessel_id+" without jumping")
		await _capture("boarding-"+vessel_id)
		await _walk_route(player.global_position-SITE+Vector3.UP*.04,start-SITE,"ship to quay "+vessel_id)
		var ashore:=player.is_on_floor() and absf(player.global_position.y-quay_point.y)<.25
		report.player_returned_ashore=ashore
		_check(ashore,"Actual player returns to the quay from "+vessel_id+" without jumping")
		await _capture("boarding-return-"+vessel_id)
		# Reconstructed berth nodes must replace the presentation reference even
		# when the ship and its accepted assignment did not otherwise change.
		var refreshed: Array=state.derived_berths().duplicate(true)
		for row in refreshed:row.review_generation=1
		presenter.load_record(state.to_dict(),refreshed)
		for frame in 15:await get_tree().physics_frame
		_check(bridge.deployed and bridge._projected_berth==presenter.berth_nodes[berth_id],"Berth rebuild updates the existing gangway reference")
		var docked_snapshot:=state.to_dict()
		var gate: Node3D=gates[0].part
		command_sequence+=1
		result=state.apply({"command_id":"boarding-audit-%d"%command_sequence,"expected_revision":state.revision(),"actor_company_id":str(vessel.owner_company_id),"kind":"undock","payload":{"vessel_id":vessel_id}})
		_check(bool(result.get("ok",false)),"Boarding audit can depart "+vessel_id)
		_on_state_changed(result.snapshot,result)
		_check(not bridge.deployed and bridge._walk.collision_layer==0 and gate.transform.is_equal_approx(closed),"Departure stows the span and restores its closed authored gate")
		await get_tree().physics_frame
		transfers.present(docked_snapshot,state.derived_berths(),[])
		for frame in 20:await get_tree().physics_frame
		var restored:=presenter.vessel_nodes[vessel_id] as ImportedDraftVessel
		_check(restored.gangway.deployed and restored.gangway._projected_berth==presenter.berth_nodes[berth_id],"Fresh snapshot reconstruction restores a usable gangway")
		transfers.present(state.to_dict(),state.derived_berths(),[])
		results.append(report)
	print("CUSTOM_PORT_BOARDING_AUDIT ",JSON.stringify(results))
	print("CUSTOM_PORT_BOARDING_REVIEW ","PASS" if audit_failures.is_empty() else "FAIL"," checks=",audit_checks," failures=",audit_failures.size())
	get_tree().quit(0 if audit_failures.is_empty() else 1)
