extends SceneTree

const CameraClass := preload("res://scripts/ui/chart/chart_camera.gd")
const LayersClass := preload("res://scripts/ui/chart/chart_layer_manager.gd")
const RendererClass := preload("res://scripts/ui/chart/chart_layer_renderer.gd")


func _initialize() -> void:
	var layers := LayersClass.new()
	assert(layers.preset == LayersClass.Preset.NAVIGATION)
	assert(layers.is_visible("routes"))
	assert(not layers.is_visible("weather"))
	assert(not layers.is_visible("fishing"))

	var revision: int = layers.revision
	layers.apply_preset(LayersClass.Preset.WEATHER)
	assert(layers.is_visible("weather"))
	assert(not layers.is_visible("fishing"))
	assert(layers.revision == revision + 1)

	layers.apply_preset(LayersClass.Preset.FISHING)
	assert(layers.is_visible("fishing"))
	assert(layers.is_visible("weather"))

	layers.apply_preset(LayersClass.Preset.NAVIGATION)
	assert(layers.is_visible("weather"))
	assert(layers.is_visible("fishing"))
	assert(layers.is_visible("routes"))

	## Legacy Harbour profile (3) folds into Navigation.
	layers.apply_preset(LayersClass.LEGACY_HARBOUR_PROFILE)
	assert(layers.preset == LayersClass.Preset.NAVIGATION)
	assert(not layers.is_visible("approaches"))
	assert(layers.is_visible("annotations"))

	var camera := CameraClass.new()
	camera.home(Vector3(100.0, 0.0, -200.0), [])
	var bounds := camera.world_bounds(Vector2(800.0, 400.0))
	assert(bounds.has_point(Vector2(100.0, -200.0)))
	var context := {
		"world_bounds": Rect2(-100.0, -100.0, 200.0, 200.0),
		"chart_rect": Rect2(0.0, 0.0, 200.0, 200.0),
	}
	var north := RendererClass._world_to_screen(Vector3(0.0, 0.0, -100.0), context)
	var south := RendererClass._world_to_screen(Vector3(0.0, 0.0, 100.0), context)
	assert(north.y < south.y)
	print("Marine chart mode/camera tests passed")
	quit()
