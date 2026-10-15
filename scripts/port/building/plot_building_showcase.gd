extends Node3D

## F6 island -> chart -> home teleport -> permanent build tool -> construction.
## All home/build records are local fixtures; no captain save or MP session.
enum Mode { BOOT, WALK, MAP, BUILD }
const SEED := 73119
const WORLD_SIZE_M := 15000.0
const PLAYER := preload("res://scenes/shared/player.tscn")
const BUILD_REACH_M := 400.0
var mode := Mode.BOOT
var layout: WorldLayout
var island: Dictionary = {}
var plot_index: CoastalPlotIndex
var documents: Dictionary = {}
var document: PlotBuildLayout
var home_position := Vector3.ZERO
var player: CharacterBody3D
var build_camera := preload("res://scripts/port/building/plot_build_camera.gd").new()
var build_camera_ready := false
var terrain: WorldTerrainStreamer
var selected_item := "foundation"
var turns := 0
var hover_cell := Vector2i(-1,-1)
var ghost: Node3D
var ghost_key := ""
var hover_valid := false
var aimed_piece_id := ""
var library_cursor := false
var painting := false
var painted_cell_key := ""
var boundary: MeshInstance3D
var grid: MeshInstance3D
var grid_key := ""
var placed_nodes: Dictionary = {}
var support_depth_cache: Dictionary = {}
var ui: Control
var map: MapOverlay
var hotbar: PlayerHotbar
var toolbar: HBoxContainer
var library: PanelContainer
var prompt: PanelContainer
var prompt_label: Label
var feedback: Label
var plot_label: Label
var count_label: Label
var snap_label: Label
var crosshair: Label
var library_buttons: Dictionary = {}
var before_map := Mode.WALK
var ready_for_review := false
var _review := false

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "This inspect scene must be isolated.")
	_review = OS.get_cmdline_user_args().has("--verify-plot-building") \
		or OS.get_cmdline_user_args().has("--capture-plot-building") \
		or OS.get_cmdline_user_args().has("--verify-plot-equipment") \
		or OS.get_cmdline_user_args().has("--capture-plot-equipment")
	WorldClock.snap_time_of_day(.46)
	WorldClock.set_process(false)
	WeatherLighting.set_process(false)
	WeatherLighting.time_of_day = .46
	WeatherLighting.cloud_cover = .25
	WeatherLighting.precipitation = 0.0
	WeatherLighting.wind_force = .2
	WeatherLighting.sea_state = .1
	layout = WorldLayoutGenerator.generate(SEED,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,WORLD_SIZE_M)
	LandField.initialize(layout)
	plot_index = CoastalPlotIndex.for_layout(layout)
	island = PlotBuildIsland.choose(layout,plot_index)
	assert(not island.is_empty(), "A medium sized island must be available.")
	print("PLOT_BUILD_ISLAND span_m=", island.span_m, " selectable_plots=", island.homes.size())
	var ids: Array[String] = []
	for id in island.homes:
		ids.append(id)
	ids.sort()
	var spawn: Vector3 = island.homes[ids[0]]
	var renderer := WorldRenderer.new()
	renderer.enable_ocean_system = RenderingServer.get_rendering_device()!=null
	renderer.enable_ssil = false
	renderer.enable_weather_post_fx = false
	renderer.enable_volumetric_fog = false
	add_child(renderer)
	player = PLAYER.instantiate()
	player.position = spawn
	add_child(player)
	build_camera.name = "BuildFreecam"
	add_child(build_camera)
	player.set_physics_process(false)
	var controls := player.get_node("PlayerCamera") as PlayerCamera
	controls._fp_pitch = deg_to_rad(-16)
	controls._apply_mode()
	terrain = WorldTerrainStreamer.new()
	terrain.name = "IslandTerrain"
	terrain.visual_radius_m = 1700.0
	terrain.collision_radius_m = 1400.0
	terrain.build_budget_ms = 8.0
	terrain.max_jobs_per_frame = 2
	terrain.begin_boot_priority(spawn)
	add_child(terrain)
	terrain.configure(layout)
	_build_ui(ids)
	await _wait_for_ground(spawn)
	_snap_player_to_ground(spawn)
	player.velocity = Vector3.ZERO
	terrain.end_boot_priority()
	mode = Mode.WALK
	player.set_physics_process(true)
	_set_walk_camera()
	prompt_label.text = "Choose your home plot\nOpen the map to select a green coastal square."
	feedback.text="WASD  Walk · V  Camera · M  Choose plot"
	ready_for_review = true
	print("PLOT_BUILDING_READY freecam WASD=fly Q/E=height Shift=fast M=map 1=build wheel=piece Tab=library fixed_deck_above_sea_m=",PlotBuildLayout.DECK_HEIGHT_ABOVE_SEA_M)
	if _review:
		set_process_input(false)
		map.set_process_input(false)
		call_deferred("_run_equipment_review" if OS.get_cmdline_user_args().has("--verify-plot-equipment") or OS.get_cmdline_user_args().has("--capture-plot-equipment") else "_run_review")

func _wait_for_ground(at: Vector3) -> void:
	var deadline := Time.get_ticks_msec()+20000
	while not terrain.is_ready_around(at,220.0) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(terrain.is_ready_around(at,220.0), "Teleport waits for physical ground.")

