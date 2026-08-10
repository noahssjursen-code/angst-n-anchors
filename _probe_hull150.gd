extends SceneTree

## scratch probe — shell half-beam along a strake line. Deleted after use.

const StructurePlanScript := preload("res://scripts/construction/structure_plan.gd")
const StructureEdgeScript := preload("res://scripts/construction/structure_edge.gd")


func _init() -> void:
	var st: HullStations = StructurePlanScript.make_hull_stations("hull_150x32", {})
	var out := PackedStringArray()
	var z: float = 0.0
	while z <= 150.001:
		var sz: float = z - 75.0
		var y: float = st.deck_y + 0.12 - 1.05
		out.append("(%.1f, %.4f)" % [z, StructureEdgeScript.deck_half_beam_at(st, sz, y)])
		z += 2.0
	print("STRAKE_HB = [" + ", ".join(out) + "]")
	quit(0)
