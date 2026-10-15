class_name CustomPortPlacementPicker
extends RefCounted

## Editor selection uses the visible rigid meshes, independently of gameplay
## collision. In particular a thin gutter must not select the wall behind it.
## Rebuild after a presenter snapshot changes; ordinary hinge/root transforms
## are read at pick time and do not require rebuilding triangle data.
var _presenter: WeakRef
var _instances: Array[Dictionary] = []
var _geometry: Dictionary = {}
var _rebuild_usec := 0
var _last_pick_usec := 0
var _exact_queries := 0


func configure(presenter: CustomPortPresenter) -> void:
	_presenter = weakref(presenter)
	rebuild()


func clear() -> void:
	_instances.clear()
	for entry in _geometry.values():
		_disconnect(entry)
	_geometry.clear()
	_presenter = null


func rebuild() -> void:
	var started := Time.get_ticks_usec()
	_instances.clear()
	var used: Dictionary = {}
	var presenter := _presenter.get_ref() as CustomPortPresenter if _presenter != null else null
	if is_instance_valid(presenter):
		for placement_id in presenter.placement_nodes:
			var root: Node3D = presenter.placement_nodes[placement_id]
			if not is_instance_valid(root) or root.is_queued_for_deletion(): continue
			var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
			if root is MeshInstance3D: meshes.push_front(root)
			for candidate in meshes:
				var visual := candidate as MeshInstance3D
				# Animated people retain their existing physical interaction target.
				# Bind-pose triangles would falsely select space between moving limbs.
				if visual.mesh == null or visual.skin != null: continue
				var mesh_id := visual.mesh.get_instance_id()
				used[mesh_id] = true
				_instances.append({"placement_id": str(placement_id), "visual": weakref(visual)})
				_cache(visual.mesh)
	for mesh_id in _geometry.keys():
		if not used.has(mesh_id):
			_disconnect(_geometry[mesh_id])
			_geometry.erase(mesh_id)
	_rebuild_usec = Time.get_ticks_usec() - started


func pick(origin: Vector3, direction: Vector3, max_distance := 500.0) -> Dictionary:
	var started := Time.get_ticks_usec()
	_exact_queries = 0
	var result: Dictionary = {}
	if not origin.is_finite() or not direction.is_finite() or not is_finite(max_distance) or max_distance <= 0 or direction.length_squared() < 0.000001:
		_last_pick_usec = Time.get_ticks_usec() - started
		return result
	var ray := direction.normalized()
	var nearest := max_distance
	for entry in _instances:
		var visual := entry.visual.get_ref() as MeshInstance3D
		if not is_instance_valid(visual) or not visual.is_inside_tree() or visual.is_queued_for_deletion() or not visual.is_visible_in_tree() or visual.mesh == null:
			continue
		var transform := visual.global_transform
		if not transform.is_finite() or absf(transform.basis.determinant()) < 0.0000001: continue
		var inverse := transform.affine_inverse()
		var local_origin := inverse * origin
		var local_end := inverse * (origin + ray * nearest)
		var geometry := _cache(visual.mesh)
		# Local bounds stay tight under rotated/non-uniformly scaled parents.
		# No visual bounds or crane work envelope is ever accepted as a hit.
		if geometry.bvh == null or geometry.bounds.intersects_segment(local_origin, local_end) == null: continue
		_exact_queries += 1
		var contact: Dictionary = geometry.bvh.intersect_segment(local_origin, local_end)
		if contact.is_empty(): continue
		var position: Vector3 = transform * contact.position
		var distance := (position - origin).dot(ray)
		if distance < 0 or distance > nearest + 0.00001: continue
		if visual.visibility_range_end > 0 and distance > visual.visibility_range_end + visual.visibility_range_end_margin: continue
		if visual.visibility_range_begin > 0 and distance < visual.visibility_range_begin - visual.visibility_range_begin_margin: continue
		var normal: Vector3 = (inverse.basis.transposed() * contact.normal).normalized()
		if normal.dot(ray) > 0: normal = -normal
		nearest = distance
		result = {"placement_id": entry.placement_id, "distance": distance,
			"position": position, "normal": normal, "face_index": contact.get("face_index", -1)}
	_last_pick_usec = Time.get_ticks_usec() - started
	return result


func stats() -> Dictionary:
	return {"mesh_cache_count": _geometry.size(), "instance_count": _instances.size(),
		"rebuild_usec": _rebuild_usec, "last_pick_usec": _last_pick_usec, "exact_queries": _exact_queries}


func _cache(mesh: Mesh) -> Dictionary:
	var id := mesh.get_instance_id()
	if _geometry.has(id) and not _geometry[id].dirty: return _geometry[id]
	if not _geometry.has(id):
		# Do not create a mesh -> callback -> picker ownership cycle. Shared
		# resources may outlive this temporary construction tool.
		var owner: WeakRef = weakref(self)
		var changed := func() -> void:
			var picker: CustomPortPlacementPicker = owner.get_ref()
			if picker != null and picker._geometry.has(id): picker._geometry[id].dirty = true
		mesh.changed.connect(changed)
		_geometry[id] = {"mesh": mesh, "changed": changed, "dirty": true}
	var entry: Dictionary = _geometry[id]
	entry.bounds = mesh.get_aabb().grow(0.0001)
	# Godot builds a triangle BVH, so a steady pick never loops over every face.
	entry.bvh = mesh.generate_triangle_mesh()
	entry.dirty = false
	return entry


func _disconnect(entry: Dictionary) -> void:
	var mesh: Mesh = entry.mesh
	if mesh.changed.is_connected(entry.changed): mesh.changed.disconnect(entry.changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted is already at zero references here: invoking another
		# method on self is invalid even though its fields remain readable.
		for entry in _geometry.values():
			var mesh: Mesh = entry.mesh
			if mesh.changed.is_connected(entry.changed): mesh.changed.disconnect(entry.changed)
