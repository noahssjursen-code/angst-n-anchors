@tool
class_name PortDebugGizmos
extends Node3D

## Debug overlays for port site registration / coast tracing.
## Stamped into named layer nodes so each group can be shown or hidden independently.

const LAYER_ORIGIN := "origin"
const LAYER_AXES := "axes"
const LAYER_SIZE_BOX := "size_box"
const LAYER_TRACE_BOX := "trace_box"
const LAYER_TERRAIN_TRACE := "terrain_trace"
const LAYER_SPINE := "spine"
const LAYER_SHORE_SPAN := "shore_span"
const LAYER_DOCK_FACE := "dock_face"
const LAYER_GRAPH_ROOT := "graph_root"
const LAYER_ASPHALT_BERTHS := "asphalt_berths"
const LAYER_QUAY_ROOTS := "quay_roots"
const LAYER_QUAY_ARMS := "quay_arms"
const LAYER_LAND_ZONE := "land_zone"
const LAYER_LAND_STRUCTURES := "land_structures"
const LAYER_HARBOUR_BERTHS := "harbour_berths"

const LAYER_IDS: PackedStringArray = [
	LAYER_ORIGIN,
	LAYER_AXES,
	LAYER_SIZE_BOX,
	LAYER_TRACE_BOX,
	LAYER_TERRAIN_TRACE,
	LAYER_SPINE,
	LAYER_SHORE_SPAN,
	LAYER_DOCK_FACE,
	LAYER_GRAPH_ROOT,
	LAYER_ASPHALT_BERTHS,
	LAYER_QUAY_ROOTS,
	LAYER_QUAY_ARMS,
	LAYER_LAND_ZONE,
	LAYER_LAND_STRUCTURES,
	LAYER_HARBOUR_BERTHS,
]

const ORIGIN_COLOR := Color(1.0, 0.15, 0.15)
const SIZE_BOX_COLOR := Color(0.2, 0.95, 0.35)
const TRACE_BOX_COLOR := Color(1.0, 0.85, 0.1)
const SEAWARD_COLOR := Color(0.25, 0.55, 1.0)
const INLAND_COLOR := Color(0.35, 1.0, 0.45)
const TERRAIN_COAST_COLOR := Color(1.0, 0.55, 0.1)
const SPINE_COLOR := Color(0.95, 0.2, 0.95)
const DOCK_COLOR := Color(0.2, 0.85, 1.0)
const ANCHOR_COLOR := Color(1.0, 1.0, 0.2)
const LAND_ZONE_COLOR := Color(0.25, 0.95, 0.55, 0.12)
const LAND_ZONE_EDGE := Color(0.15, 1.0, 0.45)
## Line grid on the foundation apron pavement (dock face → town inland).
const ASPHALT_GRID_STEP_M := PortApronPadCatalog.CELL_M
const ASPHALT_GRID_LINE_THICK_M := 0.85
const ASPHALT_GRID_COLOR := Color(1.0, 0.92, 0.12)
const ASPHALT_GRID_OUTLINE_COLOR := Color(1.0, 0.85, 0.2, 0.65)
const ASPHALT_PAD_OUTLINE_COLOR := Color(1.0, 0.55, 0.08, 0.55)
const ASPHALT_PAD_FILL_COLOR := Color(0.15, 0.75, 0.95, 0.42)
const ASPHALT_GRID_EDGE_PAD_M := 2.0
const ASPHALT_GRID_DOT_R := 1.6

## layer_id → visible. Missing keys default to true when a master enable is on.
var _layer_visible: Dictionary = {}
var _graph: PortLayoutGraph
var _harbour: HarbourController


func configure(
		graph: PortLayoutGraph,
		layer_visible: Dictionary = {},
		harbour: HarbourController = null,
) -> void:
	_unbind_harbour_signals()
	_graph = graph
	_harbour = harbour
	_bind_harbour_signals()
	_layer_visible = _normalized_layers(layer_visible)
	if any_layer_visible():
		_rebuild()
	else:
		_clear_layers()


func _clear_layers() -> void:
	for child in get_children():
		child.free()


func _ensure_built() -> void:
	if get_child_count() == 0 and _graph != null:
		_rebuild()


func _bind_harbour_signals() -> void:
	if _harbour == null:
		return
	if not _harbour.ship_plugged.is_connected(_on_harbour_occupancy_changed):
		_harbour.ship_plugged.connect(_on_harbour_occupancy_changed)
	if not _harbour.ship_unplugged.is_connected(_on_harbour_occupancy_changed):
		_harbour.ship_unplugged.connect(_on_harbour_occupancy_changed)