func _build_ui(ids: Array[String]) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(func() -> void: ui.size=get_viewport().get_visible_rect().size)
	toolbar = HBoxContainer.new()
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_left=22; toolbar.offset_right=-22; toolbar.offset_top=18
	toolbar.add_theme_constant_override("separation",12)
	ui.add_child(toolbar)
	plot_label = Ui.heading("Island home")
	plot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(plot_label)
	toolbar.add_child(Ui.button("Choose plot · M","secondary",open_map))
	toolbar.add_child(Ui.button("Home","secondary",teleport_home))
	toolbar.add_child(Ui.button("Walk · Esc","secondary",leave_build))
	toolbar.visible=false
	prompt = Ui.sheet(Vector2(380,0))
	ui.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	prompt.offset_left=-430; prompt.offset_right=-26; prompt.offset_top=26
	var content := Ui.vbox(12)
	prompt.add_child(content)
	content.add_child(Ui.eyebrow("Your island home"))
	prompt_label = Ui.heading("Preparing nearby terrain…")
	prompt_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	prompt_label.custom_minimum_size.x=350
	content.add_child(prompt_label)
	content.add_child(Ui.button("Select a plot on the map · M","primary",open_map))
	library = Ui.sheet(Vector2(264,0))
	ui.add_child(library)
	library.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	library.offset_left=18; library.offset_right=282; library.offset_top=82
	library.anchor_bottom=1.0
	library.offset_bottom=-170
	var list := Ui.vbox(7)
	library.add_child(list)
	list.add_child(Ui.eyebrow("Build · Tab to choose"))
	list.add_child(Ui.caption("One deck · %.0f m above sea level" % PlotBuildLayout.DECK_HEIGHT_ABOVE_SEA_M))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)
	var choices := Ui.vbox(7)
	choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(choices)
	for spec in PlotBuildLayout.catalog():
		var button := Ui.button("%s\n%d × %d m" % [str(spec.name),int(spec.cells[0])*2,int(spec.cells[1])*2],"secondary",_choose_from_library.bind(str(spec.id)))
		button.toggle_mode=true
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y=52
		button.add_theme_font_size_override("font_size",16)
		button.tooltip_text=str(spec.description)
		choices.add_child(button)
		library_buttons[str(spec.id)]=button
	count_label = Ui.caption("0 placed")
	list.add_child(count_label)
	snap_label = Ui.caption("Snap · 4 × 4 m")
	list.add_child(snap_label)
	list.add_child(Ui.caption("Wheel  Piece · R  Rotate"))
	list.add_child(Ui.caption("Ctrl+Z  Undo"))
	list.add_child(Ui.caption("WASD  Fly · Q / E  Down / Up"))
	list.add_child(Ui.caption("Shift  Fast · Ctrl  Slow"))
	library.visible=false
	crosshair = Ui.caption("+")
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left=-12; crosshair.offset_right=12
	crosshair.offset_top=-16; crosshair.offset_bottom=16
	crosshair.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size",24)
	crosshair.add_theme_color_override("font_shadow_color",Color("102024"))
	crosshair.add_theme_constant_override("shadow_offset_x",1)
	crosshair.add_theme_constant_override("shadow_offset_y",1)
	crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(crosshair)
	crosshair.visible=false
	feedback = Ui.caption("WASD  Walk · V  Camera · M  Choose plot")
	feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	feedback.offset_left=-440; feedback.offset_right=440; feedback.offset_top=-139; feedback.offset_bottom=-91
	feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	feedback.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	feedback.add_theme_font_size_override("font_size",18)
	feedback.add_theme_color_override("font_color",Color("edf2ef"))
	feedback.add_theme_stylebox_override("normal",VoyageStyle.box(Color("18252be8"),10))
	feedback.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(feedback)
	hotbar = PlayerHotbar.new()
	hotbar.preview_mode=true
	hotbar.preview_inventory=PlayerInventoryState.empty()
	hotbar.preview_inventory.slots[0]={"uid":"permanent-build-tool","item_id":"build_tool",
		"quantity":1,"attributes":{"permanent":true}}
	ui.add_child(hotbar)
	hotbar.visible=false
	hotbar.slots[0].mouse_filter=Control.MOUSE_FILTER_STOP
	hotbar.slots[0].pressed.connect(enter_build)
	hotbar.slots[0].tooltip_text="Build tool · permanent slot 1"
	map = MapOverlay.new()
	map.preview_mode=true
	ui.add_child(map)
	var snapshot := ChartDataSnapshot.new()
	snapshot.layout=layout; snapshot.preview=true; snapshot.world_seed=SEED
	snapshot.layout_checksum=layout.layout_checksum; snapshot.world_size_m=layout.world_size_m
	snapshot.generation_version=WorldLayoutGenerator.GENERATION_VERSION
	map.set_data_snapshot(snapshot)
	map.layers.set_visible("weather",false)
	map.layers.set_visible("traffic",false)
	map.renderer.plots.set_plot_filter(ids)
	map.plot_selected.connect(select_home_plot)
	map.close_requested.connect(close_map)
	map.visible=false
	select_placeable(selected_item)

func open_map() -> void:
	if mode==Mode.BOOT:
		return
	before_map=mode if mode!=Mode.MAP else before_map
	mode=Mode.MAP
	build_camera.set_flying(false)
	_finish_paint()
	crosshair.visible=false
	if is_instance_valid(ghost): ghost.visible=false
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_unhandled_input(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	map.visible=true
	map.first_visible_frame=false
	map.camera_initialized=true
	var bounds: Rect2=island.bounds
	map.camera.focus_harbour(bounds.get_center(),maxf(bounds.size.x,bounds.size.y)*1.35)
	map.title_label.text="CHOOSE YOUR HOME PLOT"
	map.plot_heading.text="Select a green square"
	map.plot_body.text="Choose a home on this island.\nSelecting a plot teleports you there."
	map._redraw_geography()
	prompt.visible=false
	library.visible=false
	toolbar.visible=false
	hotbar.visible=false
	feedback.visible=false
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(),true)

func close_map() -> void:
	map.visible=false
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(),false)
	if before_map==Mode.BUILD and document!=null:
		enter_build()
	else:
		leave_build()

func select_home_plot(record: Dictionary) -> void:
	var id := str(record.get("id",""))
	if not island.homes.has(id):
		return
	_finish_paint()
	mode=Mode.BOOT
	build_camera.set_flying(false)
	build_camera_ready=false
	map.visible=false
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(),false)
	var new_home := not documents.has(id)
	if new_home:
		var next := PlotBuildLayout.new()
		next.configure(record)
		documents[id]=next
	document=documents[id]
	home_position=island.homes[id]
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_unhandled_input(false)
	player.global_position=home_position
	player.velocity=Vector3.ZERO
	player.set("_last_safe_position",home_position)
	terrain.begin_boot_priority(home_position)
	await _wait_for_ground(home_position)
	home_position=_snap_player_to_ground(home_position)
	terrain.end_boot_priority()
	_refresh_plot_visuals()
	enter_build()

func _refresh_plot_visuals() -> void:
	support_depth_cache.clear()
	if is_instance_valid(boundary):
		boundary.queue_free()
	boundary=PlotBuildVisuals.plot_overlay(layout,document.bounds(),false)
	boundary.name="HomePlotBoundary"
	add_child(boundary)
	grid_key=""
	_refresh_build_grid()
	var coords: Array=document.plot.grid
	plot_label.text="Home plot %s / %s · 200 × 200 m" % [coords[0],coords[1]]
	count_label.text="%d placed" % document.placements.size()

