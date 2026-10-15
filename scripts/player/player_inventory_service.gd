extends Node
## Commands use WorldGateway; the captain document never grants MP equipment.
signal changed
signal finished(result: Dictionary)
var pending: Dictionary={}
var ready_for_use:=false
var _actor:=""
var _wait:=0.0

func _ready() -> void:
	WorldGateway.session_ready.connect(_session_ready)
	WorldGateway.session_closed.connect(func():ready_for_use=false;_actor="";pending.clear();changed.emit())
	WorldGateway.command_completed.connect(_completed)
	WorldGateway.projection_changed.connect(func(kind:String,id:String,p:Dictionary):
		if kind=="player_inventory" and id==_actor: _apply(p.get("state",{})))
	PlayerSession.data_loaded.connect(func(_data):changed.emit())

func snapshot() -> Dictionary:
	return PlayerInventoryState.normalize(PlayerSession.data.personal_inventory)

func _session_ready(remote: bool, session: Dictionary) -> void:
	_actor=str(session.get("actor_id",""));ready_for_use=not remote
	if remote:
		PlayerSession.data.personal_inventory=PlayerInventoryState.empty()
		WorldGateway.query_projections("player_inventory",_actor)
		send("inventory.ensure",{})
	else: changed.emit()

func can_change() -> bool:
	var player:=get_tree().get_first_node_in_group("player")
	var gear:=player.get_node_or_null("PersonalFishingEquipment") if player!=null else null
	return gear==null or gear.can_change()

func send(action: String,body: Dictionary) -> void:
	if not WorldGateway.is_ready(): finished.emit({"ok":false,"message":"Waiting for inventory service."});return
	if action in ["inventory.select","inventory.move"] and not can_change():
		finished.emit({"ok":false,"message":"Recover the line before changing equipment."});return
	if not pending.is_empty(): return
	var request:=WorldGateway.next_request_id("inventory")
	pending[request]={"action":action,"body":body.duplicate(true),"retry":Time.get_ticks_msec()+10000}
	WorldGateway.send_command(action,body,request)

func _process(delta: float) -> void:
	_wait+=delta
	if _wait<0.5:return
	_wait=0
	for request in pending.keys().duplicate():
		var job: Dictionary=pending[request]
		if Time.get_ticks_msec()>=int(job.retry) and WorldGateway.is_ready():
			job.retry=Time.get_ticks_msec()+10000
			WorldGateway.send_command(job.action,job.body,request)

func _completed(request: String,result: Dictionary) -> void:
	if not pending.has(request):return
	if str(result.get("error_code",result.get("code","")))=="transport_failed":return
	result["action"]=str(pending[request].action)
	pending.erase(request)
	if bool(result.get("ok",false)):
		_apply(result.get("data",{}).get("inventory",{}))
		if WorldGateway.is_remote():WorldGateway.refresh_captain_balance()
	finished.emit(result)

func _apply(raw: Dictionary) -> void:
	if raw.is_empty():return
	PlayerSession.data.personal_inventory=PlayerInventoryState.normalize(raw)
	ready_for_use=true;changed.emit()

func execute_local(action: String,body: Dictionary,request: String) -> Dictionary:
	var session:=PlayerSession
	if action=="inventory.purchase":
		for owned:Dictionary in snapshot().slots:
			if str(owned.get("attributes",{}).get("purchase_request",""))!=request:continue
			if str(owned.item_id)!=str(body.get("item_id","")):return {"ok":false,"message":"This order already purchased another item."}
			return {"ok":true,"inventory":snapshot()}
	var previous:=session.data.to_dict()
	if action=="inventory.purchase" and session.data.company.is_empty():session._ensure_company_authority()
	var result:=PlayerInventoryState.change(session.data.personal_inventory,action,body,PlayerData.new_uuid())
	if not result.ok:return result
	if action=="inventory.purchase":
		session._ensure_company_authority()
		var item:=VesselEquipment.item(str(body.item_id))
		var payment:=session.company_service.post_transaction({"request_id":request+":payment","amount_marks":-int(item.price_nok),"category":"personal_equipment","description":"Purchased "+str(item.name),"related_entity_id":str(body.item_id)})
		if not bool(payment.get("ok",false)):return payment
	if action=="inventory.purchase":
		for purchased:Dictionary in result.inventory.slots:
			if str(purchased.get("uid",""))!="" and purchased.get("attributes",{}).is_empty() and not snapshot().slots.any(func(slot):return str(slot.get("uid",""))==str(purchased.uid)):
				purchased.attributes={"purchase_request":request};break
	session.data.personal_inventory=result.inventory
	if session._persistent_io_enabled and LocalCaptainStore.has_active():
		if not PlayerSaveStore.save_player(session.data):
			session.data=PlayerData.from_dict(previous);session.company_service.bind(session.data)
			return {"ok":false,"message":"Could not save inventory. Purchase was rolled back."}
	session.marks_changed.emit(session.data.marks)
	session.company_changed.emit(session.company_service.company_summary())
	return result
