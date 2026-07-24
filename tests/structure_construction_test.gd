extends Node

## Headless checks for the parametric construction engine: plan round-trip,
## baker expand/openings, material library, and empty item catalog hooks.

var _failures := PackedStringArray()


func _ready() -> void:
	_test_material_library()
	_test_item_catalog_empty()
	_test_plan_round_trip()
	_test_plan_validate_and_duplicate()
	_test_baker_room_expand_and_openings()
	_test_baker_bake_produces_meshes()
	_test_demo_workboat_loads()
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
	_check(ids.size() >= 8, "material library has at least 8 construction materials")
	_check(StructureMaterialLibrary.has_id("painted"), "painted material exists")
	_check(StructureMaterialLibrary.has_id("wood"), "wood material exists")
	_check(StructureMaterialLibrary.normalize_id("nope") == "painted", "unknown material falls back to painted")
	_check(StructureMaterialLibrary.swatches().size() >= 8, "colour swatches present")
	var mat := StructureMaterialLibrary.make_material("wood", Color(0.8, 0.7, 0.5))
	_check(mat != null, "make_material returns StandardMaterial3D")
	_check(mat.roughness > 0.5, "wood is rough")
	var albedo := StructureMaterialLibrary.load_albedo("painted")
	_check(albedo != null, "painted albedo texture loads")


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
