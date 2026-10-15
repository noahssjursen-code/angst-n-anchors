extends Node3D

## Projection ownership only: streamed ports must never spawn or adopt ships
## already owned by the world. Run with --shipyard-playtest and isolated APPDATA.
var checks := 0
var failures: Array[String] = []
var operator_events: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var groups := [MooringComponent.DOCK_MOORING_GROUP,CargoSlotPadComponent.PAD_GROUP,CargoSlotPadComponent.YARD_PAD_GROUP,"container_yard_drop","port_service_npc",ContainerNode.GROUP]
	var group_counts: Dictionary = {}
	for group in groups: group_counts[group]=get_tree().get_nodes_in_group(group).size()
	var world := {"seed":73119,"generation_version":1,"checksum":"streaming-lifecycle"}
	var plots: Array = [{"id":"plot","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot := CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12}]
	var state := CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Lifecycle fixture validates")
	if not state.validation_errors.is_empty(): _finish();return
	var trader: Dictionary = {}
	for vessel in snapshot.vessels:
		if vessel.id=="trader":trader=vessel;break
	var berth_id := ""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,trader,[]).ok:
			berth_id=str(berth.id);break
	var dock := state.apply({"command_id":"streaming-dock","expected_revision":state.revision(),"actor_company_id":str(trader.owner_company_id),"kind":"dock","payload":{"vessel_id":"trader","berth_id":berth_id}})
	_check(bool(dock.get("ok",false)),"Authority assigns the fixture ship a berth")
	if not dock.get("ok",false): _finish();return
	snapshot=state.to_dict()
	var original := JSON.stringify(snapshot,"",true)
	var berths := state.derived_berths()
	# Deliberately shares the visible name and vessel identity with the fixture.
	# It represents a sibling owned by production vessel replication.
	var external := Node3D.new()
	external.name="Docked_trader"
	external.set_meta("vessel_id","trader")
	external.position=Vector3(42,3,-55)
	add_child(external)
	var external_pose := external.transform
	var workshop := CustomPortPresenter.new()
	add_child(workshop)
	workshop.load_record(snapshot,berths)
	_check(workshop.simulate_vessels and workshop.vessel_nodes.size()==1,"Default workshop behavior still creates its one accepted ship")
	var owned := workshop.vessel_nodes.get("trader") as ImportedDraftVessel
	_check(is_instance_valid(owned),"Default projection uses the actual imported vessel")
	if not is_instance_valid(owned): _finish();return
	var bridge := owned.gangway
	var streamed := CustomPortPresenter.new()
	streamed.simulate_vessels=false
	add_child(streamed)
	streamed.operator_selected.connect(func(id: String) -> void: operator_events.append(id))
	streamed.load_record(snapshot,berths)
	_check(streamed.vessel_nodes.is_empty() and streamed._owned_vessels.is_empty(),"Streaming mode creates no simulation ship despite a docked record")
	_check(streamed.placement_nodes.size()==snapshot.placements.size() and streamed.berth_nodes.size()==berths.size(),"Streaming retains all quay placements and proven berths")
	_check(_container_count(streamed)==6 and streamed.cargo_nodes.has("ore-stock"),"Streaming retains finite container and bulk stock visuals")
	var npc: Node=streamed.placement_nodes["crane-operator"]
	npc._on_interact()
	_check(operator_events==["crane-operator"],"Streamed operator emits the caller-owned interaction without opening workshop UI")
	for frame in 3: await get_tree().process_frame
	for placement in streamed.placement_nodes.values():
		var crane: Node=placement.find_child("Crane",true,false)
		if crane!=null:
			_check(not crane.is_processing() and not crane.is_physics_processing(),"Streamed crane has no autonomous local driver")
			if crane is BulkCrane:_check(not crane.simulate_bulk_material,"Streamed bulk grab cannot mutate live freight")
	# Even a stray public lookup does not grant the presenter ownership.
	workshop.vessel_nodes["external-reference"]=external
	workshop.simulate_vessels=false
	_check(workshop.vessel_nodes.is_empty() and workshop._owned_vessels.is_empty(),"Switching to world mode clears only tracked simulation ships")
	_check(not bridge.deployed and bridge._walk.collision_layer==0 and not owned.is_inside_tree(),"Mode change immediately stows the gangway and removes ship collision")
	_check(is_instance_valid(external) and external.get_parent()==self and external.transform==external_pose,"External replica survives mode change unchanged")
	await get_tree().process_frame
	_check(not is_instance_valid(owned),"Mode change frees its own simulation ship")
	streamed.load_record(snapshot,berths)
	streamed.load_record(snapshot,berths)
	_check(streamed.vessel_nodes.is_empty() and _container_count(streamed)==6,"Repeated world snapshots neither spawn a ship nor duplicate containers")
	workshop.simulate_vessels=true
	var recreated: BoatBody=workshop.vessel_nodes.get("trader")
	_check(is_instance_valid(recreated) and workshop.vessel_nodes.size()==1,"Returning to workshop mode reconstructs the current accepted ship")
	workshop.simulate_vessels=true
	_check(workshop.vessel_nodes.get("trader")==recreated,"Repeated mode assignment preserves the same owned ship")
	var first_quay: Node=streamed.placement_nodes.values()[0]
	var replacement: Dictionary=snapshot.duplicate(true)
	replacement.id="another-port"
	replacement.origin_m=[1000,.5,0]
	streamed.load_record(replacement,berths)
	_check(not first_quay.is_inside_tree() and streamed.position==Vector3(1000,.5,0),"Replacing a port with reused local IDs detaches the former projection")
	_check(streamed.vessel_nodes.is_empty() and _container_count(streamed)==6,"Replacement stays in world mode and hydrates stock once")
	_check(workshop.vessel_nodes.get("trader")==recreated,"Reloading one presenter does not disturb another presenter's ship")
	workshop.clear_record()
	streamed.clear_record()
	_check(workshop.get_child_count()==0 and streamed.get_child_count()==0,"Explicit unload removes all owned placements, berths, cargo and ships")
	_check(workshop.record.is_empty() and streamed.record.is_empty() and streamed.cargo_nodes.is_empty(),"Explicit unload clears stale record and cargo lookups")
	_check(is_instance_valid(external) and external.get_parent()==self and external.transform==external_pose,"External replica survives both presenters unloading")
	streamed.load_record(snapshot,berths)
	_check(not streamed.simulate_vessels and streamed.vessel_nodes.is_empty() and _container_count(streamed)==6,"Unloaded world presenter can reload without resetting its safe mode")
	workshop.queue_free()
	streamed.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_instance_valid(external) and external.transform==external_pose,"Destroying both presenters leaves the external replica intact")
	for group in groups:
		_check(get_tree().get_nodes_in_group(group).size()==group_counts[group],"Unloading removes owned discovery group members: "+str(group))
	_check(JSON.stringify(snapshot,"",true)==original,"All presentation operations leave source data untouched")
	# Stop test-created audio producers and allow one audio-mix drain before exit.
	for node in get_tree().root.find_children("*","Node",true,false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			node.stop()
			node.stream=null
	await get_tree().create_timer(.15).timeout
	_finish()

func _container_count(presenter: CustomPortPresenter) -> int:
	var count := 0
	for node in presenter.find_children("*","Node3D",true,false):
		if node is ContainerNode:count+=1
	return count

func _check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message)

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT STREAMING LIFECYCLE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
