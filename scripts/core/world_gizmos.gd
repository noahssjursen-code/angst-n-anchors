class_name WorldGizmos
extends Object

## Playtest master switch for in-world debug visuals.
## Owned by DebugHud (`world_gizmos_enabled`); toggle with F3 then G.

const GROUP := "world_gizmo"


static func is_enabled() -> bool:
	if Engine.is_editor_hint():
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var hud := tree.root.get_node_or_null("DebugHud")
	if hud == null:
		return false
	return bool(hud.get("world_gizmos_enabled"))


## Stamp-time helper: join the group and match the current master flag.
static func register(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.is_in_group(GROUP):
		node.add_to_group(GROUP)
	if node is Node3D:
		(node as Node3D).visible = is_enabled()
	elif node is CanvasItem:
		(node as CanvasItem).visible = is_enabled()


static func apply_all(tree: SceneTree, enabled: bool) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		if node == null or not is_instance_valid(node):
			continue
		if node is Node3D:
			(node as Node3D).visible = enabled
		elif node is CanvasItem:
			(node as CanvasItem).visible = enabled
