extends Node3D

## Complete documents, one rendering client. This deliberately consumes
## snapshots without changing company saves or creating simulation ships.
const STREAMER = preload("res://scripts/port/building/custom_port_streamer.gd")
const REPOSITORY = preload("res://scripts/port/state/custom_port_repository.gd")
const WORLD_POLICY = preload("res://scripts/port/building/custom_port_world_policy.gd")
const COLLECTION = preload("res://scripts/port/state/custom_port_collection.gd")
const SEED := 73119
const SITE_A := Vector3(2724,.5,-692)
const SITE_B := Vector3(76,.5,1668)
var camera := preload("res://scripts/port/building/plot_build_camera.gd").new()
var layout: WorldLayout
var terrain: WorldTerrainStreamer
var forest: WorldForestStreamer
var ports: Node3D
var label: Label
var feedback: Label
var world: Dictionary
var catalog: Dictionary
var snapshots: Array[Dictionary] = []
var source_documents: Array[Dictionary] = []
var imported_mode := false
var port_picker: OptionButton
var original_pallet: Dictionary
var failures: Array[String] = []
var checks := 0
var _height_cache: Dictionary = {}
var _status_timer := 0.0
var map: MapOverlay
var _map_previous_flying := false

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_run.call_deferred()

func _run() -> void:
	WorldClock.snap_time_of_day(.43)
	WorldClock.set_process(false)
	WeatherLighting.set_process(false)
	WeatherLighting.time_of_day=.43
	WeatherLighting.cloud_cover=.18
	WeatherLighting.precipitation=0
	WeatherLighting.wind_force=.15
	WeatherLighting.sea_state=.08
	layout=WorldLayoutGenerator.generate(SEED,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,15000)
	LandField.initialize(layout)
	ForestField.initialize(layout,SEED)
	world={"seed":SEED,"generation_version":WorldLayoutGenerator.GENERATION_VERSION,"checksum":layout.layout_checksum}
	catalog=CustomPortCatalog.definitions()
	var paths: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--travel-port-document="): paths.append(argument.trim_prefix("--travel-port-document="))
	imported_mode=not paths.is_empty()
	if imported_mode:
		var imported:=load_documents(paths,world,catalog)
		if not imported.ok:
			_show_import_error(imported)
			return
		snapshots.assign(imported.snapshots)
		source_documents.assign(imported.sources)
	else:
		var index:=CoastalPlotIndex.for_layout(layout)
		var a:=CustomPortExample.build(SITE_A,_plots(index,SITE_A),world,0,_seabed)
		CustomPortExample.survey(a,_seabed,WaveSurface.WATER_LEVEL)
		snapshots=[a,_small_workshop(index)]
		for row in a.placements:
			if str(row.id)=="pallets":original_pallet=row.duplicate(true)
	var renderer:=WorldRenderer.new()
	renderer.enable_ocean_system=RenderingServer.get_rendering_device()!=null
	renderer.enable_ssil=false
	renderer.enable_weather_post_fx=false
	renderer.enable_volumetric_fog=false
	add_child(renderer)
	add_child(camera)
	camera.far=12000
	camera.move_speed=80
	camera.current=true
	visit(0)
	terrain=WorldTerrainStreamer.new()
	terrain.visual_radius_m=12000
	# This scene has a free camera, not a walking player. Collision readiness
	# follows the real player in production; do not wait for a nonexistent one.
	terrain.collision_radius_m=0
	terrain.build_budget_ms=8
	add_child(terrain)
	terrain.configure(layout)
	forest=WorldForestStreamer.new()
	add_child(forest)
	forest.configure(layout)
	ports=STREAMER.new()
	add_child(ports)
	ports.configure(world,catalog)
	ports.bind_environment(terrain,forest)
	for snapshot in snapshots:
		var result: Dictionary=ports.upsert_record(snapshot)
		_check(bool(result.ok),"Port document accepted: "+str(snapshot.id)+" "+str(result.get("errors",[])))
		if not result.ok:
			ports.clear()
			_show_import_error(result)
			return
	_build_ui()
	_update_status()
	print("CUSTOM_PORT_STREAMING_SHOWCASE_READY")
	if OS.get_cmdline_user_args().has("--verify-streaming"):
		if imported_mode: await _review_documents()
		else: await _review()

