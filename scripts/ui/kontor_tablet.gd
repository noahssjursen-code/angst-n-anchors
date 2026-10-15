class_name KontorTablet
extends PanelContainer

## Native tablet presentation. Gameplay reads come through LocalPlayerView.
signal close_requested
signal chart_requested
signal cancel_job_requested(job: Dictionary)
var preview_mode := false
var preview_snapshot: Dictionary = {}
var current_page := "Overview"
var selected_vessel := ""
var snapshot: Dictionary = {}
var notice := ""
var _order_busy:=false
var _market_selection:Dictionary={}
var _body: VBoxContainer
var _nav: VBoxContainer
var _timer := 0.0
var _fingerprint := ""
const INK := Color("213c3e")
const MUTED := Color("75847b")
const PAPER := Color("f7f8f4")
const GREEN := Color("256650")
const PAGES := ["Overview", "My fleet", "Shipyard", "Harbour services", "Contracts", "Finances", "Equipment shop", "Company storage", "Company & crew", "Online players", "Messages", "SeaMail"]

func _ready() -> void:
	theme = VoyageStyle.theme().duplicate()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", INK)
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 20)
	var frame := VoyageStyle.box(PAPER, 34)
	frame.set_border_width_all(14)
	frame.border_color = Color("293430")
	frame.set_corner_radius_all(26)
	add_theme_stylebox_override("panel", frame)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor_left = .06
	anchor_right = .94
	anchor_top = .06
	anchor_bottom = .94
	var column := VBoxContainer.new()
	add_child(column)
	var status := HBoxContainer.new()
	column.add_child(status)
	var brand := label("YOUR COMPANY AT SEA", 14, MUTED)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(brand)
	status.add_child(button("Sea chart", func(): chart_requested.emit()))
	status.add_child(button("Close · Esc", func(): close_requested.emit()))
	column.add_child(HSeparator.new())
	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(workspace)
	var sidebar := ScrollContainer.new()
	sidebar.custom_minimum_size.x = 235
	sidebar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(sidebar)
	_nav = VBoxContainer.new()
	_nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_nav)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 18)
	scroll.add_child(_body)
	if not preview_mode:
		PersonalInventory.finished.connect(func(result:Dictionary):
			if result.get("action","") not in ["inventory.purchase",""]:return
			notice="Delivered to your on-person inventory." if bool(result.get("ok",false)) else str(result.get("message","Purchase failed."))
			if current_page=="Equipment shop" and is_visible_in_tree():refresh(true))
	refresh(true)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or preview_mode: return
	_timer += delta
	if _timer < 1.0: return
	_timer = 0.0
	refresh()

func refresh(force: bool = false) -> void:
	snapshot = preview_snapshot.duplicate(true) if preview_mode else LocalPlayerView.get_tablet_snapshot()
	# Ignore continuous helm telemetry; preserve focused controls between changes.
	var compared := snapshot.duplicate(true)
	var voyage: Dictionary = compared.get("voyage", {})
	compared["voyage"] = {"objective": voyage.get("objective", ""), "ship": voyage.get("ship", false), "name": voyage.get("name", ""), "port": voyage.get("port", "")}
	for vessel: Dictionary in compared.get("fleet", []): vessel.erase("fuel")
	if not preview_mode and current_page in ["Harbour services","Contracts"]:
		var services:Array=[]
		for service in LocalPlayerView.get_tablet_port_services():
			services.append(PortServiceDesk.describe(service))
		compared["services"]=services
	var fingerprint := JSON.stringify(compared)
	if force or fingerprint != _fingerprint:
		_fingerprint = fingerprint
		render()

func open_page(value: String) -> void:
	current_page = {"Today":"Overview", "Fleet":"My fleet", "Jobs":"Contracts", "Account":"Finances"}.get(value, value)
	selected_vessel = ""
	notice = ""
	if is_node_ready(): refresh(true)

