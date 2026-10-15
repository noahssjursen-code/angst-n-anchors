class_name CustomPortExample
extends RefCounted

## A complete harbour authored in metres. The same record drives the builder,
## rendered port and authority simulator. No meshes or node paths enter the save.
const OWNER := "company-nordvik"
const VESSELS = preload("res://scripts/port/state/custom_port_vessel_projection.gd")

static func build(origin: Vector3, plots: Array, world: Dictionary, yaw_degrees := 0.0, seabed: Callable = Callable()) -> Dictionary:
	var record := {"schema_version":1,"id":"nordvik-harbour","name":"Nordvik harbour",
		"owner_company_id":OWNER,"world":world.duplicate(true),"origin_m":[origin.x,origin.y,origin.z],
		"deck_height_above_sea_m":2.0,"plots":plots.duplicate(true),"placements":[],
		"water_regions":[],"stores":[],"vessels":[],"reservations":[],"receipts":{},"revision":0}
	# Waterfront tiles are 8 x 4; the working deck uses the accepted 4 x 4 unit.
	for x in range(-60,68,8): _add(record,"quay-%d"%x,"quay",Vector3(x,0,2),yaw_degrees,seabed)
	_add(record,"quay-left-inner","foundation",Vector3(-66,0,2),yaw_degrees,seabed)
	_add(record,"quay-right-inner","foundation",Vector3(66,0,2),yaw_degrees,seabed)
	_add(record,"quay-left-cut","quay_triangle_4m",Vector3(-70,0,2),yaw_degrees+90,seabed)
	_add(record,"quay-right-cut","quay_triangle_4m",Vector3(70,0,2),yaw_degrees,seabed)
	for z in range(6,64,4):
		for x in range(-70,72,4): _add(record,"slab-%d-%d"%[x,z],"foundation",Vector3(x,0,z),yaw_degrees,seabed)
	# Broad shore approach, not a floating industrial slab on a narrow footbridge.
	for x in range(-18,10,4):
		for z in [66,70,74,78]: _add(record,"shore-link-%d-%d"%[x,z],"foundation",Vector3(x,0,z),yaw_degrees,seabed)
	_add(record,"container-terminal","container_crane_bay",Vector3(-24,0,24),yaw_degrees,seabed)
	# A projecting bulk quay makes a stepped shorefront, with real diagonal tiles.
	for z in [-10,-6,-2]:
		for x in range(26,72,4):
			if z==-10 and x in [26,70]: continue
			_add(record,"bulk-apron-%d-%d"%[x,z],"foundation",Vector3(x,0,z),yaw_degrees,seabed)
	_add(record,"bulk-left-angle","quay_triangle_4m",Vector3(26,0,-10),yaw_degrees+90,seabed)
	_add(record,"bulk-right-angle","quay_triangle_4m",Vector3(70,0,-10),yaw_degrees,seabed)
	_add(record,"bulk-terminal","bulk_crane_bay",Vector3(48,0,24),yaw_degrees,seabed)
	for x in [-64,-24,16]: _add(record,"bollard-%d"%x,"quay_bollard",Vector3(x,0,.8),yaw_degrees,seabed)
	for x in [29,67]: _add(record,"bulk-bollard-%d"%x,"quay_bollard",Vector3(x,0,-11.2),yaw_degrees,seabed)
	for x in range(-66,24,4): _add(record,"coping-%d"%x,"quay_edge_mitre_left" if x==-66 else "quay_edge_4m",Vector3(x,0,0),yaw_degrees,seabed)
	for x in range(-60,24,8): _add(record,"tyre-%d"%x,"tractor_tire_fender",Vector3(x,0,0),yaw_degrees,seabed)
	for x in range(30,68,4): _add(record,"bulk-coping-%d"%x,"quay_edge_mitre_left" if x==30 else ("quay_edge_mitre_right" if x==66 else "quay_edge_4m"),Vector3(x,0,-12),yaw_degrees,seabed)
	for x in [32,40,48,56,64]: _add(record,"bulk-tyre-%d"%x,"tractor_tire_fender",Vector3(x,0,-12),yaw_degrees,seabed)
	for entry in [[Vector3(-70,0,2),45.0],[Vector3(26,0,-10),45.0],[Vector3(70,0,-10),-45.0]]:
		_add(record,"diagonal-coping-%s"%str(entry[0]),"quay_diagonal_coping_4m",entry[0],yaw_degrees+entry[1],seabed)
		_add(record,"diagonal-tyre-%s"%str(entry[0]),"tractor_tire_fender",entry[0],yaw_degrees+entry[1],seabed)
	for x in [-48,0]:
		_add(record,"ladder-%d"%x,"quay_ladder",Vector3(x,0,0),yaw_degrees,seabed)
		_add(record,"rescue-%d"%x,"lifering_station",Vector3(x+2,0,1),yaw_degrees,seabed)
	for at in [Vector3(-69,0,7),Vector3(19,0,8),Vector3(69,0,8),Vector3(-68,0,61),Vector3(19,0,61),Vector3(69,0,61)]:
		_add(record,"lamp-%d-%d"%[at.x,at.z],"quay_light",at,yaw_degrees,seabed)
	_waterfront(record,yaw_degrees,seabed)
	_add(record,"crane-operator","port_clerk",Vector3(-17,0,8),yaw_degrees,seabed,{"display_name":"Crane operator","service":"cargo"})
	_add(record,"harbour-clerk","port_clerk",Vector3(-17,0,50),yaw_degrees,seabed,{"display_name":"Harbour office","service":"berths"})
	for index in 3:
		_add(record,"timber-%d"%index,"timber_bundle",Vector3(-46+index*2,0,56),yaw_degrees,seabed)
	_add(record,"pallets","pallet_stack",Vector3(-44,0,61),yaw_degrees,seabed)
	var crane := CustomPortCatalog.definition("container_crane_bay")
	var slots := int(crane.slot_count)
	record.stores=[
		{"id":"container-yard","name":"Container yard","placement_id":"container-terminal","capacity_kg":slots*24000.0,"capacity_units":slots,
		 "accepted_handling_modes":["container"],"accepted_container_types":["20ft"],"accepted_commodities":["machine_parts","timber"],"public_loading":true,"public_unloading":true,"lots":[
			{"id":"parts-for-shipyard","commodity_id":"machine_parts","quantity":12,"unit_mass_kg":3200,
			 "attributes":{"container_type":"20ft","indivisible":true,"paint_variant":1,"destination_port_id":"island-shipyard","value_nok":42000,"slots_per_unit":1}},
			{"id":"timber-export","commodity_id":"timber","quantity":8,"unit_mass_kg":4100,
			 "attributes":{"container_type":"20ft","indivisible":true,"paint_variant":7,"destination_port_id":"south-harbour","value_nok":18500,"slots_per_unit":1}}]},
		{"id":"bulk-yard","name":"Iron ore stock","placement_id":"bulk-terminal","capacity_kg":450000,"accepted_handling_modes":["bulk"],"accepted_commodities":["iron_ore","coal"],"public_loading":true,"public_unloading":true,
		 "lots":[{"id":"ore-stock","commodity_id":"iron_ore","quantity":200000,"unit_mass_kg":1,"attributes":{"slots_per_unit":0,"value_per_unit_nok":1.5}}]}]
	record.vessels=[
		VESSELS.from_prebuilt("fishing_hook_line","nordlys",OWNER,"Nordlys"),
		VESSELS.from_prebuilt("28_10_m","trader","company-visitor","Harbour Cargo",48000),
		VESSELS.from_prebuilt("coastal_coaster","bulk-trader","company-visitor","Coastal Bulk"),
		{"id":"oversized","name":"Oversized visitor","owner_company_id":"company-visitor","length_m":90,"beam_m":18,"draft_m":8,"capacity_kg":500000,"lots":[],"berth_id":""}]
	return record

