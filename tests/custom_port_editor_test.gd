extends Node
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const EDITOR = preload("res://scripts/port/building/custom_port_editor.gd")
const CATALOG = preload("res://scripts/port/building/custom_port_catalog.gd")
var failures: Array[String] = []
var count := 0


func _ready() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)


func _base() -> Dictionary:
	return {"schema_version": 1, "id": "editor-test", "owner_company_id": "builder",
		"world": {"seed": 3, "generation_version": 1, "checksum": "editor-island"},
		"origin_m": [1000, 0.5, 2000], "deck_height_above_sea_m": 2,
		"plots": [{"id": "home", "owner_company_id": "builder", "rect_m": [-100, -100, 200, 200]}],
		"placements": [], "stores": [], "vessels": []}


func _run() -> void:
	if not ShipyardPlaytestMode.active():
		get_tree().quit(1)
		return
	_test_snap_and_strokes()
	_test_large_foundation()
	_test_walls_edges_and_support()
	_test_roof_alignment()
	_test_undo_preserves_operations()
	_test_diagonal_tiles()
	_test_crane_store_undo()
	_test_fish_equipment_snap()
	check(count >= 30, "all scenarios reached assertions")
	print("CUSTOM PORT EDITOR %s: %d checks; %d failures" % ["PASS" if failures.is_empty() else "FAIL", count, failures.size()])
	for failure in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_editor(record: Dictionary = {}) -> EDITOR:
	var input := _base() if record.is_empty() else record
	var catalog := CATALOG.definitions()
	var state := STATE.from_dict(input, input.world, catalog)
	check(state.validation_errors.is_empty(), "editor fixture valid: %s" % [state.validation_errors])
	var editor := EDITOR.new()
	editor.configure(state, catalog, "builder")
	return editor


func _test_snap_and_strokes() -> void:
	var editor := _new_editor()
	var before := editor.state.to_dict()
	var proposal := editor.preview("foundation", Vector3(0.2, 900, 0.2))
	check(proposal.ok and proposal.placement.position_m == [2.0, 0, 2.0], "4x4 foundation snaps to its footprint and fixed deck")
	var computed := editor.previews_evaluated
	var refreshed := editor.geometry_refreshes
	for i in 200:
		editor.preview("foundation", Vector3(0.2 + i * 0.001, -300, 0.2))
	check(editor.previews_evaluated == computed, "same-cell pointer movement reuses preview")
	check(editor.geometry_refreshes == refreshed, "same revision does not clone/rebuild port every frame")
	check(editor.state.to_dict() == before, "preview never mutates state or receipts")
	check(editor.place(proposal).ok, "place snaps through authority command")
	check(not editor.preview("foundation", Vector3(0.5, 9, 0.5)).ok, "overlapping foundation denied")
	var quay := editor.preview("quay", Vector3(9, 50, 1))
	check(quay.ok and quay.placement.position_m == [12.0, 0, 2.0], "8x4 quay uses an 8x4 grid")
	var turned := editor.preview("quay", Vector3(1, 50, 9), 90)
	check(turned.ok and turned.placement.position_m == [2.0, 0, 12.0], "rotating quay rotates its snapping dimensions")
	var world := editor.preview_world("foundation", Vector3(1009, -400, 2009))
	check(world.placement.position_m == [10.0, 0, 10.0], "world pointer converts to port local coordinates")
	editor.begin_edit()
	for x in [6, 10, 14]:
		check(editor.place_asset("foundation", Vector3(x, 70, 2)).ok, "paint foundation %d" % x)
	editor.end_edit()
	check(editor.undo_count() == 2 and editor.state.to_dict().placements.size() == 4, "three tiles form one undo stroke")
	var revision := editor.state.revision()
	check(editor.undo().ok, "undo complete paint stroke")
	check(editor.state.to_dict().placements.size() == 1 and editor.state.revision() == revision + 1, "stroke undo is one atomic revision")
	check(not editor.preview("foundation", Vector3(120, 0, 0)).ok, "unowned land shown invalid")
	check(editor.state.to_dict().placements.size() == 1, "invalid preview cannot place outside plot")


