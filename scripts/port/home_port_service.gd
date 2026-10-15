class_name HomePortService
extends RefCounted

const PENDING := "__new_home__"
static var records: Array = []
static var options: Dictionary = {}
static var chart: ChartDataSnapshot
static var welcome := false

static func request(command: String, body: Dictionary = {}) -> Dictionary:
	var id := WorldGateway.next_request_id(command)
	var box: Array = []
	var callback := func(rid: String, result: Dictionary):
		if rid == id: box.append(result)
	WorldGateway.command_completed.connect(callback)
	WorldGateway.send_command(command, body, id)
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec()+15000
	while box.is_empty() and Time.get_ticks_msec()<deadline:
		await tree.process_frame
	WorldGateway.command_completed.disconnect(callback)
	return box[0] if not box.is_empty() else {"ok":false,"message":"The server did not respond. Please try again."}

static func prepare() -> Dictionary:
	records=[]
	options={}
	var result := await request("port.home.options")
	if not result.get("ok",false):return result
	options = result.get("data",{})
	records = options.get("ports",[])
	var home:Dictionary=options.get("home",{})
	if PlayerSession.data.home_port_id.begins_with("home-") and home.is_empty():
		return {"ok":false,"message":"Your saved home is unavailable. Reconnect to load it; your captain has been preserved."}
	if not home.is_empty():
		var state:=CustomPortState.from_dict(home,home.get("world",{}),CustomPortCatalog.definitions())
		if not state.validation_errors.is_empty():return {"ok":false,"message":"Your port data could not be loaded. Your saved captain has been preserved."}
		if PlayerSession.data.home_port_document!=home:adopt(home)
	return result

static func adopt(record:Dictionary) -> void:
	var data:PlayerData=PlayerSession.data
	data.home_port_id=str(record.id)
	data.home_port_document=record.duplicate(true)
	data.company["home_port_id"]=data.home_port_id
	for lease in data.company.get("warehouse_leases",[]):
		if str(lease.get("port_id",""))==PENDING:lease.port_id=data.home_port_id
	PlayerSession.save_now()

static func local_command(command:String,body:Dictionary,actor:String) -> Dictionary:
	var data:PlayerData=PlayerSession.data
	if command=="port.home.options":
		var saved:=data.home_port_document
		return {"ok":true,"data":{"home":saved,"ports":[] if saved.is_empty() else [saved],"available":[]}}
	if not data.home_port_document.is_empty():return {"ok":true,"data":{"port":data.home_port_document}}
	if data.home_port_id!=PENDING:return {"ok":false,"message":"This captain already has a home."}
	if chart==null:return {"ok":false,"message":"Open the coastal chart first."}
	var parcel:=CoastalPlotIndex.for_layout(chart.layout).get_plot(str(body.get("plot_id","")))
	var template:=StarterPortSites.fit(parcel,chart)
	if template.is_empty():return {"ok":false,"message":"This coast cannot safely fit your starter port. Choose another plot."}
	var record:=StarterPortSites.owned(template,actor,str(data.company.get("id","")))
	var before:=data.to_dict()
	data.home_port_document=record
	data.home_port_id=str(record.id)
	data.company["home_port_id"]=str(record.id)
	var grant:=PlayerInventoryState.change(data.personal_inventory,"inventory.purchase",{"item_id":"fishing_rod"},"starter-rod-"+actor)
	if not grant.ok:
		PlayerSession.data=PlayerData.from_dict(before)
		PlayerSession.company_service.bind(PlayerSession.data)
		return grant
	data.personal_inventory=grant.inventory
	if PlayerSession._persistent_io_enabled and LocalCaptainStore.has_active() and not PlayerSaveStore.save_player(data):
		PlayerSession.data=PlayerData.from_dict(before)
		PlayerSession.company_service.bind(PlayerSession.data)
		return {"ok":false,"message":"Could not save your home. Nothing was claimed."}
	return {"ok":true,"data":{"port":record,"inventory":data.personal_inventory}}
