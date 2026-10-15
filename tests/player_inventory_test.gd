extends Node
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func _ready()->void:call_deferred("run")
func run()->void:
	var inventory:=PlayerInventoryState.empty()
	check(inventory.slots.size()==30,"Six hotbar and 24 bag slots")
	for i in 30:
		var result:=PlayerInventoryState.change(inventory,"inventory.purchase",{"item_id":"fishing_rod"},"tool-%d"%i)
		check(result.ok,"Tool fills empty slot");inventory=result.inventory
	check(not PlayerInventoryState.change(inventory,"inventory.purchase",{"item_id":"harpe"},"extra").ok,"Full inventory rejects purchase")
	check(not PlayerInventoryState.change(inventory,"inventory.move",{"from":0,"to":30}).ok,"Invalid destination rejected")
	inventory=PlayerInventoryState.change(inventory,"inventory.select",{"slot":0}).inventory
	inventory=PlayerInventoryState.change(inventory,"inventory.move",{"from":0,"to":9}).inventory
	check(inventory.slots[9].uid=="tool-0" and inventory.selected_slot==-1,"Moving equipment preserves identity and stows selection")
	var raw:Dictionary=JSON.parse_string(JSON.stringify(inventory))
	check(PlayerInventoryState.normalize(raw)==inventory,"Inventory survives JSON save")
	var legacy:=PlayerData.from_dict({"account_id":"legacy","owned_vessels":[{"uid":"boat","hull_id":"trawler_hull_14m","purchased_items":[{"uid":"paid","item_id":"harpe","quantity":1}]}]})
	check(legacy.personal_inventory.slots[0].uid=="paid","Paid ship tackle migrates to player")
	check(PlayerData.from_dict(legacy.to_dict()).personal_inventory==legacy.personal_inventory,"Migration cannot duplicate tools")
	PlayerSession.data=PlayerData.new();PlayerSession.data.account_id="inventory-test";PlayerSession.data.marks=5000
	PlayerSession._ensure_company_authority()
	var backend:=LocalWorldBackend.new()
	WorldGateway.use_backend(backend,false)
	backend.start_session("inventory-test","Test","","")
	PersonalInventory.send("inventory.purchase",{"item_id":"fishing_rod"})
	check(PersonalInventory.snapshot().slots[0].get("item_id","")=="fishing_rod","Local command purchases into player slot")
	check(PlayerSession.data.marks==3200,"Exactly one purchase debit")
	PersonalInventory.send("inventory.select",{"slot":0})
	check(PlayerInventoryState.selected(PersonalInventory.snapshot()).get("item_id","")=="fishing_rod","Hotbar equips owned tool")
	var player:Node3D=load("res://scenes/shared/player.tscn").instantiate();add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var gear:=player.get_node("PersonalFishingEquipment") as PersonalFishingEquipment
	check(is_instance_valid(gear.station) and gear.station.working,"Player owns a held fishing rig independently of a boat")
	check(is_instance_valid(gear.station._carried),"Held rig is attached to player")
	gear.station.session.phase="fishing"
	PersonalInventory.send("inventory.select",{"slot":-1})
	check(PersonalInventory.snapshot().selected_slot==0,"Active line blocks equipment switch")
	gear.station.session.recover()
	PersonalInventory.send("inventory.select",{"slot":-1})
	check(PersonalInventory.snapshot().selected_slot==-1,"Recovered line allows stow")
	GameMenu.set_gameplay_hud_visible(true)
	var previous_mouse_mode:=Input.mouse_mode
	var tab:=InputEventKey.new();tab.physical_keycode=KEY_TAB;tab.pressed=true
	GameMenu._input(tab)
	check(GameMenu.is_modal_open() and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"TAB opens on-person inventory and cursor")
	var key:=InputEventKey.new();key.physical_keycode=KEY_1;key.pressed=true
	GameMenu._input(key)
	check(PersonalInventory.snapshot().selected_slot==0,"Number key selects gear while inventory is open")
	GameMenu._input(tab)
	check(not GameMenu.is_modal_open() and Input.mouse_mode==previous_mouse_mode,"TAB closes inventory and restores walking cursor")
	GameMenu.set_gameplay_hud_visible(false)
	player.queue_free();WorldGateway.stop_session()
	await get_tree().process_frame
	print("PLAYER_INVENTORY failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
