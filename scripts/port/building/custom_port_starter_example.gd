class_name CustomPortStarterExample
extends RefCounted

## A finished first home with one owned, empty fishing vessel.
## Players can change the layout later through the same construction system.
static func build(origin: Vector3, plots: Array, world: Dictionary, seabed: Callable=Callable()) -> Dictionary:
	var owner:="company-starter"
	var record:={"schema_version":1,"id":"starter-harbour","name":"Littlehaven","owner_company_id":owner,
		"services":{"fish_reception":true},
		"world":world.duplicate(true),"origin_m":[origin.x,origin.y,origin.z],"deck_height_above_sea_m":2.0,
		"plots":plots.duplicate(true),"placements":[],"water_regions":[],"stores":[],"vessels":[],"reservations":[],"receipts":{},"revision":0}
	for plot in record.plots:plot.owner_company_id=owner
	var vessel:=CustomPortVesselProjection.from_prebuilt("fishing_hook_line","starter-fishing-boat",owner,"My fishing boat")
	record.vessels=[vessel]
	# 32m frontage with angled 4m corners. A short, wide approach reaches the
	# actual dry shore of the review island; all parts share the sea-level datum.
	for z in [42,46,50,54]:
		for x in range(-14,16,4):
			var asset:="foundation"
			var yaw:=0.0
			if z==42 and x in [-14,14]:
				asset="quay_triangle_4m";yaw=90.0 if x<0 else 0.0
			_add(record,"quay-%d-%d"%[x,z],asset,Vector3(x,0,z),seabed,yaw)
	for z in [58,62,66,70,74,78]:
		for x in [6,10]:_add(record,"shore-%d-%d"%[x,z],"foundation",Vector3(x,0,z),seabed)
	for x in [-10,-6,-2,2,6,10]:
		_add(record,"front-coping-%d"%x,"quay_edge_mitre_left" if x==-10 else ("quay_edge_mitre_right" if x==10 else "quay_edge_4m"),Vector3(x,0,40),seabed)
	for x in [-14,14]:
		var angle:=45.0 if x<0 else -45.0
		_add(record,"angle-%d"%x,"quay_diagonal_coping_4m",Vector3(x,0,42),seabed,angle)
	for z in [46,50,54]:
		_add(record,"west-edge-%d"%z,"quay_edge_mitre_right" if z==46 else "quay_edge_4m",Vector3(-16,0,z),seabed,90)
		_add(record,"east-edge-%d"%z,"quay_edge_mitre_left" if z==46 else "quay_edge_4m",Vector3(16,0,z),seabed,-90)
	for x in [-10,10]:_add(record,"bollard-%d"%x,"quay_bollard",Vector3(x,0,40.8),seabed)
	for x in [-8,0,8]:_add(record,"fender-%d"%x,"tractor_tire_fender",Vector3(x,0,40),seabed)
	_add(record,"ladder","quay_ladder",Vector3(-4,0,40),seabed)
	_add(record,"lifering","lifering_station",Vector3(-11,0,42),seabed)
	# An exterior-only, paintable shed; every component remains editable.
	record._site_yaw=0
	CustomPortExample._gabled_building(record,"starter-shed",Vector3(-4,0,48),2,"944735","sign_fish",0,seabed)
	_add(record,"covered-porch","door_canopy_4m",Vector3(-6,0,42.5),seabed)
	_add(record,"net-cage","net_storage_cage",Vector3(-11,0,52),seabed)
	_add(record,"mooring-rope","mooring_warp_coil",Vector3(12,0,43),seabed)
	_add(record,"bench","quay_bench",Vector3(-12,0,47),seabed,90)
	_add(record,"shore-supply","dock_service_pedestal",Vector3(12,0,47),seabed)
	for at in [Vector3(-14,0,54),Vector3(14,0,54),Vector3(11,0,77)]:
		_add(record,"lamp-%s"%str(at),"quay_light",at,seabed)
	for z in [58,62,66,70,74,78]:
		_add(record,"path-west-%d"%z,"quay_guardrail_4m",Vector3(4.25,0,z),seabed,90)
		_add(record,"path-east-%d"%z,"quay_guardrail_4m",Vector3(11.75,0,z),seabed,-90)
	record.erase("_site_yaw")
	return record

static func arrive(state: CustomPortState) -> Dictionary:
	var vessel:Dictionary=state.to_dict().vessels[0]
	var rejected:Array=[]
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,vessel,[]).ok:
			return state.apply({"command_id":"starter-boat-arrival","expected_revision":state.revision(),
				"actor_company_id":vessel.owner_company_id,"kind":"dock",
				"payload":{"vessel_id":vessel.id,"berth_id":berth.id}})
		rejected.append({"fit":CustomPortBerths.fit(berth,vessel,[]),"length_m":berth.max_length_m,"beam_m":berth.max_beam_m,"depth_m":berth.depth_m})
	return {"ok":false,"code":"starter_berth_unavailable","berths":rejected}

static func _add(record:Dictionary,id:String,asset:String,at:Vector3,seabed:Callable,yaw:=0.0) -> void:
	record._site_yaw=0
	CustomPortExample._add(record,id,asset,at,yaw,seabed)
