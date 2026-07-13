extends SceneTree

const SettingsClass := preload("res://scripts/state/game_settings.gd")
const MapClass := preload("res://scripts/ui/map_overlay.gd")
const MinimapClass := preload("res://scripts/ui/chart/helm_minimap.gd")
const NavClass := preload("res://scripts/ui/chart/chart_nav_snapshot.gd")


func _initialize() -> void:
	_test_settings_round_trip()
	_test_minimap_lifecycle_and_follow()
	print("Shared helm minimap tests passed")
	quit()


func _test_settings_round_trip() -> void:
	var path := "user://helm_minimap_test_settings.cfg"
	var saved := SettingsClass.new()
	saved.chart_weather_enabled = true
	saved.chart_fishing_enabled = true
	saved.chart_profile = ChartLayerManager.Preset.HARBOUR
	saved.minimap_collapsed = true
	saved.save_settings(path)

	var loaded := SettingsClass.new()
	loaded.load_settings(path)
	assert(loaded.chart_weather_enabled)
	assert(loaded.chart_fishing_enabled)
	assert(loaded.chart_profile == ChartLayerManager.Preset.HARBOUR)
	assert(loaded.minimap_collapsed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	saved.free()
	loaded.free()


func _test_minimap_lifecycle_and_follow() -> void:
	var chart := MapClass.new()
	chart.visible = false
	root.add_child(chart)
	var minimap := MinimapClass.new()
	minimap.setup(chart)
	root.add_child(minimap)

	assert(minimap.source.renderer == chart.renderer)
	assert(minimap.source.layers == chart.layers)
	minimap.set_helm_active(true)
	assert(minimap.visible)
	minimap.set_modal_hidden(true)
	assert(not minimap.visible)
	minimap.set_modal_hidden(false)
	assert(minimap.visible)

	chart.nav = NavClass.from_kinematics(
		Vector2(0.0, -1.0),
		Vector2.ZERO,
		Vector3(1234.0, 0.0, -5678.0),
		Vector3(INF, INF, INF),
	)
	assert(minimap.sync_follow_position())
	assert(minimap.camera.center.is_equal_approx(Vector2(1234.0, -5678.0)))
	assert(minimap._world_bounds().has_point(minimap.camera.center))

	minimap.set_helm_active(false)
	assert(not minimap.visible)
	root.remove_child(minimap)
	minimap.free()
	root.remove_child(chart)
	chart.free()
