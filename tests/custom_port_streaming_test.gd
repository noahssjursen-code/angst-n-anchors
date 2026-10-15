extends Node3D

const STREAMER = preload("res://scripts/port/building/custom_port_streamer.gd")
const WORLD = {"seed":73119,"generation_version":12,"checksum":"streaming-test"}
var observer := Vector3.ZERO
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var streamer := STREAMER.new()
	streamer.position = Vector3(125,20,-250)
	streamer.load_radius_m = 100
	add_child(streamer)
	_check(not streamer.upsert_record(_record("a",Vector3(0,.5,0))).ok,"Unconfigured world refuses snapshots")
	streamer.configure(WORLD)
	streamer.loader.set_process(false)
	streamer.loader.reference_position_provider = func()->Vector3:return observer
	var terrain := WorldTerrainStreamer.new()
	add_child(terrain)
	terrain.set_process(false)
	streamer.bind_environment(terrain)
	var a := _record("a",Vector3(0,.5,0))
	var b := _record("b",Vector3(5000,.5,0))
	_check(streamer.upsert_record(a).ok and streamer.upsert_record(b).ok,"Two validated port documents are registered")
	for height in [-20,20]:
		var wrong_plane: Dictionary=a.duplicate(true)
		wrong_plane.revision=1
		wrong_plane.origin_m[1]=height
		_check(CustomPortState.from_dict(wrong_plane,WORLD,CustomPortCatalog.definitions()).validation_errors.is_empty(),"Scene-free data can describe another explicit world datum")
		_check(streamer.upsert_record(wrong_plane).code=="incompatible_deck_plane" and streamer.record("a").origin_m[1]==.5,"Actual-world projection rejects a different plane without replacing the port")
	var wrong_height: Dictionary=a.duplicate(true)
	wrong_height.revision=1;wrong_height.deck_height_above_sea_m=8
	_check(streamer.upsert_record(wrong_height).code=="incompatible_deck_plane","Actual-world projection rejects a second height above sea")
	_check(streamer.loaded_port_ids().is_empty(),"Registration leaves models unloaded until a distance operation")
	_check(terrain._custom_earthworks.size()==2,"Both known terrain footprints exist independently of model residency")
	streamer.loader._tick()
	streamer.loader._process_one_operation()
	var first := streamer.get_presenter("a")
	_check(first!=null and streamer.get_presenter("b")==null,"Approach loads only the nearby port")
	if first==null:_finish();return
	_check(first.global_position.is_equal_approx(Vector3(0,.5,0)),"World position is correct beneath a transformed streamer parent")
	_check(not first.simulate_vessels and first.vessel_nodes.is_empty(),"World projection does not spawn workshop vessels")
	var foundation: Node = first.placement_nodes["deck"]
	var detached: Dictionary = streamer.record("a")
	detached.name = "Tampered"
	_check(streamer.record("a").name!="Tampered","Read snapshots cannot mutate the cached authority record")
	a.revision=1
	a.placements.append(_tile("extension",8))
	_check(streamer.upsert_record(a).ok,"A newer layout applies while loaded")
	_check(first==streamer.get_presenter("a") and foundation==first.placement_nodes.deck and first.placement_nodes.size()==2,"Incremental update retains unchanged models")
	var modifier_revision: int=terrain._terrain_modifier_revision
	a.revision=2
	a.name="Updated harbour"
	_check(streamer.upsert_record(a).ok and terrain._terrain_modifier_revision==modifier_revision,"Non-geometric updates do not rebuild terrain")
	_check(streamer.upsert_record(a).code=="unchanged","Repeated snapshot is idempotent")
	var wire: Dictionary=JSON.parse_string(JSON.stringify(a,"",true,true))
	_check(streamer.upsert_record(wire).code=="unchanged","Canonical JSON round-trip is also a fast unchanged snapshot")
	var omitted_defaults: Dictionary=a.duplicate(true)
	for field in ["stores","vessels","reservations","receipts"]:omitted_defaults.erase(field)
	_check(streamer.upsert_record(omitted_defaults).code=="unchanged","Omitted empty default collections preserve canonical equivalence")
	var unsafe: Dictionary=a.duplicate(true)
	unsafe.placements[0].attributes.json_probe=RefCounted.new()
	_check(streamer.upsert_record(unsafe).code=="invalid_snapshot","Non-JSON objects cannot masquerade as unchanged null attributes")
	var invalid_geometry: Dictionary=a.duplicate(true)
	invalid_geometry.revision=3
	invalid_geometry.placements.append(_tile("overlap",0))
	_check(streamer.upsert_record(invalid_geometry).code=="invalid_snapshot" and streamer.record("a").revision==2,"New content still receives complete construction validation")
	var conflicting: Dictionary=a.duplicate(true)
	conflicting.name="Conflicting same revision"
	_check(streamer.upsert_record(conflicting).code=="revision_conflict" and streamer.record("a").name==a.name,"Conflicting same-revision update leaves the port unchanged")
	conflicting.revision=1
	_check(streamer.upsert_record(conflicting).code=="stale_snapshot","Older packets cannot revert construction")
	observer=Vector3(500,.5,0)
	streamer.loader._tick();streamer.loader._process_one_operation()
	_check(streamer.get_presenter("a")==first,"Distance hysteresis avoids repeated unloads at the edge")
	var walking_player:=Node3D.new()
	walking_player.position=Vector3(0,.5,0)
	add_child(walking_player)
	walking_player.add_to_group("player")
	observer=Vector3(1500,.5,0)
	streamer.loader._tick();streamer.loader._process_one_operation()
	await get_tree().process_frame
	_check(streamer.get_presenter("a")==first and is_instance_valid(foundation),"Free camera cannot unload the deck beneath the independent walking player")
	walking_player.position=Vector3(100,.5,100)
	streamer.loader._tick();streamer.loader._process_one_operation()
	await get_tree().process_frame
	_check(streamer.get_presenter("a")==null and not is_instance_valid(first),"Leaving the outer radius frees the physical port")
	_check(streamer.record("a").placements.size()==2 and terrain._custom_earthworks.size()==2,"Unloading models preserves records and terrain footprints")
	a.revision=3
	a.placements.append(_tile("while-away",16))
	_check(streamer.upsert_record(a).ok and streamer.get_presenter("a")==null,"Updates received while away do not instantiate distant models")
	observer=Vector3.ZERO
	streamer.loader._tick();streamer.loader._process_one_operation()
	_check(streamer.get_presenter("a").placement_nodes.size()==3,"Returning reconstructs the latest complete layout")
	# Delete a queued distant factory before it gets its one-operation slot.
	observer=Vector3(5000,.5,0)
	streamer.loader._tick()
	_check(streamer.remove_record("b",1).ok,"Newer authority deletion removes a pending port")
	while not streamer.loader._pending_operations.is_empty():streamer.loader._process_one_operation()
	_check(streamer.get_presenter("b")==null and streamer.record("b").is_empty(),"Canceled queued factory cannot resurrect deleted geometry")
	_check(streamer.upsert_record(b).code=="stale_snapshot","Tombstone rejects an old delayed snapshot")
	b.revision=2
	_check(streamer.upsert_record(b).ok,"A deliberately newer authority record may recreate a port")
	streamer.loader._tick();streamer.loader._process_one_operation()
	_check(streamer.get_presenter("b")!=null,"Recreated port becomes visible on approach")
	var invalid: Dictionary=b.duplicate(true)
	invalid.revision=3;invalid.world.checksum="another-world"
	_check(not streamer.upsert_record(invalid).ok and streamer.record("b").revision==2,"Wrong-world record cannot replace the installed port")
	_check(streamer.remove_record("b",2).code=="revision_conflict","Deletion must advance the live revision")
	var protected_child:=Node3D.new()
	streamer.get_presenter("b").add_child(protected_child)
	protected_child.add_to_group("player_boat")
	var tracked_before: int=streamer.loader._entries.size()
	var terrain_before: int=terrain._custom_earthworks.size()
	_check(streamer.clear().code=="occupied_presentation","Clear reports refusal when an active child boat protects a loaded presentation")
	_check(streamer.loader._entries.size()==tracked_before and streamer.record("b").revision==2 and terrain._custom_earthworks.size()==terrain_before,"Refused clear preserves records, loader ownership and environment atomically")
	var another_world: Dictionary=WORLD.duplicate(true)
	another_world.checksum="other-world"
	_check(streamer.configure(another_world).code=="occupied_presentation" and streamer._world==WORLD and streamer.get_presenter("b")!=null,"Refused world reconfiguration retains the original world and presentation")
	protected_child.get_parent().remove_child(protected_child)
	protected_child.free()
	walking_player.position=Vector3(5000,.5,0)
	_check(streamer.remove_record("b",3).ok and streamer.get_presenter("b")==null,"Explicit newer authority deletion bypasses camera-only walking-player retention")
	var external:=Node3D.new()
	external.name="ExistingVesselReplica"
	add_child(external)
	external.add_to_group("player_boat")
	_check(streamer.clear().ok,"Clear succeeds when the protected child has detached")
	await get_tree().process_frame
	_check(streamer.loaded_port_ids().is_empty() and streamer.record("a").is_empty() and terrain._custom_earthworks.is_empty(),"Explicit clear releases all owned projections")
	_check(is_instance_valid(external) and external.is_inside_tree(),"Existing independently-owned vessel survives port cleanup")
	# Generic loader retains its original one-operation and active-ship contract.
	var generic:=ProximityLoader.new()
	add_child(generic)
	generic.set_process(false)
	generic.reference_position_provider=func()->Vector3:return Vector3.ZERO
	var entries: Array=[]
	for id in 2:entries.append(generic.register(Vector3.ZERO,func()->Node3D:return Node3D.new(),100,str(id)))
	generic._tick();generic._process_one_operation()
	_check(generic.get_debug_stats().loaded==1 and generic._pending_operations.size()==1,"Existing loader still performs only one lifecycle operation at a time")
	_check(generic.unregister(entries[1]) and generic._pending_operations.is_empty(),"Unregister cancels a queued factory")
	var owned_boat:=Node3D.new()
	entries[0].instance.add_child(owned_boat);owned_boat.add_to_group("player_boat")
	_check(not generic.unregister(entries[0]),"Generic loader still protects a child player boat")
	owned_boat.remove_from_group("player_boat")
	_check(generic.unregister(entries[0]),"Unregister succeeds when the active-ship protection clears")
	var same_factory:=func()->Node3D:return Node3D.new()
	var same_first:=generic.register(Vector3.ZERO,same_factory,100)
	var same_second:=generic.register(Vector3.ZERO,same_factory,100)
	_check(generic.unregister(same_second) and generic._entries.size()==1 and is_same(generic._entries[0],same_first),"Unregister uses registration identity when two entry values are identical")
	var copied_handle: Dictionary=same_first.duplicate()
	generic.update_entry(copied_handle,Vector3(500,0,0),200)
	_check(copied_handle.position==Vector3.ZERO and same_first.position==Vector3.ZERO,"Copied value record is not an updateable registration handle")
	_check(generic.unregister(copied_handle) and generic._entries.size()==1,"A value-equal copy cannot unregister the real entry")
	generic.update_entry(same_first,Vector3(250,0,0),150)
	_check(same_first.position==Vector3(250,0,0) and same_first.radius==150,"The original handle remains updateable")
	generic.unregister(same_first)
	streamer.queue_free();terrain.queue_free();generic.queue_free();external.queue_free();walking_player.queue_free()
	await get_tree().process_frame
	_finish()

func _record(id:String,at:Vector3)->Dictionary:
	return {"schema_version":1,"id":id,"name":"Port "+id,"owner_company_id":"company-a","revision":0,"world":WORLD.duplicate(true),
		"origin_m":[at.x,at.y,at.z],"deck_height_above_sea_m":2,"plots":[{"id":id+"-plot","rect_m":[-100,-100,200,200],"owner_company_id":"company-a"}],
		"placements":[_tile("deck",0)],"stores":[],"vessels":[],"reservations":[],"receipts":{},"water_regions":[]}

func _tile(id:String,x:float)->Dictionary:
	return {"id":id,"asset_id":"foundation_8m","position_m":[x,0,0],"yaw_degrees":0,"attributes":{"support_depth_m":4,"json_probe":null}}

func _check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)

func _finish()->void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT STREAMING ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