func render() -> void:
	VoyageStyle.clear(_nav)
	VoyageStyle.clear(_body)
	_nav.add_child(label("kontor.", 34))
	_nav.add_child(label("WORKSPACE", 13, MUTED))
	for title in PAGES:
		if title == "Online players": _nav.add_child(label("CONNECTED", 13, MUTED))
		var nav_button := button(title, func(): open_page(title), title == current_page)
		nav_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_nav.add_child(nav_button)
	_nav.add_child(HSeparator.new())
	_nav.add_child(label(str(snapshot.get("captain", "Captain")), 18))
	_nav.add_child(label(str(snapshot.get("company", {}).get("name", "Your company")), 14, MUTED))
	if not notice.is_empty(): _body.add_child(label(notice, 18, GREEN))
	match current_page:
		"Overview": overview()
		"My fleet": fleet()
		"Contracts": contracts()
		"Shipyard": shipyard()
		"Harbour services": harbour_services()
		"Finances": finances()
		"Equipment shop": equipment_shop()
		"Company storage": company_storage()
		"Company & crew": company()
		"Online players": unavailable("Online players", "The full server directory is not available yet.", "This list will include all connected captains, including those outside your vessel's rendering range.")
		"Messages": unavailable("Messages", "Direct messaging is not connected yet.", "Player and company conversations need server delivery and stored message history.")
		"SeaMail": unavailable("SeaMail", "Your coastal post office", "Mail delivery, company inboxes and receipts will appear here when the server mail service is connected.")

func heading(title: String, subtitle: String) -> void:
	_body.add_child(label(str(snapshot.get("company", {}).get("name", "Your company")).to_upper(), 13, MUTED))
	_body.add_child(label(title, 32))
	_body.add_child(label(subtitle, 17, MUTED))

func overview() -> void:
	heading("Welcome aboard, Captain.", "A clear view of your day on the coast.")
	var voyage: Dictionary = snapshot.get("voyage", {})
	var hero := card(_body, Color("e3eadf"))
	hero.add_child(label(str(voyage.get("port", "")).to_upper() if not str(voyage.get("port", "")).is_empty() else "YOUR NEXT VOYAGE", 14, MUTED))
	hero.add_child(label(str(voyage.get("objective", "Prepare your next voyage.")), 25))
	hero.add_child(button("Open my fleet →", func(): open_page("My fleet")))
	var metrics := HBoxContainer.new()
	_body.add_child(metrics)
	metric(metrics, "Company balance", PlayerData.format_money(int(snapshot.get("balance", 0))))
	metric(metrics, "Fleet", "%d vessels" % snapshot.get("fleet", []).size())
	var mass := 0.0
	for vessel: Dictionary in snapshot.get("fleet", []): mass += float(vessel.get("catch_mass_kg", 0))
	metric(metrics, "Catch aboard", "%.1f kg" % mass)
	var columns := HBoxContainer.new()
	_body.add_child(columns)
	var work := card(columns)
	work.add_child(label("Accepted work", 22))
	var jobs: Array = snapshot.get("jobs", [])
	if jobs.is_empty(): work.add_child(label("No active contracts. Browse available work in Contracts.", 18, MUTED))
	else:
		for job: Dictionary in jobs: work.add_child(label(job_title(job), 18))
	work.add_child(button("View contracts →", func(): open_page("Contracts")))
	var owned := card(columns)
	owned.add_child(label("Your fleet", 22))
	for vessel: Dictionary in snapshot.get("fleet", []):
		owned.add_child(button(str(vessel.name) + " · " + str(vessel.status), func(): select_vessel(str(vessel.uid))))
	if snapshot.get("fleet", []).is_empty(): owned.add_child(button("Browse ships for sale →",func():open_page("Shipyard")))

func select_vessel(uid: String) -> void:
	current_page = "My fleet"
	selected_vessel = uid
	render()

func fleet() -> void:
	heading("My fleet", "Vessels, their equipment and the cargo aboard.")
	if not selected_vessel.is_empty(): _body.add_child(button("← All vessels", func(): open_page("My fleet")))
	for vessel: Dictionary in snapshot.get("fleet", []):
		if not selected_vessel.is_empty() and str(vessel.uid) != selected_vessel: continue
		var box := card(_body)
		box.add_child(label(str(vessel.name), 26))
		pair(box, "Status", str(vessel.status))
		pair(box, "Dimensions", str(vessel.get("dimensions", "")))
		pair(box, "Services", str(vessel.get("services", "")))
		if selected_vessel.is_empty():
			box.add_child(button("View vessel →", func(): select_vessel(str(vessel.uid))))
		else:
			if bool(vessel.get("deployed", false)):
				pair(box, "Fuel", "%.0f%%" % (float(vessel.get("fuel", 0)) * 100))
				pair(box, "Location", str(vessel.get("port", "Underway")))
				box.add_child(label("Cargo manifest", 22))
				for cargo: Dictionary in vessel.get("cargo", []): pair(box, str(cargo.get("title", "Cargo")), str(cargo.get("detail", "")))
				if vessel.get("cargo", []).is_empty(): box.add_child(label("No cargo aboard.", 18, MUTED))
				if float(vessel.get("catch_mass_kg", 0)) > 0: pair(box, "Catch estimate", PlayerData.format_money(int(vessel.get("catch_value", 0))))
				box.add_child(button("Harbour services →",func():open_page("Harbour services")))
			else:
				var deploy:=button("Select berth & deploy",func():
					if not preview_mode:GameMenu.open_berth_picker(str(vessel.uid)))
				box.add_child(deploy)
	if snapshot.get("fleet", []).is_empty(): _body.add_child(button("Browse ships for sale →",func():open_page("Shipyard")))

