class_name VesselNavigationDebugDraw
extends Node3D

## F3/G navigation layer. Draws the route actually consumed by each shared
## VesselAutopilot, plus traffic agreements and port holding positions.

# Most route geometry is static. Rebuilding ArrayMeshes several times per second
# was itself a substantial debug-mode performance cost with a multi-ship fleet.
const REFRESH_S := 1.5
const LINE_Y := 5.5
const PLAYER_COLOR := Color(1.0, 0.62, 0.18, 0.96)
const NPC_COLOR := Color(0.18, 0.86, 1.0, 0.94)
const TARGET_COLOR := Color(1.0, 0.2, 0.78, 0.98)
const AGREEMENT_COLOR := Color(1.0, 0.18, 0.12, 0.98)
const HOLDING_COLOR := Color(0.72, 0.45, 1.0, 0.90)
const DEPARTURE_COLOR := Color(1.0, 0.58, 0.16, 0.98)
const PASSAGE_COLOR := Color(0.12, 0.82, 1.0, 0.98)
const ARRIVAL_COLOR := Color(0.30, 1.0, 0.48, 0.98)

var _elapsed_s := 0.0


func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("vessel_navigation_debug")
	WorldGizmos.register(self, WorldGizmos.LAYER_NAVIGATION)
	set_process(visible)
	if visible:
		_rebuild()