func _refresh_build_grid() -> void:
	var size := Vector2i(2,2) if document==null else document.snap_size(selected_item,turns)
	var step := Vector2(size)*PlotBuildLayout.GRID_XZ_M
	if snap_label!=null: snap_label.text="Snap · %d × %d m" % [step.x,step.y]
	if document==null: return
	var origin := document.snap_origin(selected_item,turns)
	var key := "%s:%s:%s" % [document.plot.id,size,origin]
	if key==grid_key: return
	if is_instance_valid(grid): grid.queue_free()
	grid=PlotBuildVisuals.plot_overlay(layout,document.bounds(),true,document.grid_world_y(),step,Vector2(origin)*PlotBuildLayout.GRID_XZ_M)
	grid.name="BuildFloorGrid"
	add_child(grid)
	grid.visible=mode==Mode.BUILD
	grid_key=key

func enter_build() -> void:
	if document==null:
		open_map()
		return
	mode=Mode.BUILD
	map.visible=false
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(),false)
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.velocity=Vector3.ZERO
	if not build_camera_ready:
		build_camera.reset_from(player.camera,document.grid_world_y())
		build_camera_ready=true
	build_camera.current=true
	var body := player.get_node("BodyMesh") as NpcBase
	if body.visual!=null: body.visual.set_local_first_person(false)
	grid.visible=true; boundary.visible=true
	library.visible=true; toolbar.visible=true; prompt.visible=false
	hotbar.visible=true; feedback.visible=true
	hotbar.preview_inventory.selected_slot=0; hotbar.refresh()
	ghost_key=""
	_set_library_cursor(false)
	_update_feedback()

func leave_build() -> void:
	if mode==Mode.BOOT:
		return
	mode=Mode.WALK
	build_camera.set_flying(false)
	build_camera_ready=false
	_finish_paint()
	library_cursor=false; crosshair.visible=false
	library.visible=false; toolbar.visible=false; map.visible=false
	prompt.visible=document==null
	hotbar.visible=document!=null; feedback.visible=true
	hotbar.preview_inventory.selected_slot=-1; hotbar.refresh()
	if is_instance_valid(ghost): ghost.visible=false
	if is_instance_valid(grid): grid.visible=false
	_set_walk_camera()
	player.set_process(true)
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	feedback.text="WASD  Walk · V  Camera · 1  Build tool · M  Map · H  Home"

