extends Node

## Headless checks for the parametric construction engine: plan round-trip,
## baker expand/openings, material library, and empty item catalog hooks.

var _failures := PackedStringArray()


func _ready() -> void:
	_test_material_library()
	_test_material_categories()
	_test_item_catalog_empty()
	_test_plan_round_trip()
	_test_plan_validate_and_duplicate()
	_test_baker_room_expand_and_openings()
	_test_baker_bake_produces_meshes()
	_test_demo_workboat_loads()
	_test_demo_harbour_shed_loads()
	_test_demo_bridge_cabin_loads()
	_test_demo_quay_office_loads()
	_test_two_sided_free_wall()
	_test_studio_math()
	_test_studio_openings()
	_test_studio_help()
	_test_overlapping_openings_and_holes()
	_test_ghost_bake_and_open_room()
	_test_validate_extent_and_materials()
	if _failures.is_empty():
		print("StructureConstruction: plan, baker, materials, and item hooks passed")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("StructureConstruction: " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_material_library() -> void:
	StructureMaterialLibrary.reload()
	var ids := StructureMaterialLibrary.ids()
	_check(ids.size() >= 20, "material library has at least 20 construction materials")
	_check(StructureMaterialLibrary.has_id("painted"), "painted material exists")
	_check(StructureMaterialLibrary.has_id("wood"), "wood material exists")
	_check(StructureMaterialLibrary.has_id("fiberglass"), "fiberglass material exists")
	_check(StructureMaterialLibrary.has_id("rust"), "rust material exists")
	_check(StructureMaterialLibrary.has_id("teak"), "teak material exists")
	_check(StructureMaterialLibrary.normalize_id("nope") == "painted", "unknown material falls back to painted")
	_check(StructureMaterialLibrary.swatches().size() >= 12, "colour swatches present")
	var mat := StructureMaterialLibrary.make_material("wood", Color(0.8, 0.7, 0.5))
	_check(mat != null, "make_material returns StandardMaterial3D")
	_check(mat.roughness > 0.5, "wood is rough")
	var albedo := StructureMaterialLibrary.load_albedo("painted")
	_check(albedo != null, "painted albedo texture loads")
	var missing_textures := 0
	for material_id in ids:
		if StructureMaterialLibrary.load_albedo(material_id) == null:
			missing_textures += 1
	_check(missing_textures == 0, "every material has a loadable albedo texture")


func _test_item_catalog_empty() -> void:
	StructureItemCatalog.reload()
	_check(StructureItemCatalog.is_empty(), "item catalog ships empty this pass")
	_check(not StructureItemCatalog.has_id("helm"), "no helm item yet")
	_check(StructureItemCatalog.try_instantiate("helm") == null, "unknown item instantiates null")


func _test_plan_round_trip() -> void:
	var plan := StructurePlan.new()
	plan.context = "vessel"
	plan.hull_id = "hull_28x10"
	var room := plan.add_room(Vector3(2, 0, 10), Vector3(6, 3, 6))
	room["material_out"] = "painted"
	room["material_in"] = "wood"
	room["color_out"] = [0.9, 0.9, 0.9]
	room["color_in"] = [0.7, 0.6, 0.5]
	(room["openings"] as Array).append({
		"face": "s", "type": "door", "offset": 2.0, "width": 1.6, "height": 2.2,
	})
	plan.add_wall(Vector3(0, 0, 6), "z", 8.0, 1.0)
	plan.add_deck(Vector3(1, 0, 6), Vector2(8, 8))
	plan.add_item("future_helm", Vector3i(4, 0, 12), 90)
	var data := plan.to_dict()
	_check(StructurePlan.is_plan(data), "serialized plan reports structure_plan_v1")
	var restored := StructurePlan.from_dict(data)
	_check(restored.hull_id == "hull_28x10", "hull_id round-trips")
	_check(restored.rooms.size() == 1, "rooms round-trip")
	_check(restored.walls.size() == 1, "walls round-trip")
	_check(restored.decks.size() == 1, "decks round-trip")
	_check(restored.items.size() == 1, "items round-trip")
	_check(restored.entity_count() == 4, "entity_count matches")
	var restored_room := restored.rooms[0] as Dictionary
	_check(str(restored_room.get("material_in")) == "wood", "room interior material preserved")
	_check((restored_room.get("openings") as Array).size() == 1, "room openings preserved")


func _test_plan_validate_and_duplicate() -> void:
	var plan := StructurePlan.new()
	plan.context = "vessel"
	plan.hull_id = "hull_28x10"
	var wall := plan.add_wall(Vector3(1, 0, 1), "x", 4.0, 3.0)
	var copy := plan.duplicate_entity(int(wall["id"]), Vector3(0, 0, 2))
	_check(not copy.is_empty(), "duplicate_entity returns a copy")
	_check(plan.walls.size() == 2, "duplicate adds a wall")
	_check(int(copy.get("id", -1)) != int(wall.get("id", -1)), "duplicate gets a new id")
	plan.add_item("missing_gear", Vector3i(0, 0, 0), 0)
	var report := plan.validate(10, 28)
	_check(bool(report.get("ok", false)), "validate ok when only warnings")
	var warns: PackedStringArray = report.get("warnings", PackedStringArray())
	_check(warns.size() >= 1, "unknown item_id warns")


func _test_baker_room_expand_and_openings() -> void:
	var plan := StructurePlan.new()
	var room := plan.add_room(Vector3(0, 0, 0), Vector3(6, 3, 6))
	room["material_out"] = "painted"
	room["material_in"] = "wood"
	room["color_out"] = [0.85, 0.85, 0.88]
	room["color_in"] = [0.75, 0.65, 0.5]
	(room["openings"] as Array).append({
		"face": "n", "type": "window", "offset": 1.0, "width": 2.0, "sill": 1.0, "height": 1.2,
	})
	(room["openings"] as Array).append({
		"face": "s", "type": "door", "offset": 2.0, "width": 1.6, "height": 2.2,
	})
	var expanded := StructureBaker.expand(plan)
	_check((expanded["walls"] as Array).size() == 4, "room expands to 4 walls")
	_check((expanded["decks"] as Array).size() == 2, "room expands to floor+ceiling")
	var door_wall: Dictionary = {}
	for wall_variant in expanded["walls"] as Array:
		var wall := wall_variant as Dictionary
		for opening_variant in wall.get("openings", []) as Array:
			if str((opening_variant as Dictionary).get("type")) == "door":
				door_wall = wall
	_check(not door_wall.is_empty(), "door opening lands on an expanded wall")
	var panels := StructureBaker.wall_panels(door_wall)
	_check(panels.size() >= 2, "door wall splits into multiple panels")
	var colliders := StructureBaker.collect_colliders(plan)
	_check(colliders.size() > 0, "collect_colliders returns boxes")


func _test_baker_bake_produces_meshes() -> void:
	var plan := StructurePlan.new()
	var room := plan.add_room(Vector3(1, 0, 1), Vector3(4, 3, 4))
	room["material_out"] = "steel"
	room["material_in"] = "wood"
	room["color_out"] = [0.6, 0.62, 0.65]
	room["color_in"] = [0.78, 0.70, 0.58]
	plan.add_deck(Vector3(0, 0, 0), Vector2(6, 6))
	var root := StructureBaker.bake(plan, Vector3(-3, 0, -3))
	_check(root.get_child_count() > 0, "bake produces mesh instances")
	var textured := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			_check(mi.mesh != null and mi.mesh.get_surface_count() > 0, "mesh surface present")
			var mat := mi.mesh.surface_get_material(0)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
				textured += 1
	_check(textured > 0, "at least one bake bucket carries an albedo texture")
	root.free()


func _test_demo_workboat_loads() -> void:
	var path := "res://resources/data/structures/demo_workboat.json"
	_check(FileAccess.file_exists(path), "demo_workboat.json exists")
	var file := FileAccess.open(path, FileAccess.READ)
	_check(file != null, "demo_workboat opens")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(parsed is Dictionary and StructurePlan.is_plan(parsed as Dictionary), "demo is structure_plan_v1")
	var plan := StructurePlan.from_dict(parsed as Dictionary)
	_check(plan.hull_id == "hull_28x10", "demo targets hull_28x10")
	_check(plan.rooms.size() >= 1, "demo has a room")
	var root := StructureBaker.bake(plan)
	_check(root.get_child_count() > 0, "demo bakes")
	root.free()


func _test_demo_harbour_shed_loads() -> void:
	var path := "res://resources/data/structures/demo_harbour_shed.json"
	_check(FileAccess.file_exists(path), "demo_harbour_shed.json exists")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("demo_harbour_shed opens")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var plan := StructurePlan.from_dict(parsed as Dictionary)
	_check(plan.context == "building", "harbour shed is building context")
	_check(str((plan.rooms[0] as Dictionary).get("material_out")) == "brick", "shed uses brick outside")
	var root := StructureBaker.bake(plan)
	_check(root.get_child_count() > 0, "harbour shed bakes")
	root.free()


func _test_two_sided_free_wall() -> void:
	var plan := StructurePlan.new()
	var wall := plan.add_wall(Vector3(0, 0, 0), "x", 6.0, 3.0)
	wall["material_out"] = "painted"
	wall["color_out"] = [0.9, 0.9, 0.9]
	wall["material_in"] = "wood"
	wall["color_in"] = [0.7, 0.55, 0.4]
	## Free walls only go two-sided when inside identity is present — baker
	## still needs outward_sign for room walls; free walls use default +1.
	var root := StructureBaker.bake(plan)
	_check(root.get_child_count() >= 2, "two-sided free wall produces multiple material buckets")
	root.free()


func _test_studio_math() -> void:
	var wall: Dictionary = StructureStudioMath.wall_from_drag(Vector3(0, 0, 0), Vector3(5, 0, 1), 0.0)
	_check(str(wall.get("axis")) == "x", "wall drag prefers longer axis")
	_check(float(wall.get("length")) == 5.0, "wall length snaps")
	var clipped: Dictionary = StructureStudioMath.wall_from_drag(Vector3(8, 0, 0), Vector3(20, 0, 0), 0.0, 10, 28)
	_check(float(clipped.get("length")) <= 2.0, "wall drag clamps to grid width")
	var rect: Dictionary = StructureStudioMath.rect_from_drag(Vector3(1, 0, 1), Vector3(4, 0, 5), 0.0, 2.0)
	_check(float(rect.get("width")) == 3.0, "rect width")
	_check(float(rect.get("length")) == 4.0, "rect length")
	var clamped: Vector3 = StructureStudioMath.clamp_origin(Vector3(-2, -1, 50), "room", Vector3(4, 3, 4), 24, 24)
	_check(is_equal_approx(clamped.x, 0.0) and is_equal_approx(clamped.y, 0.0), "clamp origin floors at zero")
	_check(is_equal_approx(clamped.z, 20.0), "clamp origin respects footprint against grid length")


func _test_overlapping_openings_and_holes() -> void:
	var plan := StructurePlan.new()
	var wall := plan.add_wall(Vector3(0, 0, 0), "x", 10.0, 3.0)
	(wall["openings"] as Array).append({"type": "door", "offset": 1.0, "width": 2.0, "height": 2.2})
	(wall["openings"] as Array).append({"type": "window", "offset": 2.5, "width": 2.0, "sill": 1.0, "height": 1.2})
	var panels := StructureBaker.wall_panels(wall)
	_check(panels.size() >= 2, "overlapping openings still produce panels")
	var root := StructureBaker.bake(plan)
	_check(root.get_child_count() > 0, "overlapping openings bake")
	root.free()
	var deck := plan.add_deck(Vector3(0, 0, 0), Vector2(6, 6))
	(deck["openings"] as Array).append({"type": "stairwell", "offset": [2.0, 2.0], "size": [2.0, 2.0]})
	var strips := StructureBaker.deck_strips(deck)
	_check(strips.size() >= 2, "deck hole produces multiple strips")
	var colliders := StructureBaker.collect_colliders(plan)
	_check(colliders.size() > 0, "colliders present with openings")


func _test_ghost_bake_and_open_room() -> void:
	var plan := StructurePlan.new()
	var room := plan.add_room(Vector3(0, 0, 0), Vector3(5, 3, 5))
	room["roof"] = false
	room["floor"] = false
	room["material_out"] = "painted"
	room["material_in"] = "wood"
	var expanded := StructureBaker.expand(plan)
	_check((expanded["decks"] as Array).is_empty(), "open room expands to no plates")
	_check((expanded["walls"] as Array).size() == 4, "open room still has four walls")
	var ghost := StructureBaker.bake(plan, Vector3.ZERO, true)
	_check(ghost.get_child_count() > 0, "ghost bake produces meshes")
	var translucent := 0
	for child in ghost.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).mesh.surface_get_material(0)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				translucent += 1
	_check(translucent > 0, "ghost materials are translucent")
	ghost.free()


