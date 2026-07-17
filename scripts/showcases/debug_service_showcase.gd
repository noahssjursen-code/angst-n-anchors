extends Control

var _elapsed := 0.0
var _event_elapsed := 0.0
var _spike_phase := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.025, 0.035, 0.045)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var title := Label.new()
	title.position = Vector2(36.0, 34.0)
	title.text = "DEBUG SERVICE SHOWCASE\n\nPress F3 to open the monitor.\nTab / Shift+Tab: pages\nH: live vs peak/worst\nC: copy report\nR: reset peaks\n1-5: select page"
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color(0.88, 0.74, 0.36)
	add_child(title)

	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null:
		telemetry.set_context_flag(&"showcase.synthetic_load", true, &"showcase.debug")
		telemetry.set_context_flag(&"showcase.profile", "debug_service", &"showcase.debug")
		telemetry.record_action(&"showcase_started", {"scene": "debug_service_showcase"})


func _exit_tree() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("clear_source"):
		telemetry.clear_source(&"showcase.debug")


func _process(delta: float) -> void:
	_elapsed += delta
	_event_elapsed += delta
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry == null:
		return
	var wave := sin(_elapsed * 1.7) * 0.5 + 0.5
	var work_ms := lerpf(1.2, 18.0, wave)
	if _spike_phase == 1:
		work_ms += 24.0
	telemetry.publish_metrics(&"showcase.debug", {
		"asset_build_ms": work_ms,
		"visible_assets": 120 + int(wave * 480.0),
		"cache_mb": 18.0 + wave * 42.0,
	}, &"showcase", {
		"asset_build_ms": {"unit": "ms"},
		"cache_mb": {"unit": "MB"},
	})
	if _event_elapsed >= 3.0:
		_event_elapsed = 0.0
		_spike_phase = 1 - _spike_phase
		telemetry.record_event(
			&"showcase.debug",
			&"synthetic_asset_batch",
			"warning" if _spike_phase == 1 else "info",
			{"batch": int(_elapsed / 3.0), "spike": _spike_phase == 1},
		)
