class_name BuildingFitout
extends RefCounted

const ROOT_NAME := "BuildingFitout"


static func build(layout: BuildingLayout, collision_enabled: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = ROOT_NAME
	if layout == null:
		return root
	var lighting := BuildingLighting.new()
	lighting.name = "BuildingLighting"
	root.add_child(lighting)
	root.set_meta("building_blueprint_id", layout.blueprint_id)
	var grid := layout.grid()
	var collision_body: StaticBody3D = null
	if collision_enabled:
		collision_body = StaticBody3D.new()
		collision_body.name = "Collision"
		root.add_child(collision_body)

	## Floor underlays on every cell (including multi-brick fillers).
	for item in layout.iter_cells():
		var cell := item["cell"] as Vector3i
		if item.has("surface"):
			var surface: Dictionary = item["surface"]
			_add_brick_visual(
				root,
				collision_body,
				grid,
				cell,
				str(surface.get("brick_id", "floor")),
				int(surface.get("yaw", 0)),
				surface,
				"%s_surface" % BuildingLayout.cell_key(cell),
				true,
			)
		elif BuildingLayout.entry_is_surface_only(item):
			_add_brick_visual(
				root,
				collision_body,
				grid,
				cell,
				str(item.get("brick_id", "floor")),
				int(item.get("yaw", 0)),
				item,
				"%s_floor" % BuildingLayout.cell_key(cell),
				true,
			)

	## Content bricks (skip floor-only cells — already drawn above).
	for item in layout.iter_primary_cells():
		if BuildingLayout.entry_is_surface_only(item):
			continue
		var cell := item["cell"] as Vector3i
		var brick_id := str(item.get("brick_id", ""))
		var yaw := int(item.get("yaw", 0))
		_add_brick_visual(
			root,
			collision_body,
			grid,
			cell,
			brick_id,
			yaw,
			item,
			"%s_%s" % [brick_id, BuildingLayout.cell_key(cell)],
			false,
		)
	return root


static func _add_brick_visual(
		root: Node3D,
		collision_body: StaticBody3D,
		grid: BuildingGrid,
		cell: Vector3i,
		brick_id: String,
		yaw: int,
		entry: Dictionary,
		node_name: String,
		surface_tile: bool,
) -> void:
	if not BrickCatalog.has(brick_id):
		return
	var opts := {}
	if entry.has("color"):
		opts["color"] = BuildingLayout.color_from_entry(entry, brick_id)
	if BrickCatalog.has_tag(brick_id, "text"):
		opts["text"] = str(entry.get("text", ""))
	var visual := BrickCatalog.create_visual(brick_id, opts)
	visual.name = node_name
	if surface_tile:
		## Single-cell floor plate at this cell (not the parent footprint centre).
		visual.position = grid.cell_center_local(cell)
		visual.rotation_degrees.y = float(yaw)
	else:
		visual.position = footprint_center_local(grid, cell, brick_id, yaw)
		visual.rotation_degrees.y = float(yaw)
	root.add_child(visual)
	if not surface_tile:
		_add_mounted_sign(root, grid, cell, entry, yaw)
	if BrickCatalog.has_tag(brick_id, "door") and not surface_tile:
		_add_brick_door(visual, collision_body, grid, cell, brick_id, yaw)
	elif BrickCatalog.has_tag(brick_id, "light") and not surface_tile:
		_add_brick_light(visual, brick_id)
	elif collision_body != null and _needs_collider(brick_id):
		_add_collider(collision_body, grid, cell, brick_id, yaw, surface_tile)


static func _add_mounted_sign(
		root: Node3D,
		grid: BuildingGrid,
		cell: Vector3i,
		entry: Dictionary,
		host_yaw: int,
) -> void:
	var sign_id := str(entry.get("sign_id", ""))
	if not BrickCatalog.has(sign_id) or not BrickCatalog.has_tag(sign_id, "text"):
		return
	var sign_yaw := int(entry.get("sign_yaw", host_yaw))
	var sign := BrickCatalog.create_visual(sign_id, {"text": str(entry.get("text", ""))})
	sign.name = "Sign_%s" % BuildingLayout.cell_key(cell)
	sign.position = grid.cell_center_local(cell)
	sign.rotation_degrees = Vector3(0.0, float(sign_yaw), 0.0)
	root.add_child(sign)


static func _add_brick_door(
		visual: Node3D,
		collision_body: StaticBody3D,
		grid: BuildingGrid,
		cell: Vector3i,
		brick_id: String,
		yaw: int,
) -> void:
	var sz := BrickCatalog.size_m(brick_id)
	var center := footprint_center_local(grid, cell, brick_id, yaw)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	## Static jambs stay solid; swinging leaf is handled by BrickDoor.
	if collision_body != null:
		var post := Vector3(0.14, sz.y * 0.95, maxf(sz.z * 0.3, 0.2))
		_add_box_collider(
			collision_body,
			"door_jamb_l_%s" % BuildingLayout.cell_key(cell),
			center + basis * Vector3(-sz.x * 0.5 + 0.07, 0.0, 0.0),
			post,
			float(yaw),
		)
		_add_box_collider(
			collision_body,
			"door_jamb_r_%s" % BuildingLayout.cell_key(cell),
			center + basis * Vector3(sz.x * 0.5 - 0.07, 0.0, 0.0),
			post,
			float(yaw),
		)
	var leaf_size := Vector3(sz.x * 0.8, sz.y * 0.88, 0.12)
	var door := BrickDoor.new()
	door.name = "BrickDoor"
	door.configure(null, Vector3.ZERO, float(yaw), leaf_size)
	## ONE DERIVATION (REALITY.md §3b). `BuildingCache` cannot flatten a
	## `BrickDoor` — it is behaviour, and its leaf swings — so it drops the
	## prototype's door and builds a fresh one per stamped instance. These two
	## metas are how it gets the same arguments this line just computed, instead
	## of re-deriving `leaf_size` from `size_m` in a second file that would then
	## drift from this one.
	door.set_meta("brick_door_yaw_deg", float(yaw))
	door.set_meta("brick_door_leaf_size", leaf_size)
	visual.add_child(door)


static func _add_brick_light(visual: Node3D, brick_id: String) -> void:
	## Land buildings use a plain warm omni (not ShipLight — boat ShipLighting
	## scans the whole tree by group and would steal these).
	var entry := BrickCatalog.get_entry(brick_id)
	var lens := _find_named_mesh(visual, "Lens")
	var light := OmniLight3D.new()
	light.name = "Fill"
	light.light_color = Color(1.0, 0.82, 0.52)
	light.omni_range = float(entry.get("omni_range_m", 6.0))
	light.omni_attenuation = 1.4
	light.light_energy = float(entry.get("omni_energy", 2.8))
	light.set_meta("building_light_base_energy", light.light_energy)
	light.set_meta("building_light_base_volumetric", 0.45)
	light.light_specular = 0.45
	light.light_volumetric_fog_energy = 0.45
	light.light_size = 0.12
	light.shadow_enabled = false
	if lens != null:
		light.position = lens.position + Vector3(0.0, -0.06, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.48, 0.32)
		mat.roughness = 0.35
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.82, 0.5)
		mat.emission_energy_multiplier = 2.4
		lens.material_override = mat
		lens.set_meta("building_lens_base_emission", 2.4)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		light.position = Vector3(0.0, BuildingGrid.CELL_M * 0.35, 0.0)
	visual.add_child(light)


