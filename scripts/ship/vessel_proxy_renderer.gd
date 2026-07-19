class_name VesselProxyRenderer
extends Node3D

## Batched presentation for authority-owned vessels outside local interaction range.
##
## A proxy is not a second simulation. Company/debug/server authority continues to
## own route progress and traffic intent; this renderer only interpolates the last
## projected pose. Vessels with the same hull + brick layout share one ArrayMesh and
## one MultiMesh, so fifty copies do not become fifty full BoatBody scene trees.

const POSITION_RESPONSE := 9.0
const HEADING_RESPONSE := 7.0
const MAX_PROXY_SURFACES := 8

static var _mesh_cache: Dictionary = {} # visual key -> ArrayMesh
static var _mesh_surface_counts: Dictionary = {}
static var _total_mesh_build_count := 0
static var _total_mesh_build_ms := 0.0

var _states: Dictionary = {} # uid -> interpolation + visual key
var _groups: Dictionary = {} # visual key -> { node, multimesh, uids }
var _uid_visual_keys: Dictionary = {}
var _groups_dirty := false
var _transform_writes := 0


static func shared_visual_mesh(
		vessel: Dictionary,
		assignment: Dictionary = {},
) -> ArrayMesh:
	var hull_id := HullRegistry.resolve_network_hull_id(str(vessel.get("hull_id", "hull_28x10")))
	var explicit := str(vessel.get("proxy_visual_id", "")).strip_edges()
	var layout := vessel.get("brick_layout", {}) as Dictionary
	var layout_key := explicit if not explicit.is_empty() else str(JSON.stringify(layout).hash())
	var cargo_key := _static_cargo_key(assignment)
	var key := "%s:%s:%s" % [hull_id, layout_key, cargo_key]
	if not _mesh_cache.has(key):
		var started := Time.get_ticks_usec()
		var mesh := _build_proxy_mesh(vessel, assignment)
		_mesh_cache[key] = mesh
		_mesh_surface_counts[key] = mesh.get_surface_count() if mesh != null else 0
		_total_mesh_build_count += 1
		_total_mesh_build_ms += float(Time.get_ticks_usec() - started) / 1000.0
	return _mesh_cache.get(key) as ArrayMesh


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	top_level = true


func set_projection(
		uid: String,
		vessel: Dictionary,
		assignment: Dictionary,
		projection: Dictionary,
) -> void:
	if uid.is_empty():
		return
	var raw_position: Variant = projection.get("position", Vector3(INF, INF, INF))
	if raw_position is not Vector3 or not (raw_position as Vector3).is_finite():
		return
	var position := raw_position as Vector3
	var raw_heading: Variant = projection.get("heading_xz", Vector2(0.0, -1.0))
	var heading := raw_heading as Vector2 if raw_heading is Vector2 else Vector2(0.0, -1.0)
	if heading.length_squared() < 0.001:
		heading = Vector2(0.0, -1.0)
	heading = heading.normalized()
	var visual_key := _visual_key(uid, vessel, assignment)
	_ensure_mesh(visual_key, vessel, assignment)
	var draft := _draft_for(vessel)
	var target := position
	target.y -= draft
	var state := _states.get(uid, {}) as Dictionary
	if state.is_empty():
		state = {
			"visual_key": visual_key,
			"position": target,
			"target_position": target,
			"heading": heading,
			"target_heading": heading,
		}
		_groups_dirty = true
	else:
		if str(state.get("visual_key", "")) != visual_key:
			state["visual_key"] = visual_key
			_groups_dirty = true
		state["target_position"] = target
		state["target_heading"] = heading
	_states[uid] = state


func retain_only(wanted: Dictionary) -> void:
	var removed := false
	for uid_raw in _states.keys():
		var uid := str(uid_raw)
		if wanted.has(uid):
			continue
		_states.erase(uid)
		_uid_visual_keys.erase(uid)
		removed = true
	if removed:
		_groups_dirty = true
	if _groups_dirty:
		_sync_groups()


