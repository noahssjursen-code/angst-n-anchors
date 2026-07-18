class_name WorldGizmos
extends Object

## Playtest layer registry for in-world debug visuals.
## DebugHud owns layer state; F3 then G opens the selector.

const GROUP := "world_gizmo"
const LAYER_GENERAL := "general"
const LAYER_PORT_LAYOUT := "port_layout"
const LAYER_CRANES := "cranes"
const LAYER_BERTH_LANES := "berth_lanes"
const LAYER_NAVIGATION := "navigation"
const LAYER_META := &"world_gizmo_layer"

const LAYERS: Array[Dictionary] = [
	{"id": LAYER_NAVIGATION, "label": "NPC & AUTOPILOT PATHS", "hint": "Routes, targets, holding positions, traffic agreements"},
	{"id": LAYER_BERTH_LANES, "label": "BERTH APPROACH LANES", "hint": "Port, starboard and spine approach curves"},
	{"id": LAYER_PORT_LAYOUT, "label": "PORT LAYOUT", "hint": "Foundations, quay slots, yards and site construction"},
	{"id": LAYER_CRANES, "label": "CRANE OPERATIONS", "hint": "Pickup, drop and crane travel targets"},
	{"id": LAYER_GENERAL, "label": "GENERAL WORLD", "hint": "Uncategorised world debug geometry"},
]


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


static func is_layer_enabled(layer_id: String) -> bool:
	if Engine.is_editor_hint():
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var hud := tree.root.get_node_or_null("DebugHud")
	if hud == null or not hud.has_method("is_gizmo_layer_enabled"):
		return false
	return bool(hud.call("is_gizmo_layer_enabled", layer_id))


## Stamp-time helper: join the group and match the current master flag.
static func register(node: Node, layer_id: String = LAYER_GENERAL) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.is_in_group(GROUP):
		node.add_to_group(GROUP)
	node.set_meta(LAYER_META, layer_id)
	if node is Node3D:
		(node as Node3D).visible = is_layer_enabled(layer_id)
	elif node is CanvasItem:
		(node as CanvasItem).visible = is_layer_enabled(layer_id)


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


static func apply_layer(tree: SceneTree, layer_id: String, enabled: bool) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		if node == null or not is_instance_valid(node) \
				or str(node.get_meta(LAYER_META, LAYER_GENERAL)) != layer_id:
			continue
		if node is Node3D:
			(node as Node3D).visible = enabled
		elif node is CanvasItem:
			(node as CanvasItem).visible = enabled
