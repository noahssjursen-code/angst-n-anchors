class_name PassengerPortSites
extends RefCounted

## Additive terminal siting against the existing harbour, without changing its
## graph, terrain, cargo berths or geographic checksum. No scene work at boot.
const DECK_Y := WaveSurface.WATER_LEVEL + 1.65
const SHORE_RAMP_LENGTH := 6.0

static func plan(graph: PortLayoutGraph, world_frame: Transform3D, layout: WorldLayout) -> Dictionary:
	if graph == null or layout == null: return {}
	var foundation: Dictionary = graph.initial_attributes.get("foundation", {})
	var spine := PackedVector2Array()
	for p: Array in foundation.get("spine", []): spine.append(_v(p))
	if spine.size()<2: return {}
	# Use the actual pavement edge, including the bay lip, not the berth plan's
	# inset dock-face guide (which lies six metres inside the solid foundation).
	var face := PortCoastTracer.offset_spine_perpendicular(spine,
		float(foundation.get("dock_reach_m",26))+float(foundation.get("bay_lip_m",6)),Vector2(0,1),false)
	var shore_y := float(foundation.get("surface_y_m", .62)) + PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var rise := world_frame.origin.y + shore_y - DECK_Y
	if absf(rise) > SHORE_RAMP_LENGTH * sin(deg_to_rad(10)): return {}
	var run := sqrt(SHORE_RAMP_LENGTH*SHORE_RAMP_LENGTH-rise*rise)
	var stations: Dictionary = graph.initial_attributes.get("berth_plan", {})
	var keepouts: Array[PackedVector2Array] = []
	for s: Dictionary in stations.get("quay_stations", []):
		var direction := _v(s.direction).normalized()
		# Reserve both cargo-side vessel pockets and the turning space at the tip.
		keepouts.append(_rectangle(_v(s.origin), direction, float(s.width_m)*.5+32, -8, float(s.length_m)+35))
	for s: Dictionary in stations.get("asphalt_stations", []):
		keepouts.append(_rectangle(_v(s.origin), _v(s.direction).normalized(), float(s.length_m)*.5+25, -float(s.depth_m), 40))
	for i in range(face.size()-1):
		var a := face[i]; var b := face[i+1]
		var along := (b-a).normalized()
		var sea := Vector2(along.y,-along.x)
		if sea.dot(Vector2(0,-1)) < 0: sea = -sea
		var length := a.distance_to(b)
		for step in range(1, maxi(2,int(length/8))):
			var at := a.lerp(b,float(step)/maxi(2,int(length/8)))
			# Enough straight frontage for the four-metre accessible connection.
			if minf(at.distance_to(a),at.distance_to(b)) < 5: continue
			var pocket := _rectangle(at,sea,17,-2,125)
			var blocked := false
			for area in keepouts:
				if not Geometry2D.intersect_polygons(pocket,area).is_empty(): blocked=true; break
			if blocked: continue
			# Sample the whole hull and reverse-out corridor, not just a centre point.
			for depth in [30.0,45.0,65.0,85.0,110.0,125.0]:
				for side in [-14.0,0.0,14.0]:
					var point: Vector2 = at+sea*depth+along*side
					var world := world_frame*Vector3(point.x,0,point.y)
					if layout.sample_height(Vector2(world.x,world.z)) > WaveSurface.WATER_LEVEL-2.5:
						blocked=true; break
				if blocked: break
			if blocked: continue
			# Terminal local +Z faces open water. Its rear is at -43m.
			var anchor := at+sea*(43+run-.15)
			return {"version":1,"position":[anchor.x,DECK_Y-world_frame.origin.y,anchor.y],
				"yaw":atan2(sea.x,sea.y),"shore_rise":rise,"shore_run":run,
				"shore":[at.x,shore_y,at.y],"clearance_polygon":Array(pocket)}
	return {}

static func install(parent: Node3D, harbour: HarbourController, site: Dictionary) -> PassengerTerminal:
	if site.is_empty() or harbour == null: return null
	var terminal := PassengerTerminal.new()
	terminal.name="PassengerTerminal"
	terminal.shore_rise=float(site.shore_rise)
	terminal.shore_connection=true
	terminal.position=Vector3(site.position[0],site.position[1],site.position[2])
	terminal.rotation.y=float(site.yaw)
	parent.add_child(terminal)
	terminal.register_berth(harbour)
	if PassengerOperations.current(parent.get_tree()) != null:
		var agent := PassengerAgentNpc.new()
		agent.name = "PassengerAgent"
		agent.port_id = harbour.port_id()
		agent.position = Vector3(4, 0, -27)
		terminal.add_child(agent)
	return terminal

static func _v(a: Array) -> Vector2:
	return Vector2(a[0],a[1])

static func _rectangle(at: Vector2, sea: Vector2, half_width: float, start: float, end: float) -> PackedVector2Array:
	var along := Vector2(sea.y,-sea.x)
	return PackedVector2Array([at+sea*start-along*half_width,at+sea*start+along*half_width,
		at+sea*end+along*half_width,at+sea*end-along*half_width])
