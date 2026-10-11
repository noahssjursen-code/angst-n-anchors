extends Node

var failures: PackedStringArray = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
	print("VOYAGE_UI ","PASS " if value else "FAIL ",label)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(),"Use --shipyard-playtest")
	call_deferred("run")

func new_captain() -> void:
	PlayerSession.begin_new_captain("UI Captain",CharacterAppearance.default_appearance(),"test-port","test-captain",424242,"Test Shipping",Color.WHITE,"")

func run() -> void:
	await get_tree().process_frame
	new_captain()
	check(PlayerSession.data.owned_vessels.is_empty(),"walk-up career grants no vessel")
	check(PlayerSession.data.marks == CompanyContracts.WALKUP_STARTING_MARKS,"walk-up career has purchase capital")
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		new_captain()
		PlayerSession.company_service.post_transaction({"request_id":"test-capital","amount_marks":200000,"category":"test_fixture"})
		var funded_balance: int = PlayerSession.data.marks
		var command := {"stock_id":entry.prebuilt_id,"vessel_name":"Test vessel","request_id":"purchase-"+str(entry.prebuilt_id)}
		var result := PlayerSession.purchase_yard_vessel(command)
		check(bool(result.get("ok",false)),"purchase canonical stock "+str(entry.prebuilt_id))
		check(PlayerSession.data.owned_vessels.size()==1,"one owned vessel")
		var balance: int = PlayerSession.data.marks
		check(balance==funded_balance-int(result.get("data",{}).get("price_marks",0)),"exact authoritative price debited")
		if PlayerSession.data.owned_vessels.is_empty(): continue
		var record: Dictionary = PlayerSession.data.owned_vessels[0]
		check(ImportedVesselLayout.valid(record.brick_layout,record.hull_id,true),"purchased imported fit-out is valid")
		check(bool(PlayerSession.purchase_yard_vessel(command).get("ok",false)),"purchase retry succeeds")
		check(PlayerSession.data.marks==balance and PlayerSession.data.owned_vessels.size()==1,"retry cannot duplicate debit or vessel")
	new_captain()
	var before := PlayerSession.data.to_dict()
	check(not PlayerSession.purchase_yard_vessel({"stock_id":"missing","request_id":"bad"}).get("ok",true),"unknown stock rejected")
	check(PlayerData.json_equivalent(before,PlayerSession.data.to_dict()),"invalid stock does not change account")
	var stock := str(PrebuiltVesselCatalog.for_sale_entries()[0].prebuilt_id)
	PlayerSession.company_service.post_transaction({"request_id":"drain","amount_marks":-CompanyContracts.WALKUP_STARTING_MARKS})
	check(not PlayerSession.purchase_yard_vessel({"stock_id":stock,"request_id":"broke"}).get("ok",true),"insufficient funds rejected")
	check(PlayerSession.data.owned_vessels.is_empty(),"rejected payment cannot create a vessel")
	new_captain()
	PlayerSession._persistent_io_enabled=true
	check(not PlayerSession.purchase_yard_vessel({"stock_id":stock,"request_id":"no-save"}).get("ok",true),"purchase with no save slot rejected")
	check(PlayerSession.data.owned_vessels.is_empty() and PlayerSession.data.marks==CompanyContracts.WALKUP_STARTING_MARKS,"failed persistence rolls back purchase and debit")
	PlayerSession._persistent_io_enabled=false
	var baseline := PlayerSession.data.to_dict()
	var showcase = load("res://scenes/showcases/gameplay_ui_showcase.tscn").instantiate()
	add_child(showcase)
	for index in showcase.SCREENS.size():
		showcase.show_screen(index)
		await get_tree().process_frame
	check(PlayerData.json_equivalent(baseline,PlayerSession.data.to_dict()),"all UI preview pages are inert")
	showcase.show_screen(0)
	showcase.panel._send("buy",{"stock_id":stock,"request_id":"preview"})
	check(PlayerData.json_equivalent(baseline,PlayerSession.data.to_dict()),"preview buy button cannot purchase")
	showcase.free()
	GameMenu.set_gameplay_hud_visible(true)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var previous_mouse_mode := Input.mouse_mode
	GameMenu.open_tablet()
	check(GameMenu.is_modal_open() and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"tablet owns cursor")
	var controller := BoatController.new()
	add_child(controller)
	controller.set_physics_process(false)
	controller._active=true
	controller._throttle_stage_idx=3
	var key := InputEventKey.new()
	key.keycode=KEY_5
	key.pressed=true
	controller._unhandled_input(key)
	Input.action_press("move_forward")
	controller._physics_process(.016)
	Input.action_release("move_forward")
	check(controller._throttle_stage_idx==3,"modal blocks number keys and held helm input")
	var field := LineEdit.new()
	GameMenu._panel._body.add_child(field)
	field.grab_focus()
	key.keycode=KEY_M
	key.physical_keycode=KEY_M
	GameMenu._input(key)
	check(GameMenu._screen==GameMenu.Screen.PANEL,"typing M stays in name field")
	key.keycode=KEY_J
	key.physical_keycode=KEY_J
	GameMenu._input(key)
	check(GameMenu._screen==GameMenu.Screen.PANEL,"typing J stays in name field")
	GameMenu._set_screen(GameMenu.Screen.NONE)
	check(Input.mouse_mode==previous_mouse_mode,"closing modal restores previous cursor mode")
	controller.free()
	GameMenu.set_gameplay_hud_visible(false)
	var title = load("res://scenes/showcases/title_ui_showcase.tscn").instantiate()
	title.show_backdrop = false
	add_child(title)
	title._show_page(title.Page.SINGLEPLAYER)
	title._on_sp_sail("sample")
	title._on_delete_captain("sample")
	title._on_new_captain()
	title._on_home_port_confirmed("sample-port")
	title._show_page(title.Page.MULTIPLAYER)
	title._login_remote_account()
	check(PlayerData.json_equivalent(baseline,PlayerSession.data.to_dict()),"title preview cannot load or create saves")
	title.free()
	await get_tree().process_frame
	print("VOYAGE_UI_RESULT ",checks," checks; ",failures.size()," failures: ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
