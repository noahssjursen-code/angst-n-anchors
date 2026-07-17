class_name WorldReference
extends RefCounted

## Shared rules for "where is the local player" vs "what should the camera stream in".
## Gameplay systems (fleet port context, NPC sim queries) must not follow freecam.


static func gameplay_position(tree: SceneTree = null) -> Vector3:
	if tree == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			tree = loop as SceneTree
	if tree == null:
		return Vector3.ZERO
	for node in tree.get_nodes_in_group("player"):
		if node is Node3D:
			return (node as Node3D).global_position
	for boat in tree.get_nodes_in_group("player_boat"):
		if boat is Node3D:
			return (boat as Node3D).global_position
	return Vector3.ZERO


## Active camera — for island/port streaming (includes freecam fly-around).
static func stream_position(viewport: Viewport = null) -> Vector3:
	if viewport == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			viewport = (loop as SceneTree).root.get_viewport()
	if viewport != null:
		var cam := viewport.get_camera_3d()
		if cam != null:
			return cam.global_position
	return gameplay_position(viewport.get_tree() if viewport != null else null)


## F3 freecam (dev) — when active, visual streaming should follow the camera.
static func is_freecam_active(tree: SceneTree = null) -> bool:
	if tree == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			tree = loop as SceneTree
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player_free_cam"):
		if node != null and node.has_method("is_active") and bool(node.call("is_active")):
			return true
	return false


## LOD / visual observer: player in normal play, camera while freecam is on.
static func visual_position(viewport: Viewport = null) -> Vector3:
	var tree: SceneTree = null
	if viewport != null:
		tree = viewport.get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	if is_freecam_active(tree):
		return stream_position(viewport)
	return gameplay_position(tree)
