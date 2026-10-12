class_name CoastalBridges
extends Node3D

signal structures_ready(structures: Array)

## One world-owned worker plans data. Main thread assembles one bridge per frame.
var report: Dictionary = {}
var _worker: Thread
var _layout: WorldLayout
var _ports: Array
var _settlements: Array
var _pending: Array = []
var _zones: Array = []
var _roads: Array = []
var _mutex := Mutex.new()
var _completed: Array = []
var _reference := Vector2.ZERO
var _nodes: Dictionary = {}
var _refresh := 0.0
var planning_complete := false
const LOAD_DISTANCE := 12000.0
const UNLOAD_DISTANCE := 13500.0

static func distance_to_plan(at: Vector2, plan: Dictionary) -> float:
	var points := PackedVector2Array([Vector2(plan.approaches[0].x,plan.approaches[0].z),plan.a,plan.b,Vector2(plan.approaches[1].x,plan.approaches[1].z)])
	var distance := INF
	for i in points.size()-1:
		distance=minf(distance,at.distance_to(Geometry2D.get_closest_point_to_segment(at,points[i],points[i+1])))
	return distance

func configure(layout: WorldLayout, ports: Array, settlements: Array = [], zones: Array = [], roads: Array = []) -> void:
	_zones=zones.duplicate(true); _roads=roads.duplicate(true)
	_layout=layout; _ports=ports.duplicate(); _settlements=settlements.duplicate(true)

func _ready() -> void:
	_worker=Thread.new()
	_worker.start(_plan)

func _plan() -> Dictionary:
	var result := CoastalBridgePlan.build(_layout,_ports,_settlements)
	result.structures=[]
	result.rejected=[]
	var remaining: Array = result.bridges.duplicate()
	while not remaining.is_empty():
		var crossing: Dictionary = remaining.pop_front()
		var started := Time.get_ticks_usec()
		var structure := BridgeStructurePlan.design(crossing,_layout,"",_zones,_roads)
		if structure.accepted and conflicts_with(structure,result.structures):
			structure={"accepted":false,"reason":"Crossing or overlapping bridge approaches"}
		if not structure.accepted:
			for option: Dictionary in result.get("alternatives",{}).get(crossing.id,[]):
				structure=BridgeStructurePlan.design(option,_layout,"",_zones,_roads)
				if structure.accepted and conflicts_with(structure,result.structures):
					structure={"accepted":false,"reason":"Crossing or overlapping bridge approaches"}
				if structure.accepted: break
		if structure.accepted:
			structure["planning_ms"]=(Time.get_ticks_usec()-started)/1000.0
			result.structures.append(structure)
			_mutex.lock()
			_completed.append(structure)
			_mutex.unlock()
			result.bridges[result.bridges.find(crossing)]=structure.source
		else: result.rejected.append({"id":crossing.id,"reason":structure.reason})
	return result

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var position_3d := WorldReference.visual_position(get_viewport()) if camera != null else Vector3.ZERO
	var at := Vector2(position_3d.x,position_3d.z)
	_mutex.lock()
	_reference=at
	var ready: Array = _completed.duplicate()
	_completed.clear()
	_mutex.unlock()
	if not ready.is_empty():
		_pending.append_array(ready)
		structures_ready.emit(ready)
	if _worker!=null and not _worker.is_alive():
		report=_worker.wait_to_finish(); _worker=null
		planning_complete=true
		_mutex.lock()
		_pending.append_array(_completed)
		if not _completed.is_empty(): structures_ready.emit(_completed.duplicate())
		_completed.clear()
		_mutex.unlock()
		var gizmos := Node3D.new()
		gizmos.name="BridgeCandidates"
		add_child(gizmos)
		CoastalBridgePreview.populate(gizmos,report)
		WorldGizmos.register(gizmos,WorldGizmos.LAYER_BRIDGES)
		print("BRIDGE STRUCTURES accepted=",report.structures.size()," rejected=",report.rejected.size())
	_refresh-=delta
	if _refresh<=0 or not ready.is_empty():
		_refresh=.25
		_pending.sort_custom(func(a:Dictionary,b:Dictionary):return distance_to_plan(at,a)<distance_to_plan(at,b))
		for id in _nodes:
			var node: Node3D = _nodes[id]
			var distance := distance_to_plan(at,node.get_meta("bridge_plan"))
			if node.visible: node.visible=distance<UNLOAD_DISTANCE
			else: node.visible=distance<LOAD_DISTANCE
			var body := node.get_node("BridgeCollision") as StaticBody3D
			body.collision_layer=1 if distance<1500 or camera==null else 0
	if not _pending.is_empty() and (camera==null or distance_to_plan(at,_pending[0])<LOAD_DISTANCE):
		var plan:Dictionary=_pending.pop_front()
		var started := Time.get_ticks_usec()
		var node := BridgeAssembler.build(plan)
		add_child(node)
		_nodes[plan.source.id]=node
		print("BRIDGE BUILD id=",plan.source.id," plan_ms=",plan.planning_ms," mesh_ms=",(Time.get_ticks_usec()-started)/1000.0)
	# Headless validation drains every bridge. Live scenes keep polling the camera.
	if camera==null and planning_complete and _pending.is_empty(): set_process(false)

func _exit_tree() -> void:
	if _worker!=null: _worker.wait_to_finish(); _worker=null

static func conflicts_with(plan: Dictionary, accepted: Array) -> bool:
	var path := _path(plan)
	for other:Dictionary in accepted:
		var other_path := _path(other)
		for i in path.size()-1:
			for j in other_path.size()-1:
				var a:=path[i];var b:=path[i+1]
				var c:=other_path[j];var d:=other_path[j+1]
				if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return true
				if minf(minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)),b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))),minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)),d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))))<40: return true
	return false

static func _path(plan:Dictionary)->PackedVector2Array:
	return PackedVector2Array([Vector2(plan.approaches[0].x,plan.approaches[0].z),plan.a,plan.b,Vector2(plan.approaches[1].x,plan.approaches[1].z)])
