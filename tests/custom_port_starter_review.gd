extends Node
const WORKSHOP=preload("res://scenes/showcases/custom_port_starter_showcase.tscn")
var failures:Array[String]=[]
var checks:=0
var workshop:Node3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	workshop=WORKSHOP.instantiate();add_child(workshop)
	var deadline:=Time.get_ticks_msec()+60000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Starter uses the real workshop")
	await get_tree().process_frame
	_check(is_instance_valid(workshop.start_choices),"First visit presents the finished starter port")
	var actions:Array[String]=[]
	for button in workshop.start_choices.find_children("*","Button",true,false):actions.append(button.text.to_lower())
	_check(actions==["start at littlehaven","back"],"Finished port is the only starting option")
	await _shot("starter-choice")
	var offered:Dictionary=workshop.state.to_dict()
	_check(offered.vessels.size()==1 and offered.vessels[0].owner_company_id==offered.owner_company_id,"Only the player's own first fishing boat is supplied")
	_check(offered.vessels[0].lots.is_empty() and offered.stores.is_empty(),"No free catch, industrial storage or advanced rigs")
	_check(workshop.state.derived_berths().size()==1,"Starter has one actual berth")
	_check(CustomPortVesselProjection.validate_snapshot(offered).ok,"Boat capacities match its real installed equipment")
	var decoded:Dictionary=JSON.parse_string(JSON.stringify(offered,"",true,true))
	var restored:=CustomPortState.from_dict(decoded,offered.world,workshop.catalog)
	_check(restored.validation_errors.is_empty() and restored.derived_berths()==workshop.state.derived_berths(),"Starter JSON reconstructs identical docking geometry")
	workshop.starter_ready_button.pressed.emit()
	deadline=Time.get_ticks_msec()+20000
	while workshop.building and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(not workshop.building and workshop.player.camera.current,"Ready-made choice goes directly into walking")
	_check(not workshop.library.visible and not workshop.vessel_session.input_blocked,"Construction UI is tucked away and boat controls are enabled")
	var boat:BoatBody=workshop.presenter.vessel_nodes.get("starter-fishing-boat")
	_check(is_instance_valid(boat) and boat.gangway.deployed,"Owned boat is alongside with the actual boarding gangway")
	_check(workshop._player_ground_is_safe(),"New player starts on unobstructed quay")
	var full:Dictionary=workshop.state.to_dict()
	var full_path:String=workshop.save_path
	await _shot("starter-first-walk")
	workshop.build();workshop._set_cursor(true)
	_check(workshop.library.visible and workshop.state.to_dict().placements==full.placements,"Building remains available later without clearing the port")
	workshop.ui.hide();workshop.overlays.hide()
	if is_instance_valid(workshop.ghost):workshop.ghost.hide()
	for shot in [
		["starter-overview",Vector3(-38,28,13),Vector3(0,1,49)],
		["starter-waterfront",Vector3(23,7,24),Vector3(-2,2,48)],
		["starter-shed",Vector3(-18,3,40),Vector3(-4,2,51)],
		["starter-shore-access",Vector3(17,6,87),Vector3(4,1,53)]]:
		workshop.camera.position=workshop.site+shot[1];workshop.camera.look_at(workshop.site+shot[2])
		await get_tree().create_timer(.25).timeout
		await _shot(shot[0])
	workshop.ui.show()
	workshop.open_start_choices()
	workshop._close_start_choices()
	_check(workshop.state.to_dict().placements==full.placements and workshop.presenter.vessel_nodes.has("starter-fishing-boat"),"Leaving the welcome panel preserves the port and boat")
	var retained:Dictionary=workshop.REPOSITORY.load_state(workshop.previous_port_copy,workshop.world_identity,workshop.catalog)
	_check(retained.ok and retained.snapshot.placements==offered.placements,"Starting preserves the previous harbour separately")
	var reopened:Dictionary=workshop.open_port_document(ProjectSettings.globalize_path(full_path))
	_check(reopened.ok and workshop.presenter.vessel_nodes.has("starter-fishing-boat"),"Saved finished starter reconstructs its boat and gangway")
	print("STARTER_PORT_SAVED ",ProjectSettings.globalize_path(full_path))
	workshop.queue_free()
	for frame in 3:await get_tree().process_frame
	print("CUSTOM PORT STARTER ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok:bool,why:String) -> void:
	checks+=1
	if not ok:failures.append(why);push_error(why)

func _shot(label:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await get_tree().process_frame
	await workshop._capture(label)