## Preflight the entire batch before any models/environment are registered.
## Sources (and a recovered backup, if used) stay read-only throughout review.
static func load_documents(paths: Array[String], expected_world: Dictionary, definitions: Dictionary) -> Dictionary:
	if paths.is_empty(): return {"ok":false,"code":"no_port_documents","errors":["Choose at least one saved port file."]}
	var documents: Array[Dictionary] = []
	var sources: Array[Dictionary] = []
	var seen: Dictionary = {}
	for path in paths:
		var result:=REPOSITORY.load_state(path,expected_world,definitions)
		if not result.ok:return result
		var plane: Dictionary=WORLD_POLICY.validate_deck_plane(result.snapshot)
		if not plane.ok: return plane
		var physical:=CustomPortVesselProjection.validate_snapshot(result.snapshot)
		if not physical.ok: return physical
		var id:=str(result.snapshot.id)
		if seen.has(id):
			return {"ok":false,"code":"duplicate_port_id","errors":["Both %s and %s describe port %s. Choose one revision per port." % [seen[id],path,id]]}
		seen[id]=path
		documents.append(result.snapshot)
		sources.append({"path":result.path,"loaded_path":result.loaded_path,"id":id,
			"source_exists":FileAccess.file_exists(result.path),"source_sha256":FileAccess.get_sha256(result.path) if FileAccess.file_exists(result.path) else "",
			"loaded_sha256":FileAccess.get_sha256(result.loaded_path),"warnings":result.get("warnings",[])})
	var collection:=COLLECTION.validate(documents)
	if not collection.ok:
		var messages: Array[String]=[]
		for conflict in collection.errors:messages.append(str(conflict.message))
		return {"ok":false,"code":collection.code,"errors":messages,"details":collection.errors}
	return {"ok":true,"code":"documents_ready","snapshots":documents,"sources":sources,"errors":[]}

func _show_import_error(result: Dictionary) -> void:
	var message:="Port review could not load these files.\n"+"\n".join(result.get("errors",[str(result.get("code","unknown_error"))]))
	var layer:=CanvasLayer.new()
	add_child(layer)
	var panel:=Ui.sheet(Vector2(740,0))
	panel.position=Vector2(24,24)
	layer.add_child(panel)
	var column:=Ui.vbox(12)
	panel.add_child(column)
	column.add_child(Ui.heading("Port files were not loaded"))
	column.add_child(Ui.caption(message))
	column.add_child(Ui.caption("The source files were left unchanged. Check the file selection and try again."))
	print("CUSTOM_PORT_TRAVEL_IMPORT_REJECTED ",result.get("code","unknown_error")," ",result.get("errors",[]))
	if OS.get_cmdline_user_args().has("--verify-streaming"):get_tree().quit(1)

func _plots(index: CoastalPlotIndex, at: Vector3) -> Array:
	var plot:=index.plot_at(Vector2(at.x,at.z+16))
	var rect:=ChartPlotLayer.plot_rect(plot)
	return [{"id":str(plot.id),"rect_m":[rect.position.x-at.x,rect.position.y-at.z,rect.size.x,rect.size.y],"owner_company_id":CustomPortExample.OWNER}]

func _small_workshop(index: CoastalPlotIndex) -> Dictionary:
	var result: Dictionary={"schema_version":1,"id":"cliff-workshop","name":"Cliff workshop","owner_company_id":CustomPortExample.OWNER,
		"world":world.duplicate(true),"origin_m":[SITE_B.x,SITE_B.y,SITE_B.z],"deck_height_above_sea_m":2,
		"revision":0,"plots":_plots(index,SITE_B),"placements":[],"stores":[],"vessels":[],"reservations":[],"receipts":{},"water_regions":[]}
	for z in [-12,-4,4,12]:
		for x in [-12,-4,4,12]:
			CustomPortExample._add(result,"slab-%d-%d"%[x,z],"foundation_8m",Vector3(x,0,z),0,_seabed)
	CustomPortExample._workshop(result,Vector3.ZERO,0,_seabed)
	CustomPortExample._add(result,"lamp","quay_light",Vector3(12,0,12),0,_seabed)
	CustomPortExample._add(result,"pallets","pallet_stack",Vector3(-11,0,-10),0,_seabed)
	result.erase("_site_yaw")
	return result

func _seabed(at: Vector2) -> float:
	return WorldForestStreamer.sample_root_height(layout,at,[],_height_cache)