static func _add(record: Dictionary, id: String, asset: String, local: Vector3, yaw: float, seabed: Callable, attributes := {}) -> void:
	# Per-item orientation may differ from the site's rotation. Position is rotated
	# by the site only, not by a door's facing direction.
	var site_yaw: float=float(record.get("_site_yaw",yaw))
	if not record.has("_site_yaw"): record._site_yaw=yaw
	var at := local.rotated(Vector3.UP,deg_to_rad(site_yaw))
	var spec:=CustomPortCatalog.definition(asset)
	if str(spec.get("kind",""))=="platform":
		var bottom: float=4.0
		if seabed.is_valid():
			var origin:=CustomPortCatalog.vector3(record.origin_m)
			var half:=Vector2(float(spec.footprint_m[0]),float(spec.footprint_m[1]))*.5
			for corner in [Vector3(-half.x,0,-half.y),Vector3(half.x,0,-half.y),Vector3(half.x,0,half.y),Vector3(-half.x,0,half.y),Vector3.ZERO]:
				var sample: Vector3=origin+at+corner.rotated(Vector3.UP,deg_to_rad(yaw))
				bottom=maxf(bottom,origin.y-float(seabed.call(Vector2(sample.x,sample.z)))+.5)
		attributes=attributes.duplicate(true)
		attributes.support_depth_m=bottom
	record.placements.append(CustomPortCatalog.placement(id,asset,at,yaw,attributes))