func _test_validate_extent_and_materials() -> void:
	var plan := StructurePlan.new()
	plan.context = "building"
	var wall := plan.add_wall(Vector3(0, 0, 0), "x", 30.0, 3.0)
	wall["material"] = "not_a_real_material"
	(wall["openings"] as Array).append({"type": "door", "offset": 28.0, "width": 4.0, "height": 2.2})
	var report := plan.validate(10, 10)
	var warns: PackedStringArray = report.get("warnings", PackedStringArray())
	_check(warns.size() >= 2, "validate warns on extent and unknown material")
	var joined := " ".join(warns)
	_check(joined.contains("outside") or joined.contains("extends"), "extent warning present")
	_check(joined.contains("unknown"), "unknown material warning present")


func _test_material_categories() -> void:
	StructureMaterialLibrary.reload()
	var cats := StructureMaterialLibrary.categories()
	_check(cats.size() >= 6, "material categories present")
	_check(StructureMaterialLibrary.category_of("wood") == "timber", "wood is timber")
	_check(StructureMaterialLibrary.category_of("brick") == "structure", "brick is structure")
	var timber := StructureMaterialLibrary.ids_in_category("timber")
	_check(timber.has("wood") and timber.has("teak"), "timber filter includes wood/teak")
	_check(not timber.has("steel"), "timber filter excludes steel")
	var all_ids := StructureMaterialLibrary.ids_in_category("all")
	_check(all_ids.size() == StructureMaterialLibrary.studio_material_ids().size(), "all category matches studio list")