func _unbind_harbour_signals() -> void:
	if _harbour == null:
		return
	if _harbour.ship_plugged.is_connected(_on_harbour_occupancy_changed):
		_harbour.ship_plugged.disconnect(_on_harbour_occupancy_changed)
	if _harbour.ship_unplugged.is_connected(_on_harbour_occupancy_changed):
		_harbour.ship_unplugged.disconnect(_on_harbour_occupancy_changed)


func _on_harbour_occupancy_changed(_berth_id: String = "", _ship: BoatBody = null) -> void:
	## Defer — plug/unplug often fires from BoatBody._exit_tree while the scene
	## is mid-teardown; stamping globals synchronously hits !is_inside_tree().
	call_deferred("_refresh_harbour_berths")


func _refresh_harbour_berths() -> void:
	if not is_inside_tree():
		return
	if not is_layer_visible(LAYER_HARBOUR_BERTHS):
		return
	_ensure_built()
	var layer := get_node_or_null(LAYER_HARBOUR_BERTHS) as Node3D
	if layer == null:
		return
	for child in layer.get_children():
		child.free()
	_stamp_harbour_berths()
	_apply_layer_visibility()


func set_layer_visible(layer_id: String, enabled: bool) -> void:
	if layer_id not in LAYER_IDS:
		return
	_layer_visible[layer_id] = enabled
	if enabled:
		_ensure_built()
	_apply_layer_visibility()


func set_all_layers_visible(enabled: bool) -> void:
	for layer_id in LAYER_IDS:
		_layer_visible[layer_id] = enabled
	if enabled:
		_ensure_built()
	_apply_layer_visibility()


func is_layer_visible(layer_id: String) -> bool:
	return bool(_layer_visible.get(layer_id, false))


func any_layer_visible() -> bool:
	for layer_id in LAYER_IDS:
		if is_layer_visible(layer_id):
			return true
	return false


func layer_state() -> Dictionary:
	return _layer_visible.duplicate()


static func default_layers(enabled: bool = false) -> Dictionary:
	var out := {}
	for layer_id in LAYER_IDS:
		out[layer_id] = enabled
	return out


func _rebuild() -> void:
	for child in get_children():
		child.free()
	if _graph == null:
		return
	var port_area := _graph.initial_attributes.get("port_area", {}) as Dictionary
	var foundation := _graph.initial_attributes.get("foundation", {}) as Dictionary
	var size := int(_graph.initial_attributes.get("size", 1))
	var half_w := float(port_area.get("half_width_m", 0.0))
	var half_d := float(port_area.get("half_depth_m", 0.0))
	var trace_w := float(port_area.get("trace_half_width_m", half_w))
	var trace_d := float(port_area.get("trace_half_depth_m", half_d))

	var origin := _ensure_layer(LAYER_ORIGIN)
	_stamp_origin(origin, size, half_w, half_d, trace_w, trace_d)

	var axes := _ensure_layer(LAYER_AXES)
	_stamp_axis_arrow(axes, Vector3(0.0, 0.0, -1.0), 90.0, SEAWARD_COLOR, "SEAWARD -Z")
	_stamp_axis_arrow(axes, Vector3(0.0, 0.0, 1.0), 90.0, INLAND_COLOR, "INLAND +Z")
	_stamp_axis_arrow(axes, Vector3(1.0, 0.0, 0.0), 70.0, Color(0.9, 0.9, 0.9), "ALONG +X")

	_stamp_ground_rect(_ensure_layer(LAYER_SIZE_BOX), "SizeBox", half_w, half_d, SIZE_BOX_COLOR, 0.8)
	_stamp_ground_rect(_ensure_layer(LAYER_TRACE_BOX), "TraceBox", trace_w, trace_d, TRACE_BOX_COLOR, 1.2)

	_stamp_polyline_dots(
		_ensure_layer(LAYER_TERRAIN_TRACE),
		port_area.get("terrain_coast_polyline", []) as Array,
		TERRAIN_COAST_COLOR,
		2.4,
		"TerrainTrace",
	)

	var spine_layer := _ensure_layer(LAYER_SPINE)
	_stamp_polyline_dots(spine_layer, foundation.get("spine", []) as Array, SPINE_COLOR, 3.2, "Spine")
	_stamp_polyline_lines(spine_layer, foundation.get("spine", []) as Array, SPINE_COLOR, 1.4)

	_stamp_polyline_dots(
		_ensure_layer(LAYER_SHORE_SPAN),
		port_area.get("natural_shore_polyline", []) as Array,
		Color(0.95, 0.45, 0.95),
		2.0,
		"ShoreSpan",
	)
	_stamp_polyline_dots(
		_ensure_layer(LAYER_DOCK_FACE),
		port_area.get("coast_polyline", []) as Array,
		DOCK_COLOR,
		2.6,
		"DockFace",
	)

	var root_layer := _ensure_layer(LAYER_GRAPH_ROOT)
	var modules := _graph.modules
	for instance_id in modules:
		var placed := modules[instance_id] as PortPlacedModule
		if str(placed.assignment.get("role", "")) == "foundation_anchor":
			_stamp_dot(root_layer, placed.position_m, ANCHOR_COLOR, 5.0, "GraphRoot")

	_stamp_berth_plan(_graph.initial_attributes.get("berth_plan", {}) as Dictionary)
	_stamp_land_zone(_graph.initial_attributes.get("land_plan", {}) as Dictionary)
	_stamp_land_plan(_graph.initial_attributes.get("land_plan", {}) as Dictionary)
	_stamp_harbour_berths()
	_apply_layer_visibility()


