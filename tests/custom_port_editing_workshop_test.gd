extends "res://tests/custom_port_showcase_input_test.gd"

func _run() -> void:
	_check(OS.get_cmdline_user_args().has("--empty-custom-port"),"Editing review uses an empty isolated parcel")
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"The actual workshop becomes ready")
	if not workshop.ready_for_review:_finish_editing();return
	_check(workshop.editor!=null,"The construction editor loads without script errors")
	if workshop.editor==null:workshop.queue_free();await _settle();_finish_editing();return
	# The empty scene opens its coast picker on the first deferred UI frame.
	await _settle()
	workshop._close_map()
	var operations: Array=[]
	for z in [4,12,20]:
		for x in [-4,4]:
			var at:=Vector3(x,0,z)
			var world: Vector3=workshop.site+at
			var depth:=maxf(.1,world.y-workshop._support_seabed(Vector2(world.x,world.z)))
			operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("deck-%d-%d"%[x,z],"foundation_8m",at,0,{"support_depth_m":depth})}})
	for piece in [["wall-a","workshop_wall_4m",Vector3(-4,0,8)],
		["wall-b","workshop_wall_4m",Vector3(-4,0,12)],
		["gutter","workshop_roof_edge_4m",Vector3(-4,0,8)],
		["drain","drain_2m",Vector3(4,0,10)],
		["ladder","quay_ladder",Vector3(4,0,0)]]:
		operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement(piece[0],piece[1],piece[2],0,{"fixture_note":"preserve me"})}})
	var built: Dictionary=workshop._command("edit_assets",{"operations":operations})
	_check(built.ok,"Quay and real decorative assets build through authority commands: "+str(built.get("errors",[])))
	if not built.ok:workshop.queue_free();await _settle();_finish_editing();return
	workshop.build()
	await _settle()
	_check(await _aim_piece(workshop,"gutter",true),"Horizontal camera ray selects the colliderless gutter, not its wall")
	_check(workshop.preview.is_empty(),"Looking horizontally at raised trim has no shared-plane placement target")
	var before: Dictionary=workshop.state.to_dict()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(not workshop.presenter.placement_nodes.has("gutter") and workshop.presenter.placement_nodes.has("wall-a"),"Actual RMB removes the trim while keeping the wall")
	await _undo()
	_check(_placements_by_id(workshop.state.to_dict())==_placements_by_id(before),"Actual Ctrl+Z restores the exact removed decoration and keeps all other pieces")
	_check(await _aim_piece(workshop,"drain"),"The restored presenter picks the thin drain")
	before=workshop.state.to_dict()
	await _mouse(MOUSE_BUTTON_MIDDLE)
	_check(workshop.moving_id=="drain" and workshop.state.to_dict()==before,"Middle mouse starts movement without deleting or changing the piece")
	workshop.camera.position=workshop.site+Vector3(7,9,15)
	workshop.camera.look_at(workshop.site+Vector3(4,0,14))
	await _settle()
	_check(workshop.preview.get("ok",false),"Existing drain has a valid snapped destination")
	await _key(KEY_R)
	_check(workshop.preview.get("ok",false) and float(workshop.preview.placement.yaw_degrees)==90,"R rotates the moving piece, preserving a valid snapped preview")
	var shown: Dictionary=workshop.preview.placement.duplicate(true)
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("editing-moving-drain-preview")
	await _mouse(MOUSE_BUTTON_LEFT)
	var moved:=_placement(workshop.state.to_dict(),"drain")
	# Authority normalizes the JSON coordinates to floats; compare their actual
	# metre positions, not Variant-array integer/float tags (0 versus 0.0).
	var moved_position:=CustomPortCatalog.vector3(moved.position_m)
	_check(workshop.moving_id.is_empty() and moved_position==CustomPortCatalog.vector3(shown.position_m) and moved_position!=CustomPortCatalog.vector3(_placement(before,"drain").position_m) and float(moved.yaw_degrees)==90,"Actual LMB commits exactly the displayed transform once")
	_check(moved.id=="drain" and moved.attributes.fixture_note=="preserve me" and workshop.state.to_dict().placements.size()==before.placements.size(),"Movement keeps identity, metadata and placement count")
	await _undo()
	_check(workshop.state.to_dict().placements==before.placements,"One Ctrl+Z reverses the complete move and rotation")
	_check(await _aim_piece(workshop,"drain"),"Moved and undone mesh remains pickable")
	await _mouse(MOUSE_BUTTON_MIDDLE)
	before=workshop.state.to_dict()
	workshop.camera.position=workshop.site+Vector3(7,9,15)
	workshop.camera.look_at(workshop.site+Vector3(4,0,14))
	await _settle()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(workshop.moving_id.is_empty() and workshop.state.to_dict()==before,"RMB cancels an uncommitted move without deleting anything")
	_check(await _aim_piece(workshop,"ladder"),"A ladder is selectable without adding a gameplay collision wall")
	await _mouse(MOUSE_BUTTON_MIDDLE)
	_check(workshop.moving_id=="ladder","Middle mouse can select quay-edge fittings")
	before=workshop.state.to_dict()
	await _key(KEY_ESCAPE)
	_check(workshop.building and workshop.moving_id.is_empty() and workshop.state.to_dict()==before,"Escape cancels the selection before leaving build mode")
	workshop.save_path="user://custom_ports/editing-workshop-%d.json"%Time.get_ticks_usec()
	workshop.save_port();workshop.load_port()
	await _settle()
	_check(workshop.state.to_dict()==before,"The edited port restores its complete document")
	workshop.build()
	_check(await _aim_piece(workshop,"gutter",true),"Loading a document refreshes selection for its new visual instances")
	if OS.get_cmdline_user_args().has("--capture"):
		workshop.camera.position=workshop.site+Vector3(19,12,-6)
		workshop.camera.look_at(workshop.site+Vector3(0,1,10))
		workshop._set_cursor(true)
		await workshop._capture("editing-restored-details")
	workshop.queue_free();await _settle();_finish_editing()

