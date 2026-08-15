@tool
class_name ModelCache
extends RefCounted

## Builds a JSON model once via ModelAssembler, bakes a dumb visual Node3D of
## childless visuals at shared resources, and stamps copies.
##
## Use for static props that do not need live part/role lookups (port street
## buildings, bollards). Interactive / articulated models stay on ModelAssembler.
##
## Critical: never duplicate a live ModelAssembler — its `_ready` would rebuild
## from JSON. Always stamp the baked prototype.
##
## ── THIS FILE USED TO SAY "MeshInstance3D children only" AND MEAN IT ────────
## The flatten and the stamp below were a hand-written pair that rebuilt
## `MeshInstance3D` and only that, and recursed only PAST a mesh rather than
## through it — byte-for-byte the pair that cost `BuildingCache` a `Label3D`,
## eight `OmniLight3D`, a metadata key and 72 of 717 meshes. Both are now
## `VisualFlatten`, the one implementation all three prototype caches call.
##
## **Measured before the port, and this cache lost NOTHING** — producer census
## against stamped census, per class, over every model document the game asks
## for (`tests/_cache_survey.gd`): 9/4/1/3/6/3/8/22 `MeshInstance3D` in, the same
## out, zero visuals nested under a visual, max visual nesting depth 1. That is
## a property of the PRODUCER, not luck: `ModelAssembler` emits only
## `MeshTransformer` and nested `ModelAssembler` (both plain `Node3D`), and a
## `MeshTransformer` hangs its single `MeshInstance3D` off ITSELF, never off
## another mesh. It cannot express the shapes the old filter dropped.
##
## So the change here is a merge, not a repair — made because that safety was a
## fact about a different file that nothing in the gate held in place, and
## because the sentence at the top of this one ("MeshInstance3D children only")
## is the exact shape of sentence that kept the same drop invisible in buildings
## for as long as the blueprint existed.
##
## The old stamp also justified itself with "Node.duplicate deep-copies
## Resources by default". **That is false in 4.6** — re-measured independently
## rather than inherited: `duplicate()` SHARES `Mesh`, `Material` and `Font` by
## reference and carries metadata and children. It was deleted with the code it
## justified; `tests/visual_stamp_cache_test.gd` asserts the measurement so it
## cannot rot back into a comment.
##
## **COST**, against a `git archive HEAD` baseline on the same box, best of
## 3 × 500 stamps (`tests/_stamp_cost_probe.gd`). Node count per stamp is
## unchanged everywhere — nothing was gained here, only unified:
##
##     foghorn_building     0.0710 -> 0.0816 ms/stamp   9 nodes  (+14.9%)
##     lighthouse_building  0.0324 -> 0.0371 ms/stamp   4 nodes  (+14.5%)
##     container_cube       0.0112 -> 0.0132 ms/stamp   1 node   (+17.9%)
##     docking_bollard      0.0255 -> 0.0300 ms/stamp   3 nodes  (+17.6%)

static var _prototypes: Dictionary = {}  ## key -> Node3D (held off-tree)


## Return a new visual root stamped from the cached prototype.
## `absolute_scale` is part of the cache key (assembler multiplies part positions).
static func instance(model_path: String, absolute_scale: float = 1.0) -> Node3D:
	if model_path.is_empty():
		push_error("ModelCache: empty model_path")
		return Node3D.new()

	# Editor: always bake fresh so JSON edits show up; do not pollute runtime cache.
	if Engine.is_editor_hint():
		return _stamp(_bake(model_path, absolute_scale))

	var key := _cache_key(model_path, absolute_scale)
	if not _prototypes.has(key):
		_prototypes[key] = _bake(model_path, absolute_scale)

	return _stamp(_prototypes[key] as Node3D)


static func invalidate(model_path: String) -> void:
	var prefix := model_path + "|"
	var to_erase: Array[String] = []
	for key in _prototypes.keys():
		if str(key).begins_with(prefix) or str(key) == model_path:
			to_erase.append(str(key))
	for key in to_erase:
		var proto: Node3D = _prototypes[key] as Node3D
		_prototypes.erase(key)
		if proto != null and is_instance_valid(proto):
			proto.free()
	JsonUtil.clear_cache(model_path)


static func clear() -> void:
	for key in _prototypes.keys():
		var proto: Node3D = _prototypes[key] as Node3D
		if proto != null and is_instance_valid(proto):
			proto.free()
	_prototypes.clear()


static func _cache_key(model_path: String, absolute_scale: float) -> String:
	return "%s|%.4f" % [model_path, absolute_scale]


## Build via ModelAssembler off-tree, flatten its visuals into a dumb root.
##
## `build_part_colliders = false`, so a `MeshTransformer` builds no
## `CollisionShape3D` and no local `StaticBody3D` — nothing physical reaches the
## prototype, and `VisualFlatten` would drop it anyway (a `CollisionShape3D` is a
## `Node3D`, not a `VisualInstance3D`). Callers that want collision build it
## themselves around the stamped visual: `ContainerNode` and `MooringPost` do;
## `LighthouseBuilding` is a bare `Node3D` and has none.
static func _bake(model_path: String, absolute_scale: float) -> Node3D:
	var assembler := ModelAssembler.new()
	assembler.build_part_colliders = false
	assembler.absolute_scale = absolute_scale
	assembler.model_data_path = model_path
	# Off-tree: `_ready` never runs — rebuild explicitly.
	assembler.rebuild()

	var root := Node3D.new()
	root.name = "CachedModel"
	VisualFlatten.flatten(assembler, root)
	assembler.free()
	return root


## The visuals are `VisualFlatten.stamp`, shared with the other two caches. The
## root keeps the prototype's `"CachedModel"` name only because it always has —
## checked, not assumed: every caller in the repo renames it on the next line
## (`"Model"`, `"LighthouseModel"`, …) and nothing looks the string up, so this
## is behaviour preservation and not a contract.
static func _stamp(prototype: Node3D) -> Node3D:
	var root := VisualFlatten.stamp(prototype)
	root.name = prototype.name
	return root
