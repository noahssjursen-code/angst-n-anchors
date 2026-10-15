class_name VoyagePanel
extends Control

signal close_requested
signal chart_requested
signal message_requested(text: String)

var preview_mode := false
var preview_data: Dictionary = {}
var service_kind := ""
var npc: NpcInteractable
var page := ""
var selected := ""
var _body: VBoxContainer
var _heading: Label
var _subtitle: Label
var _feedback: Label
var _details: VBoxContainer
var _operation: Label
var _items: Array = []
var _request_id := ""
var _refresh_time := 0.0
var _busy := false
var _preview: ShipwrightPreview
var _tablet: KontorTablet
var _card: PanelContainer


func _ready() -> void:
	theme = VoyageStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.055,0.065,.64)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	_card = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = .12
	panel.anchor_right = .88
	panel.anchor_top = .1
	panel.anchor_bottom = .9
	panel.add_theme_stylebox_override("panel",VoyageStyle.box(VoyageStyle.PAPER,30))
	add_child(panel)
	var main := VBoxContainer.new()
	panel.add_child(main)
	var header := HBoxContainer.new()
	main.add_child(header)
	_heading = VoyageStyle.label("Company portal",36)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	header.add_child(VoyageStyle.button("Close · Esc",func(): close_requested.emit()))
	_subtitle = VoyageStyle.label("",21,VoyageStyle.MUTED)
	main.add_child(_subtitle)
	main.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_feedback = VoyageStyle.label("",21,VoyageStyle.ACCENT)
	main.add_child(_feedback)
	visible = false


func _process(delta: float) -> void:
	if not visible or page != "service": return
	if not is_instance_valid(npc):
		_feedback.text = "This operator is no longer available. Close the panel and return to the quay."
		return
	_refresh_time -= delta
	if _refresh_time > 0: return
	_refresh_time = .3
	if npc is CraneOperatorNpc or npc is HarbourMasterNpc:
		var snapshot := LocalPlayerView.service_snapshot(npc)
		if is_instance_valid(_operation): _operation.text = str(snapshot.get("line",""))
		_update_service_actions(snapshot)


func _reset(title: String, subtitle: String) -> void:
	if is_instance_valid(_tablet): _tablet.hide()
	_card.show()
	visible = true
	_heading.text = title
	_subtitle.show()
	_subtitle.text = subtitle
	_feedback.text = ""
	_operation = null
	_details = null
	_preview = null
	VoyageStyle.clear(_body)
	_card.anchor_left = .12
	_card.anchor_right = .88
	_card.anchor_top = .1
	_card.anchor_bottom = .9
	_card.add_theme_stylebox_override("panel",VoyageStyle.box(VoyageStyle.PAPER,30))


func show_service(actor: NpcInteractable) -> void:
	npc = actor
	page = "service"
	service_kind = "shipwright" if actor is ShipwrightNpc else ("harbourmaster" if actor is HarbourMasterNpc else ("cargo" if actor is CargoAgentNpc else "operator"))
	show_service_snapshot(LocalPlayerView.service_snapshot(actor))