func contracts() -> void:
	heading("Contracts", "Your accepted work and delivery progress.")
	for job: Dictionary in snapshot.get("jobs", []):
		var box := card(_body)
		box.add_child(label(job_title(job), 24))
		pair(box, "Progress", "%.0f loaded · %.0f delivered / %.0f %s" % [float(job.get("loaded_quantity", 0)), float(job.get("delivered_quantity", 0)), float(job.get("quantity", 0)), str(job.get("quantity_unit", "units"))])
		pair(box, "Payment on completion", PlayerData.format_money(int(job.get("pay_marks", 0))))
		var status: Dictionary = {"allowed": true, "reason": ""} if preview_mode else LocalPlayerView.get_contract_cancellation(str(job.get("id", "")))
		var cancel := button("Cancel job", func(): cancel_job_requested.emit(job))
		cancel.disabled = not bool(status.get("allowed", false))
		cancel.tooltip_text = str(status.get("reason", ""))
		box.add_child(cancel)
	if snapshot.get("jobs", []).is_empty(): _body.add_child(label("No active cargo jobs.", 20, MUTED))
	if not preview_mode:
		for service in LocalPlayerView.get_tablet_port_services():
			if not service is CargoAgentNpc:continue
			_body.add_child(label("Available at "+LocalPlayerView.get_port_display_name(service.port_id),24))
			var offers:=LocalPlayerView.service_snapshot(service)
			for offer in offers.items:
				var box:=card(_body);box.add_child(label(str(offer.label),22));box.add_child(label(str(offer.detail)))
				var action:=button("Accept contract",func():_service_order(service,"book",{"id":offer.id}))
				action.disabled=not str(offer.reason).is_empty() or _order_busy;box.add_child(action)
				if not str(offer.reason).is_empty():box.add_child(label(str(offer.reason),16,MUTED))
			break
	var passenger: Dictionary = snapshot.get("passenger", {})
	if not passenger.is_empty():
		var box := card(_body)
		box.add_child(label("Passenger sailing", 22))
		box.add_child(label(str(passenger.get("objective", "")), 18))

func finances() -> void:
	heading("Finances", "Company account · NOK")
	var box := card(_body, Color("e3eadf"))
	box.add_child(label("Available balance", 16, MUTED))
	box.add_child(label(PlayerData.format_money(int(snapshot.get("balance", 0))), 36))
	var ledger := card(_body)
	ledger.add_child(label("Recorded transactions", 23))
	for entry: Dictionary in snapshot.get("company", {}).get("recent_transactions", []): pair(ledger, str(entry.get("description", "Transaction")), PlayerData.format_money(int(entry.get("amount_marks", 0))))
	if snapshot.get("company", {}).get("recent_transactions", []).is_empty(): ledger.add_child(label("No recorded transactions available.", 18, MUTED))
	if bool(snapshot.get("remote", false)): ledger.add_child(label("Balance follows the server. Full server transaction history is not available yet.", 16, MUTED))

func company() -> void:
	var data: Dictionary = snapshot.get("company", {})
	heading("Company & crew", "People and vessels working together.")
	var box := card(_body)
	box.add_child(label(str(data.get("name", "Your company")), 28))
	pair(box, "Captain", str(snapshot.get("captain", "")))
	pair(box, "Home port", str(data.get("home_port_name", "")))
	pair(box, "Fleet", str(snapshot.get("fleet", []).size()) + " vessels")
	var crew := card(_body)
	crew.add_child(label("Crew", 23))
	for member: Dictionary in data.get("crew", []): pair(crew, str(member.get("name", member.get("id", "Crew member"))), str(member.get("role", "Crew")))
	if data.get("crew", []).is_empty(): crew.add_child(label("No hired crew recorded.", 18, MUTED))

