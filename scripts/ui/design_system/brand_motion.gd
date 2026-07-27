class_name BrandMotion
extends RefCounted

## Shared motion rules. Motion communicates origin; it never bounces or scales.

static func reduced() -> bool:
	var loop := Engine.get_main_loop()
	var settings: Node = null
	if loop is SceneTree:
		settings = (loop as SceneTree).root.get_node_or_null("GameSettings")
	return bool(settings.get("reduced_motion")) if settings != null else false


static func panel_in(control: Control, from: Vector2 = Vector2(8.0, 0.0)) -> Tween:
	if reduced():
		control.modulate.a = 1.0
		return null
	var final_position := control.position
	control.position = final_position - from
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "position", final_position, BrandTokens.MOTION_PANEL_MS / 1000.0)
	tween.tween_property(control, "modulate:a", 1.0, BrandTokens.MOTION_CONTROL_MS / 1000.0)
	return tween


static func panel_out(control: Control, toward: Vector2 = Vector2(8.0, 0.0)) -> Tween:
	if reduced():
		control.visible = false
		return null
	var tween := control.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(
		control, "position", control.position + toward, BrandTokens.MOTION_PANEL_MS / 1000.0
	)
	tween.tween_property(control, "modulate:a", 0.0, BrandTokens.MOTION_CONTROL_MS / 1000.0)
	return tween


static func focus(control: Control) -> Tween:
	if reduced():
		return null
	var tween := control.create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "modulate", BrandTokens.PAPER_HIGH, BrandTokens.MOTION_MICRO_MS / 1000.0)
	return tween
