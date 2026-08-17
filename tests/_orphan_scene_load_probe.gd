extends Node

## SCRATCH PROBE (underscore-prefixed, not a gate unit). Lane B (scene), because
## five of the six subjects build their visuals in `_ready()` and one of them
## needs `WeatherLighting`, so nothing here works under `--script`.
##
## WHAT IT ANSWERS. `entry_reach_test` established that six `.tscn` files have
## zero referrers anywhere in the repository. "Unreferenced" is not a verdict —
## a scene that does not load is a different finding from one that loads
## perfectly and is simply orphaned. This instantiates each of the six and
## reports what actually appears: node count from the packed scene, node count
## after `_ready()` has run, mesh instances, lights, triangles, and the AABB in
## metres so it can be judged against the 1.8 m figure (CONVENTIONS §3a).
##
## `loading_screen.tscn` IS HANDLED SEPARATELY AND ON PURPOSE. Its `_ready()`
## calls `get_tree().change_scene_to_file()`, so adding it to a live tree
## destroys the probe's own scene mid-run. It is instantiated and measured
## WITHOUT being added, and that behaviour is itself reported.
##
## Nothing here is mutated, wired or fixed.

const SUBJECTS := [
	"res://scenes/systems/fuel_station.tscn",
	"res://scenes/systems/lighthouse_building.tscn",
	"res://scenes/systems/fog_horn_building.tscn",
	"res://scenes/shared/npc_base.tscn",
	"res://scenes/shared/trommel.tscn",
]

const NAVIGATES_ON_READY := "res://scenes/ui/loading_screen.tscn"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== orphan scene load probe ===")
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)

	for path in SUBJECTS:
		await _measure(path, stage)

	## Measured without entering the tree, because entering it navigates away.
	print("")
	print("--- %s" % NAVIGATES_ON_READY)
	var packed := load(NAVIGATES_ON_READY) as PackedScene
	if packed == null:
		print("  LOAD FAILED")
	else:
		var inst := packed.instantiate()
		print("  packed-scene nodes: %d  root %s (%s)"
			% [_count(inst), inst.name, inst.get_class()])
		print("  NOT added to the tree: its _ready() calls change_scene_to_file()"
			+ " and would navigate this probe away")
		print("  script: %s" % [inst.get_script().resource_path if inst.get_script() != null else "<none>"])
		inst.free()

	print("")
	print("=== probe done ===")
	get_tree().quit(0)


func _measure(path: String, stage: Node3D) -> void:
	print("")
	print("--- %s" % path)
	if not ResourceLoader.exists(path):
		print("  FILE MISSING")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("  LOAD FAILED (not a PackedScene)")
		return
	var inst := packed.instantiate()
	if inst == null:
		print("  INSTANTIATE FAILED")
		return
	var script_path := "<none>"
	if inst.get_script() != null:
		script_path = str((inst.get_script() as Script).resource_path)
	print("  packed-scene nodes: %d  root name %s  root class %s  script %s"
		% [_count(inst), inst.name, inst.get_class(), script_path])

	stage.add_child(inst)
	## The lighthouse rotates its beam every frame off the wall clock; stop that
	## now so anything measured below is a stated pose, not a phase.
	if inst.has_method("set_process"):
		inst.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame

	var meshes: Array[MeshInstance3D] = []
	var lights := 0
	var bodies := 0
	var audio := 0
	var labels := 0
	_walk(inst, meshes, [] as Array)
	for n in _all(inst):
		if n is Light3D:
			lights += 1
		if n is CollisionObject3D:
			bodies += 1
		if n is AudioStreamPlayer3D:
			audio += 1
		if n is Label3D:
			labels += 1

	var tris := 0
	var aabb := AABB()
	var first := true
	for m in meshes:
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var arrays: Array = m.mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if idx != null:
				tris += (idx as PackedInt32Array).size() / 3
			elif verts != null:
				tris += (verts as PackedVector3Array).size() / 3
		var box := m.get_aabb()
		var world_box := AABB(
			m.global_transform * box.position,
			(m.global_transform.basis * box.size).abs(),
		)
		if first:
			aabb = world_box
			first = false
		else:
			aabb = aabb.merge(world_box)

	print("  after _ready(): %d nodes | %d MeshInstance3D | %d Light3D | %d collision bodies"
		% [_count(inst), meshes.size(), lights, bodies]
		+ " | %d AudioStreamPlayer3D | %d Label3D" % [audio, labels])
	print("  triangles: %d" % tris)
	if first:
		print("  AABB: NO DRAWN GEOMETRY AT ALL")
	else:
		print("  AABB m: pos %s size %s  (height %.2f m vs the 1.8 m figure)"
			% [str(aabb.position.snapped(Vector3.ONE * 0.01)),
				str(aabb.size.snapped(Vector3.ONE * 0.01)), aabb.size.y])
	print("  child names: %s" % [_child_names(inst)])

	stage.remove_child(inst)
	inst.free()


func _walk(node: Node, meshes: Array[MeshInstance3D], _unused: Array) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for c in node.get_children():
		_walk(c, meshes, _unused)


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out


func _count(node: Node) -> int:
	return _all(node).size()


func _child_names(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append("%s(%s,%d)" % [c.name, c.get_class(), _count(c) - 1])
	return out