func _build_ui() -> void:
	var layer:=CanvasLayer.new()
	add_child(layer)
	var panel:=Ui.sheet(Vector2(670,0))
	panel.position=Vector2(18,18)
	layer.add_child(panel)
	var column:=Ui.vbox(8)
	panel.add_child(column)
	column.add_child(Ui.heading("Custom ports · Travel review"))
	port_picker=OptionButton.new()
	port_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for snapshot in snapshots:port_picker.add_item(str(snapshot.get("name",snapshot.id)))
	port_picker.item_selected.connect(visit)
	column.add_child(port_picker)
	var buttons:=HBoxContainer.new()
	column.add_child(buttons)
	for index in mini(2,snapshots.size()):
		var port_name:=str(snapshots[index].get("name",snapshots[index].id))
		var button:=Ui.button("%d · %s"%[index+1,port_name.left(22)],"secondary",visit.bind(index))
		button.tooltip_text=port_name
		buttons.add_child(button)
	buttons.add_child(Ui.button("3 · Offshore","secondary",visit_offshore))
	if not imported_mode:buttons.add_child(Ui.button("4 · Edit Nordvik","secondary",edit_nordvik))
	column.add_child(Ui.button("M · Chart","secondary",open_chart))
	label=Ui.caption("")
	column.add_child(label)
	feedback=Ui.caption("Tab · Fly / cursor    WASD · Move    Q/E · Height    Shift · Faster")
	column.add_child(feedback)
	if imported_mode:
		column.add_child(Ui.caption("Saved documents · Read-only review"))
		for source in source_documents:
			for warning in source.warnings:column.add_child(Ui.caption(str(warning)))
	var map_layer:=CanvasLayer.new()
	map_layer.layer=10
	add_child(map_layer)
	map=MapOverlay.new()
	map.preview_mode=true
	map_layer.add_child(map)
	map.visible=false
	map.close_requested.connect(close_chart)

func refresh_chart() -> void:
	if map==null or ports==null:return
	var summaries: Array=[]
	for initial in snapshots:
		var latest: Dictionary=ports.record(str(initial.id))
		if not latest.is_empty():summaries.append(CustomPortChartProjection.project(latest,catalog))
	map.set_data_snapshot(CustomPortChartProjection.chart_snapshot(layout,summaries))

