extends Control

## Native data-only client of the real Go authority. Never opens captain saves.
const Gateway = preload("res://scripts/network/world_gateway.gd")
const BINARY := "res://.godot/tools/gameplaylab.exe"
var gateway: Node
var backend: RemoteWorldBackend
var process_id := -1
var base_url := ""
var state_path := ""
var ready_path := ""
var selected_key := "company/company-demo"
var results := {}
var tree: Tree
var json_view: CodeEdit
var status: Label
var summary: Label
var journal: RichTextLabel
var buttons: Array[Button] = []
var busy := false
var event_count := 0
var _refresh_queued := false
var _test := false
var _failed := false


func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_test = OS.get_cmdline_user_args().has("--verify-gameplay-lab")
	_build_ui()
	call_deferred("_start")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("10191f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var heading := Label.new()
	heading.text = "Game data · authority lab"
	heading.add_theme_font_size_override("font_size", 28)
	root.add_child(heading)
	var intro := Label.new()
	intro.text = "Real commands, saved records and subscriptions. A separate scratch world; no terrain or captain saves."
	root.add_child(intro)
	var actions := HFlowContainer.new()
	root.add_child(actions)
	for action in [["Run freight scenario", _run_scenario], ["Buy ship", _purchase], ["Load next container", _load_next], ["Advance voyage", _arrive], ["Unload next", _unload_next], ["Settle contract", _settle], ["Restart & restore", _restart], ["Fresh scenario", _fresh]]:
		var button := Button.new()
		button.text = action[0]
		var callback: Callable = action[1]
		button.pressed.connect(func(): await _action(callback))
		actions.add_child(button)
		buttons.append(button)
	summary = Label.new()
	summary.add_theme_font_size_override("font_size", 20)
	summary.add_theme_color_override("font_color", Color("8de0bc"))
	root.add_child(summary)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 320
	root.add_child(split)
	tree = Tree.new()
	tree.hide_root = true
	tree.custom_minimum_size.x = 290
	tree.item_selected.connect(func():
		var item := tree.get_selected()
		if item != null and item.get_metadata(0) != null:
			selected_key = str(item.get_metadata(0))
			_show_selected())
	split.add_child(tree)
	json_view = CodeEdit.new()
	json_view.editable = false
	json_view.gutters_draw_line_numbers = true
	json_view.add_theme_font_size_override("font_size", 17)
	json_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(json_view)
	journal = RichTextLabel.new()
	journal.custom_minimum_size.y = 155
	journal.scroll_following = true
	root.add_child(journal)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("a3b2c0"))
	root.add_child(status)
	_set_busy(true)


func _start() -> void:
	var folder := OS.get_cache_dir().path_join("angst-gameplay-lab") if _test else ProjectSettings.globalize_path("user://data-model-lab")
	DirAccess.make_dir_recursive_absolute(folder)
	state_path = folder.path_join("world-%d.json" % Time.get_ticks_usec()) if _test else folder.path_join("world.json")
	var recent_path := folder.path_join("latest.txt")
	if not _test and FileAccess.file_exists(recent_path):
		var recent := FileAccess.get_file_as_string(recent_path).strip_edges()
		if recent == recent.get_file() and recent.ends_with(".json"):
			state_path = folder.path_join(recent)
	await _boot()
	_set_busy(false)
	if _test and not _failed:
		await _action(_run_scenario)
		if not _failed:
			print("GAMEPLAY DATA LAB PASS: real HTTP commands, events, two-slot capacity, overflow rejection, shared records, payment, restart, fresh-client reconstruction")
		if OS.get_cmdline_user_args().has("--capture-gameplay-lab") and DisplayServer.get_name() != "headless":
			await _capture()
		get_tree().quit(1 if _failed else 0)


func _boot() -> void:
	if not FileAccess.file_exists(BINARY):
		_fail("Build the lab first: tools/build_gameplay_lab.ps1")
		return
	ready_path = state_path.get_base_dir().path_join("ready-%d.json" % Time.get_ticks_usec())
	process_id = OS.create_process(ProjectSettings.globalize_path(BINARY), ["-state", state_path, "-ready-file", ready_path])
	var deadline := Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(ready_path) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	if not FileAccess.file_exists(ready_path):
		_fail("Authority did not start. Scratch data is preserved at " + state_path)
		return
	var descriptor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ready_path))
	base_url = str(descriptor.base_url)
	var opened := await _http("/lab/open", HTTPClient.METHOD_POST, {})
	if _failed:
		return
	gateway = Gateway.new()
	add_child(gateway)
	backend = RemoteWorldBackend.new()
	backend.configure(base_url)
	gateway.use_backend(backend, true)
	gateway.retain_interest("company:company-demo", self)
	gateway.command_completed.connect(func(id: String, result: Dictionary): results[id] = result)
	gateway.projection_changed.connect(func(_kind: String, _id: String, _record: Dictionary): _queue_refresh())
	gateway.world_event.connect(func(_event: Dictionary): event_count += 1)
	gateway.authority_error.connect(func(code: String, message: String): _note(code + ": " + message))
	backend.adopt_session(opened)
	# Wait for the interest confirmation before fetching a consistent snapshot.
	deadline = Time.get_ticks_msec() + 8000
	while (backend._interest_request_in_flight or backend._snapshot_in_flight) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _fetch()
	_note("Connected to scratch authority. Saved world: " + state_path)