func _test_walls_edges_and_support() -> void:
	var record := _base()
	for x in range(-10, 12, 4):
		for z in range(2, 20, 4):
			record.placements.append(CATALOG.placement("floor-%d-%d" % [x,z], "foundation", Vector3(x, 0, z)))
	var editor := _new_editor(record)
	var tire := editor.preview("tractor_tire_fender", Vector3(1.1, 6, -0.3), 180)
	check(tire.ok and is_zero_approx(tire.placement.position_m[2]), "hanging tire snaps to exposed quay edge")
	check(is_zero_approx(fposmod(float(tire.placement.yaw_degrees), 360)), "edge fitting automatically faces water")
	check(not editor.preview("tractor_tire_fender", Vector3(0, 0, 10)).ok, "interior tile seam is not a waterfront edge")
	var bollard := editor.preview("quay_bollard", Vector3(5.1, 7, 0.2))
	check(bollard.ok and is_equal_approx(float(bollard.placement.position_m[2]), 0.75), "bollard aligns to shore with supported inset")
	var first := editor.preview("workshop_wall_4m", Vector3(1.8, 0, 8.1))
	check(first.ok and editor.place(first).ok, "place first wall on fixed plane")
	var second := editor.preview("workshop_wall_4m", Vector3(5.8, 0, 8.2))
	check(second.ok and second.placement.position_m == [6.0, 0, 8.0], "wall sockets chain at exact 4m intervals")
	check(editor.place(second).ok, "second wall joins without overlap")
	var corner := editor.preview("workshop_window_4m", Vector3(8.1, 0, 10.1), 90)
	check(corner.ok and corner.placement.position_m == [8.0, 0, 10.0], "perpendicular window snaps onto wall-end socket")
	check(editor.place(corner).ok, "wall corner accepted by shared geometry rules")
	check(not editor.remove("floor-6-10").ok, "cannot remove supporting floor below installed wall")
	check(editor.remove(str(corner.placement.id)).ok, "remove wall via data command")
	check(editor.undo().ok, "undo removal reconstructs wall record")
	var unsupported := editor.preview("quay_light", Vector3(40, 0, 40))
	check(not unsupported.ok, "equipment cannot float without foundation")


func _test_roof_alignment() -> void:
	for sign_value in [1, -1]:
		var editor := _new_editor()
		for x in [4, 12]:
			for z in [4, 12]:
				check(editor.place_asset("foundation_8m", Vector3(x * sign_value, 0, z * sign_value)).ok, "room floor builds through normal 8m snapping")
		var center := Vector3(6 * sign_value, 0, 6 * sign_value)
		for wall in [["workshop_window_4m", Vector3(0,0,-2), 0], ["workshop_wall_4m", Vector3(0,0,2), 180],
				["workshop_wall_4m", Vector3(-2,0,0), 90], ["workshop_door_4m", Vector3(2,0,0), 270]]:
			var proposal := editor.preview(wall[0], center + wall[1], wall[2])
			check(proposal.ok and editor.place(proposal).ok, "room walls join through the real wall-socket preview")
		var expected := [center.x, 0, center.z]
		var roof: Dictionary
		for yaw in [0, 90, 180, 270]:
			roof = editor.preview("workshop_roof_4m", center + Vector3(.1,70,.1), yaw)
			check(roof.ok and roof.placement.position_m == expected, "roof aligns with the enclosed room at either sign and each quarter turn")
		check(editor.place(roof).ok, "matching roof is accepted through the actual authority command")
		var bounds := CustomPortPlacementRules.polygon_bounds(CustomPortPlacementRules.polygons(roof.placement, editor.catalog.workshop_roof_4m)[0])
		check(bounds == Rect2(Vector2(center.x,center.z) - Vector2(2,2), Vector2(4,4)), "roof footprint covers the whole room without a half-cell overhang")
		var trim := editor.preview("workshop_roof_edge_4m", center + Vector3(0,0,-2))
		check(trim.ok and trim.placement.position_m == [center.x,0,center.z-2], "roof edge retains wall-edge alignment rather than roof-plane centering")
		check(editor.place(trim).ok, "roof-edge trim fits the enclosed building")
	var saved := _base()
	saved.placements = [CATALOG.placement("old-floor", "foundation_8m", Vector3.ZERO),
		CATALOG.placement("old-roof", "workshop_roof_4m", Vector3.ZERO)]
	var restored := _new_editor(saved)
	check(restored.state.to_dict().placements == saved.placements, "valid older authored centres remain unchanged on import")
	var before := restored.state.to_dict()
	restored.preview("workshop_roof_4m", Vector3(6,0,6))
	check(restored.state.to_dict() == before, "new preview grid never rewrites existing saved roof positions")


