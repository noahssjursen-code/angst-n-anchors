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
	model = MarineEngineCatalog.visual(hull_id,preset_id)
	viewport.add_child(model)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = {"trawler_hull_14m":3.7,"hull_24x8":4.8,"hull_32x10":5.7}[hull_id]
	camera.position = Vector3(3,2.7,4)
	viewport.add_child(camera)
	camera.look_at(Vector3(0,.65,.3))
	holder.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			model.rotation.y += event.relative.x * .012
	)
	get_ok_button().text = "Close · drag the model to turn it"
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	popup_centered()