func _http(path: String, method: HTTPClient.Method, body: Dictionary, token: String = "") -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 10
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty(): headers.append("Authorization: Bearer " + token)
	var error := request.request(base_url + path, headers, method, JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		request.queue_free()
		_fail(error_string(error))
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) < 200 or int(response[1]) >= 300:
		_fail("HTTP request failed: %s (%s)" % [path, response[1]])
		return {}
	return JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8()) as Dictionary


func _fetch() -> void:
	var snapshot := await _http("/v2/state", HTTPClient.METHOD_GET, {}, backend.session_token())
	if snapshot.has("projections"):
		gateway._on_state_snapshot(snapshot)
		_refresh()


func _send(name: String, body: Dictionary, kind: String, id: String, request_id: String = "") -> Dictionary:
	if request_id.is_empty(): request_id = "lab-%s-%d" % [name, Time.get_ticks_usec()]
	var revision := int(gateway.projection(kind, id).get("revision", 0))
	gateway.send_command(name, body, request_id, revision)
	var deadline := Time.get_ticks_msec() + 12000
	while not results.has(request_id) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not results.has(request_id):
		_fail("Command timed out: " + name)
		return {}
	var result: Dictionary = results[request_id]
	results.erase(request_id)
	_note("%s → %s" % [name, "accepted" if result.get("ok", false) else result.get("message", "rejected")])
	await _fetch()
	return result


func _purchase() -> void:
	var result := await _send("vessel.purchase", {"company_id": "company-demo", "offer_id": "offer-harbour-cargo", "name": "Nordlys"}, "company", "company-demo")
	if result.get("ok", false):
		selected_key = "vessel/" + str(result.data.vessel_id)
		gateway.retain_interest("entity:" + str(result.data.vessel_id), self)
		_refresh()


func _vessel() -> Dictionary:
	var ships: Array = gateway.projections("vessel")
	return ships[0].state if not ships.is_empty() else {}


func _cargo_command(name: String, cargo_id: String, slot: String = "") -> Dictionary:
	var v := _vessel()
	if v.is_empty(): return {}
	var cargo: Dictionary = gateway.projection("cargo", cargo_id)
	return await _send(name, {"vessel_id": v.id, "cargo_id": cargo_id, "slot_id": slot, "cargo_revision": int(cargo.revision)}, "vessel", str(v.id))


func _load_next() -> void:
	var v := _vessel()
	if v.is_empty(): return
	var build: Dictionary = gateway.projection("construction", v.construction_id).state
	for slot: Dictionary in build.cargo_slots:
		if not v.cargo.has(slot.id):
			for id in ["cargo-a", "cargo-b", "cargo-extra"]:
				var cargo: Dictionary = gateway.projection("cargo", id).state
				if cargo.location.kind == "yard" and cargo.location.id == v.port_id:
					await _cargo_command("cargo.load", id, str(slot.id))
					return
	_note("No free compatible slot at this port.")


func _arrive() -> void:
	var v := _vessel()
	if v.is_empty(): return
	var result := await _http("/lab/advance", HTTPClient.METHOD_POST, {"vessel_id": v.id, "request_id": "arrival-%d" % Time.get_ticks_usec()})
	_note("Trusted simulation: arrival → " + str(result.get("ok", false)))
	await _fetch()


func _unload_next() -> void:
	var v := _vessel()
	if not v.is_empty() and not v.cargo.is_empty():
		await _cargo_command("cargo.unload", str(v.cargo.values()[0]))


func _settle() -> void:
	await _send("freight.settle", {"contract_id": "contract-demo"}, "contract", "contract-demo")


