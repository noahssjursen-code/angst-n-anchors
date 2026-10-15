class_name CustomPortChartProjection
extends RefCounted

## Passive public construction view. Inputs must already have passed authority
## validation. Never copy store contents, vessels, reservations or receipts into
## a chart directory, and never register this summary as a generated harbour.
static func project(snapshot: Dictionary, catalog: Dictionary, derived_berths: Array = []) -> Dictionary:
	var ground:=CustomPortEarthworks.project(snapshot,catalog)
	var polygons: Array = []
	for polygon in ground.footprints:
		var points: Array = []
		for point in polygon:points.append([point.x,point.y])
		polygons.append(points)
	var edges: Array = []
	for edge in ground.edges:
		var end: Vector2=edge.start+edge.direction*float(edge.length)
		edges.append([[edge.start.x,edge.start.y],[end.x,end.y]])
	var berths:=derived_berths
	if berths.is_empty():berths=CustomPortBerths.derive(snapshot,catalog)
	var origin: Array=snapshot.origin_m
	var bounds: Rect2=ground.bounds
	if not bounds.has_area():bounds=Rect2(Vector2(float(origin[0]),float(origin[2])),Vector2.ZERO)
	var identity: Dictionary=snapshot.world
	return {"id":str(snapshot.id),"source":"custom","revision":int(snapshot.get("revision",0)),
		"world":{"seed":identity.seed,"generation_version":identity.generation_version,"checksum":identity.checksum},"display_name":str(snapshot.get("name",snapshot.id)),
		"owner_company_id":str(snapshot.owner_company_id),"position_m":origin.duplicate(),
		"built_bounds_m":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],
		"platform_polygons_m":polygons,"exposed_edges_m":edges,
		"derived_berth_count":berths.size(),"services_ready":false}


## Explicit isolated chart adapter, not a live directory or a world mutation.
## Summary positions remain JSON on the public side; only this chart copy uses
## Vector3, which is the existing chart renderer's position contract.
static func chart_snapshot(layout: WorldLayout, summaries: Array) -> ChartDataSnapshot:
	var chart:=ChartDataSnapshot.new()
	chart.preview=true
	chart.layout=layout
	if layout!=null:
		chart.world_seed=layout.seed
		chart.generation_version=WorldLayoutGenerator.GENERATION_VERSION
		chart.layout_checksum=layout.layout_checksum
		chart.world_size_m=layout.world_size_m
	for summary in summaries:
		if not summary is Dictionary or str(summary.get("source",""))!="custom":continue
		var info: Dictionary=summary.duplicate(true)
		info.position=CustomPortCatalog.vector3(info.position_m)
		chart.ports.append(info)
	chart._index_ports()
	return chart
