extends "res://tests/world_gateway_lifecycle_test.gd"

class DelayedBackend extends LocalWorldBackend:
	var hold:=false
	var hold_claims:=false
	var commands:Array[Dictionary]=[]
	func send_command(command:Dictionary) -> void:
		if (hold and command.name==WorldContracts.COMMAND_VESSEL_MOORING_SET) or (hold_claims and command.name==WorldContracts.COMMAND_VESSEL_BERTH_CLAIM):
			commands.append(command.duplicate(true))
		else: super.send_command(command)
	func reject_first() -> void:
		var command:Dictionary=commands.pop_front()
		command_finished.emit(WorldContracts.result_error(command.request_id,"test_rejection","Delayed first toggle rejection"))
	func deliver_first() -> void:
		super.send_command(commands.pop_front())

func create_backend() -> LocalWorldBackend:
	return DelayedBackend.new()

func _test_deployed_door(ship:ImportedDraftVessel) -> void:
	await super._test_deployed_door(ship)
	var backend:=WorldGateway._backend as DelayedBackend
	var mooring:=ship.find_child("MooringComponent",true,false) as MooringComponent
	var controller:HarbourController=(ship.get_parent() as PortPlot).harbour_controller()
	var bridge:HarbourAuthorityBridge=controller._authority_bridge
	var id:=HarbourController.ship_id_of(ship)
	check(mooring.is_moored,"Delayed fixture starts moored")
	backend.hold=true
	# A rejection of the newest action still has to restore authority state.
	mooring.toggle_line_from_post(mooring._front_post)
	check(backend.commands.size()==1,"Newest toggle awaits authority")
	backend.reject_first()
	for frame in 5: await get_tree().physics_frame
	check(mooring.bow_line_tied and mooring.stern_line_tied,"Newest rejection restores authoritative ropes")
	check(not bridge._pending_mooring_by_vessel.has(id),"Newest rejection clears pending intent")
	mooring.toggle_line_from_post(mooring._front_post)
	mooring.toggle_line_from_post(mooring._rear_post)
	check(backend.commands.size()==2,"Two local toggles await authority")
	backend.reject_first()
	for frame in 5: await get_tree().physics_frame
	check(bridge._pending_mooring_by_vessel.has(id),"Older rejection must retain newest pending cast-off")
	check(not mooring.is_moored,"Older rejection must not reattach ropes from cached state")
	backend.deliver_first()
	backend.hold=false
	check(not mooring.is_moored,"Latest cast-off remains applied after acknowledgement")
	check(WorldGateway.projection("vessel_berth",id).state.status=="released","Latest cast-off reaches real authority")
	check(not bridge._pending_mooring_by_vessel.has(id),"Acknowledged cast-off clears pending state")
	print("DELAYED MOORING checked ",id)

	await _test_changed_arrival_berth(ship, backend, mooring, id)

func _test_changed_arrival_berth(ship:ImportedDraftVessel, backend:DelayedBackend, mooring:MooringComponent, id:String) -> void:
	var destination:=TestPortPlot.new()
	destination.port_id="delayed-arrival"
	add_child(destination)
	var controller:=HarbourController.new()
	controller.setup(destination.port_id)
	destination.add_child(controller)
	var posts:Array[MooringPost]=[]
	for index in 2:
		var slot:=QuayBerthSlot.new()
		slot.setup("delayed-arrival/quay%d" % index,"quay","general",[],100,20)
		destination.add_child(slot)
		var post:=MooringPost.new()
		destination.add_child(post)
		post.global_position=ship.to_global(Vector3(-ship.beam_m*.5-2,ship.depth_m,-5+index))
		slot.add_bollard(post)
		posts.append(post)
		controller.register_berth(slot)
	controller.activate()
	backend.hold_claims=true
	check(mooring.toggle_line_from_post(posts[0]),"Provisional first berth tie attaches")
	check(backend.commands.size()==1,"Arrival claim is delayed")
	mooring.toggle_line_from_post(posts[0])
	check(not mooring.is_moored,"Provisional first berth casts off")
	check(mooring.toggle_line_from_post(posts[1]),"New berth tie attaches while old claim waits")
	check(backend.commands.size()==1,"New berth intent waits for first claim reply")
	backend.hold=true
	backend.deliver_first()
	check(backend.commands.size()==1 and backend.commands[0].name==WorldContracts.COMMAND_VESSEL_MOORING_SET,"Old reservation must release before a new claim")
	for frame in 5: await get_tree().physics_frame
	check(mooring._known_berth_id=="delayed-arrival/quay1" and mooring.is_moored,"Old claim replay cannot move the provisional line")
	backend.hold=false
	if not backend.commands.is_empty(): backend.deliver_first()
	check(backend.commands.size()==1,"Changed berth requires its own authority claim")
	if not backend.commands.is_empty(): backend.deliver_first()
	backend.hold_claims=false
	for frame in 5: await get_tree().physics_frame
	var state:Dictionary=WorldGateway.projection("vessel_berth",id).state
	check(state.berth_id=="delayed-arrival/quay1","Newest arrival berth reaches authority")
	check(mooring.is_moored,"Latest arrival line survives older claim reply")
	check(not controller._authority_bridge._pending_mooring_by_vessel.has(id),"Changed arrival settles pending intent")
	mooring.release_mooring()
	destination.queue_free()
	await get_tree().process_frame
	print("DELAYED ARRIVAL BERTH checked ",id)
