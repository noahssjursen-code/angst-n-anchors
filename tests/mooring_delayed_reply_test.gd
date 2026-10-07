extends "res://tests/world_gateway_lifecycle_test.gd"

class DelayedBackend extends LocalWorldBackend:
	var hold:=false
	var commands:Array[Dictionary]=[]
	func send_command(command:Dictionary) -> void:
		if hold and command.name==WorldContracts.COMMAND_VESSEL_MOORING_SET:
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
