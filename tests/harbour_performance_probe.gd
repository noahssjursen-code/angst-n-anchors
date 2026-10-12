extends Node3D

var world: Node3D
var camera: Camera3D
var rows: Array = []

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func sample(label: String) -> void:
	for i in 60: await get_tree().process_frame
	var times: Array[float] = []
	var gpu := 0.0
	var cpu := 0.0
	var physics := 0.0
	var draws := 0.0
	var last := Time.get_ticks_usec()
	for i in 180:
		if label == "turning": camera.rotate_y(0.025)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now-last)/1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	times.sort()
	var row := {"phase":label,"median_ms":times[90],"p95_ms":times[171],"max_ms":times.back(),"gpu_ms":gpu/180,"render_cpu_ms":cpu/180,"physics_ms":physics/180,"draws":draws/180,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	rows.append(row)
	print("PERF_PROBE ", JSON.stringify(row))

func run() -> void:
	PlayerSession.data = PlayerData.new()
	PlayerSession.data.company = {"development_captain":true}
	PlayerSession.data.home_port_id = "port-home"
	WorldBootstrap.apply_seed(1212599375,8,"",3,40000)
	world = preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await world.boot_finished
	var player := get_tree().get_first_node_in_group("player") as Node3D
	camera = Camera3D.new()
	add_child(camera)
	camera.global_position = player.global_position + Vector3(0,2,0)
	camera.far = 12000
	camera.make_current()
	var port := world.get_node("HomePort") as Node3D
	camera.look_at(port.global_position + Vector3(0,5,-150))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	await get_tree().create_timer(12).timeout
	await sample("baseline")
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(archive.path_join("performance-probe-%d.png" % Time.get_unix_time_from_system()))
	await sample("turning")
	var mode := world.process_mode
	world.process_mode = Node.PROCESS_MODE_DISABLED
	await sample("world_scripts_disabled")
	world.process_mode = mode
	get_viewport().scaling_3d_scale = 0.5
	await sample("half_resolution")
	get_viewport().scaling_3d_scale = 1.0
	for path in ["HomePort", "WorldForestStreamer", "WorldTerrainStreamer", "WorldRenderer"]:
		var node := world.get_node_or_null(path) as Node3D
		if node == null: continue
		node.hide()
		await sample("hidden_"+path)
		node.show()
	await sample("restored")
	print("PERF_TELEMETRY ",Telemetry.generate_report())
	var output := "C:/Users/noahs/Documents/Codex/2026-10-11/referenced-chatgpt-conversation-this-is-an/outputs/harbour-performance.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	get_tree().quit()
