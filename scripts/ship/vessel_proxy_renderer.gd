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
const MAX_PREDICTION_S := 0.45
const MAX_PROXY_SPEED_MS := 24.0

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
	var sample_time_s := float(Time.get_ticks_msec()) * 0.001
	var state := _states.get(uid, {}) as Dictionary
	if state.is_empty():
		state = {
			"visual_key": visual_key,
			"position": target,
			"target_position": target,
			"heading": heading,
			"target_heading": heading,
			"sample_position": target,
			"sample_time_s": sample_time_s,
			"velocity": Vector3.ZERO,
		}
		_groups_dirty = true
	else:
		if str(state.get("visual_key", "")) != visual_key:
			state["visual_key"] = visual_key
			_groups_dirty = true
		var previous_sample := state.get("sample_position", target) as Vector3
		var previous_time := float(state.get("sample_time_s", sample_time_s))
		var sample_delta := sample_time_s - previous_time
		var velocity := state.get("velocity", Vector3.ZERO) as Vector3
		if sample_delta > 0.04 and sample_delta < 1.5:
			velocity = (target - previous_sample) / sample_delta
			if velocity.length() > MAX_PROXY_SPEED_MS:
				velocity = velocity.normalized() * MAX_PROXY_SPEED_MS
		state["sample_position"] = target
		state["sample_time_s"] = sample_time_s
		state["velocity"] = velocity
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
	var now_s := float(Time.get_ticks_msec()) * 0.001
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
			var target := state.get("sample_position", current) as Vector3
			var elapsed := clampf(now_s - float(state.get("sample_time_s", now_s)),
				0.0, MAX_PREDICTION_S)
			target += (state.get("velocity", Vector3.ZERO) as Vector3) * elapsed
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
	_append_authored_hull(combined, hull_id, config, loa, beam, depth, bow_frac)

	var layout_dict := vessel.get("brick_layout", {}) as Dictionary
	var layout := BrickLayout.from_dict(layout_dict)
	var grid := HullRegistry.make_grid(hull_id)
	var geometry_by_palette: Dictionary = {}
	for item_raw in layout.iter_primary_cells():
		var item := item_raw as Dictionary
		var brick_id := str(item.get("brick_id", ""))
		if brick_id.is_empty() or BrickCatalog.has_tag(brick_id, "light") \
				or BrickCatalog.has_tag(brick_id, "text"):
			continue
		var yaw := posmod(int(item.get("yaw", 0)), 360)
		var color := _proxy_color(BrickLayout.color_from_entry(item, brick_id), brick_id)
		var palette_key := _palette_key(color)
		if not geometry_by_palette.has(palette_key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			geometry_by_palette[palette_key] = {"color": color, "tool": tool}
		var group := geometry_by_palette[palette_key] as Dictionary
		var visual := BrickCatalog.create_visual(brick_id, {"color": color})
		var item_transform := Transform3D(
			Basis(Vector3.UP, deg_to_rad(float(yaw))),
			DeckFitout.footprint_center_local(
				grid, item.get("cell", Vector3i.ZERO) as Vector3i, brick_id, yaw),
		)
		_append_visual_geometry(group.get("tool") as SurfaceTool, visual, item_transform)
		visual.free()

	var palette_keys := geometry_by_palette.keys()
	palette_keys.sort()
	var manifest := assignment.get("cargo_manifest", {}) as Dictionary
	var cargo_surface_reserve := 1 if str(manifest.get("kind", "")) == "units" else 0
	var palette_budget := maxi(MAX_PROXY_SURFACES - combined.get_surface_count() \
		- cargo_surface_reserve, 0)
	for palette_raw in palette_keys.slice(0, palette_budget):
		var group := geometry_by_palette[palette_raw] as Dictionary
		var tool := group.get("tool") as SurfaceTool
		if tool == null:
			continue
		var surface_mesh := tool.commit()
		if surface_mesh == null or surface_mesh.get_surface_count() == 0:
			continue
		surface_mesh.surface_set_material(0, MeshBuilder.make_material(
			group.get("color", Color.WHITE) as Color, 0.87, 0.01, true))
		_append_mesh(combined, surface_mesh)

	var cargo_boxes := _cargo_boxes(layout, grid, assignment)
	if not cargo_boxes.is_empty() and combined.get_surface_count() < MAX_PROXY_SURFACES:
		_append_mesh(combined, _mesh_from_boxes(
			cargo_boxes, Color(0.10, 0.28, 0.50), 0.82, 0.04))
	return combined


static func _append_authored_hull(
		target: ArrayMesh,
		hull_id: String,
		config: Dictionary,
		loa: float,
		beam: float,
		depth: float,
		bow_frac: float,
) -> void:
	if hull_id == "hull_45x16_cat":
		var stations := PassengerCatamaran.make_demihull_stations()
		var hull_offset := (PassengerCatamaran.BEAM_M \
			- PassengerCatamaran.DEMIHULL_BEAM_M) * 0.5
		for side in [-1.0, 1.0]:
			_append_transformed_instance(target, MeshBuilder.lofted_hull_shell(
				stations, Color(0.14, 0.16, 0.18), 0.9, 0.05, true),
				Transform3D(Basis.IDENTITY, Vector3(hull_offset * side, 0.0, 0.0)))
		var deck := MeshBuilder.box(
			Vector3(beam, 0.1, loa), Color(0.38, 0.34, 0.28), 0.95, 0.0)
		_append_transformed_instance(target, deck,
			Transform3D(Basis.IDENTITY, Vector3(0.0, stations.deck_y + 0.05, 0.0)))
		return
	var profile := FishingTrawlerSmall.make_physics_profile() \
		if hull_id == "hull_28x10" \
		else CatalogHullVessel.make_physics_profile(config)
	var stations := profile.make_stations()
	_append_instance(target, MeshBuilder.lofted_hull_shell(
		stations, Color(0.14, 0.16, 0.18), 0.9, 0.05))
	_append_instance(target, MeshBuilder.pointed_deck_plate(
		loa, beam, stations.deck_y + 0.1, 0.1, bow_frac,
		Color(0.38, 0.34, 0.28), 0.95))


static func _append_visual_geometry(
		tool: SurfaceTool,
		node: Node,
		parent_transform: Transform3D,
) -> void:
	if tool == null or node == null:
		return
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				# Brick visuals are triangle meshes. PrimitiveMesh does not expose
				# ArrayMesh.surface_get_primitive_type(), but append_from accepts both.
				tool.append_from(instance.mesh, surface, transform)
	for child in node.get_children():
		_append_visual_geometry(tool, child as Node, transform)


static func _mesh_from_boxes(
		boxes: Array,
		color: Color,
		roughness: float,
		metallic: float,
) -> ArrayMesh:
	var source_instance := MeshBuilder.box(Vector3.ONE, color, roughness, metallic)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box_raw in boxes:
		var box := box_raw as Dictionary
		var size := box.get("size", Vector3.ONE) as Vector3
		var position := box.get("position", Vector3.ZERO) as Vector3
		tool.append_from(source_instance.mesh, 0,
			Transform3D(Basis.IDENTITY.scaled(size), position))
	var mesh := tool.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0,
			MeshBuilder.make_material(color, roughness, metallic, true))
	source_instance.free()
	return mesh


static func _append_mesh(target: ArrayMesh, source: Mesh) -> void:
	if target == null or source == null:
		return
	for surface in range(source.get_surface_count()):
		target.add_surface_from_arrays(
			source.surface_get_primitive_type(surface),
			source.surface_get_arrays(surface),
		)
		var material := source.surface_get_material(surface)
		if material != null:
			target.surface_set_material(target.get_surface_count() - 1, material)


static func _append_transformed_instance(
		target: ArrayMesh,
		instance: MeshInstance3D,
		transform: Transform3D,
) -> void:
	if target == null or instance == null or instance.mesh == null:
		if instance != null:
			instance.free()
		return
	for surface in range(instance.mesh.get_surface_count()):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(instance.mesh, surface, transform * instance.transform)
		var transformed := tool.commit()
		var material := instance.material_override
		if material == null:
			material = instance.mesh.surface_get_material(surface)
		if transformed != null and transformed.get_surface_count() > 0 and material != null:
			transformed.surface_set_material(0, material)
		_append_mesh(target, transformed)
	instance.free()


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