static func _waterfront(record: Dictionary, yaw: float, seabed: Callable) -> void:
	# An independent finger pier and sheltered inlet, joined by the back wharf.
	# This is built from the same library pieces as the player uses, no scenery mesh.
	_add(record,"west-head-left","quay_triangle_8m",Vector3(-116,0,4),yaw+90,seabed)
	_add(record,"west-head-middle","foundation_8m",Vector3(-108,0,4),yaw,seabed)
	_add(record,"west-head-right","quay_triangle_8m",Vector3(-100,0,4),yaw,seabed)
	for z in range(10,48,4):
		for x in range(-118,-96,4): _add(record,"west-pier-%d-%d"%[x,z],"foundation",Vector3(x,0,z),yaw,seabed)
	for z in range(50,64,4):
		for x in range(-118,-72,4): _add(record,"back-wharf-%d-%d"%[x,z],"foundation",Vector3(x,0,z),yaw,seabed)
	for x in [-116,-100]:
		var angle:=45.0 if x==-116 else -45.0
		_add(record,"west-angle-%d"%x,"quay_diagonal_coping_8m",Vector3(x,0,4),yaw+angle,seabed)
		_add(record,"west-angle-tyre-%d"%x,"tractor_tire_fender",Vector3(x,0,4),yaw+angle,seabed)
	for z in range(10,48,4):
		_add(record,"pier-east-edge-%d"%z,"quay_edge_mitre_left" if z==10 else "quay_edge_4m",Vector3(-96,0,z),yaw-90,seabed)
		_add(record,"pier-west-edge-%d"%z,"quay_edge_mitre_right" if z==10 else "quay_edge_4m",Vector3(-120,0,z),yaw+90,seabed)
	for x in range(-110,-102,4): _add(record,"pier-head-edge-%d"%x,"quay_edge_mitre_left" if x==-110 else "quay_edge_mitre_right",Vector3(x,0,0),yaw,seabed)
	for x in range(-94,-72,4): _add(record,"basin-back-edge-%d"%x,"quay_edge_4m",Vector3(x,0,48),yaw,seabed)
	for z in range(6,48,4): _add(record,"basin-east-edge-%d"%z,"quay_edge_mitre_right" if z==6 else "quay_edge_4m",Vector3(-72,0,z),yaw+90,seabed)
	for z in [12,40]: _add(record,"fishing-bollard-%d"%z,"quay_bollard",Vector3(-96.8,0,z),yaw-90,seabed)
	for z in [16,24,32,44]: _add(record,"fishing-tyre-%d"%z,"tractor_tire_fender",Vector3(-96,0,z),yaw-90,seabed)
	_add(record,"fishing-ladder","quay_ladder",Vector3(-96,0,36),yaw-90,seabed)
	_add(record,"fishing-rescue","lifering_station",Vector3(-98,0,36),yaw-90,seabed)
	_gabled_building(record,"net-loft",Vector3(-108,0,30),5,"944735","sign_fish",yaw,seabed)
	# Building spans share the editor's 8m-wide / 4m-long roof snap lattice.
	_gabled_building(record,"warehouse",Vector3(-52,0,54),3,"a64b37","sign_warehouse",yaw,seabed)
	_gabled_building(record,"workshop",Vector3(-36,0,54),3,"bca773","sign_workshop",yaw,seabed)
	_gabled_building(record,"office",Vector3(-20,0,56),2,"d4ccaf","sign_harbour",yaw,seabed)
	_gabled_building(record,"chandlery",Vector3(-84,0,56),2,"526e76","sign_workshop",yaw,seabed)
	# A small covered loading area, net repair storage and a place to sit at the head.
	_add(record,"net-loft-porch","door_canopy_4m",Vector3(-110,0,18.5),yaw,seabed)
	for i in 3:
		_add(record,"net-store-%d"%i,"net_storage_cage",Vector3(-115,0,25+i*2),yaw,seabed)
	_add(record,"pier-rope","mooring_warp_coil",Vector3(-98,0,15),yaw,seabed)
	_add(record,"pier-bench","quay_bench",Vector3(-109,0,9),yaw,seabed)
	_add(record,"office-bench","quay_bench",Vector3(-14,0,57),yaw-90,seabed)
	for at in [Vector3(-98,0,20),Vector3(-98,0,40),Vector3(4,0,2),Vector3(60,0,-9)]:
		_add(record,"supply-%s"%str(at),"dock_service_pedestal",at,yaw,seabed)
	for at in [Vector3(-117,0,12),Vector3(-117,0,45),Vector3(-90,0,50),Vector3(-66,0,52),Vector3(-10,0,70)]:
		_add(record,"waterfront-light-%s"%str(at),"quay_light",at,yaw,seabed)
	for x in range(26,72,4): _add(record,"ore-backwall-%d"%x,"bulk_retaining_wall_4m",Vector3(x,0,47),yaw,seabed)
	for x in [-118,-114,-110,-106,-102,-98,-94,-90,-86,-82,-78,-74]:
		_add(record,"rear-railing-%d"%x,"quay_guardrail_4m",Vector3(x,0,63),yaw,seabed)
	for z in [66,70,74,78]:
		_add(record,"approach-rail-%d"%z,"quay_guardrail_4m",Vector3(7,0,z),yaw+90,seabed)

