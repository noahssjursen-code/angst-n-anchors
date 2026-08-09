extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const SettingsClass := preload("res://scripts/state/game_settings.gd")
const MapClass := preload("res://scripts/ui/map_overlay.gd")
const MinimapClass := preload("res://scripts/ui/chart/helm_minimap.gd")
const NavClass := preload("res://scripts/ui/chart/chart_nav_snapshot.gd")


func _initialize() -> void:
	var t := TestReport.new("helm_minimap_test")
	_test_settings_round_trip(t)
	_test_minimap_lifecycle_and_follow(t)
	t.finish(self)


func _test_settings_round_trip(t: TestReport) -> void:
	var path := "user://helm_minimap_test_settings.cfg"
	var saved := SettingsClass.new()
	saved.chart_weather_enabled = true
	saved.chart_fishing_enabled = true
	saved.chart_profile = ChartLayerManager.Preset.NAVIGATION
	saved.minimap_collapsed = true
	saved.save_settings(path)

	var loaded := SettingsClass.new()
	loaded.load_settings(path)
	t.check("chart weather toggle survives the settings round trip", loaded.chart_weather_enabled)
	t.check("chart fishing toggle survives the settings round trip", loaded.chart_fishing_enabled)
	t.equal(
		"chart profile survives the settings round trip",
		loaded.chart_profile,
		ChartLayerManager.Preset.NAVIGATION,
	)
	t.check("minimap collapsed state survives the settings round trip", loaded.minimap_collapsed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	saved.free()
	loaded.free()


func _test_minimap_lifecycle_and_follow(t: TestReport) -> void:
	var chart := MapClass.new()
	chart.visible = false
	root.add_child(chart)
	var minimap := MinimapClass.new()
	minimap.setup(chart)
	root.add_child(minimap)

	t.equal("minimap shares the chart renderer", minimap.source.renderer, chart.renderer)
	t.equal("minimap shares the chart layers", minimap.source.layers, chart.layers)
	minimap.set_helm_active(true)
	t.check("minimap is visible while the helm is active", minimap.visible)
	minimap.set_modal_hidden(true)
	t.check("a modal hides the minimap", not minimap.visible)
	minimap.set_modal_hidden(false)
	t.check("dismissing the modal restores the minimap", minimap.visible)

	chart.nav = NavClass.from_kinematics(
		Vector2(0.0, -1.0),
		Vector2.ZERO,
		Vector3(1234.0, 0.0, -5678.0),
		Vector3(INF, INF, INF),
	)
	t.check("follow sync accepts the nav snapshot", minimap.sync_follow_position())
	t.check(
		"minimap camera centres on the vessel",
		minimap.camera.center.is_equal_approx(Vector2(1234.0, -5678.0)),
	)
	t.check("minimap camera centre stays inside world bounds",
		minimap._world_bounds().has_point(minimap.camera.center))

	minimap.set_helm_active(false)
	t.check("leaving the helm hides the minimap", not minimap.visible)
	root.remove_child(minimap)
	minimap.free()
	root.remove_child(chart)
	chart.free()
