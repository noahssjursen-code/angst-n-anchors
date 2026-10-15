extends Node3D
## Actual harbour meshes, exact visual picking and ordinary authority removal.
const PICKER = preload("res://scripts/port/building/custom_port_placement_picker.gd")
const PRESENTER = preload("res://scripts/port/building/custom_port_presenter.gd")
const CATALOG = preload("res://scripts/port/building/custom_port_catalog.gd")
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const EDITOR = preload("res://scripts/port/building/custom_port_editor.gd")
const ASSETS = preload("res://scripts/port/building/custom_harbour_asset_library.gd")
const DECORATIONS := ["gutter", "trim", "ladder", "drain"]
var checks := 0
var failures: Array[String] = []
var stage: Node3D
var presenter: CustomPortPresenter
var picker
var capture_path := ""

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_run.call_deferred()

func _fixture() -> Dictionary:
	var record := {"schema_version": 1, "id": "picker-test", "owner_company_id": "builder",
		"world": {"seed": 3, "generation_version": 1, "checksum": "picker-island"},
		"origin_m": [0, .5, 0], "deck_height_above_sea_m": 2,
		"plots": [{"id": "home", "owner_company_id": "builder", "rect_m": [-30, -30, 60, 60]}],
		"placements": [], "stores": [], "vessels": []}
	for x in [-4, 4]:
		for z in [4, 12]:
			record.placements.append(CATALOG.placement("quay-%d-%d" % [x, z], "foundation_8m", Vector3(x, 0, z)))
	for row in [["wall", "workshop_wall_4m", Vector3(-4, 0, 4)],
		["gutter", "workshop_roof_edge_4m", Vector3(-4, 0, 4)],
		["trim", "workshop_corner_trim", Vector3(-6, 0, 4)],
		["ladder", "quay_ladder", Vector3(-4, 0, 0)],
		["drain", "drain_2m", Vector3(4, 0, 10)],
		["door", "workshop_door_4m", Vector3(4, 0, 4)]]:
		record.placements.append(CATALOG.placement(row[0], row[1], row[2]))
	return record

func _run() -> void:
	var input := _fixture()
	var catalog: Dictionary = CATALOG.definitions()
	var state: CustomPortState = STATE.from_dict(input, input.world, catalog)
	_check(state.validation_errors.is_empty(), "The compact harbour fixture is individually valid: " + str(state.validation_errors))
	if not state.validation_errors.is_empty(): _finish(); return
	var saved := state.to_dict()
	stage = Node3D.new()
	add_child(stage)
	presenter = PRESENTER.new()
	stage.add_child(presenter)
	presenter.load_record(saved, state.derived_berths())
	var physical_count := _collision_count(presenter)
	picker = PICKER.new()
	picker.configure(presenter)
	picker.rebuild()
	_check(_collision_count(presenter) == physical_count, "Configuring and rebuilding visual picking creates no physical collision objects")
	for id in DECORATIONS:
		var root: Node3D = presenter.placement_nodes[id]
		_check(_collision_count(root) == 0, id + ": the production asset really has no collision object")
		_check(not _surface_probe(id, root).is_empty(), id + ": actual imported triangles can be picked")
	_test_parent_transform()
	_test_decorative_door()
	_measure_picks()
	var editor := EDITOR.new()
	editor.configure(state, catalog, "builder")
	for id in DECORATIONS:
		var probe := _surface_probe(id, presenter.placement_nodes[id])
		_check(not probe.is_empty(), id + ": removal starts with a real mesh hit")
		if probe.is_empty(): continue
		var result: Dictionary = editor.remove(str(probe.hit.placement_id))
		_check(result.get("ok", false), id + ": ordinary editor.remove accepts the hit placement ID")
		presenter.load_record(state.to_dict(), state.derived_berths())
		picker.rebuild()
		_check(not presenter.placement_nodes.has(id) and presenter.placement_nodes.has("wall") and _quay_count(state.to_dict()) == 4, id + ": removing decoration preserves the wall and all underlying quay tiles")
	var restored_data: Dictionary = JSON.parse_string(JSON.stringify(saved, "", false, true))
	var restored: CustomPortState = STATE.from_dict(restored_data, saved.world, catalog)
	_check(restored.validation_errors.is_empty() and restored.to_dict() == saved, "JSON restores the complete valid placement document")
	var old := presenter
	presenter = PRESENTER.new()
	stage.add_child(presenter)
	presenter.load_record(restored.to_dict(), restored.derived_berths())
	picker.configure(presenter)
	picker.rebuild()
	old.clear_record()
	old.queue_free()
	await get_tree().process_frame
	for id in DECORATIONS:
		_check(not _surface_probe(id, presenter.placement_nodes[id]).is_empty(), id + ": JSON-restored presenter remains selectable")
	_check(_collision_count(presenter) == physical_count, "Restored picking preserves the original physical collision count")
	_test_exact_geometry()
	_setup_view()
	await _capture()
	presenter.clear_record()
	stage.queue_free()
	await get_tree().process_frame
	_finish()