static func _workshop(record: Dictionary, center: Vector3, yaw: float, seabed: Callable) -> void:
	# The travel scene reuses this small arrangement, not a second building system.
	_gabled_building(record,"streamed-workshop",center,3,"a64b37","sign_workshop",yaw,seabed)

static func _gabled_building(record: Dictionary, id: String, center: Vector3, bays: int, colour: String, sign_id: String, yaw: float, seabed: Callable) -> void:
	var half_depth:=bays*2.0
	var paint:={"wall_colour":colour}
	var tall:=id=="office"
	if tall:_add(record,id+"-upper-floor","harbour_office_upper_floor",center,yaw,seabed,paint)
	for i in 2:
		var x:float=-2+i*4
		var front:="workshop_window_4m" if id=="office" and i==0 else ("workshop_open_bay_4m" if i==0 else "workshop_door_4m")
		_add(record,id+"-front-%d"%i,front,center+Vector3(x,0,-half_depth),yaw,seabed,paint)
		_add(record,id+"-back-%d"%i,"workshop_wall_4m",center+Vector3(x,0,half_depth),yaw+180,seabed,paint)
	for i in bays:
		var z:float=-half_depth+2+i*4
		_add(record,id+"-left-%d"%i,"workshop_window_4m",center+Vector3(-4,0,z),yaw+90,seabed,paint)
		_add(record,id+"-right-%d"%i,"workshop_window_4m",center+Vector3(4,0,z),yaw-90,seabed,paint)
		_add(record,id+"-roof-%d"%i,"office_roof_8x4" if tall else "warehouse_roof_8x4",center+Vector3(0,0,z),yaw,seabed)
	for side in [-1,1]:
		_add(record,id+"-gable-%d"%side,"office_gable_8m" if tall else "warehouse_gable_8m",center+Vector3(0,0,side*half_depth),yaw+(180 if side==1 else 0),seabed,paint)
		for x in [-4,4]:
			_add(record,id+"-trim-%d-%d"%[side,x],"workshop_corner_trim",center+Vector3(x,0,side*half_depth),yaw,seabed)
		_add(record,id+"-drain-%d"%side,"office_downpipe" if tall else "warehouse_downpipe",center+Vector3(side*4.36,0,-half_depth+.4),yaw+90*side,seabed)
	_add(record,id+"-sign",sign_id,center+Vector3(0,0,-half_depth-.03),yaw,seabed)

static func survey(record: Dictionary, seabed: Callable, sea_level: float) -> void:
	assert(seabed.is_valid())
	var origin:=CustomPortCatalog.vector3(record.origin_m)
	var yaw:=deg_to_rad(float(record.get("_site_yaw",0)))
	# Every cell stores a conservative lower bound from a 2m sampling lattice.
	# Unsurveyed areas remain unknown. This covers berthing water, not a route.
	for z in range(-96,64,8):
		for x in range(-128,88,8):
			var local:=Vector3(x+4,0,z+4).rotated(Vector3.UP,yaw)
			var depth:=INF
			for dz in range(-4,5,2):
				for dx in range(-4,5,2):
					var at:=origin+local+Vector3(dx,0,dz)
					depth=minf(depth,sea_level-float(seabed.call(Vector2(at.x,at.z))))
			if depth>1: record.water_regions.append({"rect_m":[local.x-4,local.z-4,8,8],"depth_m":maxf(0,depth-1.0)})
	record.erase("_site_yaw")