func _test_large_foundation() -> void:
	var editor := _new_editor()
	var spec: Dictionary = editor.catalog.get("foundation_8m", {})
	check(spec.get("footprint_m", []) == [8.0,8.0] and spec.get("kind") == "platform", "larger foundation is an actual 8m platform in the shared catalog")
	check(PlotBuildLayout.catalog()[0].id == "foundation" and "4 × 4" in editor.catalog.foundation.name and "8 × 8" in str(spec.get("name", "")), "original 4m foundation stays first and both names show dimensions")
	var proposal := editor.preview("foundation_8m", Vector3(.1, 300, .1))
	check(proposal.ok and proposal.placement.position_m == [4.0,0,4.0] and proposal.snap_m == [8.0,8.0], "8m foundation snaps by its full footprint on the fixed deck")
	check(editor.preview("foundation_8m", Vector3(7.9, -30, 7.9)).placement.position_m == proposal.placement.position_m, "moving within the 8m cell does not shift the foundation by 1m")
	check(editor.preview("foundation_8m", Vector3(8.1, 0, .1), 90).placement.position_m == [12.0,0,4.0], "adjacent and rotated large tiles keep the 8m grid")
	check(editor.preview("foundation_8m", Vector3(-.1, 0, -.1)).placement.position_m == [-4.0,0,-4.0], "negative local coordinates preserve the same origin grid")
	proposal.placement.attributes.support_depth_m = 27.5
	check(editor.place(proposal).ok, "place large foundation with terrain-derived support depth")
	check(not editor.preview("foundation", Vector3(6, 0, 6)).ok, "small foundation cannot overlap the large tile")
	editor.begin_edit()
	check(editor.place_asset("foundation", Vector3(10, 0, 2)).ok and editor.place_asset("foundation", Vector3(10, 0, 6)).ok, "two 4m tiles meet the full 8m edge without overlap or gaps")
	editor.end_edit()
	var seam_prop := editor.preview("quay_light", Vector3(8, 0, 4))
	check(seam_prop.ok and editor.place(seam_prop).ok, "a prop crossing the shared 8m/4m seam has continuous support")
	check(not editor.remove(str(proposal.placement.id)).ok, "large foundation cannot be removed while it supports installed equipment")
	var snapshot := editor.state.to_dict()
	var path := "user://custom-port-large-foundation-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var saved := CustomPortRepository.save(path, editor.state)
	check(saved.ok, "large foundation and mixed tiles save through the real repository")
	if saved.ok:
		var loaded := CustomPortRepository.load_state(path, snapshot.world, editor.catalog)
		check(loaded.ok and loaded.snapshot == snapshot, "save restores size, shared datum, support depth and attached prop exactly")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(editor.undo().ok and editor.undo().ok, "undo removes the prop and grouped small-tile extension")
	check(editor.state.to_dict().placements.size() == 1 and editor.state.to_dict().placements[0].asset_id == "foundation_8m", "undo preserves the earlier large foundation")
	check(editor.undo().ok and editor.state.to_dict().placements.is_empty(), "large foundation itself remains undoable")
	var visual := PlotBuildVisuals.create(spec, false, true, 27.5)
	var mesh := visual.get_child(0) as MeshInstance3D
	var collider := visual.get_child(1).get_child(0) as CollisionShape3D
	check(mesh.mesh.size == Vector3(8,27.5,8) and is_equal_approx(mesh.position.y, -13.75), "large concrete visual extends from the fixed plane down to the required support depth")
	check(collider.shape.size == mesh.mesh.size and collider.position == mesh.position, "large foundation collision matches its entire rendered footprint and depth")
	visual.free()
	var ghost := PlotBuildVisuals.create(spec, true, true, 27.5)
	var ghost_mesh := ghost.get_child(0) as MeshInstance3D
	check(ghost_mesh.mesh.size == Vector3(8,1,8) and ghost.get_child_count() == 1, "placement ghost keeps the 8m footprint without deep opaque geometry or collision")
	ghost.free()


