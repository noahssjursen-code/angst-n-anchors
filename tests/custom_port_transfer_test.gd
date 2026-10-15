extends "res://tests/custom_harbour_asset_review.gd"

const Transfer=preload("res://scripts/port/building/custom_port_transfer_presenter.gd")
var port: CustomPortPresenter
var state: CustomPortState
var transfer: Node
var sequence:=0
var animation_errors: Array[String]=[]
var captured_lift:=false
var captured_lowering:=false
var native_capture:=false

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_setup()
	native_capture=OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")

func _run() -> void:
	var world: Dictionary={"seed":73119,"generation_version":1,"checksum":"transfer-fixture"}
	var plots: Array=[{"id":"plot-west","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12.0}]
	snapshot.stores[0].public_unloading=true
	state=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Transfer fixture is valid: "+str(state.validation_errors))
	if not state.validation_errors.is_empty():get_tree().quit(1);return
	port=CustomPortPresenter.new()
	add_child(port)
	transfer=Transfer.new()
	add_child(transfer)
	transfer.bind(port)
	transfer.set_process(false)
	transfer.presentation_failed.connect(func(reason: String)->void:animation_errors.append(reason))
	transfer.present(state.to_dict(),state.derived_berths())
	var trader:=Transfer._find(state.to_dict().vessels,"trader")
	var berth_id:=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,trader,[]).ok and "container-yard" in CustomPortBerths.services_for_vessel(berth,trader).store_ids:
			berth_id=str(berth.id);break
	_check(not berth_id.is_empty(),"Actual cargo vessel has a serviced berth")
	if berth_id.is_empty():get_tree().quit(1);return
	_apply("dock",{"vessel_id":"trader","berth_id":berth_id})
	await get_tree().process_frame
	_check(port.vessel_nodes.has("trader"),"Docking projects the real prebuilt cargo vessel")
	if not port.vessel_nodes.has("trader"):
		print("DOCK_PROJECTION_DIAGNOSTIC ",JSON.stringify({"vessels":state.to_dict().vessels,"berths":port.berth_nodes.keys(),"files":DirAccess.get_files_at(PrebuiltVesselCatalog.PREBUILT_DIR),"global_dir":ProjectSettings.globalize_path(PrebuiltVesselCatalog.PREBUILT_DIR),"direct":PrebuiltVesselCatalog._load_entry(PrebuiltVesselCatalog.PREBUILT_DIR+"/28_10_m.json").get("prebuilt_id",""),"catalog":PrebuiltVesselCatalog.catalog_entries(false).map(func(entry:Dictionary)->String:return str(entry.prebuilt_id))}))
		get_tree().quit(1);return
	target=Vector3(-24,9,7)
	camera.position=Vector3(-78,52,-62)
	camera.look_at(target)
	label.text="COMMITTED PORT CARGO · Real crane, finite stock, exact ship slots\nReserve → commit → animate the accepted transfer; the animation never changes authority data"
	_block("Review water",Vector3(320,.05,240),Vector3(0,-1.525,-100),"roof_sheet",Color("274958"))
	if native_capture:await _capture("transfer-before")
	_apply("reserve_cargo",{"store_id":"container-yard","vessel_id":"trader","lot_id":"parts-for-shipyard","quantity":2,"reservation_id":"load-two"})
	_check(not transfer.is_busy(),"Reservation alone does not move a container")
	var result:=_apply("load_cargo",{"reservation_id":"load-two"})
	_check(transfer.is_busy() and transfer.total_units==2,"Committed load starts two visual transfers")
	var committed:=JSON.stringify(state.to_dict())
	var active_proxy: Variant=transfer._current.get("proxy")
	transfer.present(state.to_dict(),state.derived_berths(),result.events)
	_check(transfer._current.get("proxy")==active_proxy,"Duplicate delivery does not restart the lift")
	await _finish_motion()
	_check(transfer.completed_units==2,"Both boxes are lifted and landed")
	_check(JSON.stringify(state.to_dict())==committed,"Crane playback cannot mutate committed cargo data")
	_check(_visible_containers(port.vessel_nodes.trader)==2,"Both committed containers become visible aboard")
	_check(_visual_proxy_count()==0,"Completion removes every temporary container")
	_check(_hook_empty(),"Completion leaves an empty hook")
	if native_capture:
		var loaded_boat: Node3D=port.vessel_nodes.trader
		target=loaded_boat.global_position+Vector3(0,3,0)
		camera.position=loaded_boat.global_position+Vector3(-20,21,-29)
		camera.look_at(target)
		label.text="TWO COMMITTED CONTAINERS · Actual Harbour Cargo deck slots\nThe ship manifest and visible cargo agree; eighteen containers remain on the quay"
		await _capture("transfer-loaded-close")
	_apply("unload_cargo",{"store_id":"container-yard","vessel_id":"trader","lot_id":"parts-for-shipyard","quantity":1})
	_check(transfer.is_busy(),"Committed unloading animates in the opposite direction")
	await _finish_motion()
	_check(_visible_containers(port.vessel_nodes.trader)==1,"Unloading leaves one container aboard")
	_check(_hook_empty() and _visual_proxy_count()==0,"Unloading leaves no hook cargo or duplicate")
	# Rebuild during a suspended lift: the committed snapshot is sufficient to
	# recover without a remembered renderer phase or an orphan container.
	_apply("reserve_cargo",{"store_id":"container-yard","vessel_id":"trader","lot_id":"parts-for-shipyard","quantity":1,"reservation_id":"interrupt"})
	_apply("load_cargo",{"reservation_id":"interrupt"})
	var guard:=0
	while transfer.is_busy() and transfer._phase!="travel_drop" and guard<6000:
		transfer._process(.05)
		guard+=1
	_check(transfer._phase=="travel_drop","Interruption test reaches an actual suspended load")
	# Departure during a suspended lift applies the latest authority snapshot,
	# clears the transient hook load and preserves the actual vessel manifest.
	_apply("undock",{"vessel_id":"trader"})
	_check(not port.vessel_nodes.has("trader"),"Departure removes the vessel projection")
	_check(_hook_empty() and _visual_proxy_count()==0,"Departure leaves no abandoned hook or quay duplicate")
	var departed:=Transfer._find(state.to_dict().vessels,"trader")
	_check(int(Transfer._find(departed.lots,"parts-for-shipyard").quantity)==2,"Departure preserves the committed onboard manifest")
	# No frame gap here: deferred vessel setup must tolerate immediate departure.
	_apply("dock",{"vessel_id":"trader","berth_id":berth_id})
	_apply("undock",{"vessel_id":"trader"})
	_check(not port.vessel_nodes.has("trader"),"Rapid arrival/departure leaves no vessel projection")
	var restored:=Transfer.new()
	add_child(restored)
	restored.bind(port)
	restored.present(state.to_dict(),state.derived_berths())
	_check(not restored.is_busy(),"Snapshot reload does not replay historical lifts")
	_check(animation_errors.is_empty(),"No animation errors: "+str(animation_errors))
	await _settle_audio_before_exit()
	print("CUSTOM PORT TRANSFER ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _apply(kind: String,payload: Dictionary) -> Dictionary:
	sequence+=1
	var result:=state.apply({"command_id":"transfer-%d"%sequence,"kind":kind,"actor_company_id":"company-visitor","expected_revision":state.revision(),"payload":payload})
	_check(result.get("ok",false),"Authority accepts "+kind+": "+str(result.get("code","")))
	if result.get("ok",false):transfer.present(result.snapshot,state.derived_berths(),result.events)
	return result

func _finish_motion() -> void:
	var steps:=0
	while transfer.is_busy() and steps<12000:
		transfer._process(.05)
		steps+=1
		if steps%40==0:await get_tree().process_frame
		if native_capture and transfer._phase=="travel_drop" and not captured_lift:
			captured_lift=true
			await _capture("transfer-suspended")
		if native_capture and transfer._phase=="lower_drop" and not captured_lowering and transfer._current.proxy.global_position.distance_to(transfer._current.destination.global_position)<6.0:
			captured_lowering=true
			await _capture("transfer-lowering")
	_check(not transfer.is_busy(),"Crane finishes within its bounded cycle")
	await get_tree().process_frame

func _hook_empty() -> bool:
	var equipment: Node3D=port.placement_nodes.get("container-terminal")
	var crane:=equipment.find_child("Crane",true,false) as ProvisionCrane
	return crane.get_attached_container()==null

func _visible_containers(root: Node3D) -> int:
	var count:=0
	for node in root.find_children("*","Node3D",true,false):
		if node is ContainerNode and node.is_visible_in_tree():count+=1
	return count

func _visual_proxy_count() -> int:
	var count:=0
	for node in port.find_children("*","Node3D",true,false):
		if node.has_meta("custom_port_transfer_visual"):count+=1
	return count

func _settle_audio_before_exit() -> void:
	# Rapid headless ship creation/teardown can outpace the audio mixing thread.
	# Stop producers and drain its bounded buffer; do not hide Node leaks behind
	# repeated frame waits. Verbose diagnostics identified only WAV/playbacks.
	for node in get_tree().root.find_children("*","Node",true,false):
		node.set_process(false)
		node.set_physics_process(false)
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			node.stop()
			node.stream=null
	var drain:=clampf(AudioServer.get_output_latency()+2.0*AudioServer.get_time_to_next_mix(),.10,.25)
	await get_tree().create_timer(drain).timeout
