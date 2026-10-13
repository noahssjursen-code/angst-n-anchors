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
var _body: VBoxContainer
var _nav: VBoxContainer
var _timer := 0.0
var _fingerprint := ""
const INK := Color("213c3e")
const MUTED := Color("75847b")
const PAPER := Color("f7f8f4")
const GREEN := Color("256650")
const PAGES := ["Overview", "My fleet", "Contracts", "Finances", "Company & crew", "Online players", "Messages", "SeaMail"]

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
		"Finances": finances()
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
	if jobs.is_empty(): work.add_child(label("No active contracts. Visit a cargo agent for compatible work.", 18, MUTED))
	else:
		for job: Dictionary in jobs: work.add_child(label(job_title(job), 18))
	work.add_child(button("View contracts →", func(): open_page("Contracts")))
	var owned := card(columns)
	owned.add_child(label("Your fleet", 22))
	for vessel: Dictionary in snapshot.get("fleet", []):
		owned.add_child(button(str(vessel.name) + " · " + str(vessel.status), func(): select_vessel(str(vessel.uid))))
	if snapshot.get("fleet", []).is_empty(): owned.add_child(label("Visit the shipwright to purchase your first vessel.", 18, MUTED))

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
			else: box.add_child(label("Deploy this vessel through the harbourmaster to inspect its live cargo and fuel.", 18, MUTED))
	if snapshot.get("fleet", []).is_empty(): _body.add_child(label("Your fleet is empty. Visit the shipwright to inspect vessels for sale.", 20, MUTED))

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
	if snapshot.get("jobs", []).is_empty(): _body.add_child(label("No active cargo jobs. Visit the cargo agent at your vessel's port for available work.", 20, MUTED))
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