func _test_undo_preserves_operations() -> void:
	var record := _base()
	# Working quay from only data; give the future ship unambiguous safe water.
	for x in range(-18, 20, 4):
		for z in range(2, 12, 4):
			record.placements.append(CATALOG.placement("quay-%d-%d" % [x,z], "foundation", Vector3(x, 0, z)))
	record.water_regions = [{"rect_m": [-50, -100, 100, 100], "depth_m": 20}]
	record.vessels = [{"id": "visitor", "owner_company_id": "visitor-company", "length_m": 12, "beam_m": 4, "draft_m": 1,
		"capacity_kg": 5000, "lots": [], "berth_id": ""}]
	var editor := _new_editor(record)
	editor.begin_edit()
	check(editor.place_asset("quay_bollard", Vector3(-16, 0, 0.5)).ok, "build first mooring")
	check(editor.place_asset("quay_bollard", Vector3(16, 0, 0.5)).ok, "build second mooring")
	editor.end_edit()
	var berths := editor.state.derived_berths()
	check(berths.size() == 1, "builder placements create operational berth")
	if berths.size() != 1:
		return
	var dock := editor.state.apply({"command_id": "visitor-arrival", "expected_revision": editor.state.revision(),
		"actor_company_id": "visitor-company", "kind": "dock", "payload": {"vessel_id": "visitor", "berth_id": berths[0].id}})
	check(dock.ok, "another authority command docks visitor after building")
	check(not editor.preview("quay_bollard", Vector3(0, 0, 0.5)).ok, "preview still rejects a new anchor that splits an occupied berth")
	var busy_snapshot := editor.state.to_dict()
	check(not editor.undo().ok, "undo cannot remove moorings used by a visiting ship")
	check(editor.state.to_dict() == busy_snapshot and editor.undo_count() == 1, "failed group undo is atomic and remains retryable")
	check(editor.place_asset("quay_light", Vector3(0, 0, 6)).ok, "build cosmetic while visitor remains docked")
	check(editor.undo().ok, "undo cosmetic uses current revision")
	check(editor.state.to_dict().vessels[0].berth_id == berths[0].id, "undo never rolls back someone else's docking")
	check(editor.state.apply({"command_id": "visitor-departure", "expected_revision": editor.state.revision(),
		"actor_company_id": "visitor-company", "kind": "undock", "payload": {"vessel_id": "visitor"}}).ok, "visitor departs")
	check(editor.undo().ok and editor.state.derived_berths().is_empty(), "original mooring stroke undo succeeds after berth freed")


func _test_diagonal_tiles() -> void:
	var editor := _new_editor()
	var triangle := editor.preview("foundation_triangle_4m", Vector3(1, 10, 1))
	check(triangle.ok and editor.place(triangle).ok, "triangular foundation uses same 4m footprint grid")
	check(not editor.preview("quay_light", Vector3(3, 0, 1)).ok, "cut-out triangle corner does not support equipment")
	var tire := editor.preview("tractor_tire_fender", Vector3(2, 0, 2))
	check(tire.ok, "fender supports actual diagonal edge")
	check(is_equal_approx(fposmod(float(tire.placement.yaw_degrees), 90.0), 45.0), "diagonal fitting faces 45 degree water normal")
	check(absf(float(tire.placement.position_m[0]) - float(tire.placement.position_m[2])) < 0.001, "fender contact lies on actual diagonal")
	var complement := editor.preview("foundation_triangle_4m", Vector3(1, 0, 1), 180)
	check(complement.ok and editor.place(complement).ok, "complementary triangles may share bounding square")
	var filled := editor.preview("quay_light", Vector3(3, 0, 1))
	check(filled.ok, "second triangle provides previously missing support")
	var owned := _base()
	owned.plots = [{"id": "left", "owner_company_id": "builder", "rect_m": [0,0,2,4]},
		{"id": "upper", "owner_company_id": "builder", "rect_m": [2,2,2,2]}]
	var limited := _new_editor(owned)
	var fits := limited.preview("foundation_triangle_4m", Vector3(1, 0, 1))
	check(fits.ok and limited.place(fits).ok, "exact polygon fits owned union even when its bounding square does not")
	check(not limited.preview("foundation_triangle_4m", Vector3(1, 0, 1), 180).ok, "complement in unowned cut-out is rejected")