func _test_studio_openings() -> void:
	var door := StructureStudioOpenings.defaults_for(StructurePlan.OPENING_DOOR)
	_check(str(door.get("type")) == "door", "door defaults")
	_check(float(door.get("width")) >= 1.0, "door width")
	var span := StructureStudioOpenings.wall_span(8.0, 3.0, 3.0, false, 2.0)
	_check(is_equal_approx(span.y, 2.0), "click opening uses default width")
	_check(span.x >= 0.0 and span.x + span.y <= 8.0, "click opening stays on wall")
	var drag_span := StructureStudioOpenings.wall_span(8.0, 1.0, 5.0, true, 2.0)
	_check(drag_span.y >= 1.0, "drag opening has length")
	var plate := StructureStudioOpenings.plate_rect(Vector2(6, 6), Vector2(2, 2), Vector2(2, 2), false)
	_check(plate.size.x > 0.0 and plate.size.y > 0.0, "plate click rect")
	_check(
		StructureStudioOpenings.plate_opening_type(StructurePlan.OPENING_HOLE, "ceiling")
		== StructurePlan.OPENING_HOLE,
		"ceiling hole stays hole",
	)
	_check(
		StructureStudioOpenings.plate_opening_type(StructurePlan.OPENING_HOLE, "floor")
		== StructurePlan.OPENING_STAIRWELL,
		"floor hole becomes stairwell",
	)
	var geom := StructureStudioOpenings.wall_geom(Vector3.ZERO, true, 0.2, Vector2(1, 2), 0.0, 2.2)
	_check((geom["size"] as Vector3).y > 2.0, "wall opening geom height")


