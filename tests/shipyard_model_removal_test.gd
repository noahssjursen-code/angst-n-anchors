extends Node


func _ready() -> void:
	assert(not BrickCatalog.has("block"), "Retired parts must not enter the palette")
	assert(PrebuiltVesselCatalog.catalog_entries().is_empty(), "Retired ship presets must stay removed")
	var retired_part := BrickCatalog.create_visual("block")
	assert(retired_part.get_child_count() == 0, "Old IDs must not recreate procedural meshes")
	retired_part.free()
	var editor := ShipyardBrickEditor.new()
	editor.standalone_tool = true
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(editor.is_open())
	assert(editor.find_child("PartsGrid", true, false).get_child_count() == BrickCatalog.ids().size())
	assert(editor.get("_boat") == null, "Opening the editor must not recreate a retired hull")
	assert(editor.get("_hull_option").item_count == 1)
	assert(editor.get("_imported_hull_preview") != null)
	var grid := editor.get("_grid_overlay") as MeshInstance3D
	assert(grid != null)
	var vertices: PackedVector3Array = grid.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, vertices.size(), 2):
		assert(is_equal_approx(vertices[i].x, vertices[i + 1].x) or is_equal_approx(vertices[i].z, vertices[i + 1].z), "Grid segments must be straight and axis aligned")
		assert(is_equal_approx(vertices[i].y, 2.938))
	assert(not editor.get("_confirm_btn").disabled)
	var build_grid := editor.get("_grid") as DeckGrid
	assert(build_grid != null and build_grid.width == 50 and build_grid.length == 140)
	assert(build_grid.in_bounds(Vector3i(25, 0, 70)))
	assert(not build_grid.in_bounds(Vector3i(0, 0, 0)), "No construction over the curved bow edge")
	assert(build_grid.fits_size(Vector3i(3, 0, 70), Vector3(0.1, 1, 0.1)), "Small parts fit near the deck edge")
	assert(not build_grid.fits_size(Vector3i(45, 0, 70), Vector3(1, 1, 1)), "Overhanging footprints are rejected")
	assert(is_equal_approx(build_grid.cell_m, 0.1))
	var center := build_grid.cell_center_local(Vector3i(25, 0, 70))
	assert(build_grid.local_to_cell(center) == Vector3i(25, 0, 70))
	var camera := editor.get("_camera") as Camera3D
	var target := build_grid.cell_base_local(Vector3i(25, 0, 70)) + Vector3(0, 0.05, 0)
	assert(editor.call("_pick_cell", camera.unproject_position(target)) == Vector3i(25, 0, 70), "Editor mouse picking must use the actual construction grid")
	editor.open_for_hull(HullRegistry.FISHING_TRAWLER_SMALL)
	assert(editor.get("_boat") == null, "Refit entry must not restore a retired hull")
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(12):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var screenshot := get_viewport().get_texture().get_image()
		screenshot.save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/trawler-hull/godot-grid.png")
	print("PASS: imported Blender hull and 10cm placement and metre guides; no retired parts or presets")
	get_tree().quit()
