extends "res://tests/custom_port_data_test.gd"
const EDITOR=preload("res://scripts/port/building/custom_port_editor.gd")
const REPOSITORY=preload("res://scripts/port/state/custom_port_repository.gd")

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	_test_paint_preserves_document()
	_test_rejected_colours()
	_test_grouped_undo()
	_test_concurrent_operations()
	for failure in failures:push_error(failure)
	print("CUSTOM PORT CLADDING DATA ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _paint_catalog() -> Dictionary:
	var catalog:=_catalog()
	for id in ["workshop_wall_4m","workshop_window_4m","workshop_door_4m"]:
		catalog[id]=CustomPortCatalog.definition(id)
	return catalog

func _paint_fixture() -> Dictionary:
	var record:=_fixture()
	for row in [["wall","workshop_wall_4m",20],["window","workshop_window_4m",24],["door","workshop_door_4m",28]]:
		record.placements.append(CustomPortCatalog.placement(row[0],row[1],Vector3(row[2],0,10),0,{"custom_notes":{"keep":"me"},"door_open":row[0]=="door"}))
	return record

func _paint_editor(actor:="company-a") -> EDITOR:
	var record:=_paint_fixture()
	var state:=STATE.from_dict(record,record.world,_paint_catalog())
	check(state.validation_errors.is_empty(),"Paint fixture validates: "+str(state.validation_errors))
	var editor:=EDITOR.new()
	editor.configure(state,_paint_catalog(),actor)
	return editor

func _by_id(rows: Array) -> Dictionary:
	var result: Dictionary={}
	for row in rows:result[str(row.id)]=row
	return result

func _test_paint_preserves_document() -> void:
	var editor:=_paint_editor()
	var before:=editor.state.to_dict()
	var applied:=editor.paint_cladding("door",Color("456b88"))
	check(applied.ok,"Open door can receive cladding paint")
	if not applied.ok:return
	var after:=editor.state.to_dict()
	var painted: Dictionary=_by_id(after.placements).door
	check(painted.attributes.wall_colour=="#456b88" and painted.attributes.door_open,"Saved tint preserves the open door state")
	var without_colour:=painted.duplicate(true)
	without_colour.attributes.erase("wall_colour")
	check(without_colour==_by_id(before.placements).door,"Only wall_colour changes; identity, transform and custom metadata are exact")
	for key in ["stores","vessels","reservations","plots","world","origin_m","owner_company_id"]:
		check(after[key]==before[key],"Painting does not alter "+key)
	check(applied.events.size()==1 and applied.events[0].changes.keys()==["placements"],"One paint publishes only a placements change")
	var replica:=STATE.from_dict(before,before.world,_paint_catalog())
	check(replica.replay_event(JSON.parse_string(JSON.stringify(applied.events[0],"",true,true))).ok and replica.to_dict()==after,"Paint event roundtrip reconstructs exact state")
	var path:="user://custom_ports/cladding-data-review.json"
	check(REPOSITORY.save(path,editor.state).ok,"Painted data saves through the actual repository")
	var loaded: Dictionary=REPOSITORY.load_state(path,after.world,_paint_catalog())
	check(loaded.ok and loaded.snapshot==after,"Complete JSON reload retains tint and exact unrelated data")
	check(editor.undo_count()==1 and editor.undo().ok,"Standalone paint is one undo action")
	check(_by_id(editor.state.to_dict().placements)==_by_id(before.placements),"Undo restores original door metadata and all construction")
	check(editor.state.to_dict().stores==before.stores and editor.state.to_dict().vessels==before.vessels,"Paint undo leaves stock and vessels untouched")

func _test_rejected_colours() -> void:
	var editor:=_paint_editor()
	for colour in [Color(NAN,0,0),Color(0,INF,0),Color(-.1,0,0),Color(0,1.1,0),Color(.1,.2,.3,.5),Color(.1,.2,.3,NAN)]:
		var before:=editor.state.to_dict()
		var denied:=editor.paint_cladding("wall",colour)
		check(not denied.ok and denied.code=="invalid_colour","Invalid, nonfinite or translucent colour rejected")
		check(editor.state.to_dict()==before and editor.undo_count()==0,"Rejected paint cannot mutate records or history")
	for id in ["absent","crane-1","quay-1"]:
		var before:=editor.state.to_dict()
		check(not editor.paint_cladding(id,Color("456b88")).ok and editor.state.to_dict()==before,"Missing/nonpaintable placement rejected: "+id)
	check(editor.paint_cladding("wall",Color("456b88")).ok,"A valid colour remains available after rejected inputs")
	var before:=editor.state.to_dict()
	check(editor.paint_cladding("wall",Color("456b88")).code=="colour_unchanged" and editor.state.to_dict()==before and editor.undo_count()==1,"Repeated colour does not create extra revisions or history")
	var stranger:=_paint_editor("foreign-company")
	before=stranger.state.to_dict()
	check(stranger.paint_cladding("wall",Color("456b88")).code=="not_port_owner" and stranger.state.to_dict()==before and stranger.undo_count()==0,"Foreign company cannot paint the port")

func _test_grouped_undo() -> void:
	var editor:=_paint_editor()
	var before:=editor.state.to_dict()
	editor.begin_edit()
	for id in ["wall","window","door"]:check(editor.paint_cladding(id,Color("456b88")).ok,"Stroke paints "+id)
	check(editor.paint_cladding("wall",Color("a84b3f")).ok,"Same stroke may repaint an earlier piece")
	editor.end_edit()
	check(editor.undo_count()==1,"Held brush stroke produces one undo action")
	check(editor.undo().ok and editor.undo_count()==0,"Single undo atomically reverses the stroke")
	check(_by_id(editor.state.to_dict().placements)==_by_id(before.placements),"Grouped inverse order restores every original attribute")

func _test_concurrent_operations() -> void:
	var editor:=_paint_editor()
	var before:=editor.state.to_dict()
	check(editor.paint_cladding("wall",Color("456b88")).ok,"Paint before unrelated cargo operation")
	var berth: Dictionary=editor.state.derived_berths()[0]
	check(_command(editor.state,"dock",{"vessel_id":"ship-a","berth_id":berth.id}).ok,"Visitor docks after painting")
	check(_command(editor.state,"reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"coal-lot","quantity":400,"reservation_id":"after-paint"}).ok,"Cargo reservation follows painting")
	check(_command(editor.state,"load_cargo",{"reservation_id":"after-paint"}).ok,"Finite cargo loads after painting")
	var laden:=editor.state.to_dict()
	check(editor.undo().ok,"Paint undo works against the latest revision")
	var restored:=editor.state.to_dict()
	check(restored.vessels==laden.vessels and restored.stores==laden.stores and restored.reservations==laden.reservations,"Undo does not rewind cargo, stock, docking or reservations")
	check(_by_id(restored.placements)==_by_id(before.placements),"Only the earlier paint is reversed")
	editor=_paint_editor()
	check(editor.paint_cladding("wall",Color("456b88")).ok,"Initial author paints wall")
	var collaborator:=EDITOR.new()
	collaborator.configure(editor.state,_paint_catalog(),"company-a")
	check(collaborator.paint_cladding("wall",Color("e4d8b2")).ok,"A second author changes the same wall")
	before=editor.state.to_dict()
	var denied:=editor.undo()
	check(not denied.ok and denied.code=="placement_changed","Stale undo cannot overwrite another accepted colour")
	check(editor.state.to_dict()==before and editor.undo_count()==1,"Failed stale undo is atomic and keeps its history")