func _stamp_harbour_berths() -> void:
	if not is_inside_tree():
		return
	var layer := _ensure_layer(LAYER_HARBOUR_BERTHS)
	if _harbour == null:
		return
	for slot in _harbour.berths():
		var s := slot as QuayBerthSlot
		if s == null or not is_instance_valid(s) or not s.is_inside_tree():
			continue
		var occupied := _harbour.moored_ship(s.berth_id) != null
		var color := Color(0.95, 0.35, 0.2, 0.55) if occupied else Color(0.25, 0.85, 0.55, 0.45)
		var half_l := maxf(s.length_m * 0.45, 8.0)
		var half_w := maxf(s.width_m * 0.35, 6.0)
		var slot_xf := s.global_transform
		var box := MeshBuilder.box(
			Vector3(half_w * 2.0, 0.8, half_l * 2.0),
			color,
			0.85,
			0.0,
		)
		box.name = "HarbourBerth_%s" % s.station_id.replace("/", "_")
		layer.add_child(box)
		box.global_transform = Transform3D(slot_xf.basis, slot_xf.origin + Vector3(0.0, 1.2, 0.0))
		var lbl := Label3D.new()
		lbl.name = "HarbourBerthLbl_%s" % s.station_id.replace("/", "_")
		lbl.text = "%s\n%s" % [
			s.berth_id,
			"OCCUPIED" if occupied else "FREE",
		]
		lbl.pixel_size = 0.028
		lbl.modulate = color.lightened(0.25)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		layer.add_child(lbl)
		lbl.global_position = slot_xf.origin + Vector3(0.0, 14.0, 0.0)


func _stamp_berth_plan(plan: Dictionary) -> void:
	var asphalt_layer := _ensure_layer(LAYER_ASPHALT_BERTHS)
	var foundation := _graph.initial_attributes.get("foundation", {}) as Dictionary \
			if _graph != null else {}
	## Always: line grid on the grey foundation apron (what you're looking at).
	_stamp_foundation_apron_grid(asphalt_layer, foundation)
	var surface_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
			+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	_stamp_apron_pad_footprints(asphalt_layer, surface_y)
	if plan.is_empty():
		_ensure_layer(LAYER_QUAY_ROOTS)
		_ensure_layer(LAYER_QUAY_ARMS)
		return
	## Also outline any asphalt berth pads that stick seaward of the dock face.
	for raw in plan.get("asphalt_stations", []) as Array:
		var station := raw as Dictionary
		var origin := _xz(station.get("origin", [0.0, 0.0]))
		var depth := float(station.get("depth_m", 36.0))
		var length := float(station.get("length_m", 40.0))
		var tangent := _xz(station.get("tangent", [1.0, 0.0])).normalized()
		var seaward := _xz(station.get("direction", [0.0, -1.0])).normalized()
		if tangent.length_squared() < 0.01:
			tangent = Vector2(-seaward.y, seaward.x)
		if seaward.length_squared() < 0.01:
			seaward = PortCoastTracer.PORT_LOCAL_SEAWARD_DIR
		var pad := MeshBuilder.box(
			Vector3(length, 0.18, depth),
			ASPHALT_PAD_OUTLINE_COLOR,
			0.9,
			0.0,
		)
		pad.name = "%s_pad" % str(station.get("id", "asphalt"))
		asphalt_layer.add_child(pad)
		pad.position = Vector3(
			origin.x + seaward.x * depth * 0.5,
			surface_y + 0.1,
			origin.y + seaward.y * depth * 0.5,
		)
		_align_basis_on_tangent(pad, tangent, seaward)

	_stamp_berth_plan_quays(plan)


