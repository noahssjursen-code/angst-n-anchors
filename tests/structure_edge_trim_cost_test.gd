extends SceneTree

## Edge trim costs vertices, never draw calls.
##
## `probe_ferry_catamaran_trim.json` is `probe_ferry_catamaran.json` plus 47
## hand-placed trim boxes — cap rails, roof fascias, base skirts, corner posts,
## a rubbing strake. The whole point of authoring trim as `painted` boxes in a
## palette colour is that `StructureBaker._bucket_layer` keys on MATERIAL ALONE,
## so a plan may grow trim indefinitely without gaining a MeshInstance3D.
##
## This test is the machine-checkable half of that claim (`tools/capture.sh
## probe_ferry_catamaran_trim` is the picture). It asserts:
##   1. the trimmed bake has the SAME mesh-instance count as the untrimmed one;
##   2. the two bakes have the SAME set of surface materials (no new bucket
##      sneaked in under a different name);
##   3. the trim really is there — exactly TRIM_BOXES boxes' worth of extra
##      triangles, at 12 triangles per box;
##   4. the base geometry is untouched: every entity id < 100 in the trimmed
##      plan is deep-equal to the same id in the original, so the capture
##      comparison is trim-vs-no-trim and nothing else.
##
## SceneTree lane: StructureBaker / StructurePlan are `class_name` scripts with
## no autoload dependencies, so this runs under `--script`.

const TestReport := preload("res://tests/support/test_report.gd")

const PLAIN := "res://resources/data/structures/probe_ferry_catamaran.json"
const TRIMMED := "res://resources/data/structures/probe_ferry_catamaran_trim.json"

## 3 cap rails + 3 fascia rings (4 strips each) + 16 skirt bands
## + 4 rubbing-strake runs + 12 corner posts.
const TRIM_BOXES := 3 + 12 + 16 + 4 + 12
const TRIS_PER_BOX := 12

var _t: RefCounted


func _initialize() -> void:
	_t = TestReport.new("structure_edge_trim_cost_test")

	var plain := _load(PLAIN)
	var trimmed := _load(TRIMMED)
	if plain == null or trimmed == null:
		_t.fail("both fixtures load")
		_t.finish(self)
		return

	var plain_bake := StructureBaker.bake(plain)
	var trim_bake := StructureBaker.bake(trimmed)

	var plain_meshes := _mesh_instances(plain_bake)
	var trim_meshes := _mesh_instances(trim_bake)

	# 1. Draw-call neutrality — the load-bearing claim.
	_t.check(
		"untrimmed ferry bakes to at least one mesh instance (%d)" % plain_meshes.size(),
		plain_meshes.size() > 0,
	)
	_t.equal(
		"trim adds no mesh instances (plain %d)" % plain_meshes.size(),
		trim_meshes.size(),
		plain_meshes.size(),
	)

	# 2. Same buckets, by name. A trim entity that named a new material would
	#    pass a bare count check on some other plan; it cannot pass this.
	var plain_names := _instance_names(plain_meshes)
	var trim_names := _instance_names(trim_meshes)
	_t.equal("trim introduces no new surface bucket %s" % [plain_names], trim_names, plain_names)

	# 3. The trim is actually present, at the exact size it was authored.
	var plain_tris := _triangles(plain_meshes)
	var trim_tris := _triangles(trim_meshes)
	print("  [cost] mesh instances %d -> %d · triangles %d -> %d (+%d)" % [
		plain_meshes.size(), trim_meshes.size(), plain_tris, trim_tris, trim_tris - plain_tris,
	])
	_t.equal(
		"trim adds %d boxes of geometry" % TRIM_BOXES,
		trim_tris - plain_tris,
		TRIM_BOXES * TRIS_PER_BOX,
	)

	# 4. Nothing but trim changed, so the capture is a controlled comparison.
	_t.check("base entities are unchanged", _base_matches(plain, trimmed))

	_t.finish(self)


func _load(path: String) -> StructurePlan:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		_t.fail("%s is not a JSON object" % path)
		return null
	var data := raw as Dictionary
	if not StructurePlan.is_plan(data):
		_t.fail("%s is not a structure_plan_v1" % path)
		return null
	return StructurePlan.from_dict(data)


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(node, out)
	return out


func _collect(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, into)


func _instance_names(instances: Array[MeshInstance3D]) -> PackedStringArray:
	var names := PackedStringArray()
	for instance in instances:
		names.append(str(instance.name))
	names.sort()
	return names


func _triangles(instances: Array[MeshInstance3D]) -> int:
	var total := 0
	for instance in instances:
		var mesh := instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			total += (indices.size() if indices.size() > 0 else verts.size()) / 3
	return total


## Every entity the original owns must survive byte-for-byte in the trimmed
## plan. Trim ids start at 100 and are ignored here.
func _base_matches(plain: StructurePlan, trimmed: StructurePlan) -> bool:
	var ok := true
	for pair in [
		["walls", plain.walls, trimmed.walls],
		["decks", plain.decks, trimmed.decks],
		["stairs", plain.stairs, trimmed.stairs],
	]:
		var label := str(pair[0])
		for entity_variant in (pair[1] as Array):
			var entity := entity_variant as Dictionary
			var id := int(entity.get("id", -1))
			var mirror := _by_id(pair[2] as Array, id)
			if mirror.is_empty():
				print("  FAIL  %s id %d missing from the trimmed plan" % [label, id])
				ok = false
			elif mirror != entity:
				print("  FAIL  %s id %d differs from the original" % [label, id])
				ok = false
	return ok


func _by_id(collection: Array, id: int) -> Dictionary:
	for entity_variant in collection:
		var entity := entity_variant as Dictionary
		if int(entity.get("id", -1)) == id:
			return entity
	return {}
