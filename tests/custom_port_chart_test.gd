extends Node

var checks := 0
var failures: Array[String] = []
var confirmed := false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	var catalog:=CustomPortCatalog.definitions()
	var record:=_record()
	var original:=record.duplicate(true)
	var summary:=CustomPortChartProjection.project(record,catalog)
	_check(record==original,"Projection leaves the authority record unchanged")
	_check(summary.source=="custom" and summary.id==record.id and summary.display_name==record.name,"Explicit custom identity is retained")
	_check(summary.owner_company_id=="private-company-reference" and summary.derived_berth_count==0,"Company is a reference and no bollards means zero constructed berths")
	_check(summary.platform_polygons_m.size()==10,"Only actual platforms are included, including the triangle and chamfer")
	var area:=0.0
	for polygon in summary.platform_polygons_m:area+=_area(polygon)
	_check(is_equal_approx(area,8*16+8+15.5),"Triangle and chamfer preserve their exact authored area")
	_check(not _contains(summary,Vector2(100,200)),"A missing central foundation remains a real hole")
	_check(_contains(summary,Vector2(96,196)),"Constructed slab is present at translated world coordinates")
	_check(_contains(summary,Vector2(111,201)) and not _contains(summary,Vector2(109,199)),"Rotated diagonal uses placement yaw rather than an axis-aligned bounding box")
	for key in ["stores","vessels","receipts","reservations","accounts","placements","plots"]:
		_check(not summary.has(key),"Private structure excluded: "+key)
	_check(not JSON.stringify(summary).contains("TOP_SECRET"),"No private stock, cargo, receipt or account values leak")
	var chart:=CustomPortChartProjection.chart_snapshot(null,[summary])
	_check(chart.preview and chart.ports.size()==1 and chart.port_position(record.id).is_equal_approx(Vector3(100,.5,200)),"Isolated chart adapter has the actual world position")
	summary.platform_polygons_m[0][0][0]=-999
	_check(chart.ports[0].platform_polygons_m[0][0][0]!=-999,"Chart owns an independent summary copy")
	ChartHarbourPlan.clear_cache()
	var legacy:=ChartDataSnapshot.new()
	legacy.preview=true
	legacy.ports.assign([{"id":record.id,"position":Vector3(100,.5,200)}])
	legacy._index_ports()
	ChartHarbourPlan.prepare_snapshot(legacy)
	ChartHarbourPlan._cache[record.id]=ChartHarbourPlan.new()
	var plan:=ChartHarbourPlan.for_port(record.id,get_tree(),chart)
	_check(plan!=null and plan.custom_construction,"Custom summary replaces a previously cached legacy plan")
	_check(ChartHarbourPlan.resolve_port_data(record.id,get_tree(),chart)==null,"Custom record can never resolve or expand a generated harbour")
	_check(plan.foundation_poly.is_empty() and plan.quay_polys.is_empty() and plan.asphalt_polys.is_empty(),"No invented legacy pads, roads or foundation")
	_check(plan.platform_polys.size()==10 and not plan.exposed_edges.is_empty(),"Exact construction geometry reaches the render plan")
	var renderer:=ChartLayerRenderer.new()
	renderer.set_snapshot(chart)
	var context:={"chart_rect":Rect2(0,0,100,100),"world_bounds":Rect2(80,180,40,40),"world_span":40.0}
	_check(renderer.hit_test_port(Vector2(50,50),context,0)=="","The water hole is not selectable as built deck")
	_check(renderer.hit_test_port(Vector2(40,40),context,0)==record.id,"Built deck itself can be selected away from the origin marker")
	var rows:=ChartLayerRenderer.custom_port_card_rows(chart.ports[0])
	_check(rows[1].contains("0 constructed berths") and rows[2]=="Company ref: private-company-reference","Card labels construction count and raw company reference honestly")
	for forbidden in ["Export","Import","Population","available","shipwright","coal"]:
		_check(not " ".join(rows).contains(forbidden),"No invented service or availability: "+forbidden)
	var map:=MapOverlay.new()
	map.preview_mode=true
	add_child(map)
	map.set_data_snapshot(chart)
	map.home_port_confirmed.connect(func(_id: String):confirmed=true)
	map.enter_home_port_pick_mode(record.id)
	_check(map.pick_confirm.disabled and not map._home_port_supports_required_family(chart.ports[0]),"Custom summaries cannot become unsupported home-port teleport targets")
	map._confirm_home_port()
	_check(not confirmed,"Direct confirmation cannot bypass the custom-port guard")
	map.queue_free()
	var changed:=record.duplicate(true)
	changed.revision=1
	changed.placements.pop_back()
	var next:=CustomPortChartProjection.chart_snapshot(null,[CustomPortChartProjection.project(changed,catalog)])
	_check(ChartHarbourPlan.for_port(record.id,null,next)!=plan,"Construction change invalidates the retained geometry")
	var empty:=CustomPortChartProjection.chart_snapshot(null,[])
	ChartHarbourPlan.prepare_snapshot(empty)
	_check(not ChartHarbourPlan.is_cached(record.id),"Removing the port removes its retained silhouette")
	await get_tree().process_frame
	for failure in failures:push_error(failure)
	print("CUSTOM PORT CHART ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _record() -> Dictionary:
	var record:={"id":"chart-port","name":"Constructed harbour","owner_company_id":"private-company-reference","world":{"seed":73119,"generation_version":1,"checksum":"chart-test"},"origin_m":[100,.5,200],"revision":0,"placements":[],"stores":[{"TOP_SECRET":"stock"}],"vessels":[{"TOP_SECRET":"cargo"}],"receipts":{"TOP_SECRET":"payment"},"reservations":[{"TOP_SECRET":"reservation"}],"accounts":{"TOP_SECRET":"balance"}}
	for z in [-4,0,4]:
		for x in [-4,0,4]:
			if x==0 and z==0:continue
			record.placements.append({"id":"slab-%d-%d"%[x,z],"asset_id":"foundation","position_m":[x,0,z],"yaw_degrees":0,"attributes":{}})
	record.placements.append({"id":"triangle","asset_id":"foundation_triangle_4m","position_m":[10,0,0],"yaw_degrees":90,"attributes":{}})
	record.placements.append({"id":"chamfer","asset_id":"quay_chamfer_4m","position_m":[0,0,10],"yaw_degrees":270,"attributes":{}})
	return record

func _contains(summary: Dictionary, point: Vector2) -> bool:
	for raw in summary.platform_polygons_m:
		var polygon:=PackedVector2Array()
		for p in raw:polygon.append(Vector2(float(p[0]),float(p[1])))
		if Geometry2D.is_point_in_polygon(point,polygon):return true
	return false

func _area(raw: Array) -> float:
	var sum:=0.0
	for index in raw.size():
		var a: Array=raw[index]
		var b: Array=raw[(index+1)%raw.size()]
		sum+=float(a[0])*float(b[1])-float(b[0])*float(a[1])
	return absf(sum)*.5

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