func open_chart() -> void:
	if map==null:return
	refresh_chart()
	_map_previous_flying=camera.flying
	camera.set_flying(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	map.open_navigation()
	for key in ["weather","traffic","routes","plots"]:map.layers.set_visible(key,false)
	map._refresh_mode_buttons()
	map._refresh_plot_panel()
	var index:=port_picker.selected if port_picker!=null else 0
	var id:=str(snapshots[clampi(index,0,snapshots.size()-1)].id)
	var plan:=ChartHarbourPlan.for_port(id,null,map.data)
	if plan!=null:
		map.camera.focus_harbour(plan.centre_world(),maxf(400,maxf(plan.bounds.size.x,plan.bounds.size.y)*2.4))
		map.camera_initialized=true
		map.first_visible_frame=false
	map.selected_port=id
	map._redraw_geography()
	map._redraw_contacts()

func close_chart() -> void:
	if map==null:return
	map.visible=false
	camera.set_flying(_map_previous_flying)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if camera.flying else Input.MOUSE_MODE_VISIBLE

func visit(index: int) -> void:
	if index<0 or index>=snapshots.size():return
	if port_picker!=null:port_picker.select(index)
	if imported_mode:
		var snapshot:=snapshots[index]
		var origin:=CustomPortCatalog.vector3(snapshot.origin_m)
		var positions: Array=snapshot.get("placements",[])
		var bounds:=Rect2()
		for placement_index in positions.size():
			var point:=CustomPortCatalog.vector3(positions[placement_index].position_m)
			if placement_index==0:bounds=Rect2(Vector2(point.x,point.z),Vector2.ZERO)
			else:bounds=bounds.expand(Vector2(point.x,point.z))
		var focus:=origin+Vector3(bounds.get_center().x,5,bounds.get_center().y)
		var offset:=clampf(maxf(bounds.size.x,bounds.size.y)*.8,45,800)
		camera.position=focus+Vector3(-offset,offset*.78,-offset)
		camera.look_at(focus)
	elif index==0:
		camera.position=SITE_A+Vector3(-112,88,-110)
		camera.look_at(SITE_A+Vector3(0,8,28))
	else:
		camera.position=SITE_B+Vector3(-44,85,-55)
		camera.look_at(SITE_B)
	camera.reset_physics_interpolation()

func visit_offshore() -> void:
	if imported_mode and ports!=null:
		# Beyond every registered radius, even for nearby ports or large estates.
		var east:=10000.0
		for entry in ports._entries.values():
			east=maxf(east,entry.position.x+float(entry.radius)+ProximityLoader.UNLOAD_HYSTERESIS_M+3000)
		camera.position=Vector3(east,180,0)
		camera.look_at(CustomPortCatalog.vector3(snapshots[0].origin_m))
	else:
		camera.position=Vector3(-3500,180,0)
		camera.look_at(Vector3(0,0,0))
	camera.reset_physics_interpolation()

func edit_nordvik() -> void:
	if imported_mode or snapshots.is_empty():return
	# Stand in for a newer authority snapshot using the same validated command
	# path as the workshop. Editing while away must not force the models to load.
	var state:=CustomPortState.from_dict(ports.record("nordvik-harbour"),world,catalog)
	var found:=false
	for row in state.to_dict().placements:
		if str(row.id)=="pallets":found=true
	var result:=state.apply({"command_id":"travel-review-%d"%state.revision(),"expected_revision":state.revision(),
		"actor_company_id":CustomPortExample.OWNER,"kind":"remove_asset" if found else "place_asset",
		"payload":{"placement_id":"pallets"} if found else {"placement":original_pallet}})
	if result.ok:
		result=ports.upsert_record(state.to_dict())
		feedback.text="Nordvik updated to revision %d. Travel back to see the saved change."%state.revision()
	else:
		feedback.text="Edit rejected: "+str(result.code)
	_check(bool(result.ok),"Authority edit applied to cached Nordvik record")
	if map!=null and map.visible:refresh_chart()
	_update_status()

func _process(delta: float) -> void:
	camera.fly(delta)
	_status_timer-=delta
	if _status_timer<=0:
		_status_timer=.25
		_update_status()

func _update_status() -> void:
	if label==null or ports==null:return
	var loaded: Array=ports.loaded_port_ids()
	var names: Array[String]=[]
	for id in loaded:names.append(str(ports.record(id).get("name",id)))
	label.text="Known ports: %d   Loaded: %d\n%s\nLoad: 1.4 km + port size   Unload: another 800 m"%[snapshots.size(),loaded.size(),", ".join(names) if not names.is_empty() else "All ports out of range"]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_M:
		if map!=null and map.visible:close_chart()
		else:open_chart()
		get_viewport().set_input_as_handled()
		return
	if map!=null and map.visible:return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:visit(0)
			KEY_2:visit(1)
			KEY_3:visit_offshore()
			KEY_4:edit_nordvik()
			KEY_TAB:
				camera.set_flying(not camera.flying)
				Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if camera.flying else Input.MOUSE_MODE_VISIBLE
			KEY_ESCAPE:
				camera.set_flying(false)
				Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	camera.handle_input(event)

func _settle(expected: Array[String], focus: Vector3, require_nearby_terrain:=true) -> void:
	var deadline:=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		if ports.loaded_port_ids()==expected and (not require_nearby_terrain or terrain.is_ready_around(focus,150)) and terrain.is_custom_port_earthworks_ready():break
		await get_tree().process_frame
	_check(ports.loaded_port_ids()==expected,"Loaded ports match distance and residency: "+str(expected))
	if require_nearby_terrain:_check(terrain.is_ready_around(focus,150),"Nearby terrain finished loading")
	_check(terrain.is_custom_port_earthworks_ready(),"Terrain modifiers match the retained port documents")
	for frame in 45:await get_tree().process_frame
	_update_status()

func _review() -> void:
	await _settle(["nordvik-harbour"],SITE_A)
	var first: CustomPortPresenter=ports.get_presenter("nordvik-harbour")
	_check(first!=null and first.vessel_nodes.is_empty(),"World projection leaves ship spawning to the existing vessel system")
	_check(first!=null and first.placement_nodes.has("pallets"),"Initial authored pallet is visible")
	await _capture("01-nordvik")
	visit(1)
	await _settle(["cliff-workshop"],SITE_B)
	_check(not is_instance_valid(first),"Travel freed the previous harbour nodes")
	_check(forest._custom_port_exclusions.size()==2 and terrain._custom_earthworks.size()==2,"Model unloading preserves both terrain and forest projections")
	await _capture("02-cliff-workshop")
	edit_nordvik()
	_check(ports.get_presenter("nordvik-harbour")==null,"Receiving an edit while away did not load a distant harbour")
	visit(0)
	await _settle(["nordvik-harbour"],SITE_A)
	var returned: CustomPortPresenter=ports.get_presenter("nordvik-harbour")
	_check(returned!=null and not returned.placement_nodes.has("pallets"),"Returning reconstructed the newer revision")
	_check(int(ports.record("nordvik-harbour").revision)==1,"Cached revision survived travel")
	await _capture("03-return-updated")
	visit_offshore()
	await _settle([],camera.position)
	_check(not ports.record("nordvik-harbour").is_empty() and not ports.record("cliff-workshop").is_empty(),"Offshore retains data with no port models")
	await _capture("04-offshore-unloaded")
	_finish_review()

func _expected_residents() -> Array[String]:
	var expected: Array[String]=[]
	for id in ports._entries:
		var entry: Dictionary=ports._entries[id]
		var loaded:=ports.get_presenter(id)!=null
		var radius:=float(entry.radius)+(ProximityLoader.UNLOAD_HYSTERESIS_M if loaded else 0.0)
		if camera.global_position.distance_to(entry.position)<=radius:expected.append(str(id))
	expected.sort()
	return expected

func _review_documents() -> void:
	for index in snapshots.size():
		var snapshot:=snapshots[index]
		var id:=str(snapshot.id)
		visit(index)
		await _settle(_expected_residents(),CustomPortCatalog.vector3(snapshot.origin_m))
		_verify_document_projection(snapshot)
		await _capture("%02d-%s-arrive"%[index+1,id.validate_filename()])
		var previous: CustomPortPresenter=ports.get_presenter(id)
		visit_offshore()
		await _settle([],camera.position,false)
		_check(not is_instance_valid(previous),"Leaving freed the imported port models: "+id)
		_check(ports.record(id)==snapshot,"Leaving preserved the latest authorized document: "+id)
		visit(index)
		await _settle(_expected_residents(),CustomPortCatalog.vector3(snapshot.origin_m))
		_verify_document_projection(snapshot)
		await _capture("%02d-%s-return"%[index+1,id.validate_filename()])
	for source in source_documents:
		_check(FileAccess.file_exists(source.path)==source.source_exists and (not source.source_exists or FileAccess.get_sha256(source.path)==source.source_sha256),"Source file bytes remain unchanged: "+str(source.path))
		_check(FileAccess.get_sha256(source.loaded_path)==source.loaded_sha256,"Loaded document bytes remain unchanged: "+str(source.loaded_path))
	_finish_review()

func _verify_document_projection(snapshot: Dictionary) -> void:
	var id:=str(snapshot.id)
	var presenter: CustomPortPresenter=ports.get_presenter(id)
	_check(presenter!=null,"Imported port is resident: "+id)
	if presenter==null:return
	_check(str(presenter.record.id)==id and str(presenter.record.get("name",id))==str(snapshot.get("name",id)),"Actual imported port identity and name are displayed: "+id)
	_check(presenter.global_position.is_equal_approx(CustomPortCatalog.vector3(snapshot.origin_m)),"Imported port uses its saved world origin: "+id)
	var exact: bool=presenter.placement_nodes.size()==snapshot.placements.size()
	for placement in snapshot.placements:
		var node: Node3D=presenter.placement_nodes.get(str(placement.id))
		exact=exact and is_instance_valid(node) and node.position.is_equal_approx(CustomPortCatalog.vector3(placement.position_m))
	_check(exact,"All saved placements are reconstructed at their authored positions: "+id)
	var stores_match: bool=presenter._stores.size()==snapshot.stores.size()
	for store in snapshot.stores:stores_match=stores_match and presenter._stores.get(str(store.id),{})==store and presenter.placement_nodes.has(str(store.placement_id))
	_check(stores_match,"Saved stock and store owners are projected unchanged: "+id)
	_check(presenter.vessel_nodes.is_empty(),"Imported world port leaves ship ownership to existing vessel services: "+id)
	var presented:=presenter.record.duplicate(true)
	presented.erase("_presented_berths")
	_check(presented==ports.record(id) and presented==snapshot,"Projection reconstructs the complete latest resident document: "+id)

func _finish_review() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT NATIVE ","IMPORTED " if imported_mode else "","STREAMING ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(name: String) -> void:
	if RenderingServer.get_rendering_device()==null:return
	await RenderingServer.frame_post_draw
	var folder:="C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("custom-port-travel-%d-%d-%s.png"%[Time.get_unix_time_from_system(),OS.get_process_id(),name])
	get_viewport().get_texture().get_image().save_png(path)
	print("CUSTOM_PORT_TRAVEL_CAPTURE ",path)

func _check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message)

func _exit_tree() -> void:
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	# A rejected batch exits before its review camera has joined the scene.
	if is_instance_valid(camera) and camera.get_parent()==null:camera.free()
