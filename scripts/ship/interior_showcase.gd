extends Node
var editor: ShipyardBrickEditor
var parts: ImportedShipPartsEditor

func _ready() -> void:
	editor=ShipyardBrickEditor.new();editor.standalone_tool=true;add_child(editor)
	for i in 8: await get_tree().process_frame
	parts=editor.get("_imported_parts_editor")
	var camera:=editor.get("_camera") as Camera3D
	var front := [Vector2(-1.5,-.5),Vector2(-1,-1.5),Vector2(-.5,-2),Vector2(.5,-2),Vector2(1,-1.5),Vector2(1.5,-.5)]
	# Place window walls and counter along the exact same construction edges.
	for family in ["cabin_window_straight","cabin_console_straight"]:
		for i in range(front.size()-1):
			editor.call("_select_brick",family)
			_click(camera.unproject_position(Vector3(front[i].x,2.92,front[i].y)))
			_click(camera.unproject_position(Vector3(front[i+1].x,2.92,front[i+1].y)))
	assert(parts.records.size()==10,"Console must coexist with window walls")
	var rings := {}
	var joined := 0
	for model in parts.parts_root.get_children():
		var record: Dictionary=parts.records[str(model.get_meta("record_key"))]
		if BrickCatalog.get_entry(record["asset_id"])["kind"]!="console": continue
		var direction: Vector3=(parts._end(record)-parts._position(record)).normalized()
		for endpoint in [parts._position(record),parts._end(record)]:
			var ring: Array[Vector3]=[]
			for mesh in model.find_children("*","MeshInstance3D",true,false):
				for surface in mesh.mesh.get_surface_count():
					var base: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var evaluated:=parts.deformed_vertices(mesh,surface)
					for j in base.size():
						if absf((mesh.global_transform*base[j]-endpoint).dot(direction))<.0001: ring.append(mesh.global_transform*evaluated[j])
			assert(ring.size()>=8)
			var key:="%.4f,%.4f" % [endpoint.x,endpoint.z]
			if rings.has(key):
				joined+=1
				for v in ring:
					var gap:=INF
					for other in rings[key]: gap=minf(gap,v.distance_to(other))
					assert(gap<.0001,"Counter join gap: "+str(gap))
			else: rings[key]=ring
	assert(joined==4,"All angled counter joins tested")

	for placement in [["helm_wheel",0,-1.7],["helm_throttle",.35,-1.7],["helm_display",-.3,-1.7],["helm_chair",0,-.7],["passenger_seat",1,.6]]:
		editor.call("_select_brick",placement[0])
		var point:=camera.unproject_position(Vector3(placement[1],2.92,placement[2]))
		assert(not parts.candidate_at(point).is_empty(),"Valid interior placement "+placement[0])
		_click(point)
	assert(parts.records.size()==15)
	parts.place_record({"asset_id":"cabin_door_straight","position":[-1.5,2.92,1.5],"yaw_degrees":0.0})
	var wheel: Node3D
	var door: Node3D
	var throttle: Node3D
	for model in parts.parts_root.get_children():
		var record: Dictionary=parts.records[str(model.get_meta("record_key"))]
		match record["asset_id"]:
			"helm_wheel": wheel=model
			"helm_throttle": throttle=model
			"cabin_door_straight": door=model
	assert(wheel.find_children("WheelPivot*","Node3D",true,false).size()==1)
	assert(throttle.find_children("ThrottlePivot*","Node3D",true,false).size()==1)
	var driver:=wheel.get_node("PartState") as ShipPartState
	driver.local_authority=false
	driver.request("steering",.8)
	assert(driver.state["steering"]==0,"Remote interaction waits for authority")
	assert(driver.apply_snapshot({"steering":.65},10))
	assert(not driver.apply_snapshot({"steering":-.7},9),"Stale packet rejected")
	assert(not driver.apply_snapshot({"steering":NAN},11),"Invalid state rejected atomically")
	var local_controller:=BoatController.new()
	local_controller.set("_rudder",-.4)
	local_controller.set("_throttle",-.6)
	driver.bind_local_helm(local_controller)
	driver._process(.1)
	assert(is_equal_approx(driver.state["steering"],-.4) and is_equal_approx(driver.state["throttle"],.6))
	local_controller.free()
	throttle.get_node("PartState").request("throttle",.7)
	door.get_node("PartState").request("door_open",true)
	for i in 60: await get_tree().process_frame
	assert(absf(wheel.find_children("WheelPivot*","Node3D",true,false)[0].rotation.z)>1)
	assert(door.find_children("DoorLeafPivot*","Node3D",true,false)[0].rotation.y>.5)
	# Persist through the actual editor interaction UI.
	editor.call("_set_tool",ShipyardBrickEditor.Tool.MARK)
	parts.select_hit(str(door.get_meta("record_key")),false)
	parts._request_part_state("door_open",true)
	driver.local_authority=true
	parts.select_hit(str(wheel.get_meta("record_key")),false)
	parts._request_part_state("steering",.55)
	parts.select_hit(str(throttle.get_meta("record_key")),false)
	parts._request_part_state("throttle",.7)
	parts.save_draft("user://shipyard_drafts/interior_test.json")
	var saved:=JSON.stringify(parts.records)
	parts.load_draft("user://shipyard_drafts/interior_test.json")
	assert(JSON.stringify(parts.records)==saved)
	parts.selection.clear();parts.refresh_ui()
	editor.set("_cam_dist",7.3)
	editor.set("_cam_target",Vector3(0,3.8,-.8))
	editor.call("_update_camera")
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder:="C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/interior/"
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder+"console-and-seating.png")
	print("PASS: counters coexist with angled windows; equipment mounts, independent pivots; local interaction, authoritative snapshots, stale/invalid rejection, animated door/wheel and draft round-trip")
	if "--verify-interior" in OS.get_cmdline_user_args(): get_tree().quit()

func _click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		editor.call("_on_viewport_gui_input",event)
