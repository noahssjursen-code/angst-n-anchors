extends Node
## Diagnostic only: bounded timings for a full authored harbour, not tiny rules
## fixtures. Each receipt is validated normally; this probe grants no shortcuts.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world:={"seed":73119,"generation_version":1,"checksum":"performance-fixture"}
	var plots: Array=[{"id":"plot","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12}]
	snapshot.stores[1].public_unloading=true
	var started:=Time.get_ticks_usec()
	var state:=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	print("PORT_PERF initial_validation_ms=",(Time.get_ticks_usec()-started)/1000.0," placements=",snapshot.placements.size())
	if not state.validation_errors.is_empty():push_error(str(state.validation_errors));get_tree().quit(1);return
	var vessel: Dictionary={}
	for row in snapshot.vessels:
		if row.id=="bulk-trader":vessel=row
	var berth_id:=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,vessel,[]).ok and "bulk-yard" in CustomPortBerths.services_for_vessel(berth,vessel).store_ids:berth_id=berth.id;break
	if berth_id.is_empty():push_error("No physical service berth");get_tree().quit(1);return
	var actions: Array=[
		["dock",{"vessel_id":"bulk-trader","berth_id":berth_id}],
		["reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":10000,"reservation_id":"probe"}],
		["load_cargo",{"reservation_id":"probe"}],
		["unload_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":10000}],
		["undock",{"vessel_id":"bulk-trader"}]]
	for action in actions:
		started=Time.get_ticks_usec()
		var response:=state.apply({"command_id":"perf-%d"%state.revision(),"expected_revision":state.revision(),"actor_company_id":"company-visitor","kind":action[0],"payload":action[1]})
		print("PORT_PERF action=",action[0]," ms=",(Time.get_ticks_usec()-started)/1000.0," ok=",response.ok)
		if not response.ok:push_error(str(response));get_tree().quit(1);return
	get_tree().quit()