func _aim_piece(workshop: Node, id: String, horizontal:=false) -> bool:
	var root: Node3D=workshop.presenter.placement_nodes.get(id)
	if not is_instance_valid(root):return false
	for node in root.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if mesh.mesh==null:continue
		var faces:=mesh.mesh.get_faces()
		for i in range(0,faces.size()-2,3):
			var a: Vector3=mesh.global_transform*faces[i]
			var b: Vector3=mesh.global_transform*faces[i+1]
			var c: Vector3=mesh.global_transform*faces[i+2]
			var normal:=(b-a).cross(c-a).normalized()
			if normal.length_squared()<.9:continue
			if horizontal and absf(normal.y)>.0001:continue
			var centre:=(a+b+c)/3.0
			var origin:=centre+normal*2.0
			if origin.y<workshop.camera.minimum_y:continue
			workshop._update_hovered_placement(origin,-normal)
			if workshop.hovered_id!=id:continue
			workshop.camera.global_position=origin
			workshop.camera.look_at(centre,Vector3.FORWARD if absf(normal.y)>.97 else Vector3.UP)
			await _settle()
			if workshop.hovered_id==id:return true
	return false

func _undo() -> void:
	var key:=InputEventKey.new()
	key.keycode=KEY_Z;key.physical_keycode=KEY_Z;key.ctrl_pressed=true;key.pressed=true
	Input.parse_input_event(key);await get_tree().process_frame
	key=key.duplicate();key.pressed=false
	Input.parse_input_event(key);await get_tree().process_frame

func _placement(snapshot: Dictionary,id: String) -> Dictionary:
	for row in snapshot.placements:
		if str(row.id)==id:return row
	return {}

func _placements_by_id(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for row in snapshot.placements:result[str(row.id)]=row
	return result

func _finish_editing() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT EDITING WORKSHOP ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