func _test_studio_help() -> void:
	var text := StructureStudioHelp.text()
	_check(text.contains("STRUCTURE STUDIO"), "help has title")
	_check(text.contains("Ctrl+S"), "help mentions save")
	_check(text.contains("Ghost"), "help mentions ghost decks")


func _test_demo_bridge_cabin_loads() -> void:
	var path := "res://resources/data/structures/demo_bridge_cabin.json"
	_check(FileAccess.file_exists(path), "demo_bridge_cabin.json exists")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("demo_bridge_cabin opens")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var plan := StructurePlan.from_dict(parsed as Dictionary)
	_check(plan.context == "vessel", "bridge cabin is vessel")
	_check(plan.rooms.size() >= 1, "bridge cabin has a room")
	var root := StructureBaker.bake(plan)
	_check(root.get_child_count() > 0, "bridge cabin bakes")
	root.free()


func _test_demo_quay_office_loads() -> void:
	var path := "res://resources/data/structures/demo_quay_office.json"
	_check(FileAccess.file_exists(path), "demo_quay_office.json exists")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("demo_quay_office opens")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var plan := StructurePlan.from_dict(parsed as Dictionary)
	_check(plan.context == "building", "quay office is building")
	_check(plan.rooms.size() >= 2, "quay office is two-storey")
	var root := StructureBaker.bake(plan)
	_check(root.get_child_count() > 0, "quay office bakes")
	root.free()
