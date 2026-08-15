extends SceneTree

## SCRATCH PROBE. CONVENTIONS.md §2: "--script breaks autoloads at COMPILE time,
## not runtime — autoload *instances* exist under --script and resolve fine at
## runtime via root.get_node("FreightService")".
func _initialize() -> void:
	var names := ["FreightService", "WorldGateway", "LocalPlayerView", "PortCatalog", "GameState"]
	for n in names:
		var node := root.get_node_or_null(NodePath(n))
		print("  root.get_node_or_null(\"%s\") -> %s" % [n, "null" if node == null else node.get_class()])
	print("  root child count = ", root.get_child_count())
	quit(0)
