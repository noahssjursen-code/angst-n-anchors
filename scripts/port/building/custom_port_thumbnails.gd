extends Node
## One isolated studio, baked once into shared textures. No per-card live worlds.
## Uses the placement presenter so cranes include their actual attached yards.
const PRESENTER = preload("res://scripts/port/building/custom_port_presenter.gd")
const IMAGE_SIZE := Vector2i(320, 200)
static var _cache: Dictionary = {}
var _targets: Dictionary = {}
var _pending: Array[String] = []
var _viewport: SubViewport
var _camera: Camera3D
var completed := false

func configure(_catalog: Dictionary, targets: Dictionary) -> void:
	_targets = targets
	for id in targets:
		if _cache.has(id): targets[id].texture = _cache[id]
		else: _pending.append(str(id))
	if DisplayServer.get_name() != "headless": _bake.call_deferred()

func prioritize(ids: Array[String]) -> void:
	var ordered: Array[String] = []
	for id in ids:
		if _pending.has(id): ordered.append(id)
	for id in _pending:
		if not ordered.has(id): ordered.append(id)
	_pending = ordered

func _bake() -> void:
	if _pending.is_empty():
		completed = true
		return
	_viewport = SubViewport.new()
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("253640")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c2d2df")
	environment.environment.ambient_light_energy = .8
	_viewport.add_child(environment)
	for settings in [[Vector3(-48, -35, 0), 1.5], [Vector3(-25, 145, 0), .65]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = settings[0]
		light.light_energy = settings[1]
		_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.near = .01
	_viewport.add_child(_camera)
	while not _pending.is_empty():
		var id: String = _pending.pop_front()
		var presenter := PRESENTER.new()
		presenter.simulate_vessels = false
		presenter.passive_services = true
		presenter.process_mode = Node.PROCESS_MODE_DISABLED
		_viewport.add_child(presenter)
		presenter._add_placement(CustomPortCatalog.placement("thumbnail", id, Vector3.ZERO))
		# Real crane factories finish their model through a deferred build.
		await get_tree().process_frame
		await get_tree().process_frame
		var visual: Node3D = presenter.placement_nodes.get("thumbnail")
		if is_instance_valid(visual):
			for attempt in 30:
				if visual.get("ready_for_inspection") != false: break
				await get_tree().process_frame
			_isolate(visual)
			_frame(visual, id)
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var picture := _viewport.get_texture().get_image()
			if picture != null and not picture.is_empty():
				_cache[id] = ImageTexture.create_from_image(picture)
				if is_instance_valid(_targets.get(id)): _targets[id].texture = _cache[id]
		presenter.free()
		await get_tree().process_frame
	_viewport.queue_free()
	completed = true

func _isolate(node: Node) -> void:
	for group in node.get_groups(): node.remove_from_group(group)
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is GeometryInstance3D:
		node.visibility_range_begin = 0
		node.visibility_range_end = 0
	if node is Label3D: node.hide()
	for child in node.get_children(): _isolate(child)

func _frame(visual: Node3D, id: String) -> void:
	var bounds := AABB()
	var first := true
	for item in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var center := bounds.get_center()
	var reach := maxf(bounds.size.length(), 1.0)
	# The rescue board is authored facing inland; show its ring, not its back.
	var direction := Vector3(1.25, .95, 1.5 if id == "lifering_station" else -1.5)
	_camera.position = center + direction.normalized() * reach * 2.0
	_camera.look_at(center)
	_camera.far = reach * 5.0
	var projected := AABB()
	for corner in 8:
		var point := _camera.global_transform.affine_inverse() * bounds.get_endpoint(corner)
		projected = AABB(point, Vector3.ZERO) if corner == 0 else projected.expand(point)
	_camera.size = maxf(.2, maxf(projected.size.y, projected.size.x / (float(IMAGE_SIZE.x) / IMAGE_SIZE.y))) * 1.16
