extends Node
## The inspector owns request/selection only; this test connects no admission.
const FIXTURE = preload("res://tests/custom_port_data_test.gd")
const PANEL = preload("res://scripts/port/building/custom_port_inspector.gd")
const VISITORS = preload("res://scripts/port/building/custom_port_test_visitors.gd")
var checks := 0
var failures: Array[String] = []
var requests: Array[String] = []
var events := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	get_window().content_scale_size = Vector2i(1000,780)
	var fixture:=FIXTURE.new()
	var record:Dictionary=fixture._fixture()
	var catalog:Dictionary=fixture._catalog()
	fixture.free()
	record.name="My harbour"
	record.vessels=[]
	var state:=CustomPortState.from_dict(record,record.world,catalog)
	_check(state.validation_errors.is_empty(),"Empty harbour fixture is valid")
	var background:=ColorRect.new()
	background.color=Color("23353e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel:=PANEL.new()
	add_child(panel)
	panel.position=Vector2(34,28)
	panel.configure(state,catalog,"",Vector2(620,690))
	panel.test_vessel_requested.connect(func(id:String):requests.append(id))
	panel.state_changed.connect(func(_snapshot:Dictionary,_result:Dictionary):events+=1)
	var before:=state.to_dict()
	_check(not panel._test_visitor_controls.visible and panel._test_visitor.disabled and panel._invite_visitor.disabled,"Test controls are hidden and disabled by default")
	panel._invite_visitor.pressed.emit()
	_check(requests.is_empty() and state.to_dict()==before,"Disabled callback cannot invite or mutate authority")
	panel.set_test_visitors_enabled(true)
	_check(panel._test_visitor_controls.visible and not panel._invite_visitor.disabled and panel._fit_details.text.contains("Invite a test visitor"),"Workshop opt-in enables the compact visitor controls and updates the empty-state instruction")
	var options: Array=VISITORS.options()
	_check(options.size()==3 and panel._test_visitor.item_count==3,"Only the three reviewed stock presets are offered")
	var expected: Array[String]=["fishing_hook_line","28_10_m","coastal_coaster"]
	for index in options.size():
		_check(str(options[index].id)==expected[index] and str(panel._test_visitor.get_item_metadata(index))==expected[index],"Option uses the verified stock identity "+expected[index])
		panel._test_visitor.select(index)
		panel._invite_visitor.pressed.emit()
		_check(requests.back()==expected[index],"Invite emits selected preset "+expected[index])
	_check(requests.size()==3 and events==0 and state.to_dict()==before,"Invitations only emit intent; no vessel, cargo, receipt or inventory is created by the panel")
	panel._test_visitor.set_item_metadata(0,"unsupported-vessel")
	panel._test_visitor.select(0)
	panel._invite_visitor.pressed.emit()
	_check(requests.size()==3,"A forged option identity cannot emit an unsupported preset")
	panel._test_visitor.set_item_metadata(0,expected[0])
	panel.set_test_visitors_enabled(false)
	panel._invite_visitor.pressed.emit()
	_check(requests.size()==3 and not panel._test_visitor_controls.visible and panel._invite_visitor.disabled,"Disabling the feature blocks callbacks and hides its row")
	_check(not panel.select_vessel("missing") and state.to_dict()==before,"Selection never invents a vessel in an empty authority")
	var populated:=before.duplicate(true)
	for index in options.size():
		populated.vessels.append(CustomPortVesselProjection.from_prebuilt(expected[index],"visitor-%d"%index,"company-visitor",str(options[index].name),48000))
	var populated_state:=CustomPortState.from_dict(populated,populated.world,catalog)
	_check(populated_state.validation_errors.is_empty(),"Existing records retain actual stock fitouts")
	panel.configure(populated_state,catalog,"",Vector2(620,690))
	var populated_before:=populated_state.to_dict()
	_check(panel.select_vessel("visitor-2") and panel._selected(panel._vessel)=="visitor-2" and panel._vessel_details.text.contains("Dry bulk hold"),"Public selection selects the existing new visitor and refreshes its installed capacity")
	_check(not panel.select_vessel("unknown") and panel._selected(panel._vessel)=="visitor-2","Missing selection preserves the selected valid vessel")
	_check(populated_state.to_dict()==populated_before and events==0,"Selection changes no authoritative data")
	panel.configure(null,catalog)
	panel.set_test_visitors_enabled(true)
	panel._invite_visitor.pressed.emit()
	_check(panel._invite_visitor.disabled and requests.size()==3,"Opt-in without an authority cannot emit invitations")
	panel.configure(state,catalog,"",Vector2(620,690))
	panel._test_visitor.select(0)
	_check(panel._fit_details.text.contains("Invite a test visitor") and not panel._berth_details.text.contains("No crane reaches"),"Empty harbour explains invitation without inventing a crane incompatibility")
	for frame in 5:await get_tree().process_frame
	_check(panel.size.y<=690 and panel._dock.get_global_rect().end.y<=panel.get_global_rect().end.y,"Visitor controls fit the host with dock actions remaining reachable")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var archive:="C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(archive)
		var path:=archive.path_join("custom-port-test-visitors-%s.png"%Time.get_datetime_string_from_system().replace(":","-"))
		_check(get_viewport().get_texture().get_image().save_png(path)==OK,"Native test visitor UI archived")
		print("TEST_VISITOR_CAPTURE ",path)
	panel.free()
	for failure in failures:push_error(failure)
	print("CUSTOM PORT TEST VISITOR UI %s: %d checks; %d failures"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
