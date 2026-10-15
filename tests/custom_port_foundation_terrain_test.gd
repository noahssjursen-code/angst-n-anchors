extends Node
const GROUND = preload("res://scripts/port/building/custom_port_foundation_terrain.gd")
const EDITOR = preload("res://scripts/port/building/custom_port_editor.gd")
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	var catalog := CustomPortCatalog.definitions()
	var origin := Vector3(1000, .5, 2000)
	for id in ["foundation", "foundation_8m", "quay", "foundation_triangle_4m", "quay_triangle_4m", "foundation_chamfer_4m"]:
		if not catalog.has(id): continue
		for yaw in [0, 90, 180, 270]:
			var placement := CustomPortCatalog.placement("p", id, Vector3.ZERO, yaw)
			_check(GROUND.fully_buried(placement, catalog[id], origin, func(_p: Vector2): return 10.0, 25), id + " buried at rotation " + str(yaw))
			_check(not GROUND.fully_buried(placement, catalog[id], origin, func(_p: Vector2): return -10.0, 25), id + " remains buildable over water")
	var row := CustomPortCatalog.placement("p", "foundation_8m", Vector3.ZERO)
	_check(not GROUND.fully_buried(row, catalog.foundation_8m, origin, func(_p: Vector2): return .5, 25), "Deck-level ground is not fully buried")
	_check(not GROUND.fully_buried(row, catalog.foundation_8m, origin, func(p: Vector2): return p.x - 998.0, 25), "Exposed shoreline edge survives even with buried centre")
	# A terrain-grid valley inside the pad, with all four pad corners uphill.
	_check(not GROUND.fully_buried(row, catalog.foundation_8m, origin, func(p: Vector2): return absf(p.x-1000)+absf(p.y-2000)-1.0, 2), "Interior exposed terrain vertex prevents a false burial rejection")
	var triangle := CustomPortCatalog.placement("triangle", "foundation_triangle_4m", Vector3.ZERO)
	var polygon: PackedVector2Array = CustomPortPlacementRules.polygons(triangle, catalog.foundation_triangle_4m)[0]
	var height := func(p: Vector2):
		return 10.0 if Geometry2D.is_point_in_polygon(p-Vector2(origin.x,origin.z),polygon) or _on_edge(p-Vector2(origin.x,origin.z),polygon) else -10.0
	_check(GROUND.fully_buried(triangle,catalog.foundation_triangle_4m,origin,height,25), "A triangle's absent corner is not considered exposed surface")
	var snapshot := {"schema_version":1,"id":"ground-test","owner_company_id":"builder","world":{"seed":1,"generation_version":1,"checksum":"coast"},
		"origin_m":[1000,.5,2000],"deck_height_above_sea_m":2,"plots":[{"id":"plot","owner_company_id":"builder","rect_m":[-100,-100,200,200]}],
		"placements":[],"stores":[],"vessels":[]}
	var state := CustomPortState.from_dict(snapshot,snapshot.world,catalog)
	var editor := EDITOR.new()
	editor.configure(state,catalog,"builder")
	editor.configure_terrain(func(p: Vector2): return 10.0 if p.x >= 1008 else -5.0,25)
	var before := state.to_dict()
	var buried := editor.preview("foundation",Vector3(13,0,1))
	_check(not buried.ok and buried.message == GROUND.BURIED_MESSAGE,"Preview clearly rejects a buried tile")
	_check(state.to_dict()==before,"Preview does not change the port")
	buried.ok=true
	_check(not editor.place(buried).ok and state.to_dict()==before,"Commit rechecks terrain even if proposal is forged")
	editor.begin_edit()
	_check(editor.place_asset("foundation",Vector3(1,0,1)).ok,"Stroke places an exposed tile")
	_check(not editor.place_asset("foundation",Vector3(13,0,1)).ok,"Stroke skips buried tile")
	_check(editor.place_asset("foundation",Vector3(5,0,1)).ok,"Stroke continues past a skipped tile")
	editor.end_edit()
	_check(state.to_dict().placements.size()==2 and editor.undo_count()==1,"Only accepted tiles enter one undo group")
	var original: Dictionary=state.to_dict().placements[0]
	var moved := editor.preview_transform(str(original.id),Vector3(17,0,1))
	_check(not moved.ok,"Moving a tile underground is rejected")
	moved.ok=true
	_check(not editor.transform(moved).ok,"Moving also rechecks terrain at commit")
	_check(editor.undo().ok and state.to_dict().placements.is_empty(),"Undo removes exactly the placed stroke")
	var valid := editor.preview("foundation",Vector3(1,0,1))
	editor.configure_terrain(func(_p: Vector2): return 10.0,25)
	_check(not editor.preview("foundation",Vector3(1,0,1)).ok,"Changed terrain provider invalidates cached preview")
	_check(not editor.place(valid).ok,"Old preview cannot place onto newly buried ground")
	for failure in failures: push_error(failure)
	print("CUSTOM PORT FOUNDATION TERRAIN ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _on_edge(p:Vector2,polygon:PackedVector2Array)->bool:
	for i in polygon.size():
		if Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()]).distance_to(p)<.001:return true
	return false

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
