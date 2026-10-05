extends Node

var editor: ShipyardBrickEditor
var parts: ImportedShipPartsEditor
const OUT := "C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/roof-kit/"

func _ready() -> void:
	editor=ShipyardBrickEditor.new()
	editor.standalone_tool=true
	add_child(editor)
	for i in 8: await get_tree().process_frame
	parts=editor.get("_imported_parts_editor")
	var outline := PackedVector2Array([Vector2(-1.5,2),Vector2(1.5,2),Vector2(1.5,-.5),Vector2(1,-1.5),Vector2(.5,-2),Vector2(-.5,-2),Vector2(-1,-1.5),Vector2(-1.5,-.5)])
	var concave := PackedVector2Array([Vector2(-1,0),Vector2(1,0),Vector2(1,2),Vector2(0,2),Vector2(0,1),Vector2(-1,1)])
	for polygon in [outline,concave]:
		for reversed in [false,true]:
			var poly: PackedVector2Array=polygon.duplicate()
			if reversed: poly.reverse()
			assert(ShipSurfaceKit.valid(poly))
			var area := 0.0
			for tile in ShipSurfaceKit.tiles(poly,"roof"):
				assert(BrickCatalog.has(tile["id"]))
				area+=tile["area"]
			assert(absf(area-ShipSurfaceKit.area(poly))<.0001,"Exact coverage for angles / concavity / both windings")
	assert(not ShipSurfaceKit.valid(PackedVector2Array([Vector2(0,0),Vector2(1,1),Vector2(0,1),Vector2(1,0)])))
	assert(not ShipSurfaceKit.valid(PackedVector2Array([Vector2(0,0),Vector2(1.5,.5),Vector2(0,1)])))
	# Finished floor is 10cm above the hull, underside rests on the original deck.
	parts.step_cell(1)
	editor.call("_select_brick","floor_tile")
	var camera := editor.get("_camera") as Camera3D
	for p in outline: _click(camera.unproject_position(Vector3(p.x,parts.floor_y(),p.y)))
	var enter := InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true
	parts.key_input(enter)
	assert(parts.records.size()==1,"One editable floor assembly")
	assert(parts.surface_outline.is_empty())
	var floor_record: Dictionary=parts.records.values()[0]
	assert(floor_record["asset_id"]=="floor_tile")
	# Existing independent cabin walls/door/windows use the same drawn footprint.
	var segments := [
		["wall",-1.5,2,-.5,2],["door",-.5,2,.5,2],["wall",.5,2,1.5,2],
		["wall",1.5,2,1.5,1],["window",1.5,1,1.5,0],["wall",1.5,0,1.5,-.5],
		["window",1.5,-.5,1,-1.5],["window",1,-1.5,.5,-2],
		["window",.5,-2,-.5,-2],["window",-.5,-2,-1,-1.5],
		["window",-1,-1.5,-1.5,-.5],["wall",-1.5,-.5,-1.5,0],
		["window",-1.5,0,-1.5,1],["wall",-1.5,1,-1.5,2]]
	for seg in segments:
		editor.call("_select_brick","cabin_"+seg[0]+"_straight")
		_click(camera.unproject_position(Vector3(seg[1],parts.floor_y(),seg[2])))
		_click(camera.unproject_position(Vector3(seg[3],parts.floor_y(),seg[4])))
	assert(parts.records.size()==15)
	parts.cancel_placement()
	editor.set("_cam_dist",9.0)
	editor.set("_cam_target",Vector3(0,3.9,0))
	editor.call("_update_camera")
	await _shot("floor-and-walls.png")
	parts.set_floor(1,1)
	editor.call("_select_brick","roof_tile")
	parts.roof_crown.button_pressed=true
	parts.roof_visor.item_selected.emit(1)
	for p in outline: _click(camera.unproject_position(Vector3(p.x,parts.floor_y(),p.y)))
	parts.hover(camera.unproject_position(Vector3(outline[0].x,parts.floor_y(),outline[0].y)))
	assert(is_instance_valid(parts.ghost),"Actual assembled roof ghost")
	await _shot("roof-preview.png")
	_click(camera.unproject_position(Vector3(outline[0].x,parts.floor_y(),outline[0].y)))
	assert(parts.records.size()==16)
	var roof_key := ""
	for key in parts.records:
		if parts.records[key]["asset_id"]=="roof_tile": roof_key=key
	assert(not roof_key.is_empty())
	# Inspect actual imported fascia endpoints after morph evaluation.
	var roof: Node3D
	for model in parts.parts_root.get_children():
		if model.get_meta("record_key")==roof_key: roof=model
	assert(roof!=null)
	var corners := {}
	var checked_joins := 0
	var edge_count := 0
	for edge in roof.get_children():
		if not edge.has_meta("edge_asset"): continue
		edge_count+=1
		var length: float = BrickCatalog.get_entry(edge.get_meta("edge_asset")).get("end_xz",[0,0])[1]
		for endpoint in [0.0,length]:
			var point: Vector3=edge.transform*Vector3(0,0,endpoint)
			var key := "%.4f,%.4f" % [point.x,point.z]
			var ring: Array[Vector3]=[]
			for mesh in edge.find_children("*","MeshInstance3D",true,false):
				for surface in mesh.mesh.get_surface_count():
					var base: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var vertices := parts.deformed_vertices(mesh,surface)
					for j in base.size():
						if absf(base[j].z-endpoint)<.0001: ring.append(mesh.global_transform*vertices[j])
			assert(ring.size()>=5)
			if corners.has(key):
				checked_joins+=1
				for v in ring:
					var gap:=INF
					for other in corners[key]: gap=minf(gap,v.distance_to(other))
					assert(gap<.0001,"Roof perimeter profile gap "+key+" "+str(gap))
			else: corners[key]=ring
	assert(checked_joins==edge_count and edge_count>20,"Every perimeter joint checked")
	# Painting independently and draft round-trip preserve footprint and colours.
	editor.call("_set_tool",ShipyardBrickEditor.Tool.MARK)
	parts.select_hit(roof_key,false)
	parts.surface_pickers["fascia"].color_changed.emit(Color(.08,.24,.29))
	assert(parts.records[roof_key]["colors"]["surface"]!=parts.records[roof_key]["colors"]["fascia"])
	parts.save_draft("user://shipyard_drafts/roof_kit_test.json")
	var saved := parts.records.duplicate(true)
	parts.load_draft("user://shipyard_drafts/roof_kit_test.json")
	assert(JSON.stringify(parts.records)==JSON.stringify(saved))
	parts.select_hit(roof_key,false)
	parts.delete_selected();assert(parts.records.size()==15)
	parts.undo();assert(parts.records.size()==16)
	parts.selection.clear();parts.refresh_ui()
	parts.reference_root.position=Vector3(-2,2.92,2.5)
	editor.set("_cam_dist",8.5)
	editor.set("_cam_target",Vector3(0,4.1,0))
	editor.call("_update_camera")
	await _shot("finished-roof.png")
	print("PASS: Blender coverage for straight/26/45 and concave outlines, both windings; actual click drawing, roof ghost, walls, floor, paint isolation, draft reload, erase and undo")
	if "--verify-roof" in OS.get_cmdline_user_args():
		editor.queue_free()
		for i in 4: await get_tree().process_frame
		get_tree().quit()

func _click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		editor.call("_on_viewport_gui_input",event)

func _shot(filename: String) -> void:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	get_viewport().get_texture().get_image().save_png(OUT+filename)
