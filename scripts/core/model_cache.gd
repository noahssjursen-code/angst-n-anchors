@tool
class_name ModelCache
extends RefCounted

## Builds a JSON model once via ModelAssembler, bakes a dumb visual Node3D
## (MeshInstance3D children only, shared ArrayMeshes), and stamps copies.
##
## Use for static props that do not need live part/role lookups (port street
## buildings, bollards). Interactive / articulated models stay on ModelAssembler.
##
## Critical: never duplicate a live ModelAssembler — its `_ready` would rebuild
## from JSON. Always stamp the baked prototype.

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


## Build via ModelAssembler off-tree, flatten MeshInstance3Ds into a dumb root.
static func _bake(model_path: String, absolute_scale: float) -> Node3D:
	var assembler := ModelAssembler.new()
	assembler.build_part_colliders = false
	assembler.absolute_scale = absolute_scale
	assembler.model_data_path = model_path
	# Off-tree: `_ready` never runs — rebuild explicitly.
	assembler.rebuild()

	var root := Node3D.new()
	root.name = "CachedModel"
	_collect_mesh_instances(assembler, root, Transform3D.IDENTITY)
	assembler.free()
	return root


static func _collect_mesh_instances(src: Node, dst_root: Node3D, parent_xform: Transform3D) -> void:
	for child in src.get_children():
		if not (child is Node3D):
			continue
		var node_3d := child as Node3D
		var xform := parent_xform * node_3d.transform
		if child is MeshInstance3D:
			var src_mi := child as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.name = src_mi.name
			mi.mesh = src_mi.mesh
			mi.material_override = src_mi.material_override
			mi.cast_shadow = src_mi.cast_shadow
			mi.gi_mode = src_mi.gi_mode
			mi.transform = xform
			dst_root.add_child(mi)
		else:
			_collect_mesh_instances(child, dst_root, xform)


## Manual stamp so ArrayMesh / material resources stay shared (Node.duplicate
## deep-copies Resources by default).
static func _stamp(prototype: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = prototype.name
	for child in prototype.get_children():
		if child is MeshInstance3D:
			var src := child as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.name = src.name
			mi.mesh = src.mesh
			mi.material_override = src.material_override
			mi.cast_shadow = src.cast_shadow
			mi.gi_mode = src.gi_mode
			mi.transform = src.transform
			root.add_child(mi)
	return root