func clear() -> void:
	_states.clear()
	_uid_visual_keys.clear()
	for group_raw in _groups.values():
		var group := group_raw as Dictionary
		var node_raw: Variant = group.get("node")
		if node_raw != null and is_instance_valid(node_raw):
			(node_raw as Node).queue_free()
	_groups.clear()
	_groups_dirty = false


func proxy_count() -> int:
	return _states.size()


func has_proxy(uid: String) -> bool:
	return _states.has(uid)


func get_debug_stats() -> Dictionary:
	var surfaces := 0
	for key_raw in _groups.keys():
		surfaces += int(_mesh_surface_counts.get(str(key_raw), 0))
	return {
		"visual_proxies": _states.size(),
		"proxy_batches": _groups.size(),
		"proxy_draw_surfaces": surfaces,
		"proxy_mesh_builds": _total_mesh_build_count,
		"proxy_mesh_build_ms": _total_mesh_build_ms,
		"proxy_transform_writes": _transform_writes,
	}


func _process(delta: float) -> void:
	if _groups_dirty:
		_sync_groups()
	if _states.is_empty():
		return
	var position_weight := 1.0 - exp(-POSITION_RESPONSE * delta)
	var heading_weight := 1.0 - exp(-HEADING_RESPONSE * delta)
	_transform_writes = 0
	for group_raw in _groups.values():
		var group := group_raw as Dictionary
		var multimesh := group.get("multimesh") as MultiMesh
		var uids := group.get("uids", []) as Array
		if multimesh == null:
			continue
		for index in range(uids.size()):
			var uid := str(uids[index])
			var state := _states.get(uid, {}) as Dictionary
			if state.is_empty():
				continue
			var current := state.get("position", Vector3.ZERO) as Vector3
			var target := state.get("target_position", current) as Vector3
			current = current.lerp(target, position_weight)
			var heading := state.get("heading", Vector2(0.0, -1.0)) as Vector2
			var target_heading := state.get("target_heading", heading) as Vector2
			heading = heading.lerp(target_heading, heading_weight)
			if heading.length_squared() < 0.001:
				heading = target_heading
			heading = heading.normalized()
			state["position"] = current
			state["heading"] = heading
			_states[uid] = state
			var yaw := atan2(-heading.x, -heading.y)
			multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, yaw), current))
			_transform_writes += 1


func _sync_groups() -> void:
	var members: Dictionary = {}
	for uid_raw in _states.keys():
		var uid := str(uid_raw)
		var key := str((_states[uid] as Dictionary).get("visual_key", ""))
		if key.is_empty():
			continue
		if not members.has(key):
			members[key] = []
		(members[key] as Array).append(uid)
	for key_raw in _groups.keys():
		var key := str(key_raw)
		if members.has(key):
			continue
		var old_group := _groups[key] as Dictionary
		var old_node_raw: Variant = old_group.get("node")
		if old_node_raw != null and is_instance_valid(old_node_raw):
			(old_node_raw as Node).queue_free()
		_groups.erase(key)
	for key_raw in members.keys():
		var key := str(key_raw)
		var uids := members[key] as Array
		uids.sort()
		var group := _groups.get(key, {}) as Dictionary
		var multimesh := group.get("multimesh") as MultiMesh
		if multimesh == null:
			multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = _mesh_cache.get(key) as Mesh
			var node := MultiMeshInstance3D.new()
			node.name = "VesselProxyBatch_%s" % key.replace(":", "_")
			node.multimesh = multimesh
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			add_child(node)
			group = {"node": node, "multimesh": multimesh, "uids": []}
			_groups[key] = group
		if multimesh.instance_count != uids.size():
			multimesh.instance_count = uids.size()
		group["uids"] = uids
		_groups[key] = group
		# MultiMesh initializes new instances at the origin. Seed their actual
		# projection immediately so a tier transition cannot flash a pile of ships
		# at world zero for one render frame.
		for index in range(uids.size()):
			var state := _states.get(str(uids[index]), {}) as Dictionary
			var position := state.get("position", Vector3.ZERO) as Vector3
			var heading := state.get("heading", Vector2(0.0, -1.0)) as Vector2
			if heading.length_squared() < 0.001:
				heading = Vector2(0.0, -1.0)
			var yaw := atan2(-heading.x, -heading.y)
			multimesh.set_instance_transform(index,
				Transform3D(Basis(Vector3.UP, yaw), position))
	_groups_dirty = false