func show_service_snapshot(snapshot: Dictionary) -> void:
	_reset(str(snapshot.get("title","Port services")),str(snapshot.get("line","")))
	# Keep the person and their workplace in view during a conversation.
	_card.anchor_left = .38 if service_kind != "operator" else .56
	_card.anchor_right = .98
	_card.anchor_top = .16
	_card.anchor_bottom = .62 if service_kind == "operator" else .94
	_items = snapshot.get("items",[])
	if service_kind == "operator":
		_operator_content(snapshot)
		return
	if service_kind == "harbourmaster":
		var harbour_snapshot:=snapshot.duplicate(true)
		harbour_snapshot.actions=harbour_snapshot.get("actions",[]).filter(func(a):return not (str(a.id).begins_with("equipment:") or str(a.id).begins_with("equip:")))
		_service_actions(harbour_snapshot)
	if _items.is_empty():
		_body.add_child(VoyageStyle.label("No vessels owned yet. Visit the shipwright." if service_kind == "harbourmaster" else "No work fits your vessel here.",25))
		return
	var columns := HBoxContainer.new()
	_body.add_child(columns)
	var choices := VBoxContainer.new()
	choices.custom_minimum_size.x = 230
	if service_kind == "cargo":
		# Scroll destinations independently so the selected job stays visible.
		var destinations := ScrollContainer.new()
		destinations.custom_minimum_size = Vector2(280, minf(380, get_viewport_rect().size.y * 0.38))
		destinations.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		destinations.add_child(choices)
		columns.add_child(destinations)
	else:
		columns.add_child(choices)
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_details)
	for item in _items:
		var id := str(item.get("id",""))
		var caption := str(item.get("label","Vessel"))
		if service_kind == "cargo" and item.has("distance_m"):
			caption += " · %.1f nm" % (float(item.distance_m) / 1852.0)
		var button := VoyageStyle.button(caption,func(): _select(id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choices.add_child(button)
	if selected.is_empty() or not _items.any(func(item): return str(item.id)==selected): selected = str(_items[0].id)
	_select(selected)


func _select(id: String) -> void:
	selected = id
	if not is_instance_valid(_details): return
	VoyageStyle.clear(_details)
	for item in _items:
		if str(item.id) != id: continue
		_details.add_child(VoyageStyle.label(str(item.label),30))
		_details.add_child(VoyageStyle.label(str(item.get("detail","")),22,VoyageStyle.MUTED))
		var reason := str(item.get("reason",""))
		if service_kind == "shipwright":
			_add_ship_preview(item)
			VoyageStyle.row(_details,"Purchase price",PlayerData.format_money(int(item.price)))
			VoyageStyle.row(_details,"Balance after purchase",PlayerData.format_money(_balance()-int(item.price)))
			var name_field := LineEdit.new()
			name_field.text = str(item.label)
			name_field.max_length = 48
			name_field.placeholder_text = "Vessel name"
			_details.add_child(name_field)
			var purchase := VoyageStyle.button("Review purchase",func(): _confirm_purchase(item,name_field.text),true)
			purchase.disabled = not reason.is_empty()
			_details.add_child(purchase)
		else:
			var action := "deploy" if service_kind == "harbourmaster" else "book"
			var button := VoyageStyle.button("Deploy vessel" if action=="deploy" else "Accept job",func(): _send(action,{"id":id}),true)
			button.disabled = not reason.is_empty()
			_details.add_child(button)
		if not reason.is_empty(): _details.add_child(VoyageStyle.label(reason,21,VoyageStyle.ACCENT))
		break


func _add_ship_preview(item: Dictionary) -> void:
	if preview_mode:
		var preview := PanelContainer.new()
		preview.custom_minimum_size.y=175
		preview.add_theme_stylebox_override("panel",VoyageStyle.box(Color("d8e0dc")))
		var caption := VoyageStyle.label("Vessel inspection viewport\n3D content hidden in this UI-only scene",21,VoyageStyle.MUTED)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		preview.add_child(caption)
		_details.add_child(preview)
		return
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(0,235)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(720,300)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("a5b8bc")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .65
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-30,0)
	sun.light_energy = 1.4
	viewport.add_child(sun)
	_preview = ShipwrightPreview.new()
	viewport.add_child(_preview)
	_preview.show_entry(item,item.get("prebuilt_layout",{}))
	var camera := Camera3D.new()
	camera.transform = ShipwrightPreview.camera_transform_for_length(float(item.get("loa_m",24)))
	viewport.add_child(camera)
	camera.current = true


func _confirm_purchase(item: Dictionary, vessel_name: String) -> void:
	VoyageStyle.clear(_details)
	_details.add_child(VoyageStyle.label("Confirm purchase",30))
	_details.add_child(VoyageStyle.label(vessel_name,26))
	VoyageStyle.row(_details,"Charge",PlayerData.format_money(int(item.price)))
	VoyageStyle.row(_details,"Remaining operating cash",PlayerData.format_money(_balance()-int(item.price)))
	_details.add_child(VoyageStyle.label("The vessel joins your fleet. The harbourmaster can then bring it alongside.",22,VoyageStyle.MUTED))
	_request_id = PlayerData.new_uuid()
	_details.add_child(VoyageStyle.button("Buy vessel",func(): _send("buy",{"stock_id":str(item.id),"vessel_name":vessel_name,"request_id":_request_id,"expected_price_nok":int(item.price)}),true))
	_details.add_child(VoyageStyle.button("Back to inspection",func(): _select(str(item.id))))


func _send(action: String, payload: Dictionary = {}) -> void:
	if preview_mode:
		_feedback.text="Preview only — no orders, purchases or save changes."
		return
	if _busy: return
	_busy = true
	var result: Dictionary
	if action == "buy":
		_feedback.text = "Waiting for purchase confirmation…"
		result = await PortServiceDesk.purchase(npc,payload)
	else:
		result = PortServiceDesk.request(npc,action,payload)
	_busy = false
	var message := str(result.get("message",""))
	if bool(result.get("ok",false)):
		message = str((result.get("data",{}) as Dictionary).get("message","Order accepted."))
		if action == "buy":
			show_tablet("Today")
			message = "Vessel purchased. Press J for your tablet; see the harbourmaster to deploy."
		elif action.begins_with("equipment:") or action.begins_with("equip:"): _show_equipment()
		elif action in ["book","store","refuel","deploy"]: show_service(npc)
	_feedback.text = message
	message_requested.emit(message)


func _operator_content(snapshot: Dictionary) -> void:
	_subtitle.hide()
	_operation = VoyageStyle.label(str(snapshot.get("line","Ready.")),24)
	_body.add_child(_operation)
	_service_actions(snapshot)


func _service_actions(snapshot: Dictionary) -> void:
	for action in snapshot.get("actions",[]):
		var id := str(action.id)
		var button := VoyageStyle.button(str(action.label),func(): _send(id),id in ["load", "unload"])
		button.set_meta("service_action",id)
		_body.add_child(button)
		var reason := VoyageStyle.label("",18,VoyageStyle.MUTED)
		reason.set_meta("action_reason",id)
		_body.add_child(reason)
	_update_service_actions(snapshot)

func _update_service_actions(snapshot: Dictionary) -> void:
	var shown_reasons: Array[String] = []
	for action in snapshot.get("actions", []):
		var reason := str(action.get("reason", ""))
		var show_action := bool(action.get("visible", true))
		for node in _body.find_children("*", "Button", true, false):
			if str(node.get_meta("service_action", "")) != str(action.id): continue
			node.disabled = not reason.is_empty()
			node.tooltip_text = reason
			node.visible = show_action
		for node in _body.find_children("*", "Label", true, false):
			if str(node.get_meta("action_reason", "")) != str(action.id): continue
			node.text = reason
			node.visible = show_action and not reason.is_empty() and reason not in shown_reasons
			# The status line already communicates an active transfer.
			if service_kind == "operator" and bool(snapshot.get("active", false)) and reason == "Transfer in progress.": node.visible = false
			if node.visible: shown_reasons.append(reason)


func show_tablet(tab: String = "Today") -> void:
	page = tab
	npc = null
	visible = true
	_card.hide()
	if not is_instance_valid(_tablet):
		_tablet = KontorTablet.new()
		_tablet.preview_mode = preview_mode
		_tablet.preview_snapshot = _tablet_preview_snapshot()
		add_child(_tablet)
		_tablet.close_requested.connect(func(): close_requested.emit())
		_tablet.chart_requested.connect(func(): chart_requested.emit())
		_tablet.cancel_job_requested.connect(_confirm_cancel_job)
	_tablet.preview_mode = preview_mode
	_tablet.preview_snapshot = _tablet_preview_snapshot()
	_tablet.show()
	_tablet.open_page(tab)


func _tablet_preview_snapshot() -> Dictionary:
	if not preview_mode: return {}
	var company: Dictionary = preview_data.get("company", {}).duplicate(true)
	var fleet: Array = []
	for record: Dictionary in company.get("vessels", []):
		fleet.append({"uid":str(record.get("uid", "")), "name":VesselSpawn.vessel_name_of(record), "status":"Alongside", "deployed":true, "dimensions":"24 × 8 m", "services":"General cargo", "fuel":.86, "port":"Øyrvik", "cargo":[{"title":"Provisions", "detail":"20 ft container · 3,200 kg · Viknes"}], "catch_mass_kg":0})
	company["home_port_name"] = "Øyrvik"
	return {"company":company, "balance":preview_data.get("balance", 0), "voyage":preview_data.get("voyage", {}), "fleet":fleet, "jobs":preview_data.get("jobs", []), "captain":"Noah", "remote":false}


func _add_jobs(parent: Control) -> void:
	parent.add_child(VoyageStyle.label("Accepted work",27))
	var jobs: Array = preview_data.get("jobs",[]) if preview_mode else LocalPlayerView.get_active_contracts()
	var passengers := {} if preview_mode else LocalPlayerView.get_passenger_voyage_snapshot()
	var manifest: Dictionary = passengers.get("manifest", {})
	if not manifest.is_empty():
		parent.add_child(VoyageStyle.label("Passenger sailing → " + str(passengers.destination),25))
		VoyageStyle.row(parent,"Status",str(manifest.phase).capitalize())
		VoyageStyle.row(parent,"Passengers","%d aboard · %d landed / %d" % [manifest.onboard, manifest.landed, manifest.total])
		VoyageStyle.row(parent,"Payment on completion",PlayerData.format_money(int(manifest.total) * int(manifest.fare_marks)))
		parent.add_child(HSeparator.new())
	if jobs.is_empty() and manifest.is_empty(): parent.add_child(VoyageStyle.label("No active work. Ask the terminal agent for a passenger sailing." if not passengers.is_empty() else "No active cargo jobs. Ask a cargo agent at your vessel's port.",22,VoyageStyle.MUTED))
	for job in jobs:
		var destination := LocalPlayerView.get_port_display_name(str(job.get("destination_port_id","")))
		parent.add_child(VoyageStyle.label(CommodityCatalog.commodity_display(str(job.get("commodity_id","")))+" → "+destination,25))
		VoyageStyle.row(parent,"Progress","%.0f loaded · %.0f delivered / %.0f %s" % [float(job.get("loaded_quantity",0)),float(job.get("delivered_quantity",0)),float(job.get("quantity",0)),str(job.get("quantity_unit","units"))])
		VoyageStyle.row(parent,"Payment on completion",PlayerData.format_money(int(job.get("pay_marks",0))))
		if page == "Jobs":
			var contract_id := str(job.get("id",""))
			var status := {"allowed":true,"reason":"No cancellation fee. Reserved space and waiting quay cargo will be released; no delivery payment is earned."} if preview_mode else LocalPlayerView.get_contract_cancellation(contract_id)
			var cancel := VoyageStyle.button("Cancel job",func(): _confirm_cancel_job(job))
			cancel.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			cancel.custom_minimum_size.x=160
			cancel.disabled = not bool(status.allowed)
			cancel.tooltip_text = str(status.reason)
			parent.add_child(cancel)
			if not bool(status.allowed): parent.add_child(VoyageStyle.label(str(status.reason),20,VoyageStyle.MUTED))
		parent.add_child(HSeparator.new())


func _confirm_cancel_job(job: Dictionary) -> void:
	page = "cancel_job"
	_reset("Cancel this job?",CommodityCatalog.commodity_display(str(job.get("commodity_id",""))) + " → " + LocalPlayerView.get_port_display_name(str(job.get("destination_port_id",""))))
	_body.add_child(VoyageStyle.label("No fee is charged. This releases the booking, its reserved space and any cargo still waiting on the quay. You will not receive the delivery payment.",25))
	_body.add_child(VoyageStyle.button("Keep job",func():show_tablet("Jobs"),true))
	_body.add_child(VoyageStyle.button("Cancel job",func():
		if preview_mode:
			_feedback.text="Preview only — no job cancelled."
			return
		var result := FreightService.cancel_contract(str(job.get("id","")))
		show_tablet("Jobs")
		_feedback.text = str(result.get("data",{}).get("message","Job cancelled.")) if bool(result.get("ok",false)) else str(result.get("message","Cancellation failed."))
		_tablet.show_feedback(_feedback.text)
		message_requested.emit(_feedback.text)))


func show_pause() -> void:
	page = "pause"
	npc = null
	_reset("At ease", "The vessel keeps its current orders while this menu is open.")
	_body.add_child(VoyageStyle.button("Return to game",func():close_requested.emit(),true))
	_body.add_child(VoyageStyle.button("Company tablet",func():show_tablet()))
	_body.add_child(VoyageStyle.button("Sea chart",func():chart_requested.emit()))
	_body.add_child(VoyageStyle.button("Settings & controls",show_settings))
	_body.add_child(VoyageStyle.button("Save",func():
		if preview_mode: _feedback.text = "Preview only — no save written."
		else: _feedback.text = "Saved." if PlayerSession.save_now() else "Save failed. Keep the game open and retry."))
	_body.add_child(VoyageStyle.button("Save and return to title",_return_title))


func _return_title(confirmed: bool = false) -> void:
	if preview_mode: return
	if not confirmed:
		page = "exit"
		_reset("End this voyage?","Your company and fleet are saved. You return on foot at your home harbour next time.")
		_body.add_child(VoyageStyle.label("The current game does not resume a deployed vessel or its physical cargo. Finish unloading before leaving.",25,VoyageStyle.ACCENT))
		_body.add_child(VoyageStyle.button("Save and return to title",func():_return_title(true)))
		_body.add_child(VoyageStyle.button("Stay in game",func():close_requested.emit(),true))
		return
	if not PlayerSession.save_now():
		_feedback.text = "Save failed. Your session is still open; retry before leaving."
		return
	close_requested.emit()
	WorldGateway.stop_session()
	NetworkManager.end_multiplayer_session(true)
	GameMenu.set_gameplay_hud_visible(false)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func show_settings(from_title: bool = false) -> void:
	page = "settings"
	_reset("Settings & controls","Changes apply immediately. Your map and authoring tools use their own layouts.")
	for setting in [{"key":"master_volume","label":"Master volume","min":0.0,"max":1.0,"step":.05},{"key":"mouse_sensitivity","label":"Mouse sensitivity","min":.2,"max":3.0,"step":.1}]:
		var line := HBoxContainer.new()
		_body.add_child(line)
		var label := VoyageStyle.label(str(setting.label))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var slider := HSlider.new()
		slider.custom_minimum_size.x = 380
		slider.min_value = setting.min
		slider.max_value = setting.max
		slider.step = setting.step
		slider.value = float(GameSettings.get(setting.key))
		line.add_child(slider)
		slider.editable = not preview_mode
		slider.value_changed.connect(func(value):
			if preview_mode: return
			GameSettings.set(setting.key,value)
			GameSettings.apply_all()
			if not ShipyardPlaytestMode.active(): GameSettings.save_settings())
	var invert := CheckButton.new()
	invert.text = "Invert mouse Y"
	invert.button_pressed = GameSettings.invert_mouse_y
	invert.disabled = preview_mode
	invert.toggled.connect(func(value):
		if preview_mode: return
		GameSettings.invert_mouse_y=value
		if not ShipyardPlaytestMode.active(): GameSettings.save_settings())
	_body.add_child(invert)
	_body.add_child(VoyageStyle.label("W/S  Engine order    A/D  Rudder    T  Thruster mode\nQ/R  Thruster    B  Mooring lines    P  Autopilot\nF  Interact / leave helm    V  Camera    M  Chart    J  Tablet\nG  Trawl    L  Lights    Esc  Close / menu",23))
	_body.add_child(VoyageStyle.button("Back",func(): close_requested.emit() if from_title else show_pause()))


func _balance() -> int:
	return int(preview_data.get("balance",18000)) if preview_mode else LocalPlayerView.get_marks()


func _show_equipment() -> void:
	var snapshot:=LocalPlayerView.service_snapshot(npc)
	var record:=LocalPlayerView.get_active_vessel_record()
	_reset("Equipment shop", "For %s · %s available\nRod and harpe equip at the fishing mount. Trap supplies remain stored."%[VesselSpawn.vessel_name_of(record),PlayerData.format_money(LocalPlayerView.get_marks())])
	_card.anchor_left=.38;_card.anchor_right=.98
	_card.anchor_top=.12;_card.anchor_bottom=.94
	snapshot.actions=snapshot.get("actions",[]).filter(func(a):return str(a.id).begins_with("equipment:") or str(a.id).begins_with("equip:"))
	_service_actions(snapshot)
	_body.add_child(VoyageStyle.button("Back to harbourmaster",func():show_service(npc)))
