extends Node3D

## SCRATCH PROBE (leading underscore). Where does each of the studio's UI panels
## actually land on screen? The fitting-tool capture shows the left palette and
## the top bar and NOTHING on the right, and a panel a player cannot see is a
## panel that does not exist (REALITY §3d).

func _ready() -> void:
	var studio: Node = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(studio)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	print("VIEWPORT %s" % vp)
	_walk(studio, 0)
	get_tree().quit(0)


func _walk(node: Node, depth: int) -> void:
	if node is Control:
		var c := node as Control
		if not c.name.is_empty() and depth < 6:
			print("%s%-22s rect=%s visible_in_tree=%s min=%s" % [
				"  ".repeat(depth), c.name, c.get_global_rect(),
				c.is_visible_in_tree(), c.get_combined_minimum_size()
			])
	for child in node.get_children():
		_walk(child, depth + 1)