func _visual_key(uid: String, vessel: Dictionary, assignment: Dictionary) -> String:
	var cargo_key := _static_cargo_key(assignment)
	var cached := str(_uid_visual_keys.get(uid, ""))
	if not cached.is_empty() and cached.ends_with(":" + cargo_key):
		return cached
	var explicit := str(vessel.get("proxy_visual_id", "")).strip_edges()
	var hull_id := HullRegistry.resolve_network_hull_id(str(vessel.get("hull_id", "hull_28x10")))
	var layout := vessel.get("brick_layout", {}) as Dictionary
	var layout_key := explicit
	if layout_key.is_empty():
		layout_key = str(JSON.stringify(layout).hash())
	var key := "%s:%s:%s" % [hull_id, layout_key, cargo_key]
	_uid_visual_keys[uid] = key
	return key


static func _static_cargo_key(assignment: Dictionary) -> String:
	var manifest := assignment.get("cargo_manifest", {}) as Dictionary
	var kind := str(manifest.get("kind", "none"))
	if kind == "units":
		return "units%d" % mini((manifest.get("units", []) as Array).size(), 24)
	if kind == "bulk":
		return "bulk"
	return "empty"


func _ensure_mesh(key: String, vessel: Dictionary, assignment: Dictionary) -> void:
	if _mesh_cache.has(key):
		return
	var started := Time.get_ticks_usec()
	var mesh := _build_proxy_mesh(vessel, assignment)
	_mesh_cache[key] = mesh
	_mesh_surface_counts[key] = mesh.get_surface_count() if mesh != null else 0
	_total_mesh_build_count += 1
	_total_mesh_build_ms += float(Time.get_ticks_usec() - started) / 1000.0
	_groups_dirty = true


static func _build_proxy_mesh(vessel: Dictionary, assignment: Dictionary) -> ArrayMesh:
	var hull_id := HullRegistry.resolve_network_hull_id(str(vessel.get("hull_id", "hull_28x10")))
	var config := HullRegistry.get_by_id(hull_id)
	var loa := float(config.get("loa_m", 28.0))
	var beam := float(config.get("beam_m", 10.0))
	var depth := float(config.get("depth_m", 5.6))
	var bow_frac := clampf(beam * 0.5 / maxf(loa, 0.1), 0.08, 0.32)
	var combined := ArrayMesh.new()
	_append_instance(combined, MeshBuilder.pointed_hull_shell(
		loa, beam, depth, bow_frac, Color(0.055, 0.075, 0.095), 0.92, 0.03))
	_append_instance(combined, MeshBuilder.pointed_deck_plate(
		loa, beam, depth + 0.11, 0.14, bow_frac, Color(0.28, 0.29, 0.29), 0.94))

	var layout_dict := vessel.get("brick_layout", {}) as Dictionary
	var layout := BrickLayout.from_dict(layout_dict)
	var grid := HullRegistry.make_grid(hull_id)
	var boxes_by_palette: Dictionary = {}
	for item_raw in layout.iter_primary_cells():
		var item := item_raw as Dictionary
		var brick_id := str(item.get("brick_id", ""))
		if brick_id.is_empty() or BrickCatalog.has_tag(brick_id, "light") \
				or BrickCatalog.has_tag(brick_id, "text"):
			continue
		var size := BrickCatalog.size_m(brick_id)
		var yaw := posmod(int(item.get("yaw", 0)), 360)
		if yaw == 90 or yaw == 270:
			size = Vector3(size.z, size.y, size.x)
		var color := _proxy_color(BrickLayout.color_from_entry(item, brick_id), brick_id)
		var palette_key := _palette_key(color)
		if not boxes_by_palette.has(palette_key):
			boxes_by_palette[palette_key] = {"color": color, "boxes": []}
		var group := boxes_by_palette[palette_key] as Dictionary
		(group["boxes"] as Array).append({
			"size": size,
			"position": DeckFitout.footprint_center_local(
				grid, item.get("cell", Vector3i.ZERO) as Vector3i, brick_id, yaw),
		})

	var palette_keys := boxes_by_palette.keys()
	palette_keys.sort()
	for palette_raw in palette_keys.slice(0, MAX_PROXY_SURFACES - 3):
		var group := boxes_by_palette[palette_raw] as Dictionary
		var boxes := group.get("boxes", []) as Array
		if boxes.is_empty():
			continue
		_append_instance(combined, MeshBuilder.merged_boxes(
			boxes, group.get("color", Color.WHITE) as Color, 0.87, 0.01))

	var cargo_boxes := _cargo_boxes(layout, grid, assignment)
	if not cargo_boxes.is_empty() and combined.get_surface_count() < MAX_PROXY_SURFACES:
		_append_instance(combined, MeshBuilder.merged_boxes(
			cargo_boxes, Color(0.10, 0.28, 0.50), 0.82, 0.04))
	return combined