func _set_walk_camera() -> void:
	player.camera.current=true
	player.get_node("PlayerCamera")._update_body_visibility()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func _snap_player_to_ground(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*120,at-Vector3.UP*120,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit.position+Vector3.UP*.04 if not hit.is_empty() else at
	player.global_position=target
	player.velocity=Vector3.ZERO
	player.set("_last_safe_position",target)
	player.reset_physics_interpolation()
	return target

func teleport_home() -> void:
	if document==null:
		open_map()
		return
	_snap_player_to_ground(home_position)
	if mode==Mode.BUILD:
		build_camera_ready=false
		enter_build()

func select_placeable(id: String) -> void:
	_finish_paint()
	selected_item=id
	ghost_key=""
	painted_cell_key=""
	for key in library_buttons:
		(library_buttons[key] as Button).set_pressed_no_signal(key==id)
	_refresh_build_grid()
	_update_feedback()

func _choose_from_library(id: String) -> void:
	select_placeable(id)
	if mode==Mode.BUILD: _set_library_cursor(false)

func _set_library_cursor(enabled: bool) -> void:
	library_cursor=enabled
	build_camera.set_flying(not enabled and mode==Mode.BUILD)
	_finish_paint()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED
	crosshair.visible=not enabled and mode==Mode.BUILD
	if enabled and is_instance_valid(ghost): ghost.visible=false
	var focused := get_viewport().gui_get_focus_owner()
	if focused!=null: focused.release_focus()
	_update_feedback()

func _cycle_placeable(delta: int) -> void:
	var catalog := PlotBuildLayout.catalog()
	for i in catalog.size():
		if str(catalog[i].id)==selected_item:
			select_placeable(str(catalog[posmod(i+delta,catalog.size())].id))
			return

func _process(delta: float) -> void:
	if mode!=Mode.BUILD:
		return
	if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED or _review:
		build_camera.fly(delta)
	if _review: return
	_update_hover()
	_paint_hover()

func _paint_hover() -> void:
	if painting and hover_valid:
		var key := "%s:%s:%d" % [selected_item,hover_cell,turns]
		if key!=painted_cell_key and _placement_problem().is_empty():
			painted_cell_key=key
			place_current()

func _finish_paint() -> void:
	painting=false
	painted_cell_key=""
	if document!=null: document.end_edit()

func _input(event: InputEvent) -> void:
	if mode==Mode.BOOT:
		return
	if mode==Mode.BUILD and build_camera.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if code==KEY_M:
			if mode==Mode.MAP: close_map()
			else: open_map()
		elif mode==Mode.MAP:
			return
		elif code==KEY_1 or code==KEY_B:
			if mode==Mode.BUILD: leave_build()
			else: enter_build()
		elif code==KEY_ESCAPE and mode==Mode.BUILD:
			if library_cursor: _set_library_cursor(false)
			else: leave_build()
		elif code==KEY_H:
			teleport_home()
		elif mode==Mode.BUILD and code==KEY_R:
			_finish_paint()
			turns=posmod(turns+1,4); ghost_key=""
			_refresh_build_grid()
		elif mode==Mode.BUILD and code==KEY_Z and event.ctrl_pressed:
			undo_last_edit()
		elif mode==Mode.BUILD and code==KEY_TAB:
			_set_library_cursor(not library_cursor)
		elif mode==Mode.BUILD and code==KEY_V:
			get_viewport().set_input_as_handled() # Walking camera stays parked while building.
			return
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if mode!=Mode.BUILD:
		return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed: _finish_paint()
		if library_cursor:
			if _over_ui(event.position): return
			# A click outside the library resumes aiming without placing anything.
			if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
				_set_library_cursor(false)
		elif event.pressed:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
				var step := 1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1
				_cycle_placeable(step)
			elif event.button_index==MOUSE_BUTTON_LEFT:
				_finish_paint()
				_update_hover()
				document.begin_edit()
				place_current()
				painting=PlotBuildLayout.item(selected_item).get("anchor", "base")=="top"
				painted_cell_key="%s:%s:%d" % [selected_item,hover_cell,turns]
				if not painting: document.end_edit()
			elif event.button_index==MOUSE_BUTTON_RIGHT:
				_update_hover()
				remove_current()
		get_viewport().set_input_as_handled()

func _over_ui(point: Vector2) -> bool:
	for control in [library,toolbar,hotbar]:
		if control.visible and control.get_global_rect().has_point(point):
			return true
	return false

func _update_hover() -> void:
	hover_valid=false
	aimed_piece_id=""
	if library_cursor or (Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and not _review):
		if is_instance_valid(ghost): ghost.visible=false
		return
	var point := get_viewport().get_visible_rect().size*0.5
	var origin: Vector3 = build_camera.project_ray_origin(point)
	var direction: Vector3 = build_camera.project_ray_normal(point)
	# The physical ray identifies the piece to remove or an adjacent slab edge.
	# Terrain never contributes its height to the placement record.
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*BUILD_REACH_M,1,[player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var aimed_row := {}
	if not hit.is_empty() and hit.collider.has_meta("plot_build_visual"):
		var visual: Node3D=hit.collider.get_meta("plot_build_visual")
		if str(visual.get_meta("plot_id", ""))==str(document.plot.id):
			aimed_piece_id=str(visual.get_meta("placement_id", ""))
			for row in document.placements:
				if str(row.id)==aimed_piece_id:
					aimed_row=row
	var at: Variant=Plane(Vector3.UP,document.grid_world_y()).intersects_ray(origin,direction)
	if at==null or origin.distance_to(at)>BUILD_REACH_M:
		if is_instance_valid(ghost): ghost.visible=false
		feedback.text="Aim at the deck grid within %d m" % BUILD_REACH_M
		return
	hover_cell=document.centered_cell(selected_item,Vector2(at.x,at.z),turns)
	# Aim at the edge of a slab to extend the same continuous port surface.
	if not aimed_row.is_empty() and not painting:
		_snap_to_slab_edge(aimed_row,hit.position)
	hover_valid=true
	_update_ghost()

func _snap_to_slab_edge(row: Dictionary, at: Vector3) -> void:
	var spec := PlotBuildLayout.item(str(row.item_id))
	if spec.get("anchor", "base")!="top" or PlotBuildLayout.item(selected_item).get("anchor", "base")!="top": return
	var area := document.footprint(str(row.item_id),Vector2i(row.cell[0],row.cell[1]),int(row.turns))
	var size := document.footprint(selected_item,Vector2i.ZERO,turns).size
	var local := (Vector2(at.x,at.z)-document.bounds().position)/PlotBuildLayout.GRID_XZ_M
	var distances := [absf(local.x-area.position.x),absf(local.x-area.end.x),absf(local.y-area.position.y),absf(local.y-area.end.y)]
	var edge := 0
	for i in range(1,4):
		if distances[i]<distances[edge]: edge=i
	if distances[edge]>.65: return # Centre of a slab stays occupied, avoiding unexpected extensions.
	hover_cell=document.aligned_cell(selected_item,Vector2(at.x,at.z),turns,area.position)
	match edge:
		0: hover_cell.x=area.position.x-size.x
		1: hover_cell.x=area.end.x
		2: hover_cell.y=area.position.y-size.y
		3: hover_cell.y=area.end.y

func _support_depth(item_id: String, cell: Vector2i, rotation: int) -> float:
	if not PlotBuildLayout.is_platform(item_id): return PlotBuildLayout.MIN_SUPPORT_DEPTH_M
	var key := "%s:%s:%d" % [item_id,cell,rotation]
	if support_depth_cache.has(key): return float(support_depth_cache[key])
	var area := document.footprint(item_id,cell,rotation)
	var lowest := WaveSurface.WATER_LEVEL-2.0
	# Sample beneath the whole footprint. Only the bottom changes with terrain.
	for z in range(area.position.y,area.end.y+1):
		for x in range(area.position.x,area.end.x+1):
			var at := document.bounds().position+Vector2(x,z)*PlotBuildLayout.GRID_XZ_M
			lowest=minf(lowest,WorldTerrainStreamer.sample_render_terrain_height(layout,at)-1.0)
	var depth := ceilf(document.grid_world_y()-lowest)
	support_depth_cache[key]=depth
	return depth

func _placement_problem() -> String:
	if not hover_valid: return "Aim at the build grid."
	var problem := document.validate(selected_item,hover_cell,turns)
	if not problem.is_empty(): return problem
	var area := document.footprint(selected_item,hover_cell,turns)
	var platform := PlotBuildLayout.is_platform(selected_item)
	var height := _support_depth(selected_item,hover_cell,turns) if platform else float(PlotBuildLayout.item(selected_item).height_m)
	var base := Vector3(document.bounds().position.x+area.position.x*PlotBuildLayout.GRID_XZ_M,
		document.grid_world_y()-(height if platform else 0.0),document.bounds().position.y+area.position.y*PlotBuildLayout.GRID_XZ_M)
	var volume := AABB(base,Vector3(area.size.x*PlotBuildLayout.GRID_XZ_M,height,area.size.y*PlotBuildLayout.GRID_XZ_M))
	if volume.intersects(AABB(player.global_position+Vector3(-.38,.05,-.38),Vector3(.76,1.75,.76))):
		return "Your character is here · Esc to walk clear."
	return ""

func _update_ghost() -> void:
	var problem := _placement_problem()
	# Imported cranes are expensive to assemble. Move the same preview while aiming.
	var key := "%s:%s" % [selected_item,problem.is_empty()]
	if key!=ghost_key:
		if is_instance_valid(ghost): ghost.queue_free()
		ghost=PlotBuildVisuals.create(PlotBuildLayout.item(selected_item),true,problem.is_empty())
		add_child(ghost)
		ghost_key=key
	var row := {"item_id":selected_item,"cell":[hover_cell.x,hover_cell.y],"turns":turns}
	ghost.global_position=document.position_for(row)
	ghost.rotation.y=-turns*PI/2
	ghost.visible=true
	crosshair.modulate=Color("a5f3c5") if problem.is_empty() else Color("f39e8a")
	feedback.text=problem if not problem.is_empty() else "%s · LMB place · RMB remove" % PlotBuildLayout.item(selected_item).name

func place_current() -> Dictionary:
	var problem := _placement_problem()
	if not problem.is_empty():
		feedback.text=problem
		return {"ok":false,"message":problem}
	var result := document.place(selected_item,hover_cell,turns,_support_depth(selected_item,hover_cell,turns))
	if bool(result.ok):
		_stamp(result.placement)
		count_label.text="%d placed" % document.placements.size()
		_refresh_build_grid()
		ghost_key=""
	else:
		feedback.text=str(result.message)
	return result

func _stamp(row: Dictionary) -> void:
	var visual := PlotBuildVisuals.create(PlotBuildLayout.item(str(row.item_id)),false,true,float(row.get("support_depth_m",PlotBuildLayout.MIN_SUPPORT_DEPTH_M)))
	visual.name=str(row.id)
	visual.set_meta("plot_id",str(document.plot.id))
	visual.set_meta("placement_id",str(row.id))
	add_child(visual)
	visual.global_position=document.position_for(row)
	visual.rotation.y=-int(row.turns)*PI/2
	placed_nodes[str(document.plot.id)+"/"+str(row.id)]=visual

func remove_current() -> void:
	_finish_paint()
	var problem := document.removal_problem(aimed_piece_id)
	if not problem.is_empty():
		feedback.text=problem
		return
	# Remove exactly the visible targeted piece.
	var removed := document.remove_id(aimed_piece_id)
	if removed.is_empty():
		return
	_erase_visual(str(removed.id))
	count_label.text="%d placed" % document.placements.size()
	_refresh_build_grid()
	ghost_key=""
	aimed_piece_id=""

func _erase_visual(id: String) -> void:
	var key := str(document.plot.id)+"/"+id
	if placed_nodes.has(key):
		placed_nodes[key].queue_free(); placed_nodes.erase(key)

func undo_last_edit() -> void:
	_finish_paint()
	var change := document.undo()
	if change.is_empty():
		feedback.text="Nothing to undo."
		return
	for row in change.removed: _erase_visual(str(row.id))
	for row in change.restored: _stamp(row)
	count_label.text="%d placed" % document.placements.size()
	_refresh_build_grid()
	ghost_key=""
	aimed_piece_id=""
	_update_hover()

func _update_feedback() -> void:
	if feedback!=null:
		feedback.text="Choose a piece · Tab returns to building" if library_cursor else "%s · LMB place · RMB remove · Tab library" % PlotBuildLayout.item(selected_item).name

func _exit_tree() -> void:
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(),false)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_finish_paint()
		build_camera.set_flying(false)
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN and mode==Mode.BUILD:
		build_camera.set_flying(not library_cursor)

func _run_review() -> void:
	await get_tree().create_timer(.6).timeout
	var capture := OS.get_cmdline_user_args().has("--capture-plot-building")
	if capture: await _capture("spawn")
	open_map()
	await get_tree().create_timer(.6).timeout
	if capture: await _capture("select-plot")
	var ids: Array[String]=[]
	for id in island.homes: ids.append(id)
	ids.sort()
	var chosen := plot_index.get_plot(ids[ids.size()/2])
	_verify_snapping_and_undo(chosen)
	await select_home_plot(chosen)
	assert(mode==Mode.BUILD and build_camera.current and not player.is_physics_processing())
	assert(not player.camera.current and not player.is_processing())
	assert(hotbar.preview_inventory.slots[0].attributes.permanent)
	var deck_y := WaveSurface.WATER_LEVEL+PlotBuildLayout.DECK_HEIGHT_ABOVE_SEA_M
	var vertices: PackedVector3Array=grid.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		assert(is_equal_approx(vertex.y,deck_y),"The entire grid uses one sea-referenced plane.")
	var other := PlotBuildLayout.new()
	other.configure(plot_index.get_plot(ids[0]))
	assert(is_equal_approx(other.grid_world_y(),deck_y),"Every plot has the same height.")
	assert(other.place("foundation",Vector2i(40,40),0,18.0).ok)
	assert(not other.place("foundation",Vector2i(40,40),0,30.0).ok,"Depth cannot create another platform layer.")
	assert(other.place("warehouse",Vector2i(40,40),0).ok,"Buildings occupy the space above foundations.")
	assert(other.place("quay",Vector2i(42,40),0,22.0).ok)
	assert(not other.place("workshop",Vector2i(40,40),0).ok,"Overlapping buildings are rejected.")
	assert(not other.place("quay",Vector2i(99,99),0).ok,"Footprints stay in the plot.")
	var other_copy := PlotBuildLayout.from_dict(JSON.parse_string(JSON.stringify(other.to_dict())))
	assert(other_copy.placements.size()==3)
	for row in other_copy.placements:
		assert(is_equal_approx(other_copy.position_for(row).y,deck_y))
		assert(not row.has("level"),"Placements have no selectable Y layer.")
	assert(is_equal_approx(float(other_copy.placements[0].support_depth_m),18.0))
	# Real library and input events, through the detached building camera.
	set_process_input(true)
	await _press_review_key(KEY_TAB)
	assert(library_cursor)
	await _click_button(library_buttons["bollard"])
	assert(selected_item=="bollard" and not library_cursor)
	select_placeable("foundation")
	await _press_review_key(KEY_PAGEUP)
	await _press_review_key(KEY_PAGEDOWN)
	await _click_review_world(MOUSE_BUTTON_WHEEL_UP,true)
	assert(is_equal_approx(document.grid_world_y(),deck_y),"Old height controls cannot move the plane.")
	assert(selected_item=="quay")
	select_placeable("foundation")
	var ground := player.global_position
	var target := ground+Vector3(8,0,0)
	var lowest := INF
	for i in 8:
		var candidate := ground+Vector3(9,0,0).rotated(Vector3.UP,i*PI/4)
		var cell := document.centered_cell("foundation",Vector2(candidate.x,candidate.z),0)
		if not document.validate("foundation",cell,0).is_empty(): continue
		var y := WorldTerrainStreamer.sample_render_terrain_height(layout,Vector2(candidate.x,candidate.z))
		if y<lowest:
			lowest=y; target=candidate
	var target_cell := document.centered_cell("foundation",Vector2(target.x,target.z),0)
	target=document.position_for({"item_id":"foundation","cell":[target_cell.x,target_cell.y],"turns":0})
	_aim_review_at(target)
	await get_tree().physics_frame
	_update_hover()
	assert(hover_valid and hover_cell==target_cell)
	await _click_review_world(MOUSE_BUTTON_LEFT)
	assert(document.placements.size()==1)
	_assert_support_geometry(document.placements[0])
	var first_id := str(document.placements[0].id)
	await _review_paint_row(target,capture)
	# Looking away must invalidate the last target.
	_aim_review_at(build_camera.global_position+Vector3(0,20,-1))
	_update_hover()
	assert(not hover_valid and not ghost.visible)
	await _click_review_world(MOUSE_BUTTON_LEFT)
	assert(document.placements.size()==1)
	_aim_review_at(target)
	await get_tree().physics_frame
	_update_hover()
	assert(aimed_piece_id==first_id)
	await _click_review_world(MOUSE_BUTTON_RIGHT)
	assert(document.placements.is_empty())
	await get_tree().physics_frame
	await _press_review_key(KEY_Z,true)
	assert(document.placements.size()==1 and str(document.placements[0].id)==first_id,"Undo deletion restores the same item identity.")
	_assert_support_geometry(document.placements[0])
	assert(placed_nodes.has(str(document.plot.id)+"/"+first_id))
	await _press_review_key(KEY_Z,true)
	assert(document.placements.is_empty() and not placed_nodes.has(str(document.plot.id)+"/"+first_id),"Undo placement removes data and geometry.")
	await get_tree().physics_frame
	await _click_review_world(MOUSE_BUTTON_LEFT)
	assert(document.placements.size()==1)
	select_placeable("quay")
	_aim_review_at(target+Vector3(1.8,0,0))
	await get_tree().physics_frame
	_update_hover()
	assert(hover_cell.x==target_cell.x+2,"A quay joins a foundation on the same deck.")
	await _click_review_world(MOUSE_BUTTON_LEFT)
	assert(document.placements.size()==2)
	_assert_support_geometry(document.placements[-1])
	var quay := document.placements[-1].duplicate(true)
	# Preview a building directly on the shared deck, without changing any height.
	select_placeable("workshop")
	_aim_review_at(document.position_for(quay))
	await get_tree().physics_frame
	_update_hover()
	assert(hover_valid and is_equal_approx(ghost.global_position.y,deck_y))
	await _click_review_world(MOUSE_BUTTON_LEFT)
	assert(document.placements.size()==3)
	var building: Node3D=placed_nodes[str(document.plot.id)+"/"+str(document.placements[-1].id)]
	var building_mesh := building.get_child(0) as MeshInstance3D
	assert(is_equal_approx(building_mesh.global_position.y+building_mesh.mesh.get_aabb().position.y,deck_y))
	select_placeable("foundation")
	_aim_review_at(target+Vector3(0,0,-4))
	await get_tree().physics_frame
	_update_hover()
	if capture: await _capture("freecam-build")
	_assert_reconstruction(PlotBuildLayout.from_dict(JSON.parse_string(JSON.stringify(document.to_dict()))))
	var player_start := player.global_transform
	var camera_start := build_camera.global_position
	_review_hold_key(KEY_S,true)
	await get_tree().create_timer(.2).timeout
	_review_hold_key(KEY_S,false)
	assert(build_camera.global_position.distance_to(camera_start)>1.0,"WASD flies the detached camera.")
	assert(player.global_transform.is_equal_approx(player_start),"Flying leaves the character parked.")
	camera_start=build_camera.global_position
	_review_hold_key(KEY_E,true)
	await get_tree().create_timer(.2).timeout
	_review_hold_key(KEY_E,false)
	var lift := build_camera.global_position-camera_start
	assert(lift.y>1.0 and absf(lift.x)+absf(lift.z)<.001,"E lifts in world space even with a downward view.")
	assert(is_equal_approx(document.grid_world_y(),deck_y))
	await _press_review_key(KEY_TAB)
	camera_start=build_camera.global_position
	_review_hold_key(KEY_W,true)
	await get_tree().create_timer(.15).timeout
	assert(build_camera.global_position.is_equal_approx(camera_start),"Library clicks cannot fly the camera.")
	_review_hold_key(KEY_W,false)
	await _press_review_key(KEY_TAB)
	_review_hold_key(KEY_W,true)
	open_map()
	camera_start=build_camera.global_position
	await get_tree().create_timer(.15).timeout
	assert(build_camera.global_position.is_equal_approx(camera_start),"Map pauses freecam.")
	close_map()
	await get_tree().create_timer(.15).timeout
	assert(build_camera.global_position.is_equal_approx(camera_start),"Closing map keeps the view and clears held movement.")
	_review_hold_key(KEY_W,false)
	await _press_review_key(KEY_ESCAPE)
	assert(mode==Mode.WALK and player.camera.current and not build_camera.current)
	assert(player.is_physics_processing() and player.is_processing())
	assert(player.global_position.distance_to(player_start.origin)<.1,"Exit returns to the parked character.")
	assert(not grid.visible and boundary.visible)
	await _press_review_key(KEY_1)
	set_process_input(false)
	assert(is_equal_approx(document.grid_world_y(),deck_y) and document.placements.size()==3)
	print("PLOT_BUILDING PASS footprint-size snap/grid, rotated rectangles, Ctrl+Z placement/deletion/paint-stroke, freecam/parked player, map/library pause, fixed sea plane, seabed supports, edge snap, overlap/bounds, JSON reconstruction; placements=",document.placements.size())
	get_tree().quit()

func _verify_snapping_and_undo(record: Dictionary) -> void:
	var sample := PlotBuildLayout.new()
	sample.configure(record)
	sample.begin_edit()
	for z in 3:
		for x in 3:
			var cell := Vector2i(20+x*2,20+z*2)
			var center := sample.bounds().position+(Vector2(cell)+Vector2.ONE)*2.0
			for drift in [Vector2(-1.8,-1.8),Vector2(1.8,1.8),Vector2(1.2,-1.2)]:
				assert(sample.centered_cell("foundation",center+drift,0)==cell,"A 4 m tile cannot drift onto the 2 m subgrid.")
			assert(sample.place("foundation",cell,0,20.0).ok)
	sample.end_edit()
	assert(sample.placements.size()==9)
	assert(sample.undo().removed.size()==9 and sample.placements.is_empty(),"One painting stroke is one undo action.")
	for rotation in 4:
		var size := sample.footprint("quay",Vector2i.ZERO,rotation).size
		var at := sample.bounds().position+(Vector2(size)*10.0+Vector2(size)*.75)*2.0
		assert(sample.centered_cell("quay",at,rotation)==size*10,"Rectangular snap rotates with the piece.")
	var placed := sample.place("quay",Vector2i(22,20),1,31.0)
	var original: Dictionary = placed.placement.duplicate(true)
	assert(not sample.place("quay",Vector2i(22,20),1).ok)
	assert(sample.remove_id(str(original.id))==original)
	assert(sample.undo().restored[0]==original and sample.placements[0]==original,"Undo preserves depth, rotation and identity.")
	var restored := PlotBuildLayout.from_dict(sample.to_dict())
	assert(restored.undo().is_empty(),"Loading is not a user edit.")
	assert(sample.undo().removed[0]==original and sample.placements.is_empty(),"Failed placements don't consume undo.")
	assert(restored.placements.size()==1,"History belongs to its own document.")
	assert(sample.undo().is_empty())

func _review_paint_row(target: Vector3, capture: bool) -> void:
	var saved_view := build_camera.global_transform
	var direction := Vector3.ZERO
	for candidate in [Vector3(0,0,-4),Vector3(0,0,4),Vector3(4,0,0),Vector3(-4,0,0)]:
		var fits := true
		for i in range(1,4):
			var at: Vector3=target+candidate*i
			hover_cell=document.centered_cell("foundation",Vector2(at.x,at.z),0)
			hover_valid=true
			if not _placement_problem().is_empty(): fits=false
		if fits:
			direction=candidate
			break
	assert(direction!=Vector3.ZERO)
	build_camera.global_position=target+Vector3(-12,20,14)
	_aim_review_at(target+direction)
	await get_tree().physics_frame
	var mouse := InputEventMouseButton.new()
	mouse.button_index=MOUSE_BUTTON_LEFT
	mouse.pressed=true
	mouse.position=get_viewport().get_visible_rect().size*.5
	get_viewport().push_input(mouse,true)
	assert(painting and document.placements.size()==2)
	for i in range(2,4):
		_aim_review_at(target+direction*i)
		await get_tree().physics_frame
		_update_hover()
		_paint_hover()
	assert(document.placements.size()==4)
	for i in range(1,4):
		assert(is_equal_approx(document.position_for(document.placements[i]).distance_to(document.position_for(document.placements[i-1])),4.0),"Painted foundations touch edge to edge.")
	if capture: await _capture("snapped-foundation-row")
	# Undo while the mouse is still held must end the stroke, not repaint it.
	await _press_review_key(KEY_Z,true)
	assert(not painting and document.placements.size()==1 and placed_nodes.size()==1)
	mouse=mouse.duplicate()
	mouse.pressed=false
	get_viewport().push_input(mouse,true)
	build_camera.global_transform=saved_view
	await get_tree().physics_frame

func _assert_support_geometry(row: Dictionary) -> void:
	var visual: Node3D=placed_nodes[str(document.plot.id)+"/"+str(row.id)]
	var mesh := visual.get_child(0) as MeshInstance3D
	var top := mesh.global_position.y+mesh.mesh.get_aabb().end.y
	var bottom := mesh.global_position.y+mesh.mesh.get_aabb().position.y
	assert(is_equal_approx(top,document.grid_world_y()))
	assert(bottom<=WaveSurface.WATER_LEVEL-2.0)
	var area := document.footprint(str(row.item_id),Vector2i(row.cell[0],row.cell[1]),int(row.turns))
	for z in range(area.position.y,area.end.y+1):
		for x in range(area.position.x,area.end.x+1):
			var at := document.bounds().position+Vector2(x,z)*PlotBuildLayout.GRID_XZ_M
			assert(bottom<=WorldTerrainStreamer.sample_render_terrain_height(layout,at)-.99,"Supports extend into the seabed beneath the whole footprint.")
func _aim_review_at(target: Vector3) -> void:
	build_camera.look_at(target,Vector3.UP)

func _review_hold_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=key; event.keycode=key; event.pressed=pressed
	get_viewport().push_input(event,true)

func _press_review_key(key: Key, ctrl := false) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode=key; event.keycode=key; event.pressed=pressed
		event.ctrl_pressed=ctrl
		get_viewport().push_input(event,true)
		await get_tree().process_frame

func _click_review_world(button: MouseButton, ctrl := false) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index=button; event.pressed=pressed; event.ctrl_pressed=ctrl
		event.position=get_viewport().get_visible_rect().size*0.5
		get_viewport().push_input(event,true)
		await get_tree().physics_frame

func _click_button(button: Button) -> void:
	var parent := button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await get_tree().process_frame
			break
		parent=parent.get_parent()
	var motion := InputEventMouseMotion.new()
	motion.position=button.get_global_rect().get_center()
	motion.global_position=motion.position
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=button.get_global_rect().get_center()
		event.global_position=event.position
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event,true)
		await get_tree().process_frame

