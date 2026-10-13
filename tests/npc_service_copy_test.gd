extends Control
var failures: Array[String] = []
var checks := 0
var panel: VoyagePanel
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text)
	print("NPC_COPY ", "PASS " if value else "FAIL ", text)
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	run.call_deferred()
func run() -> void:
	GameMenu.set_gameplay_hud_visible(false)
	panel = VoyagePanel.new()
	panel.preview_mode = true
	panel.service_kind = "operator"
	add_child(panel)
	var state := {"title":"Crane operator", "line":"Ready.", "active":false, "actions":[{"id":"load","label":"Load cargo","reason":"Moor your vessel at this quay."},{"id":"unload","label":"Unload cargo","reason":"Moor your vessel at this quay."},{"id":"stop","label":"Stop transfer","reason":"No transfer on your vessel.","visible":false}]}
	panel.show_service_snapshot(state)
	check(not panel._subtitle.visible, "operator status appears once")
	check(reason_count() == 1, "shared blocked reason appears once")
	check(not action("stop").visible, "idle stop action hidden")
	state.active = true
	state.line = "Loading · container 2"
	state.actions[0].reason = "Transfer in progress."
	state.actions[1].reason = "Transfer in progress."
	state.actions[2].reason = ""
	state.actions[2].visible = true
	panel._update_service_actions(state)
	panel._operation.text = state.line
	check(action("stop").visible and not action("stop").disabled, "stop appears when transfer starts")
	check(action("load").disabled and reason_count() == 0, "active status is not repeated under buttons")
	await capture("crane")
	var pump := FishLandingPump.new()
	var job := FishLandingEquipmentJob.new()
	job._pump = pump
	pump._state = FishLandingPump.STATE_PUMPING
	pump._landed_mass_kg = 126.0
	check(job.progress_label() == "Landing catch · 126 kg ashore", "fish operator uses landed amount, not pump diagnostics")
	panel.show_service_snapshot({"title":"Fish landing operator","line":job.progress_label(),"active":true,"actions":[{"id":"unload","label":"Land catch","reason":"Transfer in progress."},{"id":"stop","label":"Stop transfer","reason":""}]})
	check(panel._body.find_children("*", "Button", true, false).size() == 2, "fish landing only shows land and stop")
	await capture("fish-landing")
	panel.service_kind = "shipwright"
	panel.show_service_snapshot({"title":"Shipwright", "line":"Equipment included in the price.", "items":[]})
	check(panel._subtitle.visible, "other NPC introductions restored")
	pump.free()
	job.free()
	print("NPC_COPY_RESULT ", checks, " checks; failures: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
func action(id: String) -> Button:
	for node in panel._body.find_children("*", "Button", true, false):
		if node.get_meta("service_action", "") == id: return node
	return null
func reason_count() -> int:
	var count := 0
	for node in panel._body.find_children("*", "Label", true, false):
		if node.has_meta("action_reason") and node.visible: count += 1
	return count
func capture(title: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture-npc"): return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("npc-compact-%s-%s.png" % [title,str(Time.get_unix_time_from_system()).replace(".","-")])
	get_viewport().get_texture().get_image().save_png(path)
	print("NPC_CAPTURE ", path)
