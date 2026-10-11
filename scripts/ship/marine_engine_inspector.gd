class_name MarineEngineInspector
extends AcceptDialog
## Isolated machinery inspection, using the same authored asset installed aboard.
var model: Node3D
var camera: Camera3D
var viewport: SubViewport

func inspect(hull_id: String, preset_id: String) -> void:
	title = str(MarineEngineCatalog.resolve(hull_id,preset_id).name)
	size = Vector2i(760,530)
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(720,460)
	holder.stretch = true
	add_child(holder)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(720,460)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("223039")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .7
	viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,35,0)
	light.light_energy = 1.3
	viewport.add_child(light)
	model = Node3D.new()
	viewport.add_child(model)
	var machinery := MarineEngineCatalog.visual(hull_id,preset_id)
	model.add_child(machinery)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in machinery.find_children("*", "MeshInstance3D", true, false):
		var mesh_bounds := mesh.global_transform * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	# Fit the actual installed model (including twin packages), rather than a
	# three-hull lookup that fails for the feeder and passenger catamaran.
	machinery.position = -bounds.get_center()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.length() * 1.12, 3.0)
	camera.position = Vector3(1,.72,1.2).normalized() * camera.size * 2.0
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	holder.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			model.rotation.y += event.relative.x * .012
	)
	get_ok_button().text = "Close · drag the model to turn it"
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	popup_centered()
