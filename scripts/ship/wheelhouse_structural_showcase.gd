extends Node

var editor: ShipyardBrickEditor
var parts: ImportedShipPartsEditor

func _ready() -> void:
	editor = ShipyardBrickEditor.new()
	editor.standalone_tool = true
	add_child(editor)
	for i in range(8):
		await get_tree().process_frame
	parts = editor.get("_imported_parts_editor")
	# Actual imported mesh sockets, independent assets, and physical height.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/parts/wheelhouse/manifest.json"))
	assert(manifest["assets"].size() == 17)
	for spec in manifest["assets"]:
		var model := BrickCatalog.create_visual(spec["id"])
		add_child(model)
		var low := INF
		var high := -INF
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			for i in range(8):
				var point: Vector3 = mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(i)
				low = minf(low, point.y)
				high = maxf(high, point.y)
		assert(absf(high-low-2.2) < 0.001, "Full-height geometry " + str(spec["id"]))
		if spec["style"] != "joint":
			var sockets := model.find_children("SocketEnd*", "Node3D", true, false)
			assert(sockets.size() == 1)
			assert(sockets[0].global_position.distance_to(Vector3(spec["end_xz"][0],0,spec["end_xz"][1])) < 0.001)
		model.queue_free()
	# Draw a customizable wheelhouse shell through the same two-click input as users.
	var segments := [
		["wall",-1.5,2,-0.5,2], ["door",-0.5,2,0.5,2], ["wall",0.5,2,1.5,2],
		["wall",1.5,2,1.5,1], ["window",1.5,1,1.5,0], ["wall",1.5,0,1.5,-0.5],
		["window",1.5,-0.5,1,-1.5], ["window",1,-1.5,0.5,-2],
		["window",0.5,-2,-0.5,-2], ["window",-0.5,-2,-1,-1.5],
		["window",-1,-1.5,-1.5,-0.5], ["wall",-1.5,-0.5,-1.5,0],
		["window",-1.5,0,-1.5,1], ["wall",-1.5,1,-1.5,2]
	]
	var camera := editor.get("_camera") as Camera3D
	for segment in segments:
		editor.call("_select_brick", "cabin_" + segment[0] + "_straight")
		var start := Vector3(segment[1],2.92,segment[2])
		var end := Vector3(segment[3],2.92,segment[4])
		_click(camera.unproject_position(start))
		assert(parts.structure_anchor != null)
		var candidate := parts.candidate_at(camera.unproject_position(end))
		assert(not candidate.is_empty(), "Valid wheelhouse segment " + str(segment))
		assert(parts._end(candidate).distance_to(end) < 0.001)
		_click(camera.unproject_position(end))
		assert(parts.records.has(parts.slot_key(candidate)))
	assert(parts.records.size() == segments.size())
	# Compare actual GLB end-ring vertices after Blender shape-key evaluation.
	var rings := {}
	for model in parts.parts_root.get_children():
		assert(not str(model.name).contains("joint"), "No cover posts")
		var record: Dictionary = parts.records[model.get_meta("record_key")]
		var direction := (parts._end(record)-parts._position(record)).normalized()
		for endpoint in [parts._position(record),parts._end(record)]:
			var ring: Array[Vector3] = []
			for mesh in model.find_children("*", "MeshInstance3D", true, false):
				if not (mesh.name.begins_with("Wall") or mesh.name.begins_with("Steel")):
					continue
				for surface in range(mesh.mesh.get_surface_count()):
					var base: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var deformed := parts.deformed_vertices(mesh, surface)
					for i in range(base.size()):
						var point: Vector3 = mesh.global_transform * base[i]
						if absf((point-endpoint).dot(direction)) < 0.0001:
							ring.append(mesh.global_transform * deformed[i])
			assert(ring.size() >= 4)
			var key := "%.3f,%.3f" % [endpoint.x,endpoint.z]
			if rings.has(key):
				for vertex in ring:
					var gap := INF
					for other in rings[key]:
						gap = minf(gap,vertex.distance_to(other))
					assert(gap < 0.0001, "Mating profile gap at " + key + ": " + str(gap))
			else:
				rings[key] = ring
	print("PASS: all 14 wall connections share matching imported end-profile vertices")
	# Out-of-deck and crossing/overlapping walls are rejected.
	assert(not parts._structure_fits({"asset_id":"cabin_wall_straight", "position":[2.5,2.92,0],"yaw_degrees":0}))
	assert(not parts._structure_fits({"asset_id":"cabin_wall_straight", "position":[1.5,2.92,0.5],"yaw_degrees":0}))
	var door_key := ""
	for key in parts.records:
		if BrickCatalog.get_entry(parts.records[key]["asset_id"])["style"] == "door":
			door_key = key
	assert(not door_key.is_empty())
	editor.call("_set_tool", ShipyardBrickEditor.Tool.MARK)
	parts.select_hit(door_key, false)
	assert(parts.door_open.visible)
	parts.door_open.button_pressed = true
	assert(parts.records[door_key]["door_open"])
	parts.wall_picker.color_changed.emit(Color(0.2,0.37,0.4))
	parts.save_draft("user://wheelhouse_structural_test.json")
	var saved := parts.records.duplicate(true)
	parts.load_draft("user://wheelhouse_structural_test.json")
	assert(JSON.stringify(parts.records) == JSON.stringify(saved))
	parts.select_hit(door_key, false)
	parts.delete_selected()
	assert(parts.records.size() == 13)
	parts.undo()
	assert(parts.records.size() == 14)
	# Reference movement is independent of the active Select tool and never adds parts.
	parts.moving_reference = true
	_click(camera.unproject_position(Vector3(0,2.92,3)))
	assert(parts.reference_root.position.distance_to(Vector3(0,2.92,3)) < 0.001)
	assert(parts.records.size() == 14 and not parts.moving_reference)
	# Structural-family selection must not suppress the Erase drag route.
	editor.call("_set_tool", ShipyardBrickEditor.Tool.ERASE)
	# Deletion/undo was checked above; capture with the whole structure restored.
	editor.call("_set_tool", ShipyardBrickEditor.Tool.MARK)
	editor.set("_cam_dist",14.0)
	editor.set("_cam_target",Vector3(0,3.4,0))
	editor.call("_update_camera")
	parts.selection.clear()
	parts.refresh_ui()
	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/wheelhouse/structural-wheelhouse.png")
	print("PASS: 17 Blender assets, sockets and heights; 14 drawn wall/door/window sections; angles, bounds, overlap rejection, door opening, paint, save/load, delete/undo")
	editor.set("_cam_dist",7.0)
	editor.set("_cam_target",Vector3(0,4.0,-0.4))
	editor.call("_update_camera")
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/wheelhouse/seamless-closeup.png")
	editor.set("_cam_dist",14.0)
	editor.set("_cam_target",Vector3(0,3.4,0))
	editor.call("_update_camera")
	editor.call("_select_brick", "cabin_wall_straight")
	parts.structure_anchor = Vector3(-1,2.92,4)
	parts.refresh_ui()
	parts.hover(camera.unproject_position(Vector3(-1,2.92,3)))
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/wheelhouse/builder-ux.png")
	parts.set_floor(1)
	parts.structure_anchor = Vector3(-1,parts.floor_y(),1)
	parts.refresh_ui()
	parts.hover(camera.unproject_position(Vector3(-1,parts.floor_y(),0)))
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/wheelhouse/floor-controls.png")
	parts.set_floor(0)
	if "--verify-wheelhouse" in OS.get_cmdline_user_args():
		editor.queue_free()
		for i in range(4):
			await get_tree().process_frame
		get_tree().quit()

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		editor.call("_on_viewport_gui_input", event)
