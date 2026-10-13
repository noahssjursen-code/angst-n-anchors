extends Node3D

var failures: Array[String] = []
var checks := 0
var client: MpVirtualClient
var other: MpVirtualClient
var concurrent_results: Array[Dictionary] = []

func parallel_order(command: Dictionary) -> void:
	concurrent_results.append(await client._http(HTTPClient.METHOD_POST, "/v1/vessels/purchase", command, "account"))

func check(ok: bool, label: String) -> void:
	checks += 1
	print("MP PURCHASE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	ServerConfig.use_preset("local")
	ServerConfig.is_multiplayer_mode = true
	RemoteAccountCredentialStore.store_path_override = "res://.godot/tests/purchase-credentials-%d.json" % OS.get_process_id()
	client = MpVirtualClient.new()
	client.setup("buyer", "http://127.0.0.1:8080", "127.0.0.1", 7777)
	add_child(client)
	var suffix := PlayerData.new_uuid()
	var login := await client.login_or_register("purchase-%s@integration.local" % suffix, "local-purchase-test-2026")
	check(bool(login.ok), "Isolated account authenticated")
	var captain := await client.ensure_captain("Purchase Test")
	check(bool(captain.ok), "Isolated captain created")
	RemoteAccountCredentialStore.set_session(client.base_url, client.account_token, client.account)
	PlayerSession.data = PlayerData.new()
	PlayerSession.data.captain_id = client.captain_id()
	PlayerSession.data.marks = int(client.captain.get("marks", 6400))
	PlayerSession.begin_remote_voyage(client.captain_id())
	LocalPlayerView._session = PlayerSession
	var npc := ShipwrightNpc.new()
	add_child(npc)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	var stock: Dictionary = {}
	for item in PortServiceDesk.describe(npc).items:
		if item.id == "fishing_hook_line": stock = item
	check(not stock.is_empty() and str(stock.get("reason", "blocked")).is_empty(), "Shipwright enables affordable MP stock")
	var command := {"stock_id":"fishing_hook_line", "vessel_name":"Purchased Nordlys", "request_id":suffix, "expected_price_nok":3200}
	var bought: Dictionary = await PortServiceDesk.purchase(npc, command)
	check(bool(bought.get("ok", false)), "Actual shipwright service completes remote purchase: " + str(bought.get("message", "")))
	check(PlayerSession.data.owned_vessels.size() == 1, "Purchased ship reaches local fleet")
	check(PlayerSession.data.marks == 3200, "Server price deducted exactly once")
	var again: Dictionary = await PortServiceDesk.purchase(npc, command)
	check(bool(again.get("ok", false)) and PlayerSession.data.marks == 3200 and PlayerSession.data.owned_vessels.size() == 1, "Retry returns same ship with no second debit")
	var rows := await client._http(HTTPClient.METHOD_GET, "/v1/vessels?captain_id=" + client.captain_id(), null, "account")
	check(bool(rows.ok) and rows.payload is Array and rows.payload.size() == 1, "Independent fleet fetch finds one durable ship")
	if rows.payload is Array and not rows.payload.is_empty():
		var record := VesselSync._merge_server_row(PlayerData.new(), rows.payload[0])
		check(not record.is_empty() and ImportedVesselLayout.valid(record.get("brick_layout",{}), str(record.get("hull_id","")), true), "Fresh client reconstructs purchased blueprint")
		check(not str(rows.payload[0].construction_id).is_empty(), "Ship has durable construction reference")
		var ship := VesselSpawn.instantiate_from_record(record)
		check(ship != null, "Purchased record constructs an actual playable vessel")
		if ship != null:
			add_child(ship)
			await get_tree().process_frame
			check(ship.get_node_or_null("RodFishingStation") is RodFishingStation, "Purchased vessel includes its rod fishing station")
			ship.queue_free()
	var invalid := command.duplicate(true)
	invalid.vessel_name = "Different order"
	var conflict: Dictionary = await PortServiceDesk.purchase(npc, invalid)
	check(not bool(conflict.ok), "Reusing reference for different order rejected")
	invalid = command.duplicate(true)
	invalid.request_id = PlayerData.new_uuid()
	invalid.stock_id = "28_10_m"
	invalid.expected_price_nok = 10500
	var broke: Dictionary = await PortServiceDesk.purchase(npc, invalid)
	check(not bool(broke.ok), "Insufficient funds rejected")
	invalid.stock_id = "fishing_hook_line"
	invalid.expected_price_nok = 1
	var price: Dictionary = await PortServiceDesk.purchase(npc, invalid)
	check(not bool(price.ok), "Client cannot reduce price")
	other = MpVirtualClient.new()
	other.setup("intruder", client.base_url, "127.0.0.1", 7777)
	add_child(other)
	await other.login_or_register("other-%s@integration.local" % suffix, "local-purchase-test-2026")
	invalid.captain_id = client.captain_id()
	var denied := await other._http(HTTPClient.METHOD_POST, "/v1/vessels/purchase", invalid, "account")
	check(not bool(denied.ok), "Another account cannot spend captain funds")
	rows = await client._http(HTTPClient.METHOD_GET, "/v1/vessels?captain_id=" + client.captain_id(), null, "account")
	check(rows.payload.size() == 1 and PlayerSession.data.marks == 3200, "Rejected orders leave fleet and balance unchanged")
	# Both requests can reach Postgres before either returns; only one is affordable.
	invalid = command.duplicate(true)
	invalid.captain_id = client.captain_id()
	invalid.request_id = PlayerData.new_uuid()
	parallel_order(invalid.duplicate(true))
	invalid.request_id = PlayerData.new_uuid()
	parallel_order(invalid.duplicate(true))
	while concurrent_results.size() < 2: await get_tree().process_frame
	var successes := 0
	for response in concurrent_results:
		if bool(response.ok): successes += 1
	check(successes == 1, "Concurrent orders cannot overspend account")
	var retry: Dictionary = await PortServiceDesk.purchase(npc, command)
	check(bool(retry.ok) and PlayerSession.data.marks == 0, "Old receipt returns current balance after later purchase")
	rows = await client._http(HTTPClient.METHOD_GET, "/v1/vessels?captain_id=" + client.captain_id(), null, "account")
	check(rows.payload.size() == 2, "Concurrent rejected purchase leaves no extra vessel")
	RemoteAccountCredentialStore.clear_test_storage()
	RemoteAccountCredentialStore.store_path_override = ""
	print("MP PURCHASE ", "PASS" if failures.is_empty() else "FAIL", ": ", checks, " checks")
	var report := FileAccess.open("res://.godot/tests/mp_shipwright_purchase_report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":failures.is_empty(), "checks":checks, "failures":failures, "server":client.base_url, "timestamp":Time.get_datetime_string_from_system()}, "\t"))
	report.close()
	get_tree().quit(0 if failures.is_empty() else 1)