func _assert_reconstruction(restored: PlotBuildLayout) -> void:
	assert(restored.placements.size()==document.placements.size())
	assert(str(restored.plot.id)==str(document.plot.id) and restored.bounds()==document.bounds())
	for i in document.placements.size():
		var original := document.placements[i]
		var rebuilt := restored.placements[i]
		assert(original.id==rebuilt.id and original.item_id==rebuilt.item_id and original.turns==rebuilt.turns)
		assert(is_equal_approx(float(original.get("support_depth_m",0.0)),float(rebuilt.get("support_depth_m",0.0))))
		assert(document.position_for(original).distance_to(restored.position_for(rebuilt))<.0001,
			"Construction data recreates the shared deck plane after JSON conversion.")

func _capture(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var folder := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("plot-building-%d-%d-%s.png" % [Time.get_unix_time_from_system(),OS.get_process_id(),stage])
	var task := WorkerThreadPool.add_task(func() -> void: image.save_png(path))
	while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	print("PLOT_BUILDING_CAPTURE ",path)

func _run_equipment_review() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture-plot-equipment")
	var ids: Array = island.homes.keys()
	ids.sort()
	await select_home_plot(plot_index.get_plot(ids[ids.size()/2]))
	var sample := PlotBuildLayout.new()
	sample.configure(document.plot)
	assert(not sample.place("bollard",Vector2i(20,20),0).ok)
	assert(not sample.place("container_crane_bay",Vector2i(20,20),0).ok)
	for item_id in ["container_crane_bay","bulk_crane_bay","bollard"]:
		for rotation in 4:
			sample.configure(document.plot)
			var origin := Vector2i(20,20)
			var footprint := sample.footprint(item_id,origin,rotation)
			var slabs := Vector2i(ceili(footprint.size.x/2.0),ceili(footprint.size.y/2.0))
			# The support test follows the real crane reach-derived footprint.
			for z in slabs.y:
				for x in slabs.x:
					if x==slabs.x-1 and z==slabs.y-1: continue
					assert(sample.place("foundation",origin+Vector2i(x*2,z*2),0).ok)
			assert(not sample.place(item_id,origin,rotation).ok)
			assert(sample.place("foundation",origin+(slabs-Vector2i.ONE)*2,0).ok)
			var row := {"item_id":item_id,"cell":[origin.x,origin.y],"turns":rotation}
			var center := sample.position_for(row)
			assert(sample.centered_cell(item_id,Vector2(center.x,center.z),rotation)==origin)
			var result := sample.place(item_id,origin,rotation)
			assert(result.ok)
			assert(not sample.place(item_id,origin,rotation).ok)
			assert(sample.remove_id(str(sample.placements[0].id)).is_empty(),"Equipment keeps its foundations.")
			var copy := PlotBuildLayout.from_dict(JSON.parse_string(JSON.stringify(sample.to_dict())))
			assert(copy.placements==sample.placements,"The whole assembly reconstructs from one placement.")
			assert(sample.undo().removed.size()==1)
	assert(not sample.place("bulk_crane_bay",Vector2i(96,96),0).ok)
	# Find water-side room for two adjacent bays, without moving the parked player.
	var container_size := document.footprint("container_crane_bay",Vector2i.ZERO,0).size
	var bulk_size := document.footprint("bulk_crane_bay",Vector2i.ZERO,0).size
	var assembly_size := Vector2i(container_size.x+bulk_size.x+2,maxi(container_size.y,bulk_size.y)+4)
	var plot_cells := Vector2i(document.bounds().size/PlotBuildLayout.GRID_XZ_M)
	var start := Vector2i(4,4)
	var best := INF
	for z in range(4,plot_cells.y-assembly_size.y,4):
		for x in range(4,plot_cells.x-assembly_size.x,4):
			var high := -INF
			for dz in [0,assembly_size.y/2,assembly_size.y]:
				for dx in [0,assembly_size.x/2,assembly_size.x]:
					var at := document.bounds().position+Vector2(x+dx,z+dz)*2.0
					high=maxf(high,WorldTerrainStreamer.sample_render_terrain_height(layout,at))
			if high<best:
				best=high; start=Vector2i(x,z)
	document.begin_edit()
	for z in ceili(assembly_size.y/2.0):
		for x in ceili(assembly_size.x/2.0):
			var cell := start+Vector2i(x*2,z*2)
			var result := document.place("foundation",cell,0,_support_depth("foundation",cell,0))
			assert(result.ok)
			_stamp(result.placement)
	document.end_edit()
	var initial_count := document.placements.size()
	set_process_input(true)
	var equipment_rows: Array[Dictionary] = []
	for index in 2:
		var item_id := "container_crane_bay" if index==0 else "bulk_crane_bay"
		await _press_review_key(KEY_TAB)
		await _click_button(library_buttons[item_id])
		assert(selected_item==item_id and not library_cursor)
		var cell := start+Vector2i(0 if index==0 else container_size.x+2,2)
		var target := document.position_for({"item_id":item_id,"cell":[cell.x,cell.y],"turns":0})
		build_camera.global_position=target+Vector3(0,65,30)
		_aim_review_at(target)
		await get_tree().physics_frame
		_update_hover()
		assert(hover_valid and hover_cell==cell and _placement_problem().is_empty())
		var preview_id := ghost.get_instance_id()
		_aim_review_at(target+Vector3(0,0,-4))
		_update_hover()
		assert(ghost.get_instance_id()==preview_id,"Moving a valid preview doesn't rebuild the crane.")
		_aim_review_at(target)
		_update_hover()
		await _click_review_world(MOUSE_BUTTON_LEFT)
		assert(document.placements.size()==initial_count+index+1)
		var row: Dictionary = document.placements[-1].duplicate(true)
		equipment_rows.append(row)
		var equipment: Node3D = placed_nodes[str(document.plot.id)+"/"+str(row.id)]
		await get_tree().process_frame
		await get_tree().process_frame
		assert(equipment.ready_for_inspection and equipment.crane!=null and equipment.cargo_pad!=null)
		assert(equipment.crane.get_meta("paired_cargo_pad")==equipment.cargo_pad)
		for rotation in 4:
			equipment.rotation.y=-rotation*PI/2
			assert(equipment.cargo_pad.global_position.is_equal_approx(equipment.cargo_pad.get_parent().to_global(equipment.cargo_pad.position)))
			assert(is_equal_approx(equipment.global_position.y,document.grid_world_y()))
			_verify_equipment_tree(equipment,equipment,false)
			equipment.rotation.y=0
		_verify_equipment_tree(ghost,ghost,true)
		# The empty cargo area is selectable, and removes the crane with it.
		_aim_review_at(equipment.cargo_pad.global_position)
		await get_tree().physics_frame
		_update_hover()
		assert(aimed_piece_id==str(row.id),"Cargo pad must pick its assembly: expected %s, got %s" % [row.id,aimed_piece_id])
		await _click_review_world(MOUSE_BUTTON_RIGHT)
		assert(document.placements.size()==initial_count+index)
		await _press_review_key(KEY_Z,true)
		assert(document.placements[-1].id==row.id)
	select_placeable("bollard")
	var bollard_cell := start+Vector2i(1,0)
	var bollard_target := document.position_for({"item_id":"bollard","cell":[bollard_cell.x,bollard_cell.y],"turns":0})
	build_camera.global_position=bollard_target+Vector3(0,8,-6)
	_aim_review_at(bollard_target)
	await get_tree().physics_frame
	_update_hover()
	await _click_review_world(MOUSE_BUTTON_LEFT)
	assert(document.placements.size()==initial_count+3)
	var bollard: Node3D = placed_nodes[str(document.plot.id)+"/"+str(document.placements[-1].id)]
	assert(bollard.get_node("MooringBollard").is_in_group(MooringComponent.DOCK_MOORING_GROUP))
	_verify_equipment_tree(bollard,bollard,false)
	var ground_target := bollard_target+Vector3(0,.5,0)
	build_camera.global_position=ground_target+Vector3(-3,2.4,-3)
	_aim_review_at(ground_target)
	_set_library_cursor(true)
	if capture: await _capture("equipment-bollard")
	var bay_center := document.position_for(equipment_rows[0])+Vector3(12,0,0)
	build_camera.global_position=bay_center+Vector3(-58,62,-85)
	_aim_review_at(bay_center+Vector3(0,10,-8))
	if capture: await _capture("equipment-crane-bays")
	_assert_reconstruction(PlotBuildLayout.from_dict(JSON.parse_string(JSON.stringify(document.to_dict()))))
	print("PLOT_EQUIPMENT PASS real harbour models; crane+pad pairing; support/overlap/bounds; four rotations; preview reuse/no collisions; library input; pad picking; compound remove/undo; JSON reconstruction")
	get_tree().quit()

func _verify_equipment_tree(node: Node, root: Node3D, preview: bool) -> void:
	if node is CollisionObject3D:
		assert(node.collision_layer==(0 if preview else 1))
		assert(node.get_meta("plot_build_visual")==root)
	if preview:
		assert(not node.is_in_group(MooringComponent.DOCK_MOORING_GROUP))
		assert(not node.is_in_group(CargoSlotPadComponent.YARD_PAD_GROUP))
	for child in node.get_children(): _verify_equipment_tree(child,root,preview)
