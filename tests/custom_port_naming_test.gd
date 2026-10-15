extends "res://tests/custom_port_showcase_input_test.gd"

const FIXTURE = preload("res://tests/custom_port_data_test.gd")

func _run() -> void:
	if OS.get_cmdline_user_args().has("--native-name"):
		await _native_name()
	else:
		_data_names()
	for failure in failures: push_error(failure)
	print("CUSTOM PORT NAMING ", "PASS" if failures.is_empty() else "FAIL", " checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _command(state: CustomPortState, name: Variant, actor := "company-a", extra: Dictionary = {}) -> Dictionary:
	var payload := {"name":name}
	payload.merge(extra)
	return {"command_id":"name-%d"%checks,"expected_revision":state.revision(),
		"actor_company_id":actor,"kind":"rename_port","payload":payload}

func _data_names() -> void:
	var fixture := FIXTURE.new()
	var record: Dictionary = fixture._fixture()
	var catalog: Dictionary = fixture._catalog()
	fixture.free()
	var state := CustomPortState.from_dict(record,record.world,catalog)
	var replica := CustomPortState.from_dict(record,record.world,catalog)
	_check(state.validation_errors.is_empty(),"Valid existing port fixture")
	var original := state.to_dict()
	for bad in ["", "  ", "A".repeat(81), "Two\nlines", "Tab\tname", "Bad"+String.chr(127), "Next"+String.chr(133)+"line", "Split"+String.chr(0x2028)+"line", 7, true, [], {}]:
		var rejected := state.apply(_command(state,bad))
		_check(not rejected.ok and state.to_dict()==original,"Invalid name rejects without changing the port: "+str(bad))
	_check(state.apply(_command(state,"Visitor name","other-company")).code=="not_port_owner","Visitor cannot rename port")
	_check(state.apply(_command(state,"Wrong payload","company-a",{"owner_company_id":"other"})).code=="invalid_port_name","Rename cannot alter identity through extra fields")
	var command := _command(state,"  Skjærvika fiskekai  ")
	var accepted := state.apply(command)
	_check(accepted.ok and state.to_dict().name=="Skjærvika fiskekai","Owner can name a harbour with Norwegian characters; edge spaces are trimmed")
	var after := state.to_dict()
	var untouched := after.duplicate(true)
	for key in ["name","revision","receipts"]:untouched[key]=original.get(key)
	_check(untouched==original,"Naming preserves identity, plot geometry, cargo and all other state")
	_check(accepted.events.size()==1 and accepted.events[0].changes=={"name":"Skjærvika fiskekai"},"One scalar name change is published")
	_check(replica.replay_event(accepted.events[0]).ok and replica.to_dict()==after,"Event-only reconstruction preserves the exact renamed document")
	_check(state.apply(command).code=="already_applied" and state.to_dict()==after,"Retry does not rename or charge twice")
	_check(replica.replay_event(accepted.events[0]).code=="already_applied","Repeated authority event is harmless")
	_check(state.apply(_command(state,"Skjærvika fiskekai")).code=="port_name_unchanged","Identical name makes no extra event")
	var old_command := _command(state,"Stale name")
	old_command.expected_revision=0
	_check(state.apply(old_command).code=="revision_conflict","Stale name edits cannot overwrite another change")
	for malformed in [false, "", "Bad\nname"]:
		var fresh := CustomPortState.from_dict(original,record.world,catalog)
		var event: Dictionary=accepted.events[0].duplicate(true)
		event.changes.name=malformed
		_check(fresh.replay_event(event).code=="invalid_event_field" and fresh.to_dict()==original,"Invalid scalar name event rejects atomically")
	var wrong_kind: Dictionary = accepted.events[0].duplicate(true)
	wrong_kind.kind="place_asset"
	var fresh := CustomPortState.from_dict(original,record.world,catalog)
	_check(fresh.replay_event(wrong_kind).code=="invalid_event_field","Other event kinds cannot silently rename port")
	var path := "user://port-naming-test/renamed-%d.json"%OS.get_process_id()
	var saved := CustomPortRepository.save(path,state)
	var loaded := CustomPortRepository.load_state(path,record.world,catalog)
	_check(saved.ok and loaded.ok and loaded.snapshot==state.to_dict(),"Repository save/load retains exact name and receipts")
	var summary := CustomPortChartProjection.project(state.to_dict(),catalog,state.derived_berths())
	_check(summary.display_name=="Skjærvika fiskekai" and summary.id==original.id,"Chart gets the changed display name and stable port identity")

func _native_name() -> void:
	var workshop := WORKSHOP.instantiate()
	workshop.example_kind=1
	add_child(workshop)
	var deadline := Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Actual fishing workshop is ready")
	if not workshop.ready_for_review:return
	workshop.open_inspector()
	var panel: CustomPortInspector=workshop.inspector
	panel._tabs.current_tab=4
	await _settle()
	_check(panel._port_name.editable and not panel._rename_port.disabled,"Workshop owner can edit harbour name")
	var before: Dictionary=workshop.state.to_dict()
	panel._port_name.text="Skjærvika fiskekai"
	panel._port_name.grab_focus()
	await _key(KEY_ENTER)
	_check(workshop.state.to_dict().name=="Skjærvika fiskekai","Real Enter in native name field commits one owner command")
	_check(workshop.state.revision()==int(before.revision)+1,"Native submit issues exactly one command")
	_check(panel._title.text=="Skjærvika fiskekai" and workshop.heading.text.begins_with("Skjærvika fiskekai"),"Inspector and workshop heading update together")
	_check(panel._title.size.x>100 and panel._title.size.y>20,"Native harbour title has a visible single-line rectangle")
	_check((panel._port_name.get_theme_stylebox("focus") as StyleBoxFlat).bg_color.a==0,"Focused name input keeps its readable paper background")
	_check(panel._rename_port.get_global_rect().end.y<=get_viewport().get_visible_rect().end.y,"Name action stays visible inside viewport")
	panel.set_storage_admin_actor("some-visitor")
	panel._port_name.text="Intruder"
	panel._rename_selected_port()
	_check(not panel._port_name.editable and panel._rename_port.disabled and workshop.state.to_dict().name=="Skjærvika fiskekai","Read-only visitor cannot rename using controls or direct callback")
	panel.set_storage_admin_actor(workshop.owner_company_id)
	await _settle()
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("harbour-name-owner-settings")
	panel.close_requested.emit()
	workshop.open_map()
	_check(workshop.map.data.port_info(str(before.id)).display_name=="Skjærvika fiskekai","Opening actual chart uses renamed harbour")
	workshop.map.close_requested.emit()
	workshop.save_path="user://port-naming-test/workshop-renamed-%d.json"%OS.get_process_id()
	workshop.save_port()
	var exact: Dictionary=workshop.state.to_dict()
	workshop.load_port()
	_check(workshop.state.to_dict()==exact and workshop.heading.text.begins_with("Skjærvika fiskekai"),"Actual Save/Load restores exact renamed harbour")
	workshop.queue_free()
	await _settle()
