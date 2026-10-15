extends Node

var map: MapOverlay
var failures: Array[String]=[]
var checks:=0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	var layout:=WorldLayoutGenerator.generate(73119,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,15000)
	var world:={"seed":layout.seed,"generation_version":WorldLayoutGenerator.GENERATION_VERSION,"checksum":layout.layout_checksum}
	var catalog:=CustomPortCatalog.definitions()
	var at:=Vector3(2724,.5,-692)
	var nordvik:=CustomPortExample.build(at,[{"id":"review-plot","rect_m":[-124,-20,200,200],"owner_company_id":CustomPortExample.OWNER}],world)
	var shape:=_shape_record(world)
	var first:=CustomPortChartProjection.project(nordvik,catalog)
	var second:=CustomPortChartProjection.project(shape,catalog)
	var layer:=CanvasLayer.new()
	add_child(layer)
	map=MapOverlay.new()
	map.preview_mode=true
	layer.add_child(map)
	map.set_data_snapshot(CustomPortChartProjection.chart_snapshot(layout,[first,second]))
	map.open_navigation()
	for key in ["weather","traffic","routes","plots"]:map.layers.set_visible(key,false)
	map._refresh_mode_buttons()
	map._refresh_plot_panel()
	await _focus(first,"01-nordvik-built-outline",400)
	var before:=ChartHarbourPlan._cache.size()
	await _focus(second,"02-angled-decks-and-water-hole",300)
	_check(ChartHarbourPlan._cache.size()==before,"Changing focus retains existing exact plans")
	_check(map.renderer.hit_test_port(map.renderer._world_to_screen(Vector3(3000,0,-950),map.last_ctx),map.last_ctx,0)=="","Native rendered hole stays unselectable")
	var public_before:=JSON.stringify(first)
	var private_before:=JSON.stringify(nordvik)
	map.selected_port=first.id
	map._redraw_contacts()
	await get_tree().process_frame
	_check(JSON.stringify(first)==public_before and JSON.stringify(nordvik)==private_before,"Drawing and selection do not mutate public or private records")
	for failure in failures:push_error(failure)
	print("CUSTOM PORT CHART NATIVE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _focus(summary: Dictionary, capture_name: String, span: float) -> void:
	var plan:=ChartHarbourPlan.for_port(str(summary.id),null,map.data)
	map.camera.focus_harbour(plan.centre_world(),span)
	map.camera_initialized=true
	map.first_visible_frame=false
	map.selected_port=summary.id
	map._redraw_geography()
	map._redraw_contacts()
	var until:=Time.get_ticks_msec()+2500
	while Time.get_ticks_msec()<until:await get_tree().process_frame
	_check(plan.custom_construction and plan.platform_polys.size()==summary.platform_polygons_m.size(),"Native view uses every saved platform: "+str(summary.id))
	_check(map.renderer.geography_draw_count>0 and map.renderer.draw_count>0,"Production geography and contact surfaces actually drew")
	if RenderingServer.get_rendering_device()!=null:
		await RenderingServer.frame_post_draw
		var folder:="C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(folder)
		var path:=folder.path_join("custom-port-chart-%d-%d-%s.png"%[Time.get_unix_time_from_system(),OS.get_process_id(),capture_name])
		_check(get_viewport().get_texture().get_image().save_png(path)==OK,"Native capture archived")
		print("CUSTOM_PORT_CHART_CAPTURE ",path)

func _shape_record(world: Dictionary) -> Dictionary:
	var record:={"id":"shape-review","name":"Angled harbour","owner_company_id":"company-reference-2","world":world.duplicate(true),"origin_m":[3000,.5,-950],"revision":0,"placements":[]}
	for z in [-8,0,8]:
		for x in [-8,0,8]:
			if x==0 and z==0:continue
			record.placements.append(CustomPortCatalog.placement("slab-%d-%d"%[x,z],"foundation_8m",Vector3(x,0,z),0))
	record.placements.append(CustomPortCatalog.placement("triangle","quay_triangle_4m",Vector3(14,0,-10),90))
	record.placements.append(CustomPortCatalog.placement("chamfer","quay_chamfer_4m",Vector3(14,0,10),180))
	return record

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
