extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := root.get_node_or_null("DebugHud")
	_check(hud != null, "DebugHud autoload exists")
	if hud == null:
		_finish()
		return
	hud.set_all_gizmo_layers(false)
	var port_node := Node3D.new()
	var navigation_node := Node3D.new()
	root.add_child(port_node)
	root.add_child(navigation_node)
	WorldGizmos.register(port_node, WorldGizmos.LAYER_PORT_LAYOUT)
	WorldGizmos.register(navigation_node, WorldGizmos.LAYER_NAVIGATION)
	_check(not port_node.visible and not navigation_node.visible, "layers begin independently disabled")
	hud.set_gizmo_layer_enabled(WorldGizmos.LAYER_PORT_LAYOUT, true)
	_check(port_node.visible, "port layer reveals port gizmos")
	_check(not navigation_node.visible, "port layer does not reveal navigation gizmos")
	hud.set_gizmo_layer_enabled(WorldGizmos.LAYER_NAVIGATION, true)
	_check(navigation_node.visible, "navigation layer reveals navigation gizmos")
	_check(bool(hud.gizmo_layers.get(WorldGizmos.LAYER_PORT_LAYOUT, false)), "port selection is retained")
	hud.set_all_gizmo_layers(false)
	_check(not port_node.visible and not navigation_node.visible, "clear-all hides every layer")
	port_node.free()
	navigation_node.free()
	_finish()


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("World gizmo layer tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("World gizmo layer test: " + failure)
	quit(1)
