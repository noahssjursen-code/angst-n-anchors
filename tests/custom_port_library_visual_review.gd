extends Node
## Native review of the actual workshop palette, including real pointer selection.
const WORKSHOP = preload("res://scenes/showcases/custom_port_showcase.tscn")
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var workshop = WORKSHOP.instantiate()
	add_child(workshop)
	var deadline := Time.get_ticks_msec() + 90000
	while not workshop.ready_for_review and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not workshop.ready_for_review:
		push_error("Workshop did not become ready")
		get_tree().quit(1)
		return
	workshop._set_cursor(true)
	var library = workshop.library
	while not library.thumbnail_renderer.completed and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	for id in library.thumbnails:
		var texture: Texture2D = library.thumbnails[id].texture
		if texture == null:
			failures.append("Missing model thumbnail: " + id)
			continue
		var image := texture.get_image()
		var occupied := 0
		var backdrop := image.get_pixel(0, 0)
		for y in range(4, image.get_height()-4, 4):
			for x in range(4, image.get_width()-4, 4):
				if not image.get_pixel(x,y).is_equal_approx(backdrop): occupied += 1
		if occupied < 20: failures.append("Empty rendered model: " + id)
	for group in ["Equipment", "Cargo equipment", "Quay fittings", "Workshop"]:
		var found := false
		for index in library.category.item_count:
			if library.category.get_item_text(index) == group:
				library.category.select(index)
				library.category.item_selected.emit(index)
				found = true
		if not found: continue
		await get_tree().process_frame
		await get_tree().process_frame
		await workshop._capture("model-library-" + group.to_lower().replace(" ", "-"))
	library.category.select(0)
	library.search.text = "container crane"
	library._filter()
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = library._buttons.container_crane_bay
	var location := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = location
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = location
		get_viewport().push_input(click, true)
		await get_tree().process_frame
	if workshop.selected != "container_crane_bay": failures.append("Clicking thumbnail did not equip the crane")
	workshop._set_cursor(true)
	library.search.text = ""
	library._filter()
	await workshop._capture("model-library-overview")
	if failures.is_empty(): print("CUSTOM PORT MODEL LIBRARY PASS (%d actual model thumbnails; native selection)" % library.thumbnails.size())
	else:
		for failure in failures: push_error(failure)
	workshop.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