func _surface_probe(id: String, root: Node3D) -> Dictionary:
	# Probe genuine triangle centres from both sides, close enough to isolate the
	# decoration from a supporting wall. The picker must still intersect geometry.
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var faces := mesh.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var a: Vector3 = mesh.global_transform * faces[index]
			var b: Vector3 = mesh.global_transform * faces[index + 1]
			var c: Vector3 = mesh.global_transform * faces[index + 2]
			var normal := (b-a).cross(c-a)
			if normal.length_squared() < .00000001: continue
			normal = normal.normalized()
			var center := (a+b+c) / 3.0
			for side in [1.0, -1.0]:
				var origin: Vector3 = center + normal * .025 * side
				var direction: Vector3 = normal * -side
				var hit: Dictionary = picker.pick(origin, direction, .05)
				if hit.get("placement_id", "") == id:
					return {"origin": origin, "direction": direction, "hit": hit}
	return {}

func _test_parent_transform() -> void:
	stage.transform = Transform3D(Basis(Vector3.UP, .63).scaled(Vector3(1.3, .8, 1.1)), Vector3(-37, 6, 19))
	var probe := _surface_probe("gutter", presenter.placement_nodes.gutter)
	_check(not probe.is_empty(), "Picking reads the current translated, rotated and scaled parent without rebuild")
	if not probe.is_empty():
		_check(absf(float(probe.hit.distance) - probe.origin.distance_to(probe.hit.position)) < .0001, "Returned hit distance is measured in world metres under parent scale")
	stage.transform = Transform3D.IDENTITY

func _test_decorative_door() -> void:
	var door: Node3D = presenter.placement_nodes.door
	var origin := door.global_transform * Vector3(0, 1.2, -1)
	var direction := door.global_basis * Vector3.BACK
	_check(picker.pick(origin, direction, 2).get("placement_id", "") == "door", "The closed production door leaf is selectable")
	_check(not ASSETS.set_door_open(door, true), "Decorative entrances reject opening")
	_check(picker.pick(origin, direction, 2).get("placement_id", "") == "door", "The decorative door remains selectable and closed")

func _measure_picks() -> void:
	var probe := _surface_probe("drain", presenter.placement_nodes.drain)
	if probe.is_empty(): return
	var total := 0
	var maximum := 0
	var hits := 0
	for index in 100:
		var start := Time.get_ticks_usec()
		var hit: Dictionary = picker.pick(probe.origin, probe.direction, .05)
		var elapsed := Time.get_ticks_usec() - start
		total += elapsed
		maximum = maxi(maximum, elapsed)
		if hit.get("placement_id", "") == "drain": hits += 1
	_check(hits == 100, "Repeated cached mesh picks remain stable")
	print("PLACEMENT_PICKER_TIMING ", JSON.stringify({"mean_usec": total / 100.0, "max_usec": maximum, "stats": picker.stats()}))