func unavailable(title: String, lead: String, detail: String) -> void:
	heading(title, "Connected services")
	var box := card(_body, Color("e3eadf"))
	box.add_child(label(lead, 25))
	box.add_child(label(detail, 19, MUTED))
	if not bool(snapshot.get("remote", false)): box.add_child(label("You are currently playing a local session.", 17, MUTED))

func job_title(job: Dictionary) -> String:
	var destination := str(job.get("destination_name", ""))
	if destination.is_empty(): destination = LocalPlayerView.get_port_display_name(str(job.get("destination_port_id", "")))
	return CommodityCatalog.commodity_display(str(job.get("commodity_id", ""))) + " → " + destination

func label(text: String, size: int = 18, color: Color = INK) -> Label:
	return VoyageStyle.label(text, size, color)

func button(text: String, callback: Callable, active: bool = false) -> Button:
	var result := VoyageStyle.button(text, callback)
	result.custom_minimum_size.y = 44
	result.add_theme_font_size_override("font_size", 17)
	result.add_theme_color_override("font_color", GREEN if active else INK)
	result.add_theme_stylebox_override("normal", VoyageStyle.box(Color("dbe6d9") if active else Color("edf1e9"), 10))
	return result

func card(parent: Node, color: Color = Color.WHITE) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := VoyageStyle.box(color, 20)
	style.set_border_width_all(1)
	style.border_color = Color("e2e7df")
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	return content

func metric(parent: Node, title: String, value: String) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	column.add_child(label(title, 15, MUTED))
	column.add_child(label(value, 27))