static func _cargo_boxes(layout: BrickLayout, grid: DeckGrid, assignment: Dictionary) -> Array:
	var manifest := assignment.get("cargo_manifest", {}) as Dictionary
	if str(manifest.get("kind", "")) != "units":
		return []
	var remaining := (manifest.get("units", []) as Array).size()
	var boxes: Array = []
	for pad_raw in layout.container_pads:
		var pad := pad_raw as Dictionary
		var mn := BrickLayout.zone_min(pad)
		var mx := BrickLayout.zone_max(pad)
		for z in range(mn.z, mx.z + 1, 4):
			for x in range(mn.x, mx.x + 1, 4):
				if remaining <= 0:
					return boxes
				var sx := mini(4, mx.x - x + 1)
				var sz := mini(4, mx.z - z + 1)
				boxes.append({
					"size": Vector3(float(sx) * DeckGrid.CELL_M, 4.0, float(sz) * DeckGrid.CELL_M),
					"position": Vector3(
						-grid.half_beam + (float(x) + float(sx) * 0.5) * DeckGrid.CELL_M,
						grid.deck_y + 2.0,
						-grid.half_loa + (float(z) + float(sz) * 0.5) * DeckGrid.CELL_M,
					),
				})
				remaining -= 1
	return boxes


static func _append_instance(target: ArrayMesh, instance: MeshInstance3D) -> void:
	if target == null or instance == null or instance.mesh == null:
		if instance != null:
			instance.free()
		return
	var source := instance.mesh
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		target.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
		var material := instance.material_override
		if material == null:
			material = source.surface_get_material(surface)
		if material != null:
			target.surface_set_material(target.get_surface_count() - 1, material)
	instance.free()


static func _proxy_color(source: Color, brick_id: String) -> Color:
	if BrickCatalog.has_tag(brick_id, "window"):
		return Color(0.12, 0.25, 0.34)
	var color := source
	color.a = 1.0
	var luminance := color.get_luminance()
	if luminance < 0.30:
		return Color(0.20, 0.22, 0.24)
	if luminance > 0.68:
		return Color(0.78, 0.80, 0.83)
	if color.r > color.g * 1.15 and color.r > color.b * 1.15:
		return Color(0.58, 0.38, 0.23)
	return Color(0.46, 0.49, 0.52)


static func _palette_key(color: Color) -> String:
	return "%d_%d_%d" % [
		int(round(color.r * 4.0)),
		int(round(color.g * 4.0)),
		int(round(color.b * 4.0)),
	]


static func _draft_for(vessel: Dictionary) -> float:
	var config := HullRegistry.get_by_id(str(vessel.get("hull_id", "hull_28x10")))
	return float(config.get("draft_m", float(config.get("depth_m", 5.6)) * 0.42))
