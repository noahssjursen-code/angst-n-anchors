extends Control

## UI only. Uses production components with inert sample snapshots, no world,
## NPC actor, account mutation, physics or save operations.
@export var initial_screen := 0
const SCREENS := ["Shipwright", "Harbourmaster", "Cargo agent", "Crane operator", "Today", "Jobs", "Fleet", "Account", "Helm — passage", "Helm — docking", "Walking prompt", "Walking — no interaction"]
var panel: VoyagePanel
var hud: VoyageHud
var current_screen := 0

func _ready() -> void:
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	GameMenu.set_gameplay_hud_visible(false)
	theme=VoyageStyle.theme()
	var background := ColorRect.new()
	background.color=Color("585c55")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	panel=VoyagePanel.new()
	panel.preview_mode=true
	add_child(panel)
	hud=VoyageHud.new()
	hud.preview_mode=true
	add_child(hud)
	panel.preview_data={"balance":7500,"company":{"name":"Nordvik Shipping","vessels":[{"uid":"preview-vessel","name":"Coastal Cargo","hull_id":"hull_24x8","brick_layout":{}}],"recent_transactions":[{"description":"Delivered cargo to Viknes","amount_marks":1600},{"description":"Purchased Coastal Cargo","amount_marks":-10500},{"description":"Company opening capital","amount_marks":18000}]},
		"voyage":{"helming":false,"ship":true,"name":"Coastal Cargo","port":"Øyrvik","berth":"General cargo · 02","fuel":.86,"bow":true,"stern":true,"objective":"Ask the quay operator to load your booked cargo."},
		"jobs":[{"commodity_id":"provisions","destination_port_id":"Viknes","destination_name":"Viknes","quantity":2,"quantity_unit":"units","loaded_quantity":1,"delivered_quantity":0,"pay_marks":950}]}
	panel.close_requested.connect(func():show_screen((current_screen+1)%SCREENS.size()))
	panel.chart_requested.connect(func():panel._feedback.text="The existing map is retained. This scene previews UI only.")
	show_screen(initial_screen)
	if OS.get_cmdline_user_args().has("--capture-ui"): call_deferred("capture_all")

func show_screen(index: int) -> void:
	current_screen=index
	panel.preview_data.balance=9100
	panel.preview_data.jobs[0]["loaded_quantity"]=0 if index==5 else 1
	panel.visible=index<8
	hud.visible=index>=8
	panel.page="preview"
	panel.selected=""
	if index<4:
		panel.service_kind=["shipwright","harbourmaster","cargo","operator"][index]
		var snapshot := {"title":SCREENS[index],"line":"", "items":[],"actions":[]}
		match index:
			0:
				snapshot.line="Choose a vessel for the work you want to do. Inspect its fit-out before buying."
				for pair in [["Coastal Trawler",5600,"14 × 5 m\nStern trawl · two 600 kg catch tanks"],["Harbour Cargo",10500,"24 × 8 m\nTwo 20-foot deck cargo positions"],["Coastal Bulk",10500,"24 × 8 m\nTwo 40 t bulk compartments"]]:
					snapshot.items.append({"id":pair[0],"label":pair[0],"price":pair[1],"detail":pair[2],"reason":""})
				panel.preview_data.balance=18000
			1:
				snapshot.line="Your vessel can be brought alongside at a compatible quay."
				snapshot.items=[{"id":"cargo","label":"Coastal Cargo","detail":"Preferred free quay: General cargo · 02\nContainer crane available","reason":""}]
			2:
				snapshot.line="These jobs fit your vessel and the available handling equipment."
				snapshot.items=[{"id":"job-a","label":"Viknes","detail":"General cargo\n2 containers · 3.2 nm\nPayment on delivery: 950 kr","reason":""},{"id":"job-b","label":"Fjordvik","detail":"General cargo\n1 container · 5.7 nm\nPayment on delivery: 1,200 kr","reason":""}]
			3:
				snapshot.line="Loading · lowering container 2 of 2 onto the aft cargo position"
				snapshot.actions=[{"id":"load","label":"Load cargo","reason":"A transfer is already running."},{"id":"unload","label":"Unload cargo","reason":"A transfer is already running."},{"id":"stop","label":"Stop transfer","reason":""}]
		if index == 2:
			snapshot.line = "All available destinations, nearest first. Distances are direct. Payment is for the whole shipment."
			for i in 24:
				var distance := float(i + 1) * 1000.0
				var payment := FreightOfferGenerator.payment_for(distance, "general", 2)
				snapshot.items.append({"id":"route-%d" % i, "label":WorldPortNames.NAMES[i], "distance_m":distance, "detail":"General cargo\n2 containers · %.1f nm\nPayment: %s" % [distance/1852.0, PlayerData.format_money(payment)], "reason":""})
		panel.show_service_snapshot(snapshot)
	elif index<8:
		panel.show_tablet(SCREENS[index])
	else:
		var state := {"helming":index<10,"objective":"Speak to the shipwright to inspect vessels for sale.","ahead_kn":8.4,"side_kn":.1,"heading":84,"rudder":4,"fuel":.81,"order":"HALF AHEAD","autopilot":true,"thruster":"Off","bow":false,"stern":false}
		if index==9: state.merge({"ahead_kn":1.2,"side_kn":.2,"order":"ASTERN","autopilot":false,"thruster":"Bow","bow":true,"mooring_reason":"Stern line out of reach"},true)
		state["engine_running"] = true
		hud.present(state)
		hud.present_interaction("F  Speak to the shipwright" if index==10 else ("F  Leave helm" if index<10 else ""))
		hud._notice.text="Transfer paused: receiving space is occupied."
		hud._notice.visible=index==10

func capture_all() -> void:
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var stamp := Time.get_datetime_string_from_system().replace(":","-")
	for index in SCREENS.size():
		show_screen(index)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := archive.path_join("%s-voyage-ui-%02d.png" % [stamp,index])
		get_viewport().get_texture().get_image().save_png(path)
		print("UI_CAPTURE ",path)
	await capture_helm_detail(archive, stamp)
	get_tree().quit()

func capture_helm_detail(archive: String, stamp: String) -> void:
	# Render the production instrument component at native pixels for inspection.
	var viewport := SubViewport.new()
	viewport.size=Vector2i(int(MarineHelmConsole.WIDTH)+48,int(MarineHelmConsole.HEIGHT)+48)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var console := MarineHelmConsole.new()
	viewport.add_child(console)
	console.position=Vector2(24,24)
	show_screen(9)
	console.present(hud._helm.state)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := archive.path_join("%s-voyage-helm-detail.png" % stamp)
	viewport.get_texture().get_image().save_png(path)
	print("UI_CAPTURE ",path)
	viewport.queue_free()