func _test_crane_store_undo() -> void:
	var catalog := CATALOG.definitions()
	catalog["test-platform"] = {"kind": "platform", "footprint_m": [160,160], "placement_layer": "platform"}
	var record := _base()
	record.placements = [{"id": "large-platform", "asset_id": "test-platform", "position_m": [0,0,0], "yaw_degrees": 0, "attributes": {}}]
	var state := STATE.from_dict(record, record.world, catalog)
	var editor := EDITOR.new()
	editor.configure(state, catalog, "builder")
	var proposal := editor.preview("container_crane_bay", Vector3.ZERO)
	check(proposal.ok and editor.place(proposal).ok, "player can install actual crane bundle")
	if not proposal.ok or state.to_dict().stores.is_empty():
		return
	var attached: Dictionary = state.to_dict().stores[0]
	check(attached.lots.is_empty() and attached.capacity_units == catalog.container_crane_bay.slot_count, "real crane creates empty yard with authored slot capacity")
	check(editor.undo().ok and state.to_dict().stores.is_empty(), "undo placement removes unused attached store")
	proposal = editor.preview("container_crane_bay", Vector3.ZERO)
	check(editor.place(proposal).ok, "rebuild crane after undo")
	var store_id := str(state.to_dict().stores[0].id)
	check(state.apply({"command_id": "open-yard", "expected_revision": state.revision(), "actor_company_id": "builder", "kind": "configure_store",
		"payload": {"store_id": store_id, "changes": {"public_loading": true, "name": "Player terminal"}}}).ok, "configure terminal outside construction history")
	check(editor.place_asset("quay_light", Vector3(60, 0, 60)).ok and editor.undo().ok, "independent cosmetic edit can undo after terminal configuration")
	check(state.to_dict().stores[0].public_loading and state.to_dict().stores[0].name == "Player terminal", "construction undo preserves independent terminal settings")
	var original: Dictionary = state.to_dict().stores[0]
	check(editor.remove(str(proposal.placement.id)).ok and state.to_dict().stores.is_empty(), "delete empty crane also removes yard data")
	check(editor.undo().ok and state.to_dict().stores[0] == original, "undo removal restores exact empty store identity and settings")


func _test_fish_equipment_snap() -> void:
	var record := _base()
	for x in range(-14, 16, 4):
		for z in range(2, 28, 4):
			record.placements.append(CATALOG.placement("pier-%d-%d" % [x,z], "foundation", Vector3(x,0,z)))
	var editor := _new_editor(record)
	for yaw in [0,90,180,270]:
		var plant := editor.preview("fish_landing_plant", Vector3(.1,300,12.1), yaw)
		check(plant.ok and plant.placement.position_m == [0.0,0,12.0] and plant.snap_m == 4.0,
			"20x16m plant fits a 32m pier on the 4m equipment grid at quarter turn %d" % yaw)
		var negative := editor.preview("fish_landing_plant", Vector3(-3.1,0,11.9), yaw)
		check(negative.placement.position_m == [-4.0,0,12.0], "Equipment grid remains symmetric at negative coordinates")
	var installed := editor.place_asset("fish_landing_plant", Vector3(0,0,12))
	check(installed.ok and installed.snapshot.stores.size() == 1 and installed.snapshot.stores[0].lots.is_empty(),
		"The centrally placed plant creates exactly its finite empty shore store")