func set_layer_visible(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	if enabled:
		_rebuild()
	else:
		_clear()


func _process(delta: float) -> void:
	_elapsed_s += delta
	if _elapsed_s < REFRESH_S:
		return
	_elapsed_s = 0.0
	_rebuild()


func _rebuild() -> void:
	_clear()
	var live_ids: Dictionary = {}
	for raw in get_tree().get_nodes_in_group("vessel_traffic_agent"):
		var agent := raw as Node
		var boat := agent.get_parent() as BoatBody if agent != null else null
		if boat == null or not is_instance_valid(boat):
			continue
		var canonical_id := HarbourController.ship_id_of(boat)
		if not canonical_id.is_empty():
			live_ids[canonical_id] = true
		# Keep the drawer tolerant of vessels spawned before the canonical company
		# identity was introduced. This prevents a live path and its dormant
		# timestamp projection from ever being painted together.
		var company_uid := str(boat.get_meta("company_vessel_uid", "")).strip_edges()
		if not company_uid.is_empty():
			live_ids[company_uid] = true
		_draw_vessel_navigation(boat)
	_draw_dormant_company_routes(live_ids)
	_draw_traffic_authority()


func _draw_vessel_navigation(boat: BoatBody) -> void:
	var autopilot := boat.get_node_or_null("VesselAutopilot") as VesselAutopilot
	var captain := boat.get_node_or_null("AutonomousVesselCaptain") as AutonomousVesselCaptain
	if autopilot == null and captain == null:
		return
	var is_player := boat.is_in_group(PlayerVessel.GROUP)
	var color := PLAYER_COLOR if is_player else NPC_COLOR
	if autopilot != null and autopilot.route != null and autopilot.route.is_valid():
		var route_id := HarbourController.ship_id_of(boat)
		if autopilot.route.has_berth_handoffs():
			_draw_segmented_route(autopilot.route, route_id)
			_add_polyline(PackedVector3Array([
				_lift(Vector2(boat.global_position.x, boat.global_position.z), 0.5),
				_lift(autopilot.route.point_at_distance(autopilot.progress_m), 0.5),
			]), Color(color, 0.62), "RouteRecovery_%s" % route_id)
		else:
			var points := _remaining_route_points(boat, autopilot)
			_add_polyline(points, color, "Route_%s" % route_id)
		if autopilot.target_point.is_finite():
			_add_polyline(PackedVector3Array([
				_lift(Vector2(boat.global_position.x, boat.global_position.z), 1.0),
				_lift(autopilot.target_point, 1.0),
			]), TARGET_COLOR, "Target_%s" % HarbourController.ship_id_of(boat))
	var phase_text := _vessel_state_text(boat, captain, autopilot)
	var instruction := autopilot.traffic_instruction if autopilot != null else ""
	var label := Label3D.new()
	label.name = "VesselLabel"
	label.text = "%s\n%s%s  |  PHYS %s" % [
		str(boat.get_meta("vessel_display_name", "PLAYER VESSEL" if is_player else "NPC VESSEL")),
		phase_text,
		"  |  %s" % instruction.replace("_", " ").to_upper() if not instruction.is_empty() else "",
		boat.get_physics_quality_name(),
	]
	label.position = boat.global_position + Vector3(0.0, 10.0, 0.0)
	label.font_size = 30
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 6
	add_child(label)


func _vessel_state_text(
		boat: BoatBody,
		captain: AutonomousVesselCaptain,
		autopilot: VesselAutopilot,
) -> String:
	if captain == null:
		return "AUTOPILOT" if autopilot != null and autopilot.is_engaged() else "MANUAL"
	var destination := _port_name(captain.destination_port_id)
	var snapshot := captain.authority_snapshot()
	var queue_position := int(snapshot.get("arrival_queue_position", 0))
	match captain.phase:
		AutonomousVesselCaptain.Phase.RESERVING:
			return "RESERVING DEPARTURE"
		AutonomousVesselCaptain.Phase.CASTING_OFF:
			return "UNDOCKING · CASTING OFF"
		AutonomousVesselCaptain.Phase.CRAB_CLEAR:
			return "UNDOCKING · CLEARING QUAY"
		AutonomousVesselCaptain.Phase.DEPARTURE:
			return "DEPARTING FOR %s" % destination
		AutonomousVesselCaptain.Phase.PASSAGE:
			return "TRAVELING TO %s" % destination
		AutonomousVesselCaptain.Phase.WAITING_APPROACH, \
		AutonomousVesselCaptain.Phase.HOLDING:
			return "WAITING FOR DOCK · QUEUE #%d" % queue_position if queue_position > 0 \
				else "WAITING FOR AVAILABLE DOCK"
		AutonomousVesselCaptain.Phase.APPROACH:
			return "APPROACHING %s" % destination
		AutonomousVesselCaptain.Phase.ALIGNING:
			return "ALIGNING WITH QUAY"
		AutonomousVesselCaptain.Phase.CRAB_BERTH:
			return "CRABBING INTO BERTH"
		AutonomousVesselCaptain.Phase.SECURING:
			return "SECURING MOORING LINES"
		AutonomousVesselCaptain.Phase.MOORED:
			return "MOORED AT %s" % destination
		AutonomousVesselCaptain.Phase.FAILED:
			return "NAVIGATION FAILED"
		_:
			return AutonomousVesselCaptain.Phase.keys()[captain.phase].replace("_", " ")


func _port_name(port_id: String) -> String:
	if port_id.is_empty():
		return "DESTINATION"
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog != null:
		var info := catalog.get_port_info(port_id) as Dictionary
		var display := str(info.get("name", "")).strip_edges()
		if not display.is_empty():
			return display.to_upper()
	return port_id.replace("_", " ").to_upper()


func _remaining_route_points(boat: BoatBody, autopilot: VesselAutopilot) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.append(_lift(Vector2(boat.global_position.x, boat.global_position.z)))
	points.append(_lift(autopilot.route.point_at_distance(autopilot.progress_m)))
	for index in range(autopilot.route.waypoints.size()):
		if float(autopilot.route.cumulative_distance_m[index]) <= autopilot.progress_m:
			continue
		points.append(_lift(autopilot.route.waypoints[index]))
	return points


func _draw_dormant_company_routes(live_ids: Dictionary) -> void:
	var fleet_projection := get_node_or_null("/root/CompanyFleetProjection")
	if fleet_projection == null or not fleet_projection.has_method("all_projection_records"):
		return
	for raw in fleet_projection.call("all_projection_records") as Array[Dictionary]:
		var record := raw as Dictionary
		var uid := str(record.get("uid", ""))
		if live_ids.has(uid):
			continue
		var assignment := record.get("assignment", {}) as Dictionary
		if str(assignment.get("status", "")) != "underway":
			continue
		var plan := fleet_projection.call("leg_route_plan", uid) as MarineRoutePlan
		var projection := record.get("projection", {}) as Dictionary
		var position := projection.get("position", Vector3.ZERO) as Vector3
		var progress := float(projection.get("route_progress_m", 0.0))
		if plan == null or not plan.is_valid():
			continue
		if plan.has_berth_handoffs():
			_draw_segmented_route(plan, "Dormant_%s" % uid, 0.48)
		else:
			var points := PackedVector3Array([_lift(Vector2(position.x, position.z))])
			points.append(_lift(plan.point_at_distance(progress)))
			for index in range(plan.waypoints.size()):
				if float(plan.cumulative_distance_m[index]) > progress:
					points.append(_lift(plan.waypoints[index]))
			_add_polyline(points, Color(NPC_COLOR, 0.48), "DormantRoute_%s" % uid)
		var label := Label3D.new()
		label.text = "NPC AUTHORITY  |  DORMANT PROJECTION"
		label.position = position + Vector3(0.0, 10.0, 0.0)
		label.font_size = 28
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(NPC_COLOR, 0.62)
		label.outline_size = 6
		add_child(label)


func _draw_segmented_route(plan: MarineRoutePlan, vessel_id: String, alpha: float = 1.0) -> void:
	var departure := plan.departure_handoff_m
	var arrival := plan.arrival_handoff_m
	_add_polyline(_route_section(plan, 0.0, departure), Color(DEPARTURE_COLOR, alpha),
		"Departure_%s" % vessel_id)
	_add_polyline(_route_section(plan, departure, arrival), Color(PASSAGE_COLOR, alpha),
		"Passage_%s" % vessel_id)
	_add_polyline(_route_section(plan, arrival, plan.total_distance_m()), Color(ARRIVAL_COLOR, alpha),
		"Arrival_%s" % vessel_id)
	_add_handoff_sphere(plan.departure_handoff_xz, Color(DEPARTURE_COLOR, alpha),
		"DEPARTURE HANDOFF", "DepartureHandoff_%s" % vessel_id)
	_add_handoff_sphere(plan.arrival_handoff_xz, Color(ARRIVAL_COLOR, alpha),
		"ARRIVAL HANDOFF", "ArrivalHandoff_%s" % vessel_id)


func _route_section(plan: MarineRoutePlan, start_m: float, end_m: float) -> PackedVector3Array:
	var start := clampf(start_m, 0.0, plan.total_distance_m())
	var finish := clampf(end_m, start, plan.total_distance_m())
	var points := PackedVector3Array([_lift(plan.point_at_distance(start))])
	for index in range(plan.waypoints.size()):
		var distance := float(plan.cumulative_distance_m[index])
		if distance <= start or distance >= finish:
			continue
		points.append(_lift(plan.waypoints[index]))
	points.append(_lift(plan.point_at_distance(finish)))
	return points


func _add_handoff_sphere(point: Vector2, color: Color, text: String, node_name: String) -> void:
	if not point.is_finite():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 5.0
	mesh.height = 10.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = _lift(point, 2.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	instance.material_override = material
	add_child(instance)
	var label := Label3D.new()
	label.text = text
	label.position = _lift(point, 10.0)
	label.font_size = 24
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 6
	add_child(label)


func _draw_traffic_authority() -> void:
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	if traffic == null:
		return
	var snapshot: Dictionary = traffic.snapshot()
	var intents := snapshot.get("intents", {}) as Dictionary
	for raw in (snapshot.get("agreements", {}) as Dictionary).values():
		var agreement := raw as Dictionary
		var ids := agreement.get("vessel_ids", []) as Array
		if ids.size() < 2:
			continue
		var a := intents.get(str(ids[0]), {}) as Dictionary
		var b := intents.get(str(ids[1]), {}) as Dictionary
		var pa := a.get("position_xz", []) as Array
		var pb := b.get("position_xz", []) as Array
		if pa.size() >= 2 and pb.size() >= 2:
			_add_polyline(PackedVector3Array([
				_lift(Vector2(float(pa[0]), float(pa[1])), 2.0),
				_lift(Vector2(float(pb[0]), float(pb[1])), 2.0),
			]), AGREEMENT_COLOR, "TrafficAgreement")
	for zones_raw in (snapshot.get("holding_zones", {}) as Dictionary).values():
		for point_raw in zones_raw as Array:
			var point := point_raw as Array
			if point.size() < 2:
				continue
			var center := Vector2(float(point[0]), float(point[1]))
			var radius := 16.0
			_add_polyline(PackedVector3Array([
				_lift(center + Vector2(-radius, 0.0)), _lift(center + Vector2(radius, 0.0)),
			]), HOLDING_COLOR, "HoldingCross")
			_add_polyline(PackedVector3Array([
				_lift(center + Vector2(0.0, -radius)), _lift(center + Vector2(0.0, radius)),
			]), HOLDING_COLOR, "HoldingCross")
	for raw in (snapshot.get("blocks", {}) as Dictionary).values():
		var block := raw as Dictionary
		if str(block.get("kind", "")) != "shipping_lane":
			continue
		var center_raw := block.get("center_xz", []) as Array
		if center_raw.size() < 2:
			continue
		var center := Vector2(float(center_raw[0]), float(center_raw[1]))
		var half := MaritimeTrafficService.LANE_BLOCK_SIZE_M * 0.5
		var owners := block.get("owner_vessel_ids", []) as Array
		var queue := block.get("queue", []) as Array
		var color := Color(0.25, 1.0, 0.42, 0.72) if queue.is_empty() \
			else Color(1.0, 0.25, 0.12, 0.82)
		_add_polyline(PackedVector3Array([
			_lift(center + Vector2(-half, -half), 0.4),
			_lift(center + Vector2(half, -half), 0.4),
			_lift(center + Vector2(half, half), 0.4),
			_lift(center + Vector2(-half, half), 0.4),
			_lift(center + Vector2(-half, -half), 0.4),
		]), color, "ShippingLaneBlock")
		var label := Label3D.new()
		label.text = "LANE SIGNAL  %s\n%d/%d IN BLOCK · %d WAITING" % [
			"→" if int(block.get("direction", 1)) > 0 else "←",
			owners.size(), int(block.get("capacity", 1)), queue.size(),
		]
		label.position = _lift(center, 8.0)
		label.font_size = 22
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = color
		label.outline_size = 5
		add_child(label)


func _add_polyline(points: PackedVector3Array, color: Color, node_name: String) -> void:
	if points.size() < 2:
		return
	var vertices := PackedVector3Array()
	for index in range(points.size() - 1):
		vertices.append(points[index])
		vertices.append(points[index + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	instance.material_override = material
	add_child(instance)


func _clear() -> void:
	for child in get_children():
		child.free()


static func _lift(point: Vector2, extra_y: float = 0.0) -> Vector3:
	return Vector3(point.x, WaveSurface.WATER_LEVEL + LINE_Y + extra_y, point.y)
