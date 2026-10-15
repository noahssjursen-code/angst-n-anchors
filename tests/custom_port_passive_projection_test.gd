extends Node3D

var checks:=0
var failures:Array[String]=[]
const GROUPS := [MooringComponent.DOCK_MOORING_GROUP,CargoSlotPadComponent.PAD_GROUP,
	CargoSlotPadComponent.YARD_PAD_GROUP,ContainerNode.GROUP,"container_yard_drop","quay_berth_slot","provision_crane_auto"]

func _ready()->void:_run.call_deferred()

func _run()->void:
	assert(ShipyardPlaytestMode.active())
	var identity:={"seed":73119,"generation_version":12,"checksum":"passive-proof"}
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),[{"id":"plot","rect_m":[-124,-20,200,200],"owner_company_id":CustomPortExample.OWNER}],identity)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12}]
	var state:=CustomPortState.from_dict(snapshot,identity,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Projection scenario is a valid complete harbour")
	var live_marker:=MooringPost.new()
	add_child(live_marker)
	var presenter:=CustomPortPresenter.new()
	presenter.simulate_vessels=false
	presenter.passive_services=true
	add_child(presenter)
	presenter.load_record(state.to_dict(),state.derived_berths())
	for frame in 5:await get_tree().process_frame
	_check(presenter.placement_nodes.size()==snapshot.placements.size(),"Passive mode retains every physical construction placement")
	_check(presenter.vessel_nodes.is_empty() and presenter.berth_nodes.is_empty(),"Passive mode exposes neither fixture ships nor live berth slots")
	for group in GROUPS:
		var count:=0
		for node in get_tree().get_nodes_in_group(group):
			if presenter.is_ancestor_of(node):count+=1
		_check(count==0,"No imported targets in live discovery group "+group)
	var containers:=0
	for node in _descendants(presenter):
		if node is ContainerNode:containers+=1
	_check(containers==20,"All twenty stored containers still render as projected stock")
	_check(live_marker.is_in_group(MooringComponent.DOCK_MOORING_GROUP),"Unrelated generated/world bollards remain usable")
	presenter.load_record(state.to_dict(),state.derived_berths())
	_check(not _has_live_group(presenter),"Repeat snapshot cannot reopen live cargo or mooring discovery")
	var changed:=state.to_dict()
	changed.revision+=1
	changed.stores[0].lots[0].quantity=3
	presenter.load_record(changed,state.derived_berths())
	for frame in 3:await get_tree().process_frame
	containers=0
	var all_passive:=true
	for node in _descendants(presenter):
		if node is ContainerNode:
			containers+=1
			all_passive=all_passive and not node.service_discovery_enabled
	_check(containers==11 and all_passive and not _has_live_group(presenter),"A newer stock snapshot creates every replacement container without service discovery")
	var npc:Node=presenter.placement_nodes["crane-operator"]
	var requested:=[false]
	presenter.operator_selected.connect(func(_id:String):requested[0]=true)
	npc._on_interact()
	_check(requested[0],"Read-only source can still respond to an operator interaction")
	presenter.queue_free()
	live_marker.queue_free()
	for frame in 6:await get_tree().process_frame
	for failure in failures:push_error(failure)
	print("CUSTOM PORT PASSIVE PROJECTION ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _descendants(root:Node)->Array[Node]:
	var result:Array[Node]=[]
	for child in root.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result

func _has_live_group(root:Node)->bool:
	for node in _descendants(root):
		for group in GROUPS:
			if node.is_in_group(group):return true
	return false

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