func pair(parent: Node, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var left := label(key, 18, MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := label(value, 18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)


func show_feedback(text: String) -> void:
	notice = text
	render()

func equipment_shop()->void:
	heading("Equipment shop","Personal tackle · instant delivery to your inventory")
	if not preview_mode and not LocalPlayerView.get_personal_inventory_ready():_body.add_child(label("Waiting for personal inventory service. Multiplayer requires the inventory server update.",18,MUTED))
	for item:Dictionary in PlayerInventoryState.stock():
		var box:=card(_body)
		box.add_child(label(str(item.name),25))
		box.add_child(label(str(item.description),18,MUTED))
		var buy:=button("Buy · "+PlayerData.format_money(int(item.price_nok)),func():PersonalInventory.send("inventory.purchase",{"item_id":item.id}))
		buy.disabled=preview_mode or not LocalPlayerView.get_personal_inventory_ready() or not PersonalInventory.pending.is_empty() or int(snapshot.get("balance",0))<int(item.price_nok)
		box.add_child(buy)
	_body.add_child(label("Open TAB to arrange your equipment. Use 1–6 aboard a vessel to equip it.",18,MUTED))

func company_storage()->void:
	heading("Company storage","Warehouse goods stay at their port. Personal equipment travels with you.")
	var summary:Dictionary=LocalPlayerView.get_company_summary() if not preview_mode else snapshot.get("company",{})
	var leases:Array=summary.get("warehouse_leases",[])
	var lots:Array=summary.get("inventory_lots",[])
	for lease:Dictionary in leases:
		var box:=card(_body)
		box.add_child(label(LocalPlayerView.get_port_display_name(str(lease.get("port_id",""))),24))
		var found:=false
		for lot:Dictionary in lots:
			if str(lot.get("port_id",""))!=str(lease.get("port_id","")):continue
			found=true
			pair(box,str(lot.get("commodity_id","Goods")).capitalize(),str(lot.get("quantity",0)))
		if not found:box.add_child(label("No goods stored here.",18,MUTED))
	if leases.is_empty():_body.add_child(label("No warehouse storage registered.",18,MUTED))

func _service_order(service:NpcInteractable,action:String,payload:Dictionary={}) -> void:
	if preview_mode or _order_busy:return
	_order_busy=true
	var result: Dictionary
	if action == "sell_fish" and service is HarbourMasterNpc:
		result = await LocalPlayerView.sell_home_catch(service.port_id)
	else:
		result = PortServiceDesk.request(service,action,payload)
	_order_busy=false
	notice=str(result.get("data",{}).get("message","Order sent.")) if result.get("ok",false) else str(result.get("message","Order failed."))
	refresh(true)

func harbour_services()->void:
	heading("Harbour services","Manage your vessel and cargo from the tablet.")
	if preview_mode:return
	var services:=LocalPlayerView.get_tablet_port_services()
	if services.is_empty():_body.add_child(label("No harbour in range. Approach a port to use its facilities."));return
	for service in services:
		if service is PassengerAgentNpc:
			var terminal:=service as PassengerAgentNpc
			var terminal_box:=card(_body)
			terminal_box.add_child(label("Passenger terminal · "+LocalPlayerView.get_port_display_name(terminal.port_id),22))
			terminal_box.add_child(button("Passenger sailings",func():
				GameMenu._set_screen(GameMenu.Screen.NONE)
				PassengerTerminalPanel.open(terminal)))
			continue
		if not service is HarbourMasterNpc and not service is CraneOperatorNpc:continue
		var data:=LocalPlayerView.service_snapshot(service)
		var box:=card(_body)
		box.add_child(label(LocalPlayerView.get_port_display_name(str(data.get("port_id",""))),22))
		box.add_child(label("Vessel services" if service is HarbourMasterNpc else str(data.title),20))
		if service is CraneOperatorNpc:box.add_child(label(str(data.get("line","")),17,MUTED))
		if data.has("fish_reception"):box.add_child(label(str(data.fish_reception.line),20))
		for action in data.get("actions",[]):
			if not bool(action.get("visible",true)):continue
			var b:=button(str(action.label),func():_service_order(service,str(action.id)))
			b.disabled=not str(action.get("reason","")).is_empty() or _order_busy
			box.add_child(b)
			if b.disabled:box.add_child(label(str(action.get("reason","")),16,MUTED))

func shipyard()->void:
	heading("Shipyard","Purchase a vessel, then select its berth in My fleet.")
	if preview_mode:return
	var market:=LocalPlayerView.get_tablet_vessel_market()
	if not _market_selection.is_empty():
		_body.add_child(button("← All ships",func():_market_selection={};render()))
		var item:=_market_selection
		var box:=card(_body)
		box.add_child(label(str(item.label),26));box.add_child(label(str(item.detail)))
		var display:=SubViewportContainer.new();display.custom_minimum_size=Vector2(600,270);display.stretch=true;box.add_child(display)
		var viewport:=SubViewport.new();viewport.size=Vector2i(800,320);viewport.own_world_3d=true;display.add_child(viewport)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("a5b8bc")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7
		viewport.add_child(environment)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-30,0);viewport.add_child(sun)
		var preview:=ShipwrightPreview.new();viewport.add_child(preview);preview.show_entry(item,item.get("prebuilt_layout",{}));preview.set_spin_enabled(false)
		var camera:=Camera3D.new();viewport.add_child(camera);camera.fov=36;camera.transform=ShipwrightPreview.camera_transform_for_length(float(item.get("loa_m",24)));camera.make_current()
		pair(box,"Purchase price",PlayerData.format_money(int(item.price)))
		var vessel_name:=LineEdit.new();vessel_name.placeholder_text="Name your vessel";vessel_name.text=str(item.label);box.add_child(vessel_name)
		var request_id:=PlayerData.new_uuid()
		var buy:=button("Buy vessel · "+PlayerData.format_money(int(item.price)),func():
			if _order_busy:return
			_order_busy=true;notice="Purchasing vessel…"
			var result:Dictionary=await LocalPlayerView.buy_tablet_vessel({"stock_id":str(item.id),"vessel_name":vessel_name.text,"request_id":request_id,"expected_price_nok":int(item.price)})
			_order_busy=false
			notice="Vessel purchased. Open My fleet to choose a berth." if result.get("ok",false) else str(result.get("message","Purchase failed."))
			refresh(true))
		buy.disabled=_order_busy or int(item.price)>int(snapshot.get("balance",0));box.add_child(buy)
		return
	for item in market.get("items",[]):
		var box:=card(_body);box.add_child(label(str(item.label),24));box.add_child(label(str(item.detail)))
		pair(box,"Price",PlayerData.format_money(int(item.price)))
		box.add_child(button("Inspect vessel",func():_market_selection=item;render()))