## Solid N×M brick-pad footprints from land_plan.apron_pads.
func _stamp_apron_pad_footprints(parent: Node3D, surface_y: float) -> void:
	if _graph == null:
		return
	var land: Dictionary = _graph.initial_attributes.get("land_plan", {}) as Dictionary
	var apron_pads: Dictionary = land.get("apron_pads", {}) as Dictionary
	var pads: Array = apron_pads.get("pads", []) as Array
	if pads.is_empty():
		return
	var root := Node3D.new()
	root.name = "ApronPadFootprints"
	parent.add_child(root)
	for raw in pads:
		var pad: Dictionary = raw
		var origin := _xz(pad.get("origin", [0.0, 0.0]))
		var size_arr: Array = pad.get("size_m", [PortApronPadCatalog.CELL_M, PortApronPadCatalog.CELL_M]) as Array
		var size_x := float(size_arr[0]) if size_arr.size() > 0 else PortApronPadCatalog.CELL_M
		var size_z := float(size_arr[1]) if size_arr.size() > 1 else PortApronPadCatalog.CELL_M
		var along := _xz(pad.get("along_dir", [1.0, 0.0])).normalized()
		var inland := _xz(pad.get("inland_dir", [0.0, 1.0])).normalized()
		if along.length_squared() < 0.01:
			along = Vector2(1.0, 0.0)
		if inland.length_squared() < 0.01:
			inland = Vector2(0.0, 1.0)
		var fill := ASPHALT_PAD_FILL_COLOR
		if str(pad.get("kind", "")) == "trade":
			fill = Color(0.95, 0.45, 0.2, 0.45)
		var box := MeshBuilder.box(Vector3(size_x * 0.96, 0.35, size_z * 0.96), fill, 0.9, 0.0)
		box.name = str(pad.get("id", "pad"))
		var mat := box.material_override as StandardMaterial3D
		if mat != null:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.disable_receive_shadows = true
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(box)
		box.position = Vector3(origin.x, surface_y + 0.22, origin.y)
		## Local X = along, local Z = inland (same as foundation apron UV).
		_align_basis_on_tangent(box, along, inland)
		var role_id := str(pad.get("role", "pad"))
		var cells_arr: Array = pad.get("cells", [1, 1]) as Array
		_label(
			root,
			"%s_lbl" % str(pad.get("id", "pad")),
			"%s\n%s · %s · %d×%d" % [
				PortApronPadCatalog.role_label(role_id).to_upper(),
				str(pad.get("zone", "")).to_upper(),
				str(pad.get("pad_template_id", "")),
				int(cells_arr[0]) if cells_arr.size() > 0 else 1,
				int(cells_arr[1]) if cells_arr.size() > 1 else 1,
			],
			Vector3(origin.x, surface_y + 8.0, origin.y),
			ASPHALT_GRID_COLOR,
		)


## Uniform port-local lattice clipped to the apron pavement polygon (no warp).
func _stamp_foundation_apron_grid(parent: Node3D, foundation: Dictionary) -> void:
	if foundation.is_empty():
		return
	var berth_plan: Dictionary = {}
	if _graph != null:
		berth_plan = _graph.initial_attributes.get("berth_plan", {}) as Dictionary
	var host := PortApronPadCatalog.build_host_grid(foundation, berth_plan)
	var cells: Array = host.get("cells", []) as Array
	if cells.is_empty():
		return
	var surface_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
			+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var y := surface_y + 0.35
	var step := float(host.get("cell_m", ASPHALT_GRID_STEP_M))

	var root := Node3D.new()
	root.name = "ApronSurfaceGrid"
	parent.add_child(root)

	for raw in cells:
		var entry: Dictionary = raw
		var corners_raw: Array = entry.get("corners", []) as Array
		if corners_raw.size() < 4:
			continue
		var corners := PackedVector2Array()
		for c in corners_raw:
			if c is Array and (c as Array).size() >= 2:
				var arr: Array = c
				corners.append(Vector2(float(arr[0]), float(arr[1])))
		if corners.size() < 4:
			continue
		for k in range(4):
			_stamp_grid_line(root, corners[k], corners[(k + 1) % 4], y, ASPHALT_GRID_COLOR)

	## Apron clip outline so the silhouette reads against the lattice.
	var poly := _polyline2(host.get("polygon", []) as Array)
	if poly.size() >= 2:
		for index in range(poly.size()):
			_stamp_grid_line(
				root,
				poly[index],
				poly[(index + 1) % poly.size()],
				y + 0.05,
				ASPHALT_GRID_OUTLINE_COLOR,
			)

	var origin_arr: Array = host.get("origin", [0.0, 0.0]) as Array
	var along_arr: Array = host.get("along_dir", [1.0, 0.0]) as Array
	var inland_arr: Array = host.get("inland_dir", [0.0, 1.0]) as Array
	var label_xz := Vector2.ZERO
	if origin_arr.size() >= 2 and along_arr.size() >= 2 and inland_arr.size() >= 2:
		var o := Vector2(float(origin_arr[0]), float(origin_arr[1]))
		var along_n := Vector2(float(along_arr[0]), float(along_arr[1])).normalized()
		var inland_n := Vector2(float(inland_arr[0]), float(inland_arr[1])).normalized()
		label_xz = o \
				+ along_n * (float(host.get("along_count", 0)) * step * 0.5) \
				+ inland_n * (float(host.get("inland_count", 0)) * step * 0.45)
	_label(
		root,
		"ApronGridLabel",
		"APRON GRID\n%.0f m uniform · %d host cells (clipped)" % [step, cells.size()],
		Vector3(label_xz.x, y + 14.0, label_xz.y),
		ASPHALT_GRID_COLOR,
	)


