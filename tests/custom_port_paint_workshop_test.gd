extends "res://tests/custom_port_editing_workshop_test.gd"

func _run() -> void:
	var workshop:=WORKSHOP.instantiate()
	workshop.example_kind=1
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Actual fishing workshop ready")
	if not workshop.ready_for_review:_finish_paint();return
	workshop._set_cursor(true)
	await _settle()
	var before: Dictionary=workshop.state.to_dict()
	await _click_control(workshop.library.paint_button)
	_check(workshop.cladding_paint_mode and workshop.library.paint_palette.visible and workshop.cursor_mode,"Actual palette button exposes colours without stealing the cursor")
	await _click_control(workshop.library._paint_buttons[3])
	_check(workshop.cladding_paint_colour.to_html(false)=="486d80","Actual blue swatch chooses the paint")
	_check(workshop.state.to_dict()==before,"Choosing colour does not modify any port data")
	_check(get_viewport().get_visible_rect().encloses(workshop.library.paint_palette.get_global_rect()),"Palette remains inside actual viewport")
	await _key(KEY_TAB)
	_check(workshop.camera.flying and workshop.cladding_paint_mode,"Tab enters freecam with the selected paint")
	_check(await _aim_piece(workshop,"front--10",true),"Aim can select the front window cladding")
	_check(workshop.preview.is_empty() and (not is_instance_valid(workshop.ghost) or not workshop.ghost.visible),"Painting does not show or place a foundation ghost")
	var count: int=workshop.state.to_dict().placements.size()
	var undo_before: int=workshop.editor.undo_count()
	await _press_mouse(true)
	await _settle()
	_check(_placement(workshop.state.to_dict(),"front--10").attributes.get("wall_colour")=="#486d80","Actual held LMB paints the selected existing window")
	_check(await _aim_piece(workshop,"front--6",true),"A held stroke moves to the adjacent door")
	await _settle()
	await _press_mouse(false)
	var painted: Dictionary=workshop.state.to_dict()
	_check(_placement(painted,"front--6").attributes.get("wall_colour")=="#486d80","Same held stroke paints the existing door")
	_check(painted.placements.size()==count and painted.stores==before.stores and painted.vessels==before.vessels,"Paint preserves construction count and full cargo manifests")
	_check(workshop.editor.undo_count()==undo_before+1,"The two-piece stroke is one undo group")
	_check(_cladding_colours(workshop.presenter.placement_nodes["front--10"]).has("486d80"),"Rendered timber material uses the persisted blue colour")
	var original_trim:=_named_materials(workshop.presenter.placement_nodes["front--10"],"Ivory trim")
	_check(not original_trim.is_empty() and not original_trim.has("486d80"),"Window trim keeps its separate finish")
	await _undo()
	_check(_placement(workshop.state.to_dict(),"front--10")==_placement(before,"front--10") and _placement(workshop.state.to_dict(),"front--6")==_placement(before,"front--6"),"Actual Ctrl+Z restores both complete pieces in one stroke")
	_check(await _aim_piece(workshop,"front--10",true),"Restored piece remains pickable")
	await _mouse(MOUSE_BUTTON_LEFT)
	_check(_placement(workshop.state.to_dict(),"front--10").attributes.get("wall_colour")=="#486d80","Paint works again after undo")
	var revision: int=workshop.state.revision()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(not workshop.cladding_paint_mode and workshop.state.revision()==revision and workshop.state.to_dict().placements.size()==count,"RMB leaves paint mode without demolishing the target")
	workshop.save_path="user://paint-workshop-%d.json"%OS.get_process_id()
	workshop.save_port()
	var saved: Dictionary=workshop.state.to_dict()
	workshop.load_port()
	_check(workshop.state.to_dict()==saved and _cladding_colours(workshop.presenter.placement_nodes["front--10"]).has("486d80"),"Save/Load reconstructs exact data and textured cladding colour")
	workshop.camera.position=workshop.site+Vector3(10,9,14)
	workshop.camera.look_at(workshop.site+Vector3(-7,1.7,27))
	workshop._set_cursor(true)
	await _click_control(workshop.library.paint_button)
	await _settle()
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("painted-cladding-and-palette")
	workshop.queue_free()
	await _settle()
	_finish_paint()

func _click_control(control: Control) -> void:
	var position:=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new()
	motion.position=position;motion.global_position=position
	Input.parse_input_event(motion)
	await _settle()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=position;event.global_position=position
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		Input.parse_input_event(event)
		await _settle()

func _press_mouse(pressed: bool) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	Input.parse_input_event(event)
	await _settle()

func _cladding_colours(node: Node3D) -> Array:
	return _named_materials(node,"Office cladding")

func _named_materials(node: Node3D, name: String) -> Array:
	var result: Array=[]
	for mesh in SurfaceMaterialLibrary.meshes(node):
		for index in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(index)
			if material!=null and material.resource_name.get_slice(".",0)==name:
				result.append(SurfaceMaterialLibrary.colour_of(material).to_html(false))
	return result

func _finish_paint() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT PAINT WORKSHOP ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