static func _find_named_mesh(node: Node, mesh_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == mesh_name:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_named_mesh(child, mesh_name)
		if found != null:
			return found
	return null


static func apply(target: Node3D, layout: BuildingLayout, collision_enabled: bool = true) -> Node3D:
	var existing := target.get_node_or_null(ROOT_NAME)
	if existing != null:
		target.remove_child(existing)
		existing.free()
	var fitout := build(layout, collision_enabled)
	target.add_child(fitout)
	return fitout


static func footprint_center_local(
		grid: BuildingGrid,
		origin: Vector3i,
		brick_id: String,
		yaw: int,
) -> Vector3:
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	if yaw_steps < 0:
		yaw_steps += 4
	var occupied := grid.footprint_cells(origin, fp, yaw_steps)
	if occupied.is_empty():
		return grid.cell_center_local(origin)
	var sum := Vector3.ZERO
	for c in occupied:
		sum += grid.cell_center_local(c)
	return sum / float(occupied.size())


static func _needs_collider(brick_id: String) -> bool:
	if BrickCatalog.has_tag(brick_id, "door"):
		return false
	if BrickCatalog.has_tag(brick_id, "light"):
		return false
	if BrickCatalog.has_tag(brick_id, "text"):
		return false
	if BrickCatalog.has_tag(brick_id, "surface") or BrickCatalog.has_tag(brick_id, "floor"):
		return true
	return BrickCatalog.has_tag(brick_id, "solid") \
		or BrickCatalog.has_tag(brick_id, "wall") \
		or BrickCatalog.has_tag(brick_id, "window") \
		or BrickCatalog.has_tag(brick_id, "stairs") \
		or BrickCatalog.has_tag(brick_id, "railing") \
		or BrickCatalog.has_tag(brick_id, "prop")


static func _add_collider(
		body: StaticBody3D,
		grid: BuildingGrid,
		cell: Vector3i,
		brick_id: String,
		yaw: int,
		surface_tile: bool = false,
) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "Shape_%s_%s" % [brick_id, BuildingLayout.cell_key(cell)]
	var shape := BoxShape3D.new()
	var size := BrickCatalog.size_m(brick_id)
	var center := grid.cell_center_local(cell) if surface_tile \
		else footprint_center_local(grid, cell, brick_id, yaw)
	if brick_id == "floor" or BrickCatalog.has_tag(brick_id, "surface"):
		size.y = 0.12
		center.y = grid.cell_center_local(cell).y - BuildingGrid.CELL_M * 0.5 + 0.06
	elif BrickCatalog.is_flat_roof(brick_id):
		## The plate, where `BrickCatalog` draws it. This case used to read
		## `brick_id == "roof_flat"` and thin the box without moving it, so the
		## two multi-cell roofs got a full-cell collider and the 1x1 got a
		## 0.18 m one centred half a cell under its own plate.
		center.y += BrickCatalog.roof_plate_offset_y(brick_id)
		size.y = BrickCatalog.ROOF_PLATE_M
	elif brick_id == "roof_slope":
		## Lower half under the slope — walkable / blocks attic space.
		size.y = size.y * 0.5
		center.y -= BuildingGrid.CELL_M * 0.25
	elif brick_id == "roof_slope_inv":
		## Upper half above the underside slope — eave / overhang mass.
		size.y = size.y * 0.5
		center.y += BuildingGrid.CELL_M * 0.25
	elif brick_id == "roof_corner":
		size.y = size.y * 0.5
		center.y -= BuildingGrid.CELL_M * 0.25
	elif brick_id == "roof_corner_inv":
		size.y = size.y * 0.5
		center.y += BuildingGrid.CELL_M * 0.25
	elif brick_id == "ledge_45_corner":
		size.y = size.y * 0.5
		center.y -= BuildingGrid.CELL_M * 0.25
	elif brick_id == "ledge_45_corner_inv":
		size.y = size.y * 0.5
		center.y += BuildingGrid.CELL_M * 0.25
	elif brick_id == "roof_corner_inner" or brick_id == "ledge_45_inner":
		size.y = size.y * 0.5
		center.y -= BuildingGrid.CELL_M * 0.25
	elif brick_id == "roof_corner_inner_inv" or brick_id == "ledge_45_inner_inv":
		size.y = size.y * 0.5
		center.y += BuildingGrid.CELL_M * 0.25
	elif brick_id == "beam":
		size = Vector3(0.22, size.y, 0.22)
	if BrickCatalog.has_tag(brick_id, "diagonal_plan"):
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var hz := size.z * 0.5
		var convex := ConvexPolygonShape3D.new()
		convex.points = PackedVector3Array([
			Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, hz),
			Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, hz),
		])
		shape_node.shape = convex
	else:
		shape.size = size
		shape_node.shape = shape
	shape_node.position = center
	shape_node.rotation_degrees.y = float(yaw)
	body.add_child(shape_node)


static func _add_box_collider(
		body: StaticBody3D,
		shape_name: String,
		center: Vector3,
		size: Vector3,
		yaw_degrees: float,
) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = shape_name
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = center
	shape_node.rotation_degrees.y = yaw_degrees
	body.add_child(shape_node)