func _test_exact_geometry() -> void:
	var view := PRESENTER.new()
	add_child(view)
	view.position = Vector3(1000, 0, 0)
	var ring_faces := PackedVector3Array()
	for rectangle in [Rect2(-2, -2, 1, 4), Rect2(1, -2, 1, 4), Rect2(-1, 1, 2, 1), Rect2(-1, -2, 2, 1)]:
		_add_rectangle(ring_faces, rectangle)
	var ring_mesh := _mesh(ring_faces)
	_add_mesh(view, "ring", ring_mesh, Vector3.ZERO)
	var exact = PICKER.new()
	exact.configure(view)
	exact.rebuild()
	_check(exact.pick(Vector3(1000, 0, 5), Vector3.FORWARD, 10).is_empty(), "A ray through the hollow mesh's empty AABB centre does not select it")
	for side in [1.0, -1.0]:
		var hit: Dictionary = exact.pick(Vector3(1001.5, 0, 5 * side), Vector3.FORWARD * side, 6)
		_check(hit.get("placement_id", "") == "ring" and is_equal_approx(float(hit.get("distance", 0)), 5), "Both sides of a single triangle surface can be selected")
	var plane_faces := PackedVector3Array()
	_add_rectangle(plane_faces, Rect2(-2, -2, 4, 4))
	_add_mesh(view, "far", _mesh(plane_faces), Vector3(0, 0, -2))
	_add_mesh(view, "shared-ring", ring_mesh, Vector3(10, 0, 0))
	exact.rebuild()
	var front := Vector3(1001.5, 0, 5)
	_check(exact.pick(front, Vector3.FORWARD, 10).get("placement_id", "") == "ring", "The nearest exact mesh wins over the farther surface")
	_check(exact.pick(Vector3(1000, 0, 5), Vector3.FORWARD, 10).get("placement_id", "") == "far", "An open mesh hole reveals the real farther surface")
	_check(exact.pick(front, Vector3.FORWARD, 4.99).is_empty() and exact.pick(front, Vector3.FORWARD, 5.01).get("placement_id", "") == "ring", "The physical-distance limit excludes hits behind a nearer obstruction")
	_check(exact.pick(front, Vector3.FORWARD * 7, 4.99).is_empty(), "A non-unit ray direction cannot bypass the world-distance limit")
	_check(exact.stats().mesh_cache_count == 2 and exact.stats().instance_count == 3, "Multiple instances of one mesh share a cached triangle acceleration structure")
	_check(_collision_count(view) == 0, "Exact mesh and hole tests introduce no physical collision objects")
	view.clear_record()
	view.queue_free()

func _add_rectangle(faces: PackedVector3Array, rectangle: Rect2) -> void:
	var a := Vector3(rectangle.position.x, rectangle.position.y, 0)
	var b := Vector3(rectangle.end.x, rectangle.position.y, 0)
	var c := Vector3(rectangle.end.x, rectangle.end.y, 0)
	var d := Vector3(rectangle.position.x, rectangle.end.y, 0)
	faces.append_array(PackedVector3Array([a, b, c, a, c, d]))

func _mesh(faces: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_mesh(view: CustomPortPresenter, id: String, mesh: Mesh, at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	root.set_meta("port_placement_id", id)
	view.add_child(root)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	root.add_child(instance)
	view.placement_nodes[id] = root

func _collision_count(root: Node) -> int:
	return root.find_children("*", "CollisionObject3D", true, false).size()

func _quay_count(snapshot: Dictionary) -> int:
	var count := 0
	for placement in snapshot.placements:
		if str(placement.id).begins_with("quay-"): count += 1
	return count

func _setup_view() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -32, 0)
	light.light_energy = 1.7
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.22, .31, .40)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.72, .8, .9)
	environment.environment.ambient_light_energy = .7
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(17, 13, -16)
	camera.look_at(Vector3(0, .5, 6))
	camera.fov = 42
	camera.far = 120
	camera.current = true

func _capture() -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	capture_path = archive.path_join("custom-port-placement-picker-%d-%d.png" % [Time.get_unix_time_from_system(), OS.get_process_id()])
	_check(get_viewport().get_texture().get_image().save_png(capture_path) == OK, "Native restored asset stage capture is archived")
	print("PLACEMENT_PICKER_CAPTURE ", capture_path)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _finish() -> void:
	print("CUSTOM PORT PLACEMENT PICKER ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size(), " capture=", capture_path)
	get_tree().quit(0 if failures.is_empty() else 1)
