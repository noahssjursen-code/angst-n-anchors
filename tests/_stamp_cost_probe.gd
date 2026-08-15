extends SceneTree

## SCRATCH PROBE (leading underscore). Per-stamp cost and node count for the two
## caches, through their public API only, so it runs unchanged on a `git archive
## HEAD` baseline and on the working tree.

const N := 500
const MODELS := [
	"res://resources/data/models/buildings/foghorn_building.json",
	"res://resources/data/models/buildings/lighthouse_building.json",
	"res://resources/data/models/cargo/container_cube.json",
	"res://resources/data/meshes/docks/docking_bollard.json",
]


func _initialize() -> void:
	## Warm the prototypes so the bake is not in the measurement.
	LandDecorCache.clear()
	var warm := LandDecorCache.house_instance(3, 0.0, 0.0)
	var house_nodes := _count(warm)
	warm.free()

	var best := 1e30
	for run in range(3):
		var t0 := Time.get_ticks_usec()
		for i in range(N):
			var h := LandDecorCache.house_instance(3, 0.0, 0.0)
			h.free()
		best = minf(best, float(Time.get_ticks_usec() - t0) / float(N))
	print("LandDecorCache house_instance: %.4f ms/stamp  nodes/stamp=%d  (best of 3 x %d)"
		% [best / 1000.0, house_nodes, N])

	for path in MODELS:
		ModelCache.clear()
		var w := ModelCache.instance(path, 1.0)
		var nodes := _count(w)
		w.free()
		var b := 1e30
		for run in range(3):
			var t0 := Time.get_ticks_usec()
			for i in range(N):
				var n := ModelCache.instance(path, 1.0)
				n.free()
			b = minf(b, float(Time.get_ticks_usec() - t0) / float(N))
		print("ModelCache %-24s %.4f ms/stamp  nodes/stamp=%d  (best of 3 x %d)"
			% [path.get_file(), b / 1000.0, nodes, N])
	ModelCache.clear()
	LandDecorCache.clear()
	quit(0)


func _count(node: Node, n: int = 0) -> int:
	for child in node.get_children():
		n = _count(child, n + 1)
	return n
