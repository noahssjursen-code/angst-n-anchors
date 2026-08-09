extends SceneTree

const CameraClass := preload("res://scripts/ui/chart/chart_camera.gd")
const LayersClass := preload("res://scripts/ui/chart/chart_layer_manager.gd")
const RendererClass := preload("res://scripts/ui/chart/chart_layer_renderer.gd")
const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("chart_layer_manager_test")
	var layers := LayersClass.new()
	t.equal("default preset is Navigation", layers.preset, LayersClass.Preset.NAVIGATION)
	t.check("navigation shows routes", layers.is_visible("routes"))
	t.check("navigation hides weather", not layers.is_visible("weather"))
	t.check("navigation hides fishing", not layers.is_visible("fishing"))

	var revision: int = layers.revision
	layers.apply_preset(LayersClass.Preset.WEATHER)
	t.check("weather preset shows weather", layers.is_visible("weather"))
	t.check("weather preset hides fishing", not layers.is_visible("fishing"))
	t.equal("applying a preset bumps the revision", layers.revision, revision + 1)

	layers.apply_preset(LayersClass.Preset.FISHING)
	t.check("fishing preset shows fishing", layers.is_visible("fishing"))
	t.check("fishing preset shows weather", layers.is_visible("weather"))

	layers.apply_preset(LayersClass.Preset.NAVIGATION)
	t.check("navigation preset shows weather", layers.is_visible("weather"))
	t.check("navigation preset shows fishing", layers.is_visible("fishing"))
	t.check("navigation preset shows routes", layers.is_visible("routes"))

	## Legacy Harbour profile (3) folds into Navigation.
	layers.apply_preset(LayersClass.LEGACY_HARBOUR_PROFILE)
	t.equal("legacy harbour profile folds into Navigation", layers.preset, LayersClass.Preset.NAVIGATION)
	t.check("legacy harbour profile hides approaches", not layers.is_visible("approaches"))
	t.check("legacy harbour profile shows annotations", layers.is_visible("annotations"))

	var camera := CameraClass.new()
	camera.home(Vector3(100.0, 0.0, -200.0), [])
	var bounds := camera.world_bounds(Vector2(800.0, 400.0))
	t.check("homed camera bounds contain the home point", bounds.has_point(Vector2(100.0, -200.0)))
	var context := {
		"world_bounds": Rect2(-100.0, -100.0, 200.0, 200.0),
		"chart_rect": Rect2(0.0, 0.0, 200.0, 200.0),
	}
	var north := RendererClass._world_to_screen(Vector3(0.0, 0.0, -100.0), context)
	var south := RendererClass._world_to_screen(Vector3(0.0, 0.0, 100.0), context)
	t.check("north projects above south on screen", north.y < south.y)
	t.finish(self)