func _run_scenario() -> void:
	if not _vessel().is_empty():
		_note("Starting a new scratch scenario; the previous file is kept.")
		await _fresh()
	await _purchase()
	if _vessel().is_empty(): _fail("Purchase failed"); return
	await _load_next()
	await _load_next()
	var v := _vessel()
	_check(v.cargo.size() == 2, "Ship holds exactly two containers")
	var slot: String = v.cargo.keys()[0]
	var rejected := await _cargo_command("cargo.load", "cargo-extra", slot)
	_check(not rejected.get("ok", true), "Third container rejected")
	await _restart()
	_check(_vessel().cargo.size() == 2, "Fresh client restores both cargo slots")
	await _arrive()
	await _unload_next()
	await _unload_next()
	await _settle()
	var paid: Dictionary = gateway.projection("company", "company-demo").state
	_check(int(paid.balance_nok) == 44000, "Purchase and delivery produce NOK 44,000")
	await _settle()
	_check(int(gateway.projection("company", "company-demo").state.balance_nok) == 44000, "Repeat settlement cannot pay twice")
	await _restart()
	_check(gateway.projection("contract", "contract-demo").state.status == "settled", "Contract survives restart")
	_check(event_count > 0, "Subscriptions received real authority events")
	selected_key = "company/company-demo"
	_refresh()
	_note("Scenario complete. Inspect the ship, build, cargo, contract and transaction records.")


func _restart() -> void:
	var before: Array = gateway.projections()
	_shutdown()
	results.clear()
	await get_tree().process_frame
	await _boot()
	if _failed: return
	# Compare each private record; public interests can be expanded by reconnect.
	for record: Dictionary in before:
		if record.kind == "vessel_public": continue
		_check(gateway.projection(record.kind, record.id) == record, "Restored " + str(record.kind) + "/" + str(record.id))
	_note("Server restarted. New client rebuilt records from the saved world.")


func _fresh() -> void:
	_shutdown()
	state_path = state_path.get_base_dir().path_join("world-%d.json" % Time.get_unix_time_from_system())
	if not _test:
		var latest := FileAccess.open(state_path.get_base_dir().path_join("latest.txt"), FileAccess.WRITE)
		latest.store_string(state_path.get_file())
		latest.close()
	_failed = false
	await get_tree().process_frame
	await _boot()


func _shutdown() -> void:
	if is_instance_valid(gateway):
		gateway.stop_session()
		gateway.queue_free()
		gateway = null
	if process_id > 0 and OS.is_process_running(process_id): OS.kill(process_id)
	process_id = -1


func _exit_tree() -> void:
	if process_id > 0 and OS.is_process_running(process_id): OS.kill(process_id)


func _action(callback: Callable) -> void:
	if busy: return
	_set_busy(true)
	await callback.call()
	_set_busy(false)


func _set_busy(value: bool) -> void:
	busy = value
	for button in buttons: button.disabled = value


func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		call_deferred("_refresh")


func _refresh() -> void:
	_refresh_queued = false
	if not is_instance_valid(gateway): return
	tree.clear()
	var root := tree.create_item()
	var records: Array = gateway.projections()
	records.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.kind) + str(a.id) < str(b.kind) + str(b.id))
	var groups := {}
	for record: Dictionary in records:
		if not groups.has(record.kind):
			var group := tree.create_item(root)
			group.set_text(0, str(record.kind))
			group.set_selectable(0, false)
			groups[record.kind] = group
		var item := tree.create_item(groups[record.kind])
		item.set_text(0, str(record.state.get("name", record.id)).left(45))
		item.set_metadata(0, str(record.kind) + "/" + str(record.id))
		if str(item.get_metadata(0)) == selected_key: item.select(0)
	var company: Dictionary = gateway.projection("company", "company-demo").get("state", {})
	var v := _vessel()
	summary.text = "%s  ·  NOK %d  ·  %d ships  ·  %d containers aboard" % [company.get("name", "Connecting…"), int(company.get("balance_nok", 0)), gateway.projections("vessel").size(), v.get("cargo", {}).size()]
	status.text = "Subscribed events: %d   |   %s   |   Saved: %s" % [event_count, base_url, state_path]
	_show_selected()


func _show_selected() -> void:
	if not is_instance_valid(gateway): return
	var split := selected_key.find("/")
	json_view.text = JSON.stringify(gateway.projection(selected_key.left(split), selected_key.substr(split + 1)), "\t", false)


func _note(message: String) -> void:
	journal.append_text(message + "\n")


func _check(ok: bool, message: String) -> void:
	if not ok: _fail(message)


func _fail(message: String) -> void:
	_failed = true
	_note("FAILED: " + message)
	push_error(message)


func _capture() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("gameplay-data-lab-%d.png" % Time.get_unix_time_from_system())
	get_viewport().get_texture().get_image().save_png(path)
	print("LAB CAPTURE: " + path)
