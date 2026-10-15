class_name CustomPortFishingExample
extends RefCounted

## Compact one-plot fishing pier authored with the same placeable library.
## Catch is explicit scenario input, never a side effect of constructing a plant.
static func build(origin: Vector3, plots: Array, world: Dictionary, seabed: Callable=Callable()) -> Dictionary:
	var owner:="company-fishing-pier"
	var record:={"schema_version":1,"id":"fishing-pier","name":"Skjærvik fishing pier","owner_company_id":owner,
		"world":world.duplicate(true),"origin_m":[origin.x,origin.y,origin.z],"deck_height_above_sea_m":2.0,
		"plots":plots.duplicate(true),"placements":[],"water_regions":[],"stores":[],"vessels":[],"reservations":[],"receipts":{},"revision":0}
	for plot in record.plots:plot.owner_company_id=owner
	for z in range(4,40,8):
		for x in [-12,-4,4,12]:_add(record,"deck-%d-%d"%[x,z],"foundation_8m",Vector3(x,0,z),seabed)
	# A small shore connection uses the same deck plane, not an extra-height ramp.
	for z in range(42,80,4):
		for x in [-2,2]:_add(record,"walkway-%d-%d"%[x,z],"foundation",Vector3(x,0,z),seabed)
	_add(record,"landing","fish_landing_plant",Vector3(0,0,12),seabed)
	for x in [-14,14]:_add(record,"bollard-%d"%x,"quay_bollard",Vector3(x,0,.8),seabed)
	for x in range(-14,16,4):_add(record,"edge-%d"%x,"quay_edge_4m",Vector3(x,0,0),seabed)
	for x in [-12,-4,4,12]:_add(record,"fender-%d"%x,"tractor_tire_fender",Vector3(x,0,0),seabed)
	_add(record,"ladder","quay_ladder",Vector3(-8,0,0),seabed)
	_add(record,"lifering","lifering_station",Vector3(-6,0,1.5),seabed)
	for at in [Vector3(-14,0,22),Vector3(14,0,22),Vector3(2,0,38)]:_add(record,"light-%s"%str(at),"quay_light",at,seabed)
	# A modest 8x8m room assembled from the shared walls/door/windows/roof.
	for x in [-10,-6]:
		_add(record,"front-%d"%x,"workshop_door_4m" if x==-6 else "workshop_window_4m",Vector3(x,0,24),seabed)
		_add(record,"back-%d"%x,"workshop_wall_4m",Vector3(x,0,32),seabed,180)
		for z in [26,30]:_add(record,"roof-%d-%d"%[x,z],"workshop_roof_4m",Vector3(x,0,z),seabed)
	for z in [26,30]:
		_add(record,"left-%d"%z,"workshop_wall_4m",Vector3(-12,0,z),seabed,90)
		_add(record,"right-%d"%z,"workshop_window_4m",Vector3(-4,0,z),seabed,-90)
	for x in [-12,-4]:
		for z in [24,32]:_add(record,"trim-%d-%d"%[x,z],"workshop_corner_trim",Vector3(x,0,z),seabed)
	_add(record,"landing-operator","port_clerk",Vector3(10,0,24),seabed,180,{"display_name":"Fish landing operator","service":"cargo","store_id":"fish-receiver"})
	var store: Dictionary=CustomPortCatalog.definition("fish_landing_plant").get("attached_store",{}).duplicate(true)
	store.merge({"id":"fish-receiver","placement_id":"landing","name":"Fresh catch ashore","public_unloading":true,"public_loading":true,"lots":[]},true)
	record.stores=[store]
	var vessel:=CustomPortVesselProjection.from_prebuilt("fishing_hook_line","nordlys","company-visitor","Nordlys")
	vessel.lots=[
		{"id":"morning-catch","commodity_id":"fresh_groundfish","quantity":420,"unit_mass_kg":1,"attributes":{"species_id":"cod","quality":.94,"caught_game_hours":6,"caught_position":[origin.x-600,origin.z-400],"specimen":false}},
		{"id":"large-halibut","commodity_id":"fresh_groundfish","quantity":1,"unit_mass_kg":38.5,"attributes":{"species_id":"halibut","quality":.97,"caught_game_hours":6.1,"caught_position":[origin.x-700,origin.z-500],"specimen":true,"length_cm":132,"size_grade":"Large","value_nok":9400}}]
	record.vessels=[vessel]
	record.erase("_site_yaw")
	return record

static func _add(record: Dictionary,id: String,asset: String,at: Vector3,seabed: Callable,yaw:=0.0,attributes: Dictionary={}) -> void:
	# Reuse the existing builder's actual-seabed support-depth projection.
	record._site_yaw=0
	CustomPortExample._add(record,id,asset,at,yaw,seabed,attributes)