func _stamp_grid_line(
		parent: Node3D,
		a_xz: Vector2,
		b_xz: Vector2,
		y: float,
		color: Color = ASPHALT_GRID_COLOR,
) -> void:
	var a := Vector3(a_xz.x, y, a_xz.y)
	var b := Vector3(b_xz.x, y, b_xz.y)
	var span := a.distance_to(b)
	if span < 0.5:
		return
	var t := ASPHALT_GRID_LINE_THICK_M
	var edge := MeshBuilder.box(Vector3(t, t, span), color, 0.75, 0.0)
	var mat := edge.material_override as StandardMaterial3D
	if mat != null:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_receive_shadows = true
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(edge)
	_align_segment(edge, a, b)


func _polyline2(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in raw:
		var arr := point as Array
		if arr.size() >= 2:
			out.append(Vector2(float(arr[0]), float(arr[1])))
	return out


func _stamp_berth_plan_quays(plan: Dictionary) -> void:
	var roots := _ensure_layer(LAYER_QUAY_ROOTS)
	var arms := _ensure_layer(LAYER_QUAY_ARMS)
	for raw in plan.get("quay_stations", []) as Array:
		var station := raw as Dictionary
		var origin := _xz(station.get("origin", [0.0, 0.0]))
		var tip := _xz(station.get("tip", [origin.x, origin.y]))
		var family := str(station.get("family", "general"))
		var color := CommodityCatalog.terminal_family_color(family)
		_stamp_dot(roots, Vector3(origin.x, 6.0, origin.y), color, 4.2, "%s_root" % str(station.get("id", "quay")))
		_stamp_dot(arms, Vector3(tip.x, 5.0, tip.y), color.lightened(0.35), 2.8, "%s_tip" % str(station.get("id", "quay")))
		var length_m := float(station.get("length_m", origin.distance_to(tip)))
		var width_m := float(station.get("width_m", 12.0))
		var seaward := _xz(station.get("direction", [0.0, -1.0])).normalized()
		## Outline only — solid deck + crane live on the foundation visualizer.
		var outline := color
		outline.a = 0.35
		var arm := MeshBuilder.box(Vector3(width_m, 0.4, length_m), outline, 0.85, 0.05)
		arm.name = "%s_arm" % str(station.get("id", "quay"))
		arms.add_child(arm)
		arm.position = Vector3(
			(origin.x + tip.x) * 0.5,
			4.2,
			(origin.y + tip.y) * 0.5,
		)
		var tangent := _xz(station.get("tangent", [1.0, 0.0])).normalized()
		_align_basis_on_tangent(arm, tangent, seaward)
		var commodity_bits: PackedStringArray = []
		for commodity in station.get("commodities", []) as Array:
			commodity_bits.append(CommodityCatalog.commodity_display(str(commodity)))
		for side in station.get("sides", []) as Array:
			for commodity in (side as Dictionary).get("commodities", []) as Array:
				var name := CommodityCatalog.commodity_display(str(commodity))
				if not commodity_bits.has(name):
					commodity_bits.append(name)
		var layout_name := "twin quay" if str(station.get("layout", "")) == "twin_joined" \
				else CommodityCatalog.terminal_family_display(family)
		_label(
			roots,
			"%s_lbl" % str(station.get("id", "quay")),
			"%s\n%s\n%.0f×%.0f m" % [
				layout_name,
				", ".join(commodity_bits),
				width_m,
				length_m,
			],
			Vector3(origin.x, 18.0, origin.y) + Vector3(seaward.x, 0.0, seaward.y) * (length_m * 0.35),
			color,
		)


func _stamp_land_zone(plan: Dictionary) -> void:
	var layer := _ensure_layer(LAYER_LAND_ZONE)
	var zone: Dictionary = plan.get("buildable_zone", {}) as Dictionary
	if zone.is_empty():
		return
	var span_sea := float(zone.get("along_span_seaward_m", zone.get("along_span_m", 0.0)))
	var span_in := float(zone.get("along_span_inland_m", span_sea))
	var inland_depth := float(zone.get("inland_depth_m", 0.0))
	if span_sea < 1.0 or inland_depth < 1.0:
		return
	var origin := _xz(zone.get("origin", zone.get("center", [0.0, 0.0])))
	var along_dir := _xz(zone.get("along_dir", [1.0, 0.0])).normalized()
	var inland_dir := _xz(zone.get("inland_dir", [0.0, 1.0])).normalized()
	if along_dir.length_squared() < 0.01:
		along_dir = Vector2(1.0, 0.0)
	if inland_dir.length_squared() < 0.01:
		inland_dir = Vector2(0.0, 1.0)
	var h_sea := float(zone.get("height_seaward_m", 12.0))
	var h_in := float(zone.get("height_inland_m", 110.0))
	var y_base := 0.4
	## Inverse trapezoid: narrow at apron, blooms wider + taller into the hills.
	var volume := _make_rising_land_volume(
		span_sea,
		span_in,
		inland_depth,
		h_sea,
		h_in,
		LAND_ZONE_COLOR,
	)
	volume.name = "LandBuildableArea"
	layer.add_child(volume)
	## Bottom sits on apron; volume extends inland along +Z local after basis align.
	volume.position = Vector3(
		origin.x + inland_dir.x * inland_depth * 0.5,
		y_base,
		origin.y + inland_dir.y * inland_depth * 0.5,
	)
	## Local +Z = inland (rising / blooming edge).
	_align_basis_on_tangent(volume, along_dir, inland_dir)

	## Four corner markers only — no ribbon slats.
	for raw in zone.get("corners", []) as Array:
		var c := raw as Array
		if c.size() < 2:
			continue
		_stamp_dot(layer, Vector3(float(c[0]), y_base + 8.0, float(c[1])), LAND_ZONE_EDGE, 4.0, "LandCorner")

	var center_arr: Array = zone.get("center", [0.0, 0.0]) as Array
	var cx := float(center_arr[0]) if center_arr.size() > 0 else 0.0
	var cz := float(center_arr[1]) if center_arr.size() > 1 else 0.0
	_stamp_dot(layer, Vector3(cx, y_base + h_in * 0.55, cz), LAND_ZONE_EDGE, 5.5, "LandZoneCenter")
	_label(
		layer,
		"LandZoneLabel",
		"BUILDABLE AREA\n%.0f → %.0f m wide\n%.0f m inland · h %.0f→%.0f" % [
			span_sea,
			span_in,
			inland_depth,
			h_sea,
			h_in,
		],
		Vector3(cx, y_base + h_in + 18.0, cz),
		LAND_ZONE_EDGE.lightened(0.15),
	)


## Trapezoid footprint (narrow seaward → wide inland); top rises inland.
## Local space: X = along-shore, Z = inland (−hd seaward … +hd hills).
func _make_rising_land_volume(
		width_seaward_m: float,
		width_inland_m: float,
		depth_m: float,
		height_seaward_m: float,
		height_inland_m: float,
		color: Color,
) -> MeshInstance3D:
	var hw_sea := maxf(width_seaward_m, 4.0) * 0.5
	var hw_in := maxf(width_inland_m, hw_sea * 2.0) * 0.5
	var hd := depth_m * 0.5
	var z_sea := -hd
	var z_in := hd
	var hs := maxf(height_seaward_m, 2.0)
	var hi := maxf(height_inland_m, hs + 1.0)
	var verts := PackedVector3Array([
		## bottom
		Vector3(-hw_sea, 0.0, z_sea),
		Vector3(hw_sea, 0.0, z_sea),
		Vector3(hw_in, 0.0, z_in),
		Vector3(-hw_in, 0.0, z_in),
		## top (rises + blooms inland)
		Vector3(-hw_sea, hs, z_sea),
		Vector3(hw_sea, hs, z_sea),
		Vector3(hw_in, hi, z_in),
		Vector3(-hw_in, hi, z_in),
	])
	var faces := [
		[0, 1, 2, 3], ## bottom
		[4, 7, 6, 5], ## top
		[0, 4, 5, 1], ## seaward
		[3, 2, 6, 7], ## inland
		[0, 3, 7, 4], ## −X
		[1, 5, 6, 2], ## +X
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var a: Vector3 = verts[face[0]]
		var b: Vector3 = verts[face[1]]
		var c: Vector3 = verts[face[2]]
		var d: Vector3 = verts[face[3]]
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshBuilder.make_material(color, 0.95, 0.0)
	return mi


func _stamp_land_plan(plan: Dictionary) -> void:
	var layer := _ensure_layer(LAYER_LAND_STRUCTURES)
	if plan.is_empty():
		return
	for raw in plan.get("structures", []) as Array:
		var entry: Dictionary = raw
		var origin := _xz(entry.get("origin", [0.0, 0.0]))
		var size_arr: Array = entry.get("size_m", [10.0, 5.0, 8.0]) as Array
		var size := Vector3(
			float(size_arr[0]) if size_arr.size() > 0 else 10.0,
			float(size_arr[1]) if size_arr.size() > 1 else 5.0,
			float(size_arr[2]) if size_arr.size() > 2 else 8.0,
		)
		var color_arr: Array = entry.get("color", [0.5, 0.5, 0.45]) as Array
		var color := Color(
			float(color_arr[0]) if color_arr.size() > 0 else 0.5,
			float(color_arr[1]) if color_arr.size() > 1 else 0.5,
			float(color_arr[2]) if color_arr.size() > 2 else 0.45,
		)
		color.a = 0.55
		var box := MeshBuilder.box(size, color, 0.9, 0.0)
		box.name = str(entry.get("id", "land"))
		layer.add_child(box)
		box.position = Vector3(origin.x, 2.0 + size.y * 0.5, origin.y)
		box.rotation.y = deg_to_rad(float(entry.get("yaw_degrees", 0.0)))
		_stamp_dot(layer, Vector3(origin.x, 8.0, origin.y), color.lightened(0.2), 2.4, str(entry.get("id", "land")))
		_label(
			layer,
			"%s_lbl" % str(entry.get("id", "land")),
			"%s\n%s" % [
				str(entry.get("label", entry.get("kind", "land"))),
				str(entry.get("band", "")).to_upper(),
			],
			Vector3(origin.x, 14.0 + size.y, origin.y),
			color.lightened(0.25),
		)


func _xz(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))


## Box local Z = seaward, local X = alongshore tangent.
func _align_basis_on_tangent(node: Node3D, tangent: Vector2, seaward: Vector2) -> void:
	var z_axis := Vector3(seaward.x, 0.0, seaward.y)
	if z_axis.length_squared() < 0.001:
		z_axis = Vector3(0.0, 0.0, -1.0)
	else:
		z_axis = z_axis.normalized()
	var x_axis := Vector3(tangent.x, 0.0, tangent.y)
	if x_axis.length_squared() < 0.001:
		x_axis = Vector3.UP.cross(z_axis).normalized()
	else:
		x_axis = x_axis.normalized()
	## Re-orthogonalise if tangent wasn't perpendicular.
	x_axis = Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	node.basis = Basis(x_axis, y_axis, z_axis)


func _ensure_layer(layer_id: String) -> Node3D:
	var existing := get_node_or_null(layer_id) as Node3D
	if existing != null:
		return existing
	var layer := Node3D.new()
	layer.name = layer_id
	add_child(layer)
	return layer


func _apply_layer_visibility() -> void:
	for layer_id in LAYER_IDS:
		var layer := get_node_or_null(layer_id) as Node3D
		if layer != null:
			layer.visible = is_layer_visible(layer_id)


func _normalized_layers(raw: Dictionary) -> Dictionary:
	var out := default_layers(false)
	for layer_id in LAYER_IDS:
		if raw.has(layer_id):
			out[layer_id] = bool(raw[layer_id])
	return out


func _stamp_origin(
		parent: Node3D,
		size: int,
		half_w: float,
		half_d: float,
		trace_w: float,
		trace_d: float,
) -> void:
	var pole := MeshBuilder.cylinder(1.8, 28.0, ORIGIN_COLOR, 0.7, 0.1)
	pole.name = "PortOrigin"
	pole.position = Vector3(0.0, 14.0, 0.0)
	parent.add_child(pole)
	_stamp_dot(parent, Vector3.ZERO, ORIGIN_COLOR, 4.5, "OriginDot")
	_label(
		parent,
		"OriginLabel",
		"PORT ORIGIN (registered site)\nsize %d · area %.0f×%.0f m\nscan %.0f×%.0f m" % [
			size,
			half_w * 2.0,
			half_d * 2.0,
			trace_w * 2.0,
			trace_d * 2.0,
		],
		Vector3(0.0, 34.0, 0.0),
		ORIGIN_COLOR,
	)


func _stamp_axis_arrow(
		parent: Node3D,
		direction: Vector3,
		length_m: float,
		color: Color,
		text: String,
) -> void:
	var shaft := MeshBuilder.box(Vector3(1.2, 1.2, length_m), color, 0.75, 0.0)
	shaft.name = "Axis_%s" % text
	shaft.position = direction * (length_m * 0.5) + Vector3(0.0, 2.0, 0.0)
	parent.add_child(shaft)
	_label(parent, "AxisLabel_%s" % text, text, shaft.position + Vector3(0.0, 8.0, 0.0), color)


func _stamp_ground_rect(
		parent: Node3D,
		node_name: String,
		half_x: float,
		half_z: float,
		color: Color,
		y: float,
) -> void:
	if half_x < 1.0 or half_z < 1.0:
		return
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	var thickness := 1.4
	var y_pos := y
	var corners := [
		Vector3(-half_x, y_pos, -half_z),
		Vector3(half_x, y_pos, -half_z),
		Vector3(half_x, y_pos, half_z),
		Vector3(-half_x, y_pos, half_z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[0, 2], [1, 3],
	]
	for pair in edges:
		var a: Vector3 = corners[pair[0]]
		var b: Vector3 = corners[pair[1]]
		var edge := MeshBuilder.box(Vector3(thickness, thickness, a.distance_to(b)), color, 0.8, 0.0)
		root.add_child(edge)
		_align_segment(edge, a, b)
	_label(
		parent,
		"%sLabel" % node_name,
		node_name.replace("Box", " box ") + " %.0f × %.0f m" % [half_x * 2.0, half_z * 2.0],
		Vector3(0.0, y + 10.0, -half_z - 12.0),
		color,
	)


func _stamp_polyline_dots(
		parent: Node3D,
		points: Array,
		color: Color,
		radius: float,
		prefix: String,
) -> void:
	for index in range(points.size()):
		var raw := points[index] as Array
		if raw.size() < 2:
			continue
		var pos := Vector3(float(raw[0]), 3.0, float(raw[1]))
		_stamp_dot(parent, pos, color, radius, "%s_%d" % [prefix, index])


func _stamp_polyline_lines(
		parent: Node3D,
		points: Array,
		color: Color,
		thickness: float,
) -> void:
	if points.size() < 2:
		return
	for index in range(points.size() - 1):
		var a_raw := points[index] as Array
		var b_raw := points[index + 1] as Array
		if a_raw.size() < 2 or b_raw.size() < 2:
			continue
		var a := Vector3(float(a_raw[0]), 4.0, float(a_raw[1]))
		var b := Vector3(float(b_raw[0]), 4.0, float(b_raw[1]))
		var span := a.distance_to(b)
		if span < 0.5:
			continue
		var edge := MeshBuilder.box(Vector3(thickness, thickness, span), color, 0.75, 0.0)
		parent.add_child(edge)
		_align_segment(edge, a, b)


## Box meshes are authored length-on-local-Z; align -Z from midpoint → b without look_at tree quirks.
func _align_segment(node: Node3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var span := delta.length()
	if span < 0.001:
		return
	var direction := delta / span
	node.position = (a + b) * 0.5
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.999:
		up = Vector3.FORWARD
	node.basis = Basis.looking_at(direction, up)


func _stamp_dot(parent: Node3D, position: Vector3, color: Color, radius: float, node_name: String) -> void:
	var dot := MeshBuilder.sphere(radius, color, 0.7, 0.05)
	dot.name = node_name
	dot.position = position
	parent.add_child(dot)


## Bright unshaded stake — readable on black unlit apron / pad surfaces.
func _stamp_grid_stake(parent: Node3D, position: Vector3, node_name: String) -> void:
	var dot := MeshBuilder.sphere(ASPHALT_GRID_DOT_R, ASPHALT_GRID_COLOR, 0.7, 0.0)
	dot.name = node_name
	dot.position = position
	var mat := dot.material_override as StandardMaterial3D
	if mat != null:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_receive_shadows = true
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(dot)


func _label(parent: Node3D, node_name: String, text: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.position = position
	label.pixel_size = 0.018
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 6
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	parent.add_child(label)
